import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';

class WatchTogetherScreen extends StatelessWidget {
  const WatchTogetherScreen({super.key});

  static final Uri _watchTogetherUri = Uri.parse(
    'https://cineviet.live/xem-chung',
  );

  Future<void> _openWatchTogether(BuildContext context) async {
    final ok = await launchUrl(
      _watchTogetherUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa mở được trang Xem chung.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1B2F), CineVietColors.bg],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              CineVietSpacing.lg,
              top + CineVietSpacing.xl,
              CineVietSpacing.lg,
              CineVietSpacing.xxl,
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(CineVietSpacing.xl),
                decoration: BoxDecoration(
                  color: CineVietColors.card.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(CineVietRadius.xl),
                  border: Border.all(
                    color: CineVietColors.accent.withValues(alpha: 0.18),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: CineVietColors.accentGlow,
                      blurRadius: 32,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: CineVietColors.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(CineVietRadius.lg),
                        border: Border.all(
                          color: CineVietColors.accent.withValues(alpha: 0.32),
                        ),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: CineVietColors.accent,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: CineVietSpacing.lg),
                    const Text(
                      'Xem chung',
                      style: TextStyle(
                        color: CineVietColors.text,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: CineVietSpacing.sm),
                    Text(
                      'Tạo phòng, mời bạn bè và xem phim đồng bộ với tính năng Xem chung trên website CineViet.',
                      style: TextStyle(
                        color: CineVietColors.textSoft,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: CineVietSpacing.xl),
                    TvFocus(
                      onTap: () => _openWatchTogether(context),
                      borderRadius: BorderRadius.circular(CineVietRadius.full),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CineVietSpacing.lg,
                          vertical: CineVietSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: CineVietColors.accent,
                          borderRadius: BorderRadius.circular(
                            CineVietRadius.full,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: CineVietColors.accentGlow,
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              color: Color(0xFF061A13),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Mở Xem chung',
                              style: TextStyle(
                                color: Color(0xFF061A13),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CineVietSpacing.lg),
              _InfoTile(
                icon: Icons.sync_rounded,
                title: 'Đồng bộ với website',
                text:
                    'Dùng chung phòng xem, mã phòng và playlist từ CineViet web.',
              ),
              _InfoTile(
                icon: Icons.chat_bubble_rounded,
                title: 'Xem cùng bạn bè',
                text:
                    'Vào phòng, chat và điều khiển buổi xem chung theo quyền host.',
              ),
              _InfoTile(
                icon: Icons.tv_rounded,
                title: 'Hỗ trợ TV remote',
                text: 'Nút mở Xem chung có focus rõ để dùng được với D-pad.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: CineVietSpacing.md),
      padding: const EdgeInsets.all(CineVietSpacing.lg),
      decoration: BoxDecoration(
        color: CineVietColors.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(CineVietRadius.lg),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CineVietColors.accent, size: 26),
          const SizedBox(width: CineVietSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: CineVietColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    color: CineVietColors.textSoft,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
