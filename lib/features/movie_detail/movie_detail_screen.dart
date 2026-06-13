import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../player/cineviet_player_screen.dart';
import '../player/resume_player_loader_screen.dart';
import '../search/search_browse_screen.dart';
import '../watch_together/watch_together_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';
import '../../data/models/movie.dart';
import '../../data/repositories/movie_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/cloud_history_service.dart';
import '../../data/services/playlist_service.dart';
import '../../data/services/social_service.dart';

class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({super.key, required this.idOrSlug});
  final String idOrSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(movieDetailProvider(idOrSlug));
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: detail.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: CineVietColors.accent),
        ),
        error: (error, stackTrace) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(CineVietSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(height: CineVietSpacing.lg),
                Text(
                  'Không tải được chi tiết phim',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: CineVietSpacing.sm),
                Text(
                  '$error',
                  style: const TextStyle(color: CineVietColors.textSoft),
                ),
                const SizedBox(height: CineVietSpacing.lg),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(movieDetailProvider(idOrSlug)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
        data: (movie) => _AutoResumeDetail(movie: movie),
      ),
    );
  }
}


class _AutoResumeDetail extends ConsumerStatefulWidget {
  const _AutoResumeDetail({required this.movie});
  final Movie movie;

  @override
  ConsumerState<_AutoResumeDetail> createState() => _AutoResumeDetailState();
}

class _AutoResumeDetailState extends ConsumerState<_AutoResumeDetail> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeIfWatched());
  }

  Future<void> _resumeIfWatched() async {
    try {
      final history = await ref.read(syncedWatchHistoryProvider.future);
      for (final item in history) {
        if (item.movieId == widget.movie.id ||
            (widget.movie.slug.isNotEmpty && item.slug == widget.movie.slug)) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ResumePlayerLoaderScreen(item: item),
            ),
          );
          return;
        }
      }
    } catch (_) {
      // If history cannot be loaded, keep the normal detail page usable.
    }
  }

  @override
  Widget build(BuildContext context) => _MovieDetailContent(movie: widget.movie);
}

class _MovieDetailContent extends ConsumerStatefulWidget {
  const _MovieDetailContent({required this.movie});
  final Movie movie;

  @override
  ConsumerState<_MovieDetailContent> createState() =>
      _MovieDetailContentState();
}

