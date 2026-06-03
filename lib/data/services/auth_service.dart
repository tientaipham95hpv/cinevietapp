import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../models/movie.dart';
import 'cineviet_api.dart';
import '../repositories/movie_repository.dart';

const _mobileKey = 'cineviet-mobile-app-v1';
const _googleServerClientId =
    '511689034636-c7127b68vmqibg1t2jab2t7mek8mq1mt.apps.googleusercontent.com';
const _tokenKey = 'cineviet_access_token';
const _refreshKey = 'cineviet_refresh_token';
const _rememberLoginKey = 'cineviet_remember_login';
const _rememberEmailKey = 'cineviet_remember_email';

class AuthState {
  const AuthState({this.user, this.loading = false, this.error});
  final AppUser? user;
  final bool loading;
  final String? error;
  bool get loggedIn => user != null;

  AuthState copyWith({
    AppUser? user,
    bool? loading,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) => AuthState(
    user: clearUser ? null : (user ?? this.user),
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);
final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);
final favoriteMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(authControllerProvider.notifier).favorites(),
);
final favoriteIdsProvider = FutureProvider<Set<int>>(
  (ref) => ref.watch(authControllerProvider.notifier).favoriteIds(),
);

class RegisterOtpResult {
  const RegisterOtpResult({
    required this.email,
    required this.verifyToken,
    required this.requireEmailVerification,
  });

  final String email;
  final String verifyToken;
  final bool requireEmailVerification;
}

