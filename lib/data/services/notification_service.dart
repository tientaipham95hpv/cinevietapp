import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_notification.dart';
import 'cineviet_api.dart';
import '../repositories/movie_repository.dart';

final appVersionProvider = FutureProvider<AppVersionInfo>((ref) async {
  return ref.read(notificationServiceProvider).checkVersion();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.read(cineVietApiProvider));
});

class NotificationService {
  NotificationService(this._api);
  final CineVietApi _api;

  Future<AppVersionInfo> checkVersion() async {
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 0;
    final res = await _api.dio.get(
      '/app/version',
      queryParameters: {
        'version': info.version,
        'build': build,
        ..._updateTargetParameters(),
      },
    );
    return AppVersionInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Map<String, String> _updateTargetParameters() {
    if (kIsWeb) return const {'platform': 'web'};

    if (Platform.isIOS) return const {'platform': 'ios'};
    if (Platform.isWindows) return const {'platform': 'windows'};
    if (Platform.isMacOS) return const {'platform': 'macos'};
    if (Platform.isLinux) return const {'platform': 'linux'};

    if (Platform.isAndroid) {
      const buildVariant = String.fromEnvironment('APP_VARIANT');
      final currentAbi = Abi.current();
      final abi = currentAbi == Abi.androidArm
          ? 'armeabi-v7a'
          : currentAbi == Abi.androidArm64
              ? 'arm64-v8a'
              : currentAbi == Abi.androidX64
                  ? 'x86_64'
                  : currentAbi == Abi.androidIA32
                      ? 'x86'
                      : currentAbi.toString().split('.').last;
      return {
        'platform': 'android',
        if (buildVariant.isNotEmpty) 'variant': buildVariant,
        'abi': abi,
      };
    }

    return const {};
  }
}