class _MovieDetailContentState extends ConsumerState<_MovieDetailContent> {
  final ScrollController _scrollController = ScrollController();
  Movie get movie => widget.movie;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRemoteKey);
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleRemoteKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || !_scrollController.hasClients) {
      return false;
    }
    final platform = PlatformDetector.of(context);
    if (!platform.isTv && !platform.isDesktop) return false;
    final key = event.logicalKey;
    final current = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    if (key == LogicalKeyboardKey.pageDown) {
      _scrollTo((current + 720).clamp(0.0, max));
      return true;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _scrollTo((current - 720).clamp(0.0, max));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _scrollTo((current + 260).clamp(0.0, max));
      return false;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _scrollTo((current - 260).clamp(0.0, max));
      return false;
    }
    return false;
  }

  void _scrollTo(double offset) => _scrollController.animateTo(
    offset,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );

  void _openEpisode(int serverIndex, int episodeIndex) {
    final server = movie.episodes[serverIndex];
    final episode = server.items[episodeIndex];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CineVietPlayerScreen(
          movie: movie,
          server: server,
          episode: episode,
        ),
      ),
    );
  }

  void _openWatchTogether() {
    final server = movie.episodes.isNotEmpty ? movie.episodes.first : null;
    final episode = server?.items.isNotEmpty == true
        ? server!.items.first
        : null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchTogetherScreen(
          prefillMovie: movie,
          prefillServer: server,
          prefillEpisode: episode,
        ),
      ),
    );
  }

  Future<void> _shareMovie() async {
    final url =
        'https://cineviet.live/phim/${movie.slug.isNotEmpty ? movie.slug : movie.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã copy link phim: $url')));
  }

  Future<void> _toggleFavorite(bool isFavorite) async {
    try {
      await ref
          .read(authControllerProvider.notifier)
          .toggleFavorite(movie, !isFavorite);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFavorite ? 'Đã bỏ yêu thích' : 'Đã thêm vào danh sách yêu thích',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showAddToPlaylist() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để dùng playlist')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddToPlaylistSheet(movie: movie),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    final favoriteIds = ref
        .watch(favoriteIdsProvider)
        .maybeWhen(data: (ids) => ids, orElse: () => <int>{});
    final isFavorite = favoriteIds.contains(movie.id);
    final padding = platform.isMobile ? CineVietSpacing.md : CineVietSpacing.xl;
    final heroHeight = platform.isMobile
        ? 760.0
        : platform.isTablet
        ? 760.0
        : platform.isDesktop
        ? 780.0
        : 700.0;
    final heroImageUrl = platform.isMobile
        ? (movie.portraitImageUrl ?? movie.landscapeImageUrl)
        : (movie.landscapeImageUrl ?? movie.portraitImageUrl);

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (heroImageUrl != null)
                  CachedNetworkImage(
                    imageUrl: heroImageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (context, url) =>
                        const ColoredBox(color: CineVietColors.bg3),
                    errorWidget: (context, url, error) =>
                        const ColoredBox(color: CineVietColors.bg3),
                  )
                else
                  const ColoredBox(color: CineVietColors.bg3),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.14),
                          CineVietColors.bg.withValues(alpha: 0.99),
                        ],
                        stops: const [0.30, 1],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: platform.isMobile ? 440 : 860,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: CineVietSpacing.sm,
                                runSpacing: CineVietSpacing.sm,
                                children: [
                                  if ((movie.quality ?? '').isNotEmpty)
                                    _Chip(text: movie.quality!),
                                  if ((movie.language ?? '').isNotEmpty)
                                    _Chip(text: movie.language!),
                                  if ((movie.country ?? '').isNotEmpty)
                                    _Chip(text: movie.country!),
                                  if ((movie.episodeCurrent ?? '').isNotEmpty)
                                    _Chip(text: movie.episodeCurrent!),
                                ],
                              ),
                              const SizedBox(height: CineVietSpacing.md),
                              Text(
                                movie.title,
                                style: TextStyle(
                                  fontSize: platform.isTv
                                      ? 48
                                      : platform.isMobile
                                      ? 32
                                      : 42,
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                              if ((movie.titleEn ?? '').isNotEmpty) ...[
                                const SizedBox(height: CineVietSpacing.xs),
                                Text(
                                  movie.titleEn!,
                                  style: const TextStyle(
                                    color: CineVietColors.textSoft,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                              const SizedBox(height: CineVietSpacing.md),
                              Text(
                                movie.metaLine,
                                style: const TextStyle(
                                  color: CineVietColors.textSoft,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: CineVietSpacing.md),
                              Text(
                                movie.description ?? 'Chưa có mô tả.',
                                maxLines: platform.isMobile ? 4 : 5,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CineVietColors.textSoft,
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: CineVietSpacing.lg),
                              _MovieActionGrid(
                                isMobile: platform.isMobile,
                                isTablet: platform.isTablet,
                                isDesktop: platform.isDesktop,
                                isFavorite: isFavorite,
                                canPlay:
                                    movie.episodes.isNotEmpty &&
                                    movie.episodes.first.items.isNotEmpty,
                                onPlay: () => _openEpisode(0, 0),
                                onWatchTogether: _openWatchTogether,
                                onFavorite: () => _toggleFavorite(isFavorite),
                                onPlaylist: _showAddToPlaylist,
                                onShare: _shareMovie,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.all(padding),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const _SectionTitle(title: 'Chọn tập / server'),
              const SizedBox(height: CineVietSpacing.md),
              _EpisodeList(movie: movie, onSelected: _openEpisode),
              const SizedBox(height: CineVietSpacing.xl),
              _SocialSection(movie: movie),
              const SizedBox(height: CineVietSpacing.xl),
              if (movie.related.isNotEmpty) ...[
                const _SectionTitle(title: 'Phim tương tự'),
                const SizedBox(height: CineVietSpacing.md),
                _RelatedRail(movies: movie.related),
              ],
              const SizedBox(height: 96),
            ]),
          ),
        ),
      ],
    );
  }
}

class _MovieActionGrid extends StatelessWidget {
  const _MovieActionGrid({
    required this.isMobile,
    required this.isTablet,
    required this.isDesktop,
    required this.isFavorite,
    required this.canPlay,
    required this.onPlay,
    required this.onWatchTogether,
    required this.onFavorite,
    required this.onPlaylist,
    required this.onShare,
  });

