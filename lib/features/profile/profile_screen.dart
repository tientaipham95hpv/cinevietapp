import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/movie_repository.dart';
import '../tv_pairing/mobile_pairing_screen.dart';
import '../tv_pairing/tv_pairing_screen.dart';
import '../about/about_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _otp = TextEditingController();
  final _tvApproveCode = TextEditingController();
  bool _register = false;
  bool _registerOtpStep = false;
  String _registerVerifyToken = '';
  String _registerVerifyEmail = '';
  bool _approvingTvCode = false;
  String? _tvApproveError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _otp.dispose();
    _tvApproveCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final platform = PlatformDetector.of(context);
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(CineVietSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: platform.isTv ? 760 : 560),
              child: auth.loggedIn
                  ? _profile(auth)
                  : (platform.isTv ? _tvLogin(auth) : _form(auth, false)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profile(AuthState auth) {
    final user = auth.user!;
    final platform = PlatformDetector.of(context);
    return Container(
      padding: EdgeInsets.all(
        platform.isMobile ? CineVietSpacing.lg : CineVietSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: CineVietColors.card,
        borderRadius: BorderRadius.circular(CineVietRadius.xl),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!platform.isMobile)
            Row(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundImage: (user.avatar ?? '').isNotEmpty
                      ? NetworkImage(user.avatar!)
                      : null,
                  child: (user.avatar ?? '').isEmpty
                      ? const Icon(Icons.person_rounded, size: 42)
                      : null,
                ),
                const SizedBox(width: CineVietSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        user.email,
                        style: const TextStyle(color: CineVietColors.textSoft),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundImage: (user.avatar ?? '').isNotEmpty
                      ? NetworkImage(user.avatar!)
                      : null,
                  child: (user.avatar ?? '').isEmpty
                      ? const Icon(Icons.person_rounded, size: 38)
                      : null,
                ),
                const SizedBox(height: CineVietSpacing.md),
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CineVietColors.textSoft),
                ),
              ],
            ),
          const SizedBox(height: CineVietSpacing.xl),
          _InfoRow(
            icon: Icons.verified_user_rounded,
            label: 'Vai trò',
            value: user.role ?? 'user',
          ),
          _InfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: user.emailVerified ? 'Đã xác thực' : 'Chưa xác thực',
          ),
          const SizedBox(height: CineVietSpacing.md),
          _pairingActionsCard(auth.loggedIn, platform.isTv),
          const SizedBox(height: CineVietSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
              icon: const Icon(Icons.system_update_rounded),
              label: const Text('Phiên bản & cập nhật'),
            ),
          ),
          const SizedBox(height: CineVietSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: auth.loading
                  ? null
                  : () => ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Đăng xuất'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(AuthState auth, bool tv) {
    return Container(
      padding: const EdgeInsets.all(CineVietSpacing.xl),
      decoration: BoxDecoration(
        color: CineVietColors.card,
        borderRadius: BorderRadius.circular(CineVietRadius.xl),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _registerOtpStep
                ? 'Xác thực email'
                : (_register ? 'Tạo tài khoản' : 'Đăng nhập'),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: CineVietSpacing.sm),
          Text(
            _registerOtpStep
                ? 'Nhập mã OTP 6 số đã gửi tới $_registerVerifyEmail.'
                : 'Đăng nhập để lưu phim yêu thích và chuẩn bị đồng bộ đa thiết bị.',
            style: const TextStyle(color: CineVietColors.textSoft),
          ),
          if (tv) ...[
            const SizedBox(height: CineVietSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startTvLogin,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Đăng nhập nhanh bằng mã/QR'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: CineVietSpacing.md),
              child: Center(
                child: Text(
                  'hoặc nhập bằng remote',
                  style: TextStyle(color: CineVietColors.textSoft),
                ),
              ),
            ),
          ] else
            const SizedBox(height: CineVietSpacing.lg),
          if (_registerOtpStep) ...[
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Mã OTP',
                prefixIcon: Icon(Icons.pin_rounded),
              ),
            ),
          ] else ...[
            if (_register) ...[
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tên hiển thị',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: CineVietSpacing.md),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_rounded),
              ),
            ),
            const SizedBox(height: CineVietSpacing.md),
            TextField(
              controller: _password,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Mật khẩu',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
            ),
          ],
          if (auth.error != null) ...[
            const SizedBox(height: CineVietSpacing.md),
            Text(
              auth.error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (!_registerOtpStep && !tv) ...[
            const SizedBox(height: CineVietSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: auth.loading ? null : _loginWithGoogle,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                label: const Text('Đăng nhập bằng Google'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CineVietColors.text,
                  side: const BorderSide(color: CineVietColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: CineVietSpacing.md),
              child: Center(
                child: Text(
                  'hoặc',
                  style: TextStyle(color: CineVietColors.textSoft),
                ),
              ),
            ),
          ] else
            const SizedBox(height: CineVietSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: auth.loading ? null : _submit,
              icon: auth.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _register
                          ? Icons.person_add_rounded
                          : Icons.login_rounded,
                    ),
              label: Text(
                _registerOtpStep
                    ? 'Xác thực'
                    : (_register ? 'Đăng ký' : 'Đăng nhập'),
              ),
            ),
          ),
          if (_registerOtpStep) ...[
            const SizedBox(height: CineVietSpacing.md),
            Center(
              child: TextButton.icon(
                onPressed: auth.loading ? null : _resendRegisterOtp,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Gửi lại mã'),
              ),
            ),
          ],
          const SizedBox(height: CineVietSpacing.md),
          Center(
            child: TextButton(
              onPressed: auth.loading
                  ? null
                  : () => setState(() {
                      if (_registerOtpStep) {
                        _registerOtpStep = false;
                        _registerVerifyToken = '';
                        _otp.clear();
                      } else {
                        _register = !_register;
                      }
                    }),
              child: Text(
                _registerOtpStep
                    ? 'Quay lại đăng ký'
                    : (_register
                          ? 'Đã có tài khoản? Đăng nhập'
                          : 'Chưa có tài khoản? Đăng ký'),
              ),
            ),
          ),
          if (!_register && !tv) ...[
            const SizedBox(height: CineVietSpacing.sm),
            Center(
              child: TextButton.icon(
                onPressed: auth.loading ? null : _openMobilePairing,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Ghép nối TV'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tvLogin(AuthState auth) {
    return Container(
      padding: const EdgeInsets.all(CineVietSpacing.xl),
      decoration: BoxDecoration(
        color: CineVietColors.card,
        borderRadius: BorderRadius.circular(CineVietRadius.xl),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.tv_rounded, size: 64, color: CineVietColors.accent),
          const SizedBox(height: CineVietSpacing.md),
          const Text(
            'Đăng nhập TV bằng điện thoại',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CineVietSpacing.sm),
          const Text(
            'Bấm nút bên dưới để hiện QR code và mã 6 chữ số. Sau đó dùng mobile đã đăng nhập để quét QR hoặc nhập mã.',
            style: TextStyle(color: CineVietColors.textSoft),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CineVietSpacing.xl),
          FilledButton.icon(
            onPressed: _startTvLogin,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Đăng nhập nhanh bằng mã/QR'),
          ),
          const SizedBox(height: CineVietSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: auth.loading ? null : _loginWithGoogle,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 34),
              label: const Text('Đăng nhập bằng Google'),
              style: OutlinedButton.styleFrom(
                foregroundColor: CineVietColors.text,
                side: const BorderSide(color: CineVietColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pairingActionsCard(bool loggedIn, bool isTv) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CineVietSpacing.md),
      decoration: BoxDecoration(
        color: CineVietColors.bg,
        borderRadius: BorderRadius.circular(CineVietRadius.lg),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: CineVietColors.accent),
              SizedBox(width: CineVietSpacing.sm),
              Text(
                'Ghép đôi TV',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: CineVietSpacing.sm),
          const Text(
            'Quét QR hoặc nhập mã 6 số đang hiển thị trên TV để đăng nhập TV bằng tài khoản này.',
            style: TextStyle(color: CineVietColors.textSoft),
          ),
          const SizedBox(height: CineVietSpacing.md),
          if (isTv)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openMobilePairing,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Quét QR / nhập mã'),
                  ),
                ),
                const SizedBox(width: CineVietSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _startTvLogin,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Tạo mã TV'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openMobilePairing,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Quét QR / nhập mã'),
              ),
            ),
          if (loggedIn) ...[
            const SizedBox(height: CineVietSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  size: 18,
                  color: CineVietColors.accent,
                ),
                const SizedBox(width: CineVietSpacing.xs),
                const Expanded(
                  child: Text(
                    'Đã đăng nhập nên có thể xác nhận TV ngay sau khi quét.',
                    style: TextStyle(color: CineVietColors.textSoft),
                  ),
                ),
              ],
            ),
          ],
          if (!loggedIn) ...[
            const SizedBox(height: CineVietSpacing.sm),
            const Text(
              'Chưa đăng nhập vẫn có thể mở màn QR, nhưng cần đăng nhập trước khi xác nhận TV.',
              style: TextStyle(color: CineVietColors.textSoft),
            ),
          ],
          const SizedBox(height: CineVietSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tvApproveCode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Mã TV 6 số, ví dụ 123456',
                  ),
                  onSubmitted: (_) => _approveTvCode(),
                ),
              ),
              const SizedBox(width: CineVietSpacing.sm),
              FilledButton.icon(
                onPressed: _approvingTvCode ? null : _approveTvCode,
                icon: _approvingTvCode
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Xác nhận'),
              ),
            ],
          ),
          if (_tvApproveError != null) ...[
            const SizedBox(height: CineVietSpacing.sm),
            Text(
              _tvApproveError!,
              style: TextStyle(
                color: _tvApproveError!.startsWith('Đã')
                    ? CineVietColors.accent
                    : Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approveTvCode() async {
    final code = _normalizeTvCode(_tvApproveCode.text);
    if (code.isEmpty) {
      setState(() => _tvApproveError = 'Nhập mã trên TV trước nhé.');
      return;
    }
    setState(() {
      _approvingTvCode = true;
      _tvApproveError = null;
    });
    try {
      final api = ref.read(cineVietApiProvider);
      await api.dio.post('/auth/tv/confirm', data: {'code': code});
      if (!mounted) return;
      setState(() {
        _approvingTvCode = false;
        _tvApproveError = 'Đã xác nhận. TV sẽ tự đăng nhập sau vài giây.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _approvingTvCode = false;
        _tvApproveError =
            'Không xác nhận được mã TV. Mã có thể sai hoặc đã hết hạn.';
      });
    }
  }

  String _normalizeTvCode(String raw) {
    return raw.replaceAll(RegExp(r'\D'), '').trim();
  }

  Future<void> _startTvLogin() async {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TvPairingScreen()));
  }

  Future<void> _loginWithGoogle() async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .loginWithGoogle();
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đăng nhập Google thành công')),
    );
  }

  Future<void> _submit() async {
    final c = ref.read(authControllerProvider.notifier);
    if (_registerOtpStep) {
      final code = _otp.text.replaceAll(RegExp(r'\D'), '');
      if (code.length != 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng nhập đủ 6 số OTP')),
        );
        return;
      }
      await c.verifyEmailCode(_registerVerifyToken, code);
      return;
    }
    if (_register) {
      final result = await c.register(_name.text, _email.text, _password.text);
      if (!mounted || result == null) return;
      if (result.requireEmailVerification) {
        setState(() {
          _registerOtpStep = true;
          _registerVerifyToken = result.verifyToken;
          _registerVerifyEmail = result.email;
          _otp.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi mã OTP tới email của bạn')),
        );
      }
    } else {
      await c.login(_email.text, _password.text);
    }
  }

  Future<void> _resendRegisterOtp() async {
    final result = await ref
        .read(authControllerProvider.notifier)
        .resendRegisterOtp(
          email: _registerVerifyEmail,
          verifyToken: _registerVerifyToken,
        );
    if (!mounted || result == null) return;
    setState(() {
      _registerVerifyToken = result.verifyToken;
      _registerVerifyEmail = result.email;
      _otp.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã gửi lại mã OTP')));
  }

  void _openMobilePairing() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MobilePairingScreen()));
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CineVietSpacing.md),
    child: Row(
      children: [
        Icon(icon, color: CineVietColors.accent),
        const SizedBox(width: CineVietSpacing.md),
        Text(label, style: const TextStyle(color: CineVietColors.textSoft)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
}
