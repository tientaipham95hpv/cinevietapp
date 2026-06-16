import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';
import '../../data/models/movie.dart';
import '../../data/models/watch_history.dart';
import '../../data/repositories/movie_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/cloud_history_service.dart';
import '../player/resume_navigation.dart';

final cinemaMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).cinema(limit: 14),
);
final seriesMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).byType('series', limit: 14),
);
final singleMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).byType('movie', limit: 14),
);
final animeMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).byType('anime', limit: 14),
);
final tvShowsMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref.watch(movieRepositoryProvider).byType('tvshows', limit: 14),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final FocusScopeNode _contentFocusScope = FocusScopeNode(
    debugLabel: 'homeContent',
  );
  final Set<String> _prefetchedPosters = <String>{};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRemoteKey);
    _contentFocusScope.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleRemoteKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || !_scrollController.hasClients) {
      return false;
    }
    final platform = PlatformDetector.of(context);
    if (!platform.isTv && !platform.isDesktop) return false;
    // Chỉ cuộn home khi focus thực sự nằm trong nội dung home. Nếu focus đang ở
    // sidebar (chọn menu), không cuộn danh sách phim theo.
    if (!_contentFocusScope.hasFocus) return false;

    final current = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    const step = 360.0;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _animateTo((current + step).clamp(0.0, max));
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _animateTo((current - step).clamp(0.0, max));
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _animateTo((current + 760).clamp(0.0, max));
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _animateTo((current - 760).clamp(0.0, max));
      return true;
    }
    return false;
  }

  void _animateTo(double offset) {
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _prefetchPosters(BuildContext context, Iterable<Movie> movies) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final movie in movies) {
        final url = movie.posterUrl ?? movie.backdropUrl;
        if (url == null || url.isEmpty || _prefetchedPosters.contains(url)) {
          continue;
        }
        _prefetchedPosters.add(url);
        precacheImage(CachedNetworkImageProvider(url), context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    final auth = ref.watch(authControllerProvider);
    final featured = ref.watch(featuredMoviesProvider);
    final latest = ref.watch(latestMoviesProvider);
    final cinema = ref.watch(cinemaMoviesProvider);
    final series = ref.watch(seriesMoviesProvider);
    final single = ref.watch(singleMoviesProvider);
    final anime = ref.watch(animeMoviesProvider);
    final tvShows = ref.watch(tvShowsMoviesProvider);
    final history = ref.watch(syncedWatchHistoryProvider);

    final featuredMovies = featured.maybeWhen(
      data: (v) => v,
      orElse: () => const <Movie>[],
    );
    final latestMovies = latest.maybeWhen(
      data: (v) => v,
      orElse: () => const <Movie>[],
    );
    _prefetchPosters(context, [
      ...featuredMovies.take(8),
      ...latestMovies.take(8),
    ]);

    final contentPadding = platform.isMobile
        ? CineVietSpacing.md
        : CineVietSpacing.xl;
    final cardWidth = platform.isMobile
        ? 132.0
        : platform.isTablet
        ? 168.0
        : 210.0;
    final heroHeight = platform.isMobile
        ? 520.0
        : platform.isTablet
        ? 560.0
        : 640.0;

    return FocusScope(
      node: _contentFocusScope,
      child: RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(featuredMoviesProvider);
        ref.invalidate(latestMoviesProvider);
        ref.invalidate(cinemaMoviesProvider);
        ref.invalidate(seriesMoviesProvider);
        ref.invalidate(singleMoviesProvider);
        ref.invalidate(animeMoviesProvider);
        ref.invalidate(tvShowsMoviesProvider);
        ref.invalidate(syncedWatchHistoryProvider);
        await Future.wait([
          ref.read(featuredMoviesProvider.future),
          ref.read(latestMoviesProvider.future),
          ref.read(cinemaMoviesProvider.future),
          ref.read(seriesMoviesProvider.future),
          ref.read(singleMoviesProvider.future),
          ref.read(animeMoviesProvider.future),
          ref.read(tvShowsMoviesProvider.future),
        ]);
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _FeaturedHeroCarousel(
              data: featured,
              fallback: latestMovies,
              height: heroHeight,
              platform: platform,
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              contentPadding,
              CineVietSpacing.lg,
              contentPadding,
              CineVietSpacing.xl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (auth.loggedIn) ...[
                  _ContinueWatchingSection(
                    data: history,
                    platform: platform,
                    cardWidth: cardWidth,
                  ),
                  const SizedBox(height: CineVietSpacing.xl),
                ],
                _HomeMovieSection(
                  title: 'Phim mới cập nhật',
                  icon: Icons.new_releases_rounded,
                  data: latest,
                  cardWidth: cardWidth,
                ),
                _HomeMovieSection(
                  title: 'Phim chiếu rạp',
                  icon: Icons.theaters_rounded,
                  data: cinema,
                  cardWidth: cardWidth,
                ),
                _HomeMovieSection(
                  title: 'Phim bộ',
                  icon: Icons.video_library_rounded,
                  data: series,
                  cardWidth: cardWidth,
                ),
                _HomeMovieSection(
                  title: 'Phim lẻ',
                  icon: Icons.movie_creation_rounded,
                  data: single,
                  cardWidth: cardWidth,
                ),
                _HomeMovieSection(
                  title: 'Anime',
                  icon: Icons.auto_awesome_rounded,
                  data: anime,
                  cardWidth: cardWidth,
                ),
                _HomeMovieSection(
                  title: 'TV Shows',
                  icon: Icons.live_tv_rounded,
                  data: tvShows,
                  cardWidth: cardWidth,
                ),
                const SizedBox(height: 96),
              ]),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _FeaturedHeroCarousel extends ConsumerStatefulWidget {
  const _FeaturedHeroCarousel({
    required this.data,
    required this.fallback,
    required this.height,
    required this.platform,
  });
  final AsyncValue<List<Movie>> data;
  final List<Movie> fallback;
  final double height;
  final PlatformInfo platform;

  @override
  ConsumerState<_FeaturedHeroCarousel> createState() =>
      _FeaturedHeroCarouselState();
}

class _FeaturedHeroCarouselState extends ConsumerState<_FeaturedHeroCarousel> {
  static const _interval = Duration(seconds: 7);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant _FeaturedHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _armTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      final items = _items;
      if (!mounted || items.length <= 1) return;
      setState(() => _index = (_index + 1) % items.length);
    });
  }

  List<Movie> get _items {
    final movies = widget.data.maybeWhen(
      data: (v) => v,
      orElse: () => const <Movie>[],
    );
    final source = movies.isNotEmpty ? movies : widget.fallback;
    return source.take(10).toList();
  }

  void _go(int next) {
    final items = _items;
    if (items.isEmpty) return;
    setState(() => _index = (next + items.length) % items.length);
    _armTimer();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (widget.data.isLoading && items.isEmpty) {
      return SizedBox(height: widget.height, child: const _HeroSkeleton());
    }
    if (items.isEmpty) {
      return SizedBox(height: widget.height, child: const _HeroSkeleton());
    }
    final safeIndex = _index.clamp(0, items.length - 1);
    final movie = items[safeIndex];
    final image = widget.platform.isMobile
        ? movie.portraitImageUrl
        : movie.landscapeImageUrl;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd:
          widget.platform.isMobile ||
              widget.platform.isTablet ||
              widget.platform.isDesktop
          ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -160) _go(safeIndex + 1);
              if (velocity > 160) _go(safeIndex - 1);
            }
          : null,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 650),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(movie.id),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image != null)
                      CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        alignment: widget.platform.isMobile
                            ? Alignment.topCenter
                            : Alignment.center,
                        placeholder: (context, url) =>
                            const ColoredBox(color: CineVietColors.bg3),
                        errorWidget: (context, url, error) =>
                            const ColoredBox(color: CineVietColors.bg3),
                      )
                    else
                      const ColoredBox(color: CineVietColors.bg3),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Colors.transparent,
                            CineVietColors.bg.withValues(
                              alpha: widget.platform.isMobile ? 0.46 : 0.62,
                            ),
                            CineVietColors.bg.withValues(
                              alpha: widget.platform.isMobile ? 0.82 : 0.96,
                            ),
                          ],
                          stops: const [0.0, 0.50, 1.0],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(
                              alpha: widget.platform.isMobile ? 0.04 : 0.10,
                            ),
                            Colors.transparent,
                            CineVietColors.bg.withValues(
                              alpha: widget.platform.isMobile ? 0.84 : 1.0,
                            ),
                          ],
                          stops: const [0.0, 0.56, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.platform.isMobile
                      ? CineVietSpacing.md
                      : CineVietSpacing.xl,
                  CineVietSpacing.lg,
                  widget.platform.isMobile
                      ? CineVietSpacing.md
                      : CineVietSpacing.xl,
                  CineVietSpacing.xl,
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.platform.isMobile ? 390 : 760,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Wrap(
                          spacing: CineVietSpacing.sm,
                          runSpacing: CineVietSpacing.xs,
                          children: [
                            _HeroPill(
                              icon: Icons.star_rounded,
                              text: 'Phim nổi bật',
                            ),
                          ],
                        ),
                        const SizedBox(height: CineVietSpacing.md),
                        Text(
                          movie.title,
                          maxLines: widget.platform.isMobile ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.platform.isTv
                                ? 48
                                : widget.platform.isMobile
                                ? 32
                                : 42,
                            height: 1.04,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: CineVietSpacing.sm),
                        Text(
                          movie.metaLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CineVietColors.textSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: CineVietSpacing.sm),
                        Text(
                          (movie.description ?? '').isNotEmpty
                              ? movie.description!
                              : 'Cập nhật phim mới nhanh, chất lượng cao trên CineViet.',
                          maxLines: widget.platform.isMobile ? 3 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.platform.isMobile ? 14 : 16,
                            color: CineVietColors.textSoft,
                            height: 1.48,
                          ),
                        ),
                        const SizedBox(height: CineVietSpacing.lg),
                        _HeroButton(
                          movie: movie,
                          label: 'Xem ngay',
                          icon: Icons.play_arrow_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (items.length > 1) ...[
              Positioned(
                right: widget.platform.isMobile
                    ? CineVietSpacing.md
                    : CineVietSpacing.xl,
                bottom: widget.platform.isMobile ? 22 : 34,
                child: Row(
                  children: List.generate(
                    items.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == safeIndex ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == safeIndex
                            ? CineVietColors.accent
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.platform.isTv)
                Positioned(
                  right: widget.platform.isMobile
                      ? CineVietSpacing.md
                      : CineVietSpacing.xl,
                  top: widget.platform.isMobile ? 92 : 120,
                  child: Column(
                    children: [
                      _HeroArrow(
                        icon: Icons.keyboard_arrow_up_rounded,
                        onTap: () => _go(safeIndex - 1),
                      ),
                      const SizedBox(height: CineVietSpacing.sm),
                      _HeroArrow(
                        icon: Icons.keyboard_arrow_down_rounded,
                        onTap: () => _go(safeIndex + 1),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: CineVietColors.bg3,
    child: Center(
      child: CircularProgressIndicator(color: CineVietColors.accent),
    ),
  );
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({this.icon, required this.text});
  final IconData? icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CineVietSpacing.md,
      vertical: CineVietSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.42),
      border: Border.all(color: Colors.white24),
      borderRadius: BorderRadius.circular(CineVietRadius.full),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: CineVietColors.accent, size: 16),
          const SizedBox(width: CineVietSpacing.xs),
        ],
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ],
    ),
  );
}

