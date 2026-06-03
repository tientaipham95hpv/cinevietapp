import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/movie_repository.dart';

class TvPairingScreen extends ConsumerStatefulWidget {
  const TvPairingScreen({super.key});

  @override
  ConsumerState<TvPairingScreen> createState() => _TvPairingScreenState();
}

class _TvPairingScreenState extends ConsumerState<TvPairingScreen> {
  String? _sessionId;
  String? _code;
  String? _qrData;
  DateTime? _expiresAt;
  Timer? _pollTimer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPairing();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPairing() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(cineVietApiProvider).dio;
      final response = await api.post('/auth/tv/pair');
      final data = response.data;

      if (data['ok'] == true) {
        setState(() {
          _sessionId = data['sessionId'];
          _code = data['code'];
          _qrData = data['qrData'];
          _expiresAt = DateTime.fromMillisecondsSinceEpoch(data['expiresAt']);
          _loading = false;
        });

        // Start polling
        _startPolling();
      } else {
        setState(() {
          _error = 'Không thể tạo mã ghép nối.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi: $e';
        _loading = false;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_sessionId == null) return;

      // Check expiry
      if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
        _pollTimer?.cancel();
        setState(() {
          _error = 'Mã đã hết hạn. Vui lòng tạo mã mới.';
        });
        return;
      }

      try {
        final api = ref.read(cineVietApiProvider).dio;
        final response = await api.get('/auth/tv/poll/$_sessionId');
        final data = response.data;

        if (data['ok'] == true) {
          if (data['status'] == 'confirmed') {
            _pollTimer?.cancel();
            final token = data['token'];
            if (token != null) {
              // Save token and login
              await ref.read(authControllerProvider.notifier).loginWithToken(token);
              if (mounted) {
                Navigator.of(context).pop();
              }
            }
          }
        }
      } catch (e) {
        // Ignore poll errors, keep trying
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);

    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: CineVietColors.accent)
              : _error != null
                  ? _buildError()
                  : _buildPairingContent(platform),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(CineVietSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: CineVietColors.red,
            size: 64,
          ),
          const SizedBox(height: CineVietSpacing.lg),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CineVietColors.textSoft,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: CineVietSpacing.xl),
          ElevatedButton.icon(
            onPressed: _initPairing,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CineVietColors.accent,
              foregroundColor: CineVietColors.bg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingContent(PlatformInfo platform) {
    final timeLeft = _expiresAt != null
        ? _expiresAt!.difference(DateTime.now()).inSeconds
        : 0;
    final minutes = timeLeft ~/ 60;
    final seconds = timeLeft % 60;

    return SingleChildScrollView(
      padding: EdgeInsets.all(
        platform.isMobile ? CineVietSpacing.xl : CineVietSpacing.xxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Đăng nhập trên TV',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: CineVietSpacing.md),
          const Text(
            'Quét mã QR hoặc nhập mã 6 chữ số trên điện thoại',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CineVietColors.textSoft,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: CineVietSpacing.xxl),
          // QR Code
          if (_qrData != null)
            Container(
              padding: const EdgeInsets.all(CineVietSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(CineVietRadius.xl),
              ),
              child: QrImageView(
                data: _qrData!,
                version: QrVersions.auto,
                size: platform.isMobile ? 200 : 280,
              ),
            ),
          const SizedBox(height: CineVietSpacing.xxl),
          // 6-digit code
          if (_code != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CineVietSpacing.xl,
                vertical: CineVietSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: CineVietColors.card,
                borderRadius: BorderRadius.circular(CineVietRadius.lg),
                border: Border.all(
                  color: CineVietColors.accent,
                  width: 2,
                ),
              ),
              child: Text(
                _code!,
                style: TextStyle(
                  fontSize: platform.isMobile ? 48 : 64,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: CineVietColors.accent,
                ),
              ),
            ),
          const SizedBox(height: CineVietSpacing.xl),
          // Timer
          Text(
            'Mã hết hạn sau: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: CineVietColors.textSoft,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: CineVietSpacing.lg),
          // Refresh button
          TextButton.icon(
            onPressed: _initPairing,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tạo mã mới'),
          ),
        ],
      ),
    );
  }
}