class TvLoginSession {
  const TvLoginSession({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final String verificationUriComplete;
  final int expiresIn;
  final int interval;

  factory TvLoginSession.fromJson(Map<String, dynamic> json) => TvLoginSession(
    deviceCode: '${json['deviceCode'] ?? ''}',
    userCode: '${json['userCode'] ?? ''}',
    verificationUrl: '${json['verificationUrl'] ?? ''}',
    verificationUriComplete: '${json['verificationUriComplete'] ?? ''}',
    expiresIn: int.tryParse('${json['expiresIn'] ?? 600}') ?? 600,
    interval: int.tryParse('${json['interval'] ?? 5}') ?? 5,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this.ref) : super(const AuthState(loading: true)) {
    _installAuthInterceptor();
    _bootstrap();
  }
  final Ref ref;
  Future<bool>? _refreshFuture;

  CineVietApi get _api => ref.read(cineVietApiProvider);
  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);

  void _installAuthInterceptor() {
    _api.dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _readToken(_tokenKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final path = error.requestOptions.path;
          final isAuthRefresh = path.contains('/auth/refresh');
          final alreadyRetried =
              error.requestOptions.extra['authRetried'] == true;
          if (error.response?.statusCode != 401 ||
              isAuthRefresh ||
              alreadyRetried) {
            handler.next(error);
            return;
          }

          final ok = await _refreshOnce();
          if (!ok) {
            handler.next(error);
            return;
          }

          try {
            final token = await _readToken(_tokenKey);
            final retryOptions = error.requestOptions;
            retryOptions.extra['authRetried'] = true;
            if (token != null && token.isNotEmpty) {
              retryOptions.headers['Authorization'] = 'Bearer $token';
            }
            final response = await _api.dio.fetch<dynamic>(retryOptions);
            handler.resolve(response);
          } catch (e) {
            handler.next(error);
          }
        },
      ),
    );
  }

  Future<String?> _readToken(String key) async {
    final secureValue = await _storage.read(key: key);
    if (secureValue != null && secureValue.isNotEmpty) return secureValue;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _writeToken(String key, String value) async {
    await _storage.write(key: key, value: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _bootstrap() async {
    try {
      final token = await _readToken(_tokenKey);
      if (token == null || token.isEmpty) {
        state = const AuthState();
        return;
      }
      _api.dio.options.headers['Authorization'] = 'Bearer $token';
      final res = await _api.dio.get('/auth/me');
      if (res.data is Map) {
        state = AuthState(
          user: AppUser.fromJson(Map<String, dynamic>.from(res.data as Map)),
        );
      } else {
        final refreshed = await refresh();
        if (!refreshed) state = const AuthState();
      }
    } catch (_) {
      final refreshed = await refresh();
      if (!refreshed) state = const AuthState();
    }
  }

  Future<void> _setRememberPreference(bool remember, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberLoginKey, remember);
    if (remember) {
      await prefs.setString(_rememberEmailKey, email.trim());
    } else {
      await prefs.remove(_rememberEmailKey);
    }
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final token = '${data['accessToken'] ?? data['token'] ?? ''}';
    final refresh = '${data['refreshToken'] ?? ''}';
    if (token.isNotEmpty) {
      await _writeToken(_tokenKey, token);
      _api.dio.options.headers['Authorization'] = 'Bearer $token';
    }
    if (refresh.isNotEmpty) {
      await _writeToken(_refreshKey, refresh);
    }
    final user = data['user'] is Map
        ? AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map))
        : null;
    state = AuthState(user: user);
  }

  Future<bool> _refreshOnce() {
    final running = _refreshFuture;
    if (running != null) return running;
    _refreshFuture = refresh().whenComplete(() => _refreshFuture = null);
    return _refreshFuture!;
  }

  Future<bool> refresh() async {
    try {
      final refreshToken = await _readToken(_refreshKey);
      if (refreshToken == null || refreshToken.isEmpty) return false;
      final res = await _api.dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(headers: {'X-Mobile-Key': _mobileKey}),
      );
      await _saveSession(Map<String, dynamic>.from(res.data as Map));
      return true;
    } catch (_) {
      await _clearTokens();
      return false;
    }
  }

  Future<TvLoginSession> createTvLoginSession() async {
    final res = await _api.dio.post('/auth/tv/device-code');
    return TvLoginSession.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<bool> pollTvLogin(String deviceCode) async {
    try {
      final res = await _api.dio.post(
        '/auth/tv/token',
        data: {'deviceCode': deviceCode},
      );
      await _saveSession(Map<String, dynamic>.from(res.data as Map));
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final code = data is Map ? '${data['error'] ?? ''}' : '';
      if (status == 428 || code == 'authorization_pending') return false;
      rethrow;
    }
  }

  Future<void> login(
    String email,
    String password, {
    bool remember = true,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final normalizedEmail = email.trim();
      final res = await _api.dio.post(
        '/auth/login',
        data: {
          'email': normalizedEmail,
          'password': password,
          'remember': remember,
        },
        options: Options(headers: {'X-Mobile-Key': _mobileKey}),
      );
      await _saveSession(Map<String, dynamic>.from(res.data as Map));
      await _setRememberPreference(remember, normalizedEmail);
    } catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  Future<bool> loginWithGoogle() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final google = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: _googleServerClientId,
      );
      await google.signOut();
      final account = await google.signIn();
      if (account == null) {
        state = state.copyWith(loading: false, clearError: true);
        return false;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: 'Không lấy được Google ID token.',
        );
        return false;
      }
      final res = await _api.dio.post(
        '/auth/google/mobile',
        data: {'idToken': idToken, 'remember': true},
        options: Options(headers: {'X-Mobile-Key': _mobileKey}),
      );
      await _saveSession(Map<String, dynamic>.from(res.data as Map));
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
      return false;
    }
  }

  Future<RegisterOtpResult?> register(
    String name,
    String email,
    String password,
  ) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await _api.dio.post(
        '/auth/register',
        data: {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
          'remember': true,
          'require_email_otp': true,
        },
        options: Options(headers: {'X-Mobile-Key': _mobileKey}),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['requireEmailVerification'] == true) {
        state = state.copyWith(loading: false, clearError: true);
        return RegisterOtpResult(
          email: email.trim(),
          verifyToken: '${data['verifyToken'] ?? data['token'] ?? ''}',
          requireEmailVerification: true,
        );
      }
      await _saveSession(data);
      return const RegisterOtpResult(
        email: '',
        verifyToken: '',
        requireEmailVerification: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
      return null;
    }
  }

  Future<bool> verifyEmailCode(String verifyToken, String code) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await _api.dio.post(
        '/auth/verify-email',
        data: {'code': code.trim()},
        options: Options(headers: {'Authorization': 'Bearer $verifyToken'}),
      );
      await _saveSession(Map<String, dynamic>.from(res.data as Map));
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
      return false;
    }
  }

  Future<RegisterOtpResult?> resendRegisterOtp({
    required String email,
    required String verifyToken,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await _api.dio.post(
        '/auth/resend-verification',
        options: Options(headers: {'Authorization': 'Bearer $verifyToken'}),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      state = state.copyWith(loading: false, clearError: true);
      return RegisterOtpResult(
        email: '${data['email'] ?? email}',
        verifyToken: '${data['verifyToken'] ?? verifyToken}',
        requireEmailVerification: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _api.dio.post(
        '/auth/logout',
        data: {'refreshToken': await _readToken(_refreshKey)},
      );
    } catch (_) {}
    await _clearTokens();
    state = const AuthState();
    ref.invalidate(favoriteMoviesProvider);
    ref.invalidate(favoriteIdsProvider);
  }

  Future<void> loginWithToken(String token) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _writeToken(_tokenKey, token);
      _api.dio.options.headers['Authorization'] = 'Bearer $token';
      final res = await _api.dio.get('/auth/me');
      if (res.data is Map) {
        state = AuthState(
          user: AppUser.fromJson(Map<String, dynamic>.from(res.data as Map)),
        );
      } else {
        await _clearTokens();
        state = state.copyWith(
          loading: false,
          error: 'Không thể tải thông tin người dùng.',
        );
      }
    } catch (e) {
      await _clearTokens();
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  Future<bool> loginWithOAuthCallback(String callbackUrl) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final uri = Uri.parse(callbackUrl);
      final code = uri.queryParameters['code'] ?? '';
      if (code.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: 'Không nhận được mã đăng nhập Google.',
        );
        return false;
      }
      final res = await _api.dio.get(
        '/auth/oauth-token',
        queryParameters: {'code': code},
        options: Options(headers: {'X-Mobile-Key': _mobileKey}),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final token = '${data['token'] ?? data['accessToken'] ?? ''}';
      if (token.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: 'Không nhận được token Google.',
        );
        return false;
      }
      await _saveSession(data);
      if (!state.loggedIn) {
        await loginWithToken(token);
      }
      await _setRememberPreference(true, state.user?.email ?? '');
      return state.loggedIn;
    } catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
      return false;
    }
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    _api.dio.options.headers.remove('Authorization');
  }

  Future<List<Movie>> favorites() async {
    if (!state.loggedIn) return const [];
    final res = await _api.dio.get('/user/favorites');
    final list = (res.data as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Set<int>> favoriteIds() async {
    if (!state.loggedIn) return <int>{};
    final res = await _api.dio.get('/user/favorite-ids');
    return (res.data as List? ?? const [])
        .map((e) => int.tryParse('$e'))
        .whereType<int>()
        .toSet();
  }

  Future<void> toggleFavorite(Movie movie, bool add) async {
    if (!state.loggedIn) {
      throw Exception('Vui lòng đăng nhập để lưu phim yêu thích');
    }
    if (add) {
      await _api.dio.post('/user/favorites/${movie.id}');
    } else {
      await _api.dio.delete('/user/favorites/${movie.id}');
    }
    ref.invalidate(favoriteMoviesProvider);
    ref.invalidate(favoriteIdsProvider);
  }

  Future<void> removeFavorite(Movie movie) => toggleFavorite(movie, false);

  Future<void> clearFavorites() async {
    if (!state.loggedIn) {
      throw Exception('Vui lòng đăng nhập để xóa yêu thích');
    }
    final movies = await favorites();
    for (final movie in movies) {
      await _api.dio.delete('/user/favorites/${movie.id}');
    }
    ref.invalidate(favoriteMoviesProvider);
    ref.invalidate(favoriteIdsProvider);
  }

  String _message(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        return '${data['error'] ?? data['message'] ?? 'Có lỗi xảy ra'}';
      }
    }
    return 'Có lỗi xảy ra. Vui lòng thử lại.';
  }
}