class _HeroArrow extends StatelessWidget {
  const _HeroArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TvFocus(
    onTap: onTap,
    borderRadius: BorderRadius.circular(CineVietRadius.full),
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.44),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: Icon(icon, color: Colors.white),
    ),
  );
}

class _HeroButton extends ConsumerWidget {
  const _HeroButton({
    required this.movie,
    required this.label,
    required this.icon,
  });
  final Movie movie;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: CineVietColors.accent,
      foregroundColor: CineVietColors.bg,
      padding: const EdgeInsets.symmetric(
        horizontal: CineVietSpacing.lg,
        vertical: CineVietSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CineVietRadius.full),
        side: BorderSide(color: CineVietColors.accent),
      ),
    ),
    onPressed: () => openMovieOrResume(context, ref, movie),
    icon: Icon(icon),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
  );
}

class _HomeMovieSection extends StatelessWidget {
  const _HomeMovieSection({
    required this.title,
    required this.icon,
    required this.data,
    required this.cardWidth,
  });
  final String title;
  final IconData icon;
  final AsyncValue<List<Movie>> data;
  final double cardWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CineVietSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, icon: icon),
        const SizedBox(height: CineVietSpacing.md),
        _MovieAsyncRail(data: data, cardWidth: cardWidth),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 26,
        decoration: BoxDecoration(
          color: CineVietColors.accent,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      const SizedBox(width: CineVietSpacing.sm),
      Icon(icon, color: CineVietColors.accent, size: 22),
      const SizedBox(width: CineVietSpacing.sm),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ),
    ],
  );
}

