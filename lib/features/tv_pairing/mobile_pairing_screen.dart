import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../data/repositories/movie_repository.dart';

class MobilePairingScreen extends ConsumerStatefulWidget {
  const MobilePairingScreen({super.key});

  @override
  ConsumerState<MobilePairingScreen> createState() => _MobilePairingScreenState();
}

class _MobilePairingScreenState extends ConsumerState<MobilePairingScreen> {
  final _codeController = TextEditingController();
  final _scannerController = MobileScannerController();
  bool _isScanning = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _confirmPairing(String code) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(cineVietApiProvider).dio;
      final response = await api.post('/auth/tv/confirm', data: {'code': code});
      final data = response.data;

      if (data['ok'] == true && data['confirmed'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Đã xác thực thành công!'),
              backgroundColor: CineVietColors.accent,
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _error = data['error'] ?? 'Không thể xác thực.';
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

  void _onQrDetect(BarcodeCapture capture) {
    if (_loading) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    try {
      final json = jsonDecode(rawValue);
      if (json['type'] == 'cineviet_tv_pairing') {
        final code = json['code'];
        if (code != null && code is String && RegExp(r'^\d{6}$').hasMatch(code)) {
          _scannerController.stop();
          _confirmPairing(code);
        }
      }
    } catch (e) {
      if (RegExp(r'^\d{6}$').hasMatch(rawValue.trim())) {
        _scannerController.stop();
        _confirmPairing(rawValue.trim());
      }
    }
  }

  void _onManualSubmit() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Vui lòng nhập mã 6 chữ số.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Mã phải là 6 chữ số.');
      return;
    }
    _confirmPairing(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      appBar: AppBar(
        backgroundColor: CineVietColors.bg,
        title: const Text('Ghép nối TV'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.keyboard_rounded : Icons.qr_code_scanner_rounded),
            onPressed: () {
              setState(() {
                _isScanning = !_isScanning;
                _error = null;
              });
              if (_isScanning) {
                _scannerController.start();
              } else {
                _scannerController.stop();
              }
              
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isScanning ? _buildScanner() : _buildManualInput(),
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _onQrDetect,
              ),
              if (_loading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: CineVietColors.accent),
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(CineVietSpacing.lg),
          color: CineVietColors.card,
          child: Column(
            children: [
              const Text(
                'Quét mã QR trên màn hình TV',
                style: TextStyle(fontSize: 16),
              ),
              if (_error != null) ...[
                const SizedBox(height: CineVietSpacing.sm),
                Text(
                  _error!,
                  style: const TextStyle(color: CineVietColors.red),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualInput() {
    return Padding(
      padding: const EdgeInsets.all(CineVietSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.tv_rounded,
            size: 80,
            color: CineVietColors.accent,
          ),
          const SizedBox(height: CineVietSpacing.xl),
          const Text(
            'Nhập mã 6 chữ số hiển thị trên TV',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: CineVietSpacing.xl),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              filled: true,
              fillColor: CineVietColors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CineVietRadius.lg),
                borderSide: const BorderSide(color: CineVietColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CineVietRadius.lg),
                borderSide: const BorderSide(color: CineVietColors.accent, width: 2),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: CineVietSpacing.md),
            Text(
              _error!,
              style: const TextStyle(color: CineVietColors.red),
            ),
          ],
          const SizedBox(height: CineVietSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _onManualSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: CineVietColors.accent,
                foregroundColor: CineVietColors.bg,
                padding: const EdgeInsets.symmetric(vertical: CineVietSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CineVietRadius.lg),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CineVietColors.bg,
                      ),
                    )
                  : const Text(
                      'Xác nhận',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