  final bool isMobile;
  final bool isTablet;
  final bool isDesktop;
  final bool isFavorite;
  final bool canPlay;
  final VoidCallback onPlay;
  final VoidCallback onWatchTogether;
  final VoidCallback onFavorite;
  final VoidCallback onPlaylist;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      FilledButton.icon(
        onPressed: canPlay ? onPlay : null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Xem ngay'),
      ),
      OutlinedButton.icon(
        onPressed: canPlay ? onWatchTogether : null,
        icon: const Icon(Icons.groups_rounded),
        label: const Text('Xem chung'),
      ),
      OutlinedButton.icon(
        onPressed: onFavorite,
        icon: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isFavorite ? Colors.redAccent : null,
        ),
        label: Text(isFavorite ? 'Đã yêu thích' : 'Yêu thích'),
      ),
      OutlinedButton.icon(
        onPressed: onPlaylist,
        icon: const Icon(Icons.playlist_add_rounded),
        label: const Text('Thêm playlist'),
      ),
      OutlinedButton.icon(
        onPressed: onShare,
        icon: const Icon(Icons.ios_share_rounded),
        label: const Text('Chia sẻ'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = isMobile
            ? 2
            : isTablet
            ? 3
            : isDesktop
            ? 3
            : 4;
        final itemWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * CineVietSpacing.sm) /
            crossAxisCount;
        return Wrap(
          spacing: CineVietSpacing.sm,
          runSpacing: CineVietSpacing.sm,
          children: actions
              .map(
                (child) => SizedBox(
                  width: itemWidth,
                  height: isMobile ? 56 : 54,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({required this.movie, required this.onSelected});
  final Movie movie;
  final void Function(int serverIndex, int episodeIndex) onSelected;

  @override
  Widget build(BuildContext context) {
    if (movie.episodes.isEmpty) {
      return const Text(
        'Chưa có dữ liệu tập.',
        style: TextStyle(color: CineVietColors.textSoft),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var serverIndex = 0;
          serverIndex < movie.episodes.length;
          serverIndex++
        ) ...[
          Row(
            children: [
              const Icon(
                Icons.dns_rounded,
                color: CineVietColors.accent,
                size: 18,
              ),
              const SizedBox(width: CineVietSpacing.sm),
              Text(
                movie.episodes[serverIndex].displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: CineVietSpacing.sm),
          Wrap(
            spacing: CineVietSpacing.sm,
            runSpacing: CineVietSpacing.sm,
            children: [
              for (
                var episodeIndex = 0;
                episodeIndex < movie.episodes[serverIndex].items.length;
                episodeIndex++
              )
                _EpisodeButton(
                  item: movie.episodes[serverIndex].items[episodeIndex],
                  selected: false,
                  onPressed: () => onSelected(serverIndex, episodeIndex),
                ),
            ],
          ),
          const SizedBox(height: CineVietSpacing.lg),
        ],
      ],
    );
  }
}

class _EpisodeButton extends StatefulWidget {
  const _EpisodeButton({
    required this.item,
    required this.selected,
    required this.onPressed,
  });
  final EpisodeItem item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_EpisodeButton> createState() => _EpisodeButtonState();
}

class _EpisodeButtonState extends State<_EpisodeButton> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || focused;
    return Focus(
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CineVietRadius.full),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: CineVietColors.accent.withValues(alpha: 0.26),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: widget.selected
                ? CineVietColors.accentSoft
                : active
                ? CineVietColors.cardHover
                : CineVietColors.card,
            side: BorderSide(
              color: active
                  ? CineVietColors.accent
                  : CineVietColors.borderLight,
              width: active ? 2 : 1,
            ),
            foregroundColor: active
                ? CineVietColors.accent
                : CineVietColors.text,
            padding: const EdgeInsets.symmetric(
              horizontal: CineVietSpacing.md,
              vertical: CineVietSpacing.md,
            ),
          ),
          onPressed: widget.onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.selected) ...[
                const Icon(Icons.check_circle_rounded, size: 17),
                const SizedBox(width: CineVietSpacing.xs),
              ],
              Text(
                widget.item.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialSection extends ConsumerStatefulWidget {
  const _SocialSection({required this.movie});
  final Movie movie;

  int get movieId => movie.id;

  @override
  ConsumerState<_SocialSection> createState() => _SocialSectionState();
}

class _SocialSectionState extends ConsumerState<_SocialSection> {
  final TextEditingController _controller = TextEditingController();
  int _selectedRating = 0;
  bool _spoiler = false;
  bool _submitting = false;
  bool _ratingSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final auth = ref.read(authControllerProvider);
    if (!auth.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để bình luận.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(socialServiceProvider)
          .addComment(widget.movieId, text, isSpoiler: _spoiler);
      _controller.clear();
      _spoiler = false;
      ref.invalidate(movieCommentsProvider(widget.movieId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã gửi bình luận.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _rate(int rating) async {
    final auth = ref.read(authControllerProvider);
    if (!auth.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để đánh giá.')),
      );
      return;
    }
    setState(() {
      _selectedRating = rating;
      _ratingSubmitting = true;
    });
    try {
      await ref.read(socialServiceProvider).rateMovie(widget.movieId, rating);
      ref.invalidate(movieRatingStatsProvider(widget.movieId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu đánh giá.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _ratingSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(movieCommentsProvider(widget.movieId));
    final ratingStats = ref.watch(movieRatingStatsProvider(widget.movieId));
    final loggedIn = ref.watch(authControllerProvider).loggedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ratingStats.when(
          loading: () => _RatingBox(
            average: 0,
            total: 0,
            userRating: _selectedRating,
            enabled: loggedIn,
            submitting: _ratingSubmitting,
            onChanged: _rate,
          ),
          error: (_, _) => _RatingBox(
            average: 0,
            total: 0,
            userRating: _selectedRating,
            enabled: loggedIn,
            submitting: _ratingSubmitting,
            onChanged: _rate,
          ),
          data: (stats) => _RatingBox(
            average: stats.average,
            total: stats.total,
            userRating: _selectedRating > 0
                ? _selectedRating
                : stats.userRating,
            enabled: loggedIn,
            submitting: _ratingSubmitting,
            onChanged: _rate,
          ),
        ),
        if (widget.movie.cast.isNotEmpty) ...[
          const SizedBox(height: CineVietSpacing.xl),
          _PeopleCard(
            title: 'Diễn viên',
            icon: Icons.groups_rounded,
            people: widget.movie.cast.take(24).toList(),
          ),
        ],
        if (widget.movie.directors.isNotEmpty) ...[
          const SizedBox(height: CineVietSpacing.xl),
          _PeopleCard(
            title: 'Đạo diễn',
            icon: Icons.movie_creation_rounded,
            people: widget.movie.directors,
          ),
        ],
        const SizedBox(height: CineVietSpacing.xl),
        const _SectionTitle(title: 'Bình luận'),
        const SizedBox(height: CineVietSpacing.md),
        TvFocus(
          borderRadius: BorderRadius.circular(CineVietRadius.xl),
          padding: EdgeInsets.zero,
          scale: 1.01,
          enabled: PlatformDetector.of(context).isTv,
          child: Container(
            padding: const EdgeInsets.all(CineVietSpacing.md),
            decoration: BoxDecoration(
              color: CineVietColors.card,
              borderRadius: BorderRadius.circular(CineVietRadius.xl),
              border: Border.all(color: CineVietColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  enabled: loggedIn && !_submitting,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: loggedIn
                        ? 'Viết bình luận về phim...'
                        : 'Đăng nhập để bình luận',
                    filled: true,
                    fillColor: CineVietColors.bg2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CineVietRadius.lg),
                      borderSide: const BorderSide(
                        color: CineVietColors.border,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: CineVietSpacing.sm),
                Wrap(
                  spacing: CineVietSpacing.sm,
                  runSpacing: CineVietSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Có spoiler'),
                      selected: _spoiler,
                      onSelected: loggedIn
                          ? (v) => setState(() => _spoiler = v)
                          : null,
                    ),
                    FilledButton.icon(
                      onPressed: loggedIn && !_submitting ? _submit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('Gửi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: CineVietSpacing.md),
        comments.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(CineVietSpacing.lg),
              child: CircularProgressIndicator(color: CineVietColors.accent),
            ),
          ),
          error: (e, _) => Text(
            'Không tải được bình luận: $e',
            style: const TextStyle(color: CineVietColors.textSoft),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const Text(
                'Chưa có bình luận. Hãy là người đầu tiên nhé.',
                style: TextStyle(color: CineVietColors.textSoft),
              );
            }
            return Column(
              children: [
                for (final item in items.take(20))
                  _CommentTile(movieId: widget.movieId, comment: item),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PeopleCard extends StatelessWidget {
  const _PeopleCard({
    required this.title,
    required this.icon,
    required this.people,
  });
  final String title;
  final IconData icon;
  final List<MoviePerson> people;

  void _openSearch(BuildContext context, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchBrowseScreen(initialSearch: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CineVietSpacing.md),
      decoration: BoxDecoration(
        color: CineVietColors.card,
        borderRadius: BorderRadius.circular(CineVietRadius.xl),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CineVietColors.accentSoft,
                  borderRadius: BorderRadius.circular(CineVietRadius.md),
                ),
                child: Icon(icon, color: CineVietColors.accent, size: 20),
              ),
              const SizedBox(width: CineVietSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${people.length} ${title.toLowerCase()}',
                    style: const TextStyle(color: CineVietColors.textSoft),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CineVietSpacing.md),
          if (platform.isTv)
            Wrap(
              spacing: CineVietSpacing.sm,
              runSpacing: CineVietSpacing.sm,
              children: [
                for (final person in people)
                  _PersonMiniCard(
                    person: person,
                    onTap: () => _openSearch(context, person.name),
                  ),
              ],
            )
          else
            SizedBox(
              height: platform.isMobile ? 106 : 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: people.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: CineVietSpacing.sm),
                itemBuilder: (context, index) {
                  final person = people[index];
                  return _PersonMiniCard(
                    person: person,
                    onTap: () => _openSearch(context, person.name),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonMiniCard extends StatelessWidget {
  const _PersonMiniCard({required this.person, required this.onTap});
  final MoviePerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TvFocus(
    borderRadius: BorderRadius.circular(CineVietRadius.lg),
    onTap: onTap,
    child: Container(
      width: 92,
      padding: const EdgeInsets.all(CineVietSpacing.sm),
      decoration: BoxDecoration(
        color: CineVietColors.bg2,
        borderRadius: BorderRadius.circular(CineVietRadius.lg),
        border: Border.all(color: CineVietColors.borderLight),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: CineVietColors.accentSoft,
            backgroundImage: person.avatarUrl.isNotEmpty
                ? CachedNetworkImageProvider(person.avatarUrl)
                : null,
            child: person.avatarUrl.isEmpty
                ? Text(
                    person.name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: CineVietColors.accent,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: CineVietSpacing.xs),
          Text(
            person.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _RatingBox extends StatelessWidget {
  const _RatingBox({
    required this.average,
    required this.total,
    required this.userRating,
    required this.enabled,
    required this.submitting,
    required this.onChanged,
  });
  final double average;
  final int total;
  final int? userRating;
  final bool enabled;
  final bool submitting;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = userRating ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: CineVietColors.accent,
                  size: 22,
                ),
                const SizedBox(width: CineVietSpacing.xs),
                const Text(
                  'Đánh giá',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const Spacer(),
                Text(
                  average > 0 ? average.toStringAsFixed(1) : '--',
                  style: const TextStyle(
                    color: CineVietColors.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const Text(
                  '/10',
                  style: TextStyle(color: CineVietColors.muted),
                ),
              ],
            ),
            const SizedBox(height: CineVietSpacing.xs),
            Text(
              selected > 0
                  ? 'Bạn đã chọn $selected/10 • $total lượt đánh giá'
                  : total > 0
                  ? '$total lượt đánh giá'
                  : 'Chạm để đánh giá phim',
              style: const TextStyle(color: CineVietColors.textSoft),
            ),
          ],
        );
        final stars = Wrap(
          spacing: compact ? 0 : 2,
          runSpacing: 0,
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          children: [
            for (var i = 1; i <= 10; i++)
              TvFocus(
                borderRadius: BorderRadius.circular(CineVietRadius.full),
                scale: 1.12,
                onTap: enabled && !submitting ? () => onChanged(i) : null,
                enabled: enabled && !submitting,
                child: SizedBox(
                  width: compact ? 32 : 40,
                  height: compact ? 36 : 40,
                  child: Icon(
                    i <= selected
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: compact ? 24 : 28,
                    color: CineVietColors.accent,
                  ),
                ),
              ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(CineVietSpacing.sm),
          decoration: BoxDecoration(
            color: CineVietColors.card,
            borderRadius: BorderRadius.circular(CineVietRadius.xl),
            border: Border.all(color: CineVietColors.border),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CineVietSpacing.sm,
                        vertical: CineVietSpacing.xs,
                      ),
                      child: info,
                    ),
                    const SizedBox(height: CineVietSpacing.xs),
                    stars,
                    if (submitting) ...[
                      const SizedBox(height: CineVietSpacing.xs),
                      const LinearProgressIndicator(
                        minHeight: 2,
                        color: CineVietColors.accent,
                      ),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CineVietSpacing.sm,
                        ),
                        child: info,
                      ),
                    ),
                    const SizedBox(width: CineVietSpacing.sm),
                    Flexible(child: stars),
                    if (submitting) ...[
                      const SizedBox(width: CineVietSpacing.sm),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.movieId, required this.comment});
  final int movieId;
  final dynamic comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: CineVietSpacing.sm),
      padding: const EdgeInsets.all(CineVietSpacing.md),
      decoration: BoxDecoration(
        color: CineVietColors.card,
        borderRadius: BorderRadius.circular(CineVietRadius.lg),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: CineVietColors.accentSoft,
            backgroundImage: (comment.userAvatar ?? '').isNotEmpty
                ? NetworkImage(comment.userAvatar!)
                : null,
            child: (comment.userAvatar ?? '').isEmpty
                ? Text(
                    (comment.userName ?? 'U').trim().isEmpty
                        ? 'U'
                        : (comment.userName ?? 'U').trim()[0].toUpperCase(),
                  )
                : null,
          ),
          const SizedBox(width: CineVietSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.userName ?? 'Thành viên',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CineVietSpacing.xs),
                if (comment.isSpoiler)
                  const Text(
                    '⚠️ Có spoiler',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(comment.content, style: const TextStyle(height: 1.45)),
                const SizedBox(height: CineVietSpacing.xs),
                TextButton.icon(
                  onPressed: () async {
                    final auth = ref.read(authControllerProvider);
                    if (!auth.loggedIn) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vui lòng đăng nhập để thả tim.'),
                        ),
                      );
                      return;
                    }
                    await ref
                        .read(socialServiceProvider)
                        .toggleLike(movieId, comment.id);
                    ref.invalidate(movieCommentsProvider(movieId));
                  },
                  icon: Icon(
                    comment.userLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 18,
                  ),
                  label: Text('${comment.likeCount}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.movie});

  final Movie movie;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  int? _addingId;

  Future<void> _createAndAdd() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    var isPublic = false;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: CineVietColors.bg2,
          title: const Text('Tạo playlist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Tên playlist',
                  hintText: 'Ví dụ: Phim muốn xem',
                ),
              ),
              const SizedBox(height: CineVietSpacing.sm),
              TextField(
                controller: descriptionController,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  hintText: 'Không bắt buộc',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: isPublic,
                activeThumbColor: CineVietColors.accent,
                title: const Text('Công khai'),
                subtitle: const Text('Cho phép chia sẻ playlist trên website'),
                onChanged: saving
                    ? null
                    : (value) => setDialogState(() => isPublic = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Tên playlist không được để trống'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final playlist = await ref
                            .read(playlistServiceProvider)
                            .create(
                              name: name,
                              description: descriptionController.text.trim(),
                              isPublic: isPublic,
                            );
                        await ref
                            .read(playlistServiceProvider)
                            .addMovie(playlist.id, widget.movie.id);
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        Navigator.of(this.context).pop();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Đã tạo playlist và thêm vào "${playlist.name}"',
                            ),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceFirst('Exception: ', ''),
                            ),
                          ),
                        );
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: const Text('Tạo'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _add(CineVietPlaylist playlist) async {
    setState(() => _addingId = playlist.id);
    try {
      await ref
          .read(playlistServiceProvider)
          .addMovie(playlist.id, widget.movie.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm vào playlist "${playlist.name}"')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _addingId = null);
      final data = e.response?.data;
      final message = data is Map
          ? '${data['error'] ?? data['message'] ?? 'Không thêm được vào playlist'}'
          : 'Không thêm được vào playlist';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(myPlaylistsProvider);
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .72,
        ),
        decoration: const BoxDecoration(
          color: CineVietColors.bg2,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CineVietRadius.xl),
          ),
          border: Border(top: BorderSide(color: CineVietColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(
          CineVietSpacing.lg,
          CineVietSpacing.md,
          CineVietSpacing.lg,
          CineVietSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: CineVietColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: CineVietSpacing.lg),
            const Row(
              children: [
                Icon(Icons.playlist_add_rounded, color: CineVietColors.accent),
                SizedBox(width: CineVietSpacing.sm),
                Text(
                  'Thêm vào playlist',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: CineVietSpacing.xs),
            Text(
              widget.movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CineVietColors.textSoft),
            ),
            const SizedBox(height: CineVietSpacing.md),
            OutlinedButton.icon(
              onPressed: _createAndAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tạo playlist mới'),
            ),
            const SizedBox(height: CineVietSpacing.lg),
            Expanded(
              child: playlists.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: CineVietColors.accent,
                  ),
                ),
                error: (error, stackTrace) => Center(
                  child: Text(
                    'Không tải được playlist: $error',
                    style: const TextStyle(color: CineVietColors.textSoft),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Chưa có playlist nào.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: CineVietColors.textSoft),
                          ),
                          const SizedBox(height: CineVietSpacing.md),
                          FilledButton.icon(
                            onPressed: _createAndAdd,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Tạo playlist mới'),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: CineVietSpacing.sm),
                    itemBuilder: (context, index) {
                      final playlist = items[index];
                      final adding = _addingId == playlist.id;
                      return TvFocus(
                        onTap: adding ? null : () => _add(playlist),
                        borderRadius: BorderRadius.circular(CineVietRadius.lg),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: CineVietSpacing.md,
                            vertical: CineVietSpacing.xs,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              CineVietRadius.lg,
                            ),
                            side: const BorderSide(
                              color: CineVietColors.border,
                            ),
                          ),
                          tileColor: CineVietColors.card,
                          leading: const Icon(
                            Icons.playlist_play_rounded,
                            color: CineVietColors.accent,
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text('${playlist.movieCount} phim'),
                          trailing: adding
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: CineVietColors.accent,
                                  ),
                                )
                              : const Icon(Icons.add_rounded),
                          onTap: adding ? null : () => _add(playlist),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelatedRail extends StatelessWidget {
  const _RelatedRail({required this.movies});
  final List<Movie> movies;

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    final children = [
      for (final movie in movies)
        _RelatedMovieCard(
          movie: movie,
          onTap: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MovieDetailScreen(idOrSlug: movie.slug),
            ),
          ),
        ),
    ];

    if (platform.isTv) {
      return Wrap(
        spacing: CineVietSpacing.md,
        runSpacing: CineVietSpacing.lg,
        children: children,
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: CineVietSpacing.md),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }
}

class _RelatedMovieCard extends StatelessWidget {
  const _RelatedMovieCard({required this.movie, required this.onTap});
  final Movie movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 318,
    child: TvFocus(
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      onTap: onTap,
      builder: (context, focused, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: focused ? CineVietColors.cardHover : Colors.transparent,
          borderRadius: BorderRadius.circular(CineVietRadius.lg),
        ),
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            height: 225,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CineVietRadius.lg),
              child: movie.posterUrl == null
                  ? const ColoredBox(color: CineVietColors.card)
                  : CachedNetworkImage(
                      imageUrl: movie.posterUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
            ),
          ),
          const SizedBox(height: CineVietSpacing.sm),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: CineVietSpacing.xs),
          Text(
            movie.englishTitleLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: CineVietColors.textSoft,
            ),
          ),
          const SizedBox(height: CineVietSpacing.xs),
          Text(
            movie.yearLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: CineVietColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CineVietSpacing.sm,
      vertical: CineVietSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: CineVietColors.accentSoft,
      borderRadius: BorderRadius.circular(CineVietRadius.full),
      border: Border.all(color: CineVietColors.accent.withValues(alpha: 0.45)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: CineVietColors.accent,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );
}