class _MovieAsyncRail extends StatelessWidget {
  const _MovieAsyncRail({required this.data, required this.cardWidth});
  final AsyncValue<List<Movie>> data;
  final double cardWidth;

  @override
  Widget build(BuildContext context) => data.when(
    loading: () => SizedBox(
      height: cardWidth * 1.66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (context, index) =>
            const SizedBox(width: CineVietSpacing.md),
        itemBuilder: (context, index) => _SkeletonCard(width: cardWidth),
      ),
    ),
    error: (error, stackTrace) => _RailError(error: error),
    data: (movies) =>
        _MovieRail(movies: movies.take(14).toList(), cardWidth: cardWidth),
  );
}

class _RailError extends StatelessWidget {
  const _RailError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(CineVietSpacing.lg),
    decoration: BoxDecoration(
      color: CineVietColors.card,
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      border: Border.all(color: CineVietColors.border),
    ),
    child: Text(
      'Không tải được danh sách: $error',
      style: const TextStyle(color: CineVietColors.textSoft),
    ),
  );
}

class _MovieRail extends StatelessWidget {
  const _MovieRail({required this.movies, required this.cardWidth});
  final List<Movie> movies;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: cardWidth * 1.5 + 92 + CineVietSpacing.xl,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: CineVietSpacing.sm,
          vertical: CineVietSpacing.sm,
        ),
        itemCount: movies.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: CineVietSpacing.md),
        itemBuilder: (context, index) =>
            _RealMovieCard(movie: movies[index], width: cardWidth),
      ),
    );
  }
}

