import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../models/movie_page.dart';
import '../services/cineviet_api.dart';

final cineVietApiProvider = Provider<CineVietApi>((ref) => CineVietApi());
final movieRepositoryProvider = Provider<MovieRepository>(
  (ref) => MovieRepository(ref.watch(cineVietApiProvider)),
);
final latestMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).latest(limit: 18),
);
final featuredMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).featured(limit: 10),
);
final movieDetailProvider = FutureProvider.family<Movie, String>(
  (ref, idOrSlug) => ref.watch(movieRepositoryProvider).detail(idOrSlug),
);
final browseMoviesProvider = FutureProvider.family<MoviePage, BrowseQuery>(
  (ref, query) => ref.watch(movieRepositoryProvider).browse(query),
);

class MovieRepository {
  MovieRepository(this.api);
  final CineVietApi api;
  final Map<String, Movie> _detailCache = <String, Movie>{};

  Future<List<Movie>> latest({int limit = 18}) async {
    final res = await api.dio.get(
      '/movies',
      queryParameters: {'limit': limit, 'sort': 'created_at', 'order': 'desc'},
    );
    return _movieList(res.data);
  }

  Future<List<Movie>> featured({int limit = 10}) async {
    final res = await api.dio.get(
      '/movies',
      queryParameters: {'limit': limit, 'featured': '1'},
    );
    return _movieList(res.data);
  }

  Future<List<Movie>> cinema({int limit = 14}) async {
    final res = await api.dio.get(
      '/movies',
      queryParameters: {
        'limit': limit,
        'chieu_rap': '1',
        'sort': 'created_at',
        'order': 'desc',
      },
    );
    return _movieList(res.data);
  }

  Future<List<Movie>> byType(String type, {int limit = 14}) async {
    final res = await api.dio.get(
      '/movies',
      queryParameters: {
        'limit': limit,
        'type': type,
        'sort': 'created_at',
        'order': 'desc',
      },
    );
    return _movieList(res.data);
  }

  List<Movie> _movieList(dynamic data) {
    final list = (data['movies'] as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<MoviePage> browse(BrowseQuery query, {int limit = 24}) async {
    final params = <String, dynamic>{
      'page': query.page,
      'limit': limit,
      'sort': query.sort,
      'order': 'desc',
    };
    if (query.search.trim().isNotEmpty) params['search'] = query.search.trim();
    if (query.type.isNotEmpty) params['type'] = query.type;
    if (query.genre.isNotEmpty) params['genre'] = query.genre;
    if (query.country.isNotEmpty) params['country'] = query.country;
    if (query.year.isNotEmpty) params['release_year'] = query.year;
    final res = await api.dio.get('/movies', queryParameters: params);
    return MoviePage.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<Movie> detail(String idOrSlug) async {
    final key = idOrSlug.trim();
    final cached = _detailCache[key];
    if (cached != null) return cached;
    final res = await api.dio.get('/movies/$key');
    final movie = Movie.fromJson(Map<String, dynamic>.from(res.data as Map));
    _detailCache[key] = movie;
    if (movie.slug.isNotEmpty) _detailCache[movie.slug] = movie;
    _detailCache[movie.id.toString()] = movie;
    if (_detailCache.length > 80) {
      _detailCache.remove(_detailCache.keys.first);
    }
    return movie;
  }
}
