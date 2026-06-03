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
      },
    );
    return AppVersionInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
  }
}