class _RealMovieCard extends ConsumerWidget {
  const _RealMovieCard({required this.movie, required this.width});
  final Movie movie;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TvFocus(
    onTap: () => openMovieOrResume(context, ref, movie),
    borderRadius: BorderRadius.circular(CineVietRadius.xl),
    padding: const EdgeInsets.all(CineVietSpacing.xs),
    scale: 1.025,
    builder: (context, focused, child) => SizedBox(
      width: width + CineVietSpacing.sm,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: focused ? CineVietColors.cardHover : Colors.transparent,
          borderRadius: BorderRadius.circular(CineVietRadius.xl),
        ),
        child: child,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width,
          height: width * 1.5,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CineVietRadius.lg),
              border: Border.all(color: CineVietColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (movie.posterUrl != null)
                  CachedNetworkImage(
                    imageUrl: movie.posterUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const ColoredBox(color: CineVietColors.bg3),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.local_movies_rounded,
                      color: CineVietColors.accent,
                    ),
                  )
                else
                  const ColoredBox(
                    color: CineVietColors.bg3,
                    child: Icon(
                      Icons.local_movies_rounded,
                      color: CineVietColors.accent,
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.74),
                        ],
                        stops: const [0.56, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: CineVietSpacing.sm,
                  right: CineVietSpacing.sm,
                  child: _Badge(
                    text: movie.quality?.isNotEmpty == true
                        ? movie.quality!
                        : 'HD',
                  ),
                ),
                if ((movie.language ?? '').isNotEmpty)
                  Positioned(
                    left: CineVietSpacing.sm,
                    bottom: CineVietSpacing.sm,
                    child: _Badge(text: _compactLanguage(movie.language!)),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 92,
          width: width,
          child: Padding(
            padding: const EdgeInsets.only(top: CineVietSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  style: const TextStyle(fontSize: 12, color: CineVietColors.textSoft),
                ),
                const SizedBox(height: CineVietSpacing.xs),
                Text(
                  movie.yearLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: CineVietColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

List<WatchHistoryItem> _latestEpisodePerMovie(List<WatchHistoryItem> items) {
  final latestByMovie = <String, WatchHistoryItem>{};
  for (final item in items) {
    final key = item.slug.isNotEmpty ? item.slug : item.movieId.toString();
    final current = latestByMovie[key];
    if (current == null || item.updatedAtMs > current.updatedAtMs) {
      latestByMovie[key] = item;
    }
  }
  final result = latestByMovie.values.toList()
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  return result;
}

class _ContinueWatchingSection extends StatelessWidget {
  const _ContinueWatchingSection({
    required this.data,
    required this.platform,
    required this.cardWidth,
  });
  final AsyncValue<List<WatchHistoryItem>> data;
  final PlatformInfo platform;
  final double cardWidth;

  @override
  Widget build(BuildContext context) => data.when(
    loading: () => const SizedBox.shrink(),
    error: (error, stackTrace) => const SizedBox.shrink(),
    data: (items) {
      final filtered =
          items.where((e) => !e.completed && e.progress > 0.02).toList()
            ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      final displayItems = _latestEpisodePerMovie(filtered);
      if (displayItems.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Xem tiếp',
            icon: Icons.play_circle_outline_rounded,
          ),
          const SizedBox(height: CineVietSpacing.md),
          SizedBox(
            height: platform.isMobile ? 136 : 152,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: displayItems.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: CineVietSpacing.md),
              itemBuilder: (context, index) => _ContinueCard(
                key: ValueKey(displayItems[index].key),
                item: displayItems[index],
                width: platform.isMobile ? 260 : 330,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ContinueCard extends ConsumerStatefulWidget {
  const _ContinueCard({super.key, required this.item, required this.width});
  final WatchHistoryItem item;
  final double width;

  @override
  ConsumerState<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends ConsumerState<_ContinueCard> {
  bool _removing = false;

  Future<void> _remove() async {
    if (_removing) return;
    setState(() => _removing = true);
    try {
      await ref.read(cloudHistoryServiceProvider).remove(widget.item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa khỏi Xem tiếp.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _removing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa khỏi Xem tiếp.')),
      );
    }
  }

  Future<void> _openResume() => openWatchHistoryItem(context, widget.item);



  @override
  Widget build(BuildContext context) => TvFocus(
    onTap: _openResume,
    borderRadius: BorderRadius.circular(CineVietRadius.lg),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openResume,
      child: Container(
      width: widget.width,
      padding: const EdgeInsets.all(CineVietSpacing.sm),
      decoration: BoxDecoration(
        color: CineVietColors.card,
        borderRadius: BorderRadius.circular(CineVietRadius.lg),
        border: Border.all(color: CineVietColors.border),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Container(
                width: 96,
                height: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: CineVietColors.bg3,
                  borderRadius: BorderRadius.circular(CineVietRadius.md),
                ),
                child:
                    (widget.item.backdropUrl?.isNotEmpty == true ||
                        widget.item.posterUrl?.isNotEmpty == true)
                    ? CachedNetworkImage(
                        imageUrl: widget.item.backdropUrl?.isNotEmpty == true
                            ? widget.item.backdropUrl!
                            : widget.item.posterUrl!,
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Icons.movie_rounded,
                        color: CineVietColors.accent,
                      ),
              ),
              const SizedBox(width: CineVietSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: CineVietSpacing.xs),
                    Text(
                      '${widget.item.episodeName} • ${(widget.item.progress * 100).round()}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CineVietColors.textSoft,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: CineVietSpacing.sm),
                    LinearProgressIndicator(
                      value: widget.item.progress,
                      backgroundColor: CineVietColors.border,
                      color: CineVietColors.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Tooltip(
              message: 'Xóa khỏi Xem tiếp',
              child: Material(
                color: Colors.black.withValues(alpha: 0.62),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _removing ? null : _remove,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: _removing
                        ? const Padding(
                            padding: EdgeInsets.all(9),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    ),
  );
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.width});
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      decoration: BoxDecoration(
        color: CineVietColors.card,
        borderRadius: BorderRadius.circular(CineVietRadius.lg),
        border: Border.all(color: CineVietColors.border),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CineVietSpacing.sm,
      vertical: CineVietSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: CineVietColors.accentSoft,
      border: Border.all(color: CineVietColors.accent.withValues(alpha: 0.55)),
      borderRadius: BorderRadius.circular(CineVietRadius.full),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        color: CineVietColors.accent,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

String _compactLanguage(String text) => text
    .replaceAll('Vietsub', 'VS')
    .replaceAll('Thuyết Minh', 'TM')
    .replaceAll('Lồng Tiếng', 'LT');

