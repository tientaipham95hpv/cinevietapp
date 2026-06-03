import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/app_notification.dart';
import '../../data/services/notification_service.dart';
import '../theme/cineviet_colors.dart';
import '../theme/cineviet_dimensions.dart';
import 'tv_focus.dart';

class UpdatePrompt extends ConsumerStatefulWidget {
  const UpdatePrompt({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<UpdatePrompt> {
  bool _checked = false;
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (!mounted || _showing) return;
    try {
      final info = await ref.read(notificationServiceProvider).checkVersion();
      if (!mounted || (!info.updateAvailable && !info.forceUpdate)) return;
      _showing = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !info.forceUpdate,
        builder: (_) => _UpdateDialog(info: info),
      );
    } catch (_) {
      // Startup update checks must never block opening the app.
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.info});
  final AppVersionInfo info;

  Future<void> _openDownload() async {
    final uri = Uri.tryParse(info.apkUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final title = info.forceUpdate ? 'Cần cập nhật app' : 'Có bản cập nhật mới';
    return Dialog(
      backgroundColor: CineVietColors.bg2,
      insetPadding: EdgeInsets.all(CineVietSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CineVietRadius.xl),
        side: BorderSide(color: CineVietColors.borderLight),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: EdgeInsets.all(CineVietSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: CineVietColors.accentSoft,
                      borderRadius: BorderRadius.circular(CineVietRadius.lg),
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: CineVietColors.accent,
                    ),
                  ),
                  SizedBox(width: CineVietSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: CineVietSpacing.xs),
                        Text(
                          'Phiên bản ${info.latestVersion}+${info.latestBuild} đã sẵn sàng.',
                          style: const TextStyle(
                            color: CineVietColors.textSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (info.notes.isNotEmpty) ...[
                SizedBox(height: CineVietSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(CineVietSpacing.md),
                  decoration: BoxDecoration(
                    color: CineVietColors.card,
                    borderRadius: BorderRadius.circular(CineVietRadius.lg),
                    border: Border.all(color: CineVietColors.border),
                  ),
                  child: Text(
                    info.notes,
                    style: TextStyle(
                      color: CineVietColors.textSoft,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              SizedBox(height: CineVietSpacing.xl),
              Row(
                children: [
                  if (!info.forceUpdate) ...[
                    Expanded(
                      child: TvFocus(
                        borderRadius: BorderRadius.circular(CineVietRadius.lg),
                        onTap: () => Navigator.of(context).pop(),
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Để sau'),
                        ),
                      ),
                    ),
                    SizedBox(width: CineVietSpacing.md),
                  ],
                  Expanded(
                    child: TvFocus(
                      borderRadius: BorderRadius.circular(CineVietRadius.lg),
                      onTap: _openDownload,
                      child: FilledButton.icon(
                        onPressed: _openDownload,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Cập nhật'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
