import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/auth_service.dart';

class DesktopOAuthHandler extends ConsumerStatefulWidget {
  const DesktopOAuthHandler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopOAuthHandler> createState() =>
      _DesktopOAuthHandlerState();
}

class _DesktopOAuthHandlerState extends ConsumerState<DesktopOAuthHandler> {
  bool _handledInitialLink = false;
  Timer? _callbackPollTimer;
  String? _lastCallbackUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialArgs();
      _startCallbackBridgePolling();
    });
  }

  @override
  void dispose() {
    _callbackPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleInitialArgs() async {
    if (_handledInitialLink || kIsWeb || !Platform.isWindows) return;
    _handledInitialLink = true;
    for (final arg in Platform.executableArguments) {
      if (arg.startsWith('cineviet://auth/callback')) {
        await _handleCallbackUrl(arg);
        break;
      }
    }
  }

  void _startCallbackBridgePolling() {
    if (kIsWeb || !Platform.isWindows || _callbackPollTimer != null) return;
    _callbackPollTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      _consumeCallbackBridgeFile();
    });
    _consumeCallbackBridgeFile();
  }

  Future<void> _consumeCallbackBridgeFile() async {
    final file = File(_windowsCallbackBridgePath);
    if (!await file.exists()) return;
    final callbackUrl = (await file.readAsString()).trim();
    try {
      await file.delete();
    } catch (_) {
      await file.writeAsString('');
    }
    if (callbackUrl.startsWith('cineviet://auth/callback')) {
      await _handleCallbackUrl(callbackUrl);
    }
  }

  Future<void> _handleCallbackUrl(String callbackUrl) async {
    if (_lastCallbackUrl == callbackUrl) return;
    _lastCallbackUrl = callbackUrl;
    await ref
        .read(authControllerProvider.notifier)
        .loginWithOAuthCallback(callbackUrl);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String get _windowsCallbackBridgePath =>
    '${Directory.systemTemp.path}\\cineviet_oauth_callback.txt';

Future<bool> launchWindowsGoogleLogin() async {
  if (kIsWeb || !Platform.isWindows) return false;
  final bridgeFile = File(_windowsCallbackBridgePath);
  if (await bridgeFile.exists()) {
    await bridgeFile.delete();
  }
  final uri = Uri.parse('https://cineviet.live/api/auth/google?desktop=1');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
