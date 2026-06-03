import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/cineviet_logo.dart';
import '../../data/services/notification_service.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider);
    final platform = PlatformDetector.of(context);
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Phiên bản & cập nhật'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(
            platform.isMobile ? CineVietSpacing.md : CineVietSpacing.xl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(CineVietSpacing.xl),
                    decoration: BoxDecoration(
                      color: CineVietColors.card,
                      borderRadius: BorderRadius.circular(CineVietRadius.xl),
                      border: Border.all(color: CineVietColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            CineVietLogo(size: 58, showText: false),
                            SizedBox(width: CineVietSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CineViet',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: CineVietSpacing.xs),
                                  Text(
                                    'Ứng dụng xem phim CineViet cho mobile, tablet và TV.',
                                    style: TextStyle(
                                      color: CineVietColors.textSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CineVietSpacing.xl),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snap) {
                            final info = snap.data;
                            return _InfoLine(
                              icon: Icons.tag_rounded,
                              label: 'Phiên bản đang dùng',
                              value: info == null
                                  ? 'Đang tải...'
                                  : '${info.version}+${info.buildNumber}',
                            );
                          },
                        ),
                        version.when(
                          loading: () => const _InfoLine(
                            icon: Icons.cloud_sync_rounded,
                            label: 'Bản mới nhất',
                            value: 'Đang kiểm tra...',
                          ),
                          error: (e, _) => _InfoLine(
                            icon: Icons.error_outline_rounded,
                            label: 'Bản mới nhất',
                            value: 'Không kiểm tra được: $e',
                          ),
                          data: (data) => Column(
                            children: [
                              _InfoLine(
                                icon: Icons.system_update_rounded,
                                label: 'Bản mới nhất',
                                value:
                                    '${data.latestVersion}+${data.latestBuild}',
                              ),
                              _InfoLine(
                                icon: data.forceUpdate
                                    ? Icons.warning_rounded
                                    : Icons.info_outline_rounded,
                                label: 'Trạng thái',
                                value: data.forceUpdate
                                    ? 'Bắt buộc cập nhật'
                                    : (data.updateAvailable
                                          ? 'Có bản cập nhật mới'
                                          : 'Đang là bản mới nhất'),
                              ),
                              if (data.notes.isNotEmpty) ...[
                                const SizedBox(height: CineVietSpacing.lg),
                                const Text(
                                  'Release notes',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: CineVietSpacing.sm),
                                Text(
                                  data.notes,
                                  style: const TextStyle(
                                    color: CineVietColors.textSoft,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                              const SizedBox(height: CineVietSpacing.xl),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: data.apkUrl.isEmpty
                                      ? null
                                      : () => launchUrl(
                                          Uri.parse(data.apkUrl),
                                          mode: LaunchMode.externalApplication,
                                        ),
                                  icon: const Icon(Icons.download_rounded),
                                  label: Text(
                                    data.updateAvailable || data.forceUpdate
                                        ? 'Tải bản cập nhật'
                                        : 'Tải APK hiện tại',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CineVietSpacing.lg),
                  const Text(
                    'Ghi chú: Android không cho app tự cài APK im lặng. Nút tải sẽ mở link tải APK chính thức, sau đó user xác nhận cài đặt theo hệ thống.',
                    style: TextStyle(
                      color: CineVietColors.textSoft,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CineVietSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: CineVietColors.accent, size: 22),
          const SizedBox(width: CineVietSpacing.md),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: CineVietColors.textSoft),
            ),
          ),
          const SizedBox(width: CineVietSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
