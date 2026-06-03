import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';
import '../../data/models/movie.dart';
import '../../data/services/auth_service.dart';
import '../movie_detail/movie_detail_screen.dart';

class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final platform = PlatformDetector.of(context);
    final padding = platform.isMobile ? CineVietSpacing.md : CineVietSpacing.xl;
    if (!auth.loggedIn) {
      return const Scaffold(
        backgroundColor: CineVietColors.bg,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(CineVietSpacing.xl),
            child: Text(
              'Đăng nhập ở tab Cá nhân để xem danh sách yêu thích.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CineVietColors.textSoft),
            ),
          ),
        ),
      );
    }
    final favs = ref.watch(favoriteMoviesProvider);
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: SafeArea(
        child: favs.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: CineVietColors.accent),
          ),
          error: (e, _) => Center(
            child: Text(
              'Không tải được yêu thích: $e',
              style: const TextStyle(color: CineVietColors.textSoft),
            ),
          ),
          data: (movies) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Yêu thích',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: CineVietSpacing.xs),
                            Text(
                              'Phim yêu thích đã lưu.',
                              style: TextStyle(color: CineVietColors.textSoft),
                            ),
                          ],
                        ),
                      ),
                      if (movies.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _confirmClear(context, ref),
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: const Text('Xóa tất cả'),
                        ),
                    ],
                  ),
                ),
              ),
              if (movies.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Chưa có phim yêu thích.',
                      style: TextStyle(color: CineVietColors.textSoft),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    0,
                    padding,
                    padding + 80,
                  ),
                  sliver: SliverGrid.builder(
                    itemCount: movies.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: platform.isMobile
                          ? 2
                          : platform.isTablet
                          ? 4
                          : 5,
                      mainAxisSpacing: CineVietSpacing.md,
                      crossAxisSpacing: CineVietSpacing.md,
                      childAspectRatio: platform.isMobile ? .62 : .66,
                    ),
                    itemBuilder: (context, i) => _FavCard(movie: movies[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa toàn bộ yêu thích?'),
        content: const Text('Danh sách yêu thích trên tài khoản sẽ bị xóa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).clearFavorites();
  }
}

class _FavCard extends ConsumerStatefulWidget {
  const _FavCard({required this.movie});
  final Movie movie;

  @override
  ConsumerState<_FavCard> createState() => _FavCardState();
}

class _FavCardState extends ConsumerState<_FavCard> {
  final _cardFocusNode = FocusNode();
  final _removeFocusNode = FocusNode();
  bool _cardFocused = false;
  bool _removeFocused = false;

  Movie get movie => widget.movie;

  @override
  void dispose() {
    _cardFocusNode.dispose();
    _removeFocusNode.dispose();
    super.dispose();
  }

  void _openDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(idOrSlug: movie.slug),
      ),
    );
  }

  Future<void> _removeFavorite() async {
    await ref.read(authControllerProvider.notifier).removeFavorite(movie);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã bỏ "${movie.title}" khỏi yêu thích'),
        backgroundColor: CineVietColors.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _cardFocusNode,
    onFocusChange: (value) => setState(() => _cardFocused = value),
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _removeFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        _openDetail();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: TvFocus(
      enabled: false,
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      onTap: _openDetail,
      builder: (context, focused, child) => Container(
        decoration: BoxDecoration(
          color: _cardFocused || _removeFocused
              ? CineVietColors.cardHover
              : CineVietColors.card,
          borderRadius: BorderRadius.circular(CineVietRadius.lg),
          border: Border.all(
            color: _cardFocused || _removeFocused
                ? CineVietColors.accent
                : CineVietColors.border,
            width: _cardFocused || _removeFocused ? 2 : 1,
          ),
          boxShadow: _cardFocused || _removeFocused
              ? const [
                  BoxShadow(
                    color: CineVietColors.accentGlow,
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                movie.posterUrl == null
                    ? const ColoredBox(color: CineVietColors.bg3)
                    : CachedNetworkImage(
                        imageUrl: movie.posterUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                Positioned(
                  right: CineVietSpacing.xs,
                  top: CineVietSpacing.xs,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.62),
                    shape: const CircleBorder(),
                    child: Focus(
                      focusNode: _removeFocusNode,
                      onFocusChange: (value) =>
                          setState(() => _removeFocused = value),
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                            event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _cardFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space) {
                          _removeFavorite().ignore();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _removeFocused
                                ? CineVietColors.accent
                                : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: _removeFocused
                              ? const [
                                  BoxShadow(
                                    color: CineVietColors.accentGlow,
                                    blurRadius: 18,
                                  ),
                                ]
                              : null,
                        ),
                        child: IconButton(
                          tooltip: 'Xóa khỏi yêu thích',
                          onPressed: _removeFavorite,
                          icon: Icon(
                            Icons.close_rounded,
                            color: _removeFocused
                                ? CineVietColors.accent
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(CineVietSpacing.sm),
            child: Row(
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: Colors.redAccent,
                  size: 16,
                ),
                const SizedBox(width: CineVietSpacing.xs),
                Expanded(
                  child: Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
