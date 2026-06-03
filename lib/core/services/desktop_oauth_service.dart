import 'dart:io' show Platform;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleInitialArgs());
  }

  Future<void> _handleInitialArgs() async {
    if (_handledInitialLink || kIsWeb || !Platform.isWindows) return;
    _handledInitialLink = true;
    final args = Platform.executableArguments;
    for (final arg in args) {
      if (arg.startsWith('cineviet://auth/callback')) {
        await ref
            .read(authControllerProvider.notifier)
            .loginWithOAuthCallback(arg);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<bool> launchWindowsGoogleLogin() async {
  if (kIsWeb || !Platform.isWindows) return false;
  final uri = Uri.parse('https://cineviet.live/api/auth/google?desktop=1');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
