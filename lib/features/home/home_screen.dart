import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/adaptive_scaffold.dart' show TvSearchFocus;
import '../../core/widgets/tv_focus.dart';
import '../../data/models/movie.dart';
import '../../data/models/watch_history.dart';
import '../../data/repositories/movie_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/cloud_history_service.dart';
import '../../data/services/watch_history_service.dart';
import '../player/resume_navigation.dart';

const bool _isTvBuild = bool.fromEnvironment('APP_IS_TV');
const int _tvHomeSectionLimit = 8;

final cinemaMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref
      .watch(movieRepositoryProvider)
      .cinema(limit: _isTvBuild ? _tvHomeSectionLimit : 14),
);
final seriesMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref
      .watch(movieRepositoryProvider)
      .byType('series', limit: _isTvBuild ? _tvHomeSectionLimit : 14),
);
final singleMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref
      .watch(movieRepositoryProvider)
      .byType('movie', limit: _isTvBuild ? _tvHomeSectionLimit : 14),
);
final animeMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref
      .watch(movieRepositoryProvider)
      .byType('anime', limit: _isTvBuild ? _tvHomeSectionLimit : 14),
);
final tvShowsMoviesProvider = FutureProvider<List<Movie>>(
  (ref) => ref
      .watch(movieRepositoryProvider)
      .byType('tvshows', limit: _isTvBuild ? _tvHomeSectionLimit : 14),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _prefetchedPosters = <String>{};
  ValueNotifier<int>? _searchFocusSignal;
  FocusNode? _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_keepHeroPinnedForSearchFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextSignal = TvSearchFocus.searchFocusSignalOf(context);
    final nextSearchNode = TvSearchFocus.maybeOf(context);
    if (_searchFocusSignal != nextSignal) {
      _searchFocusSignal?.removeListener(_forceTvHeroTop);
      _searchFocusSignal = nextSignal;
      _searchFocusSignal?.addListener(_forceTvHeroTop);
    }
    _searchFocusNode = nextSearchNode;
  }

  @override
  void dispose() {
    _searchFocusSignal?.removeListener(_forceTvHeroTop);
    _scrollController.removeListener(_keepHeroPinnedForSearchFocus);
    _scrollController.dispose();
    super.dispose();
  }

  void _keepHeroPinnedForSearchFocus() {
    if (!_isTvBuild) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (_searchFocusNode?.hasFocus == true &&
        pos.pixels > pos.minScrollExtent + 1) {
      _forceTvHeroTop();
      return;
    }

    // Android TV focus scrolling can park Home halfway between the hero and
    // first rail. When the user is moving back upward in that boundary area,
    // always restore the hero to the top instead of leaving a half-visible
    // "Phim nổi bật" header.
    if (pos.userScrollDirection == ScrollDirection.forward &&
        pos.pixels > pos.minScrollExtent + 1 &&
        pos.pixels < _tvHeroSnapBoundary) {
      _forceTvHeroTop();
    }
  }

  double get _tvHeroSnapBoundary => 820;

  void _forceTvHeroTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    });
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    });
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    });
  }

  bool _snapTvHeroIfPartial(double heroHeight) {
    if (!_isTvBuild || !_scrollController.hasClients) return false;
    final pos = _scrollController.position;
    if (pos.pixels <= pos.minScrollExtent + 1) return false;
    // On Android TV, D-pad focus/scroll can leave the viewport parked in the
    // hero/first-rail boundary. Visually that makes "Phim nổi bật" show only
    // the lower half when the user scrolls back up. If the scroll rests above
    // the first full rail, normalize it all the way back to the hero top.
    final firstRailBoundary = heroHeight + 260;
    if (pos.pixels < firstRailBoundary) {
      _forceTvHeroTop();
      return true;
    }
    return false;
  }

  void _prefetchPosters(BuildContext context, Iterable<Movie> movies) {
    if (PlatformDetector.of(context).isTv) return;
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
    final localHistory = ref.watch(watchHistoryProvider);
    final heroFocusNode = platform.isTv ? TvSearchFocus.heroOf(context) : null;

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

    final continueWatchingItems = _continueWatchingItems(history, localHistory);

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
        : platform.isTv
        ? (MediaQuery.sizeOf(context).height * 0.48).clamp(320.0, 420.0)
        : 640.0;

    if (platform.isTv) {
      // TV home uses a split layout: the hero is fixed, only the rails below
      // scroll. This removes the bad intermediate state where the vertical
      // scroll position can stop halfway through the hero and show "Phim nổi
      // bật" clipped after moving down then back up with a remote.
      return Column(
        children: [
          SizedBox(
            height: heroHeight,
            child: _FeaturedHeroCarousel(
              data: featured,
              fallback: latestMovies,
              height: heroHeight,
              platform: platform,
              onHeroFocusChanged: (focused) {
                if (focused) _forceTvHeroTop();
              },
            ),
          ),
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    contentPadding,
                    CineVietSpacing.lg,
                    contentPadding,
                    CineVietSpacing.xl,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (auth.loggedIn ||
                          continueWatchingItems.isNotEmpty) ...[
                        _ContinueWatchingSection(
                          items: continueWatchingItems,
                          platform: platform,
                          cardWidth: cardWidth,
                        ),
                        const SizedBox(height: CineVietSpacing.xl),
                      ],
                      _HomeMovieSection(
                        title: 'Top CineViet',
                        icon: Icons.star_rounded,
                        data: featured,
                        fallbackMovies: latestMovies,
                        cardWidth: cardWidth,
                        skipFirstMovie: true,
                        upFocusNode: heroFocusNode,
                        onRequestHeroFocus: () {
                          _forceTvHeroTop();
                        },
                      ),
                      _HomeMovieSection(
                        title: 'Mới cập nhật hôm nay',
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
        ],
      );
    }

    return RefreshIndicator(
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
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (!platform.isTv) return false;
          if (notification is ScrollEndNotification) {
            return _snapTvHeroIfPartial(heroHeight);
          }
          if (notification is UserScrollNotification &&
              notification.direction == ScrollDirection.idle) {
            return _snapTvHeroIfPartial(heroHeight);
          }
          return false;
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
                onHeroFocusChanged: platform.isTv
                    ? (focused) {
                        if (focused) _forceTvHeroTop();
                      }
                    : null,
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
                  if (auth.loggedIn || continueWatchingItems.isNotEmpty) ...[
                    _ContinueWatchingSection(
                      items: continueWatchingItems,
                      platform: platform,
                      cardWidth: cardWidth,
                    ),
                    const SizedBox(height: CineVietSpacing.xl),
                  ],
                  _HomeMovieSection(
                    title: 'Mới cập nhật hôm nay',
                    icon: Icons.new_releases_rounded,
                    data: latest,
                    cardWidth: cardWidth,
                    upFocusNode: heroFocusNode,
                    onRequestHeroFocus: platform.isTv
                        ? () {
                            _forceTvHeroTop();
                          }
                        : null,
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
    this.onHeroFocusChanged,
  });
  final AsyncValue<List<Movie>> data;
  final List<Movie> fallback;
  final double height;
  final PlatformInfo platform;
  final ValueChanged<bool>? onHeroFocusChanged;

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
    if (!widget.platform.isTv) _armTimer();
  }

  @override
  void didUpdateWidget(covariant _FeaturedHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.platform.isTv) {
      _timer?.cancel();
      if (_index >= _items.length) _index = 0;
    } else {
      _armTimer();
    }
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
    final preferred = widget.platform.isTv
        ? source.where((movie) => movie.landscapeImageUrl != null).toList()
        : source;
    final items = preferred.isNotEmpty ? preferred : source;
    return items.take(widget.platform.isTv ? 8 : 10).toList();
  }

  void _go(int next) {
    final items = _items;
    if (items.isEmpty) return;
    setState(() => _index = (next + items.length) % items.length);
    _armTimer();
  }

  void _focusFirstRail() {
    FocusScope.of(context).focusInDirection(TraversalDirection.down);
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
                        fit: widget.platform.isTv
                            ? BoxFit.contain
                            : BoxFit.cover,
                        memCacheWidth: widget.platform.isTv ? 960 : null,
                        maxWidthDiskCache: widget.platform.isTv ? 960 : null,
                        alignment:
                            (widget.platform.isMobile || widget.platform.isTv)
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
                            CineVietColors.brandRed.withValues(
                              alpha: widget.platform.isMobile ? 0.12 : 0.18,
                            ),
                            CineVietColors.bg.withValues(
                              alpha: widget.platform.isMobile ? 0.46 : 0.62,
                            ),
                            CineVietColors.bg.withValues(
                              alpha: widget.platform.isMobile ? 0.82 : 0.96,
                            ),
                          ],
                          stops: const [0.0, 0.36, 0.64, 1.0],
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
                      maxWidth: widget.platform.isMobile
                          ? 390
                          : widget.platform.isTv
                          ? 680
                          : 760,
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
                              text: 'CineViet đề xuất',
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
                                ? 46
                                : widget.platform.isMobile
                                ? 32
                                : 42,
                            height: 1.04,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0,
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
                        const SizedBox(height: CineVietSpacing.lg),
                        _HeroButton(
                          movie: movie,
                          label: 'Xem ngay',
                          icon: Icons.play_arrow_rounded,
                          onFocusChanged: widget.onHeroFocusChanged,
                          onArrowDown: widget.platform.isTv
                              ? _focusFirstRail
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (items.length > 1)
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
      color: CineVietColors.brandRedSoft,
      border: Border.all(
        color: CineVietColors.brandRed.withValues(alpha: 0.62),
      ),
      borderRadius: BorderRadius.circular(CineVietRadius.full),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: CineVietColors.gold, size: 16),
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

class _HeroButton extends ConsumerWidget {
  const _HeroButton({
    required this.movie,
    required this.label,
    required this.icon,
    this.onFocusChanged,
    this.onArrowDown,
  });
  final Movie movie;
  final String label;
  final IconData icon;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = PlatformDetector.of(context);
    void open() => openMovieOrResume(context, ref, movie);

    if (platform.isTv) {
      final searchNode = TvSearchFocus.maybeOf(context);
      final heroNode = TvSearchFocus.heroOf(context);
      return TvFocus(
        focusNode: heroNode,
        onTap: open,
        borderRadius: BorderRadius.circular(CineVietRadius.full),
        padding: EdgeInsets.zero,
        ensureVisibleAlignment: 0.0,
        autoEnsureVisible: false,
        onFocusChanged: onFocusChanged,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                searchNode != null) {
              searchNode.requestFocus();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                onArrowDown != null) {
              onArrowDown!.call();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CineVietSpacing.lg,
            vertical: CineVietSpacing.md,
          ),
          decoration: BoxDecoration(
            color: CineVietColors.accent,
            borderRadius: BorderRadius.circular(CineVietRadius.full),
            border: Border.all(color: CineVietColors.accent),
            boxShadow: [
              BoxShadow(
                color: CineVietColors.accentGlow,
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: CineVietColors.bg),
              const SizedBox(width: CineVietSpacing.xs),
              Text(
                label,
                style: const TextStyle(
                  color: CineVietColors.bg,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final button = FilledButton.icon(
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
      onPressed: open,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
    return button;
  }
}

class _HomeMovieSection extends StatelessWidget {
  const _HomeMovieSection({
    required this.title,
    required this.icon,
    required this.data,
    required this.cardWidth,
    this.fallbackMovies = const <Movie>[],
    this.skipFirstMovie = false,
    this.upFocusNode,
    this.onRequestHeroFocus,
  });
  final String title;
  final IconData icon;
  final AsyncValue<List<Movie>> data;
  final double cardWidth;
  final List<Movie> fallbackMovies;
  final bool skipFirstMovie;
  final FocusNode? upFocusNode;
  final VoidCallback? onRequestHeroFocus;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CineVietSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, icon: icon),
        const SizedBox(height: CineVietSpacing.md),
        _MovieAsyncRail(
          data: data,
          cardWidth: cardWidth,
          fallbackMovies: fallbackMovies,
          skipFirstMovie: skipFirstMovie,
          upFocusNode: upFocusNode,
          onRequestHeroFocus: onRequestHeroFocus,
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    return Row(
      children: [
        Container(
          width: platform.isTv ? 6 : 5,
          height: platform.isTv ? 32 : 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [CineVietColors.brandRed, CineVietColors.accent],
            ),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: CineVietColors.brandRed.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        const SizedBox(width: CineVietSpacing.sm),
        Container(
          width: platform.isTv ? 34 : 30,
          height: platform.isTv ? 34 : 30,
          decoration: BoxDecoration(
            color: CineVietColors.cardHover,
            border: Border.all(color: CineVietColors.borderLight),
            borderRadius: BorderRadius.circular(CineVietRadius.sm),
          ),
          child: Icon(icon, color: CineVietColors.accent, size: 19),
        ),
        const SizedBox(width: CineVietSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: platform.isTv ? 25 : 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _MovieAsyncRail extends StatelessWidget {
  const _MovieAsyncRail({
    required this.data,
    required this.cardWidth,
    this.fallbackMovies = const <Movie>[],
    this.skipFirstMovie = false,
    this.upFocusNode,
    this.onRequestHeroFocus,
  });
  final AsyncValue<List<Movie>> data;
  final double cardWidth;
  final List<Movie> fallbackMovies;
  final bool skipFirstMovie;
  final FocusNode? upFocusNode;
  final VoidCallback? onRequestHeroFocus;

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
    error: (error, stackTrace) => fallbackMovies.isNotEmpty
        ? _MovieRail(
            movies: _railMovies(fallbackMovies),
            cardWidth: cardWidth,
            upFocusNode: upFocusNode,
            onRequestHeroFocus: onRequestHeroFocus,
          )
        : _RailError(error: error),
    data: (movies) {
      final source = movies.isNotEmpty ? movies : fallbackMovies;
      return _MovieRail(
        movies: _railMovies(source),
        cardWidth: cardWidth,
        upFocusNode: upFocusNode,
        onRequestHeroFocus: onRequestHeroFocus,
      );
    },
  );

  List<Movie> _railMovies(List<Movie> source) {
    final items = skipFirstMovie && source.length > 1 ? source.skip(1) : source;
    return items.take(_isTvBuild ? _tvHomeSectionLimit : 14).toList();
  }
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
  const _MovieRail({
    required this.movies,
    required this.cardWidth,
    this.upFocusNode,
    this.onRequestHeroFocus,
  });
  final List<Movie> movies;
  final double cardWidth;
  final FocusNode? upFocusNode;
  final VoidCallback? onRequestHeroFocus;

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
        itemBuilder: (context, index) => _RealMovieCard(
          movie: movies[index],
          width: cardWidth,
          upFocusNode: upFocusNode,
          onRequestHeroFocus: onRequestHeroFocus,
        ),
      ),
    );
  }
}

class _RealMovieCard extends ConsumerWidget {
  const _RealMovieCard({
    required this.movie,
    required this.width,
    this.upFocusNode,
    this.onRequestHeroFocus,
  });
  final Movie movie;
  final double width;
  final FocusNode? upFocusNode;
  final VoidCallback? onRequestHeroFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = PlatformDetector.of(context);
    return TvFocus(
      onTap: () => openMovieOrResume(context, ref, movie),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowUp &&
            upFocusNode != null) {
          onRequestHeroFocus?.call();
          upFocusNode!.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      borderRadius: BorderRadius.circular(CineVietRadius.xl),
      padding: const EdgeInsets.all(CineVietSpacing.xs),
      scale: 1.025,
      ensureParentScrollable: false,
      builder: (context, focused, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: width + CineVietSpacing.sm,
        decoration: BoxDecoration(
          color: focused ? CineVietColors.cardHover : Colors.transparent,
          borderRadius: BorderRadius.circular(CineVietRadius.xl),
          border: Border.all(
            color: focused ? CineVietColors.accent : Colors.transparent,
            width: focused ? 1.5 : 1,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: CineVietColors.accentGlow,
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: child,
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
                border: Border.all(color: CineVietColors.borderLight),
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
                      memCacheWidth: platform.isTv ? 260 : null,
                      maxWidthDiskCache: platform.isTv ? 320 : null,
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
                            CineVietColors.brandRed.withValues(alpha: 0.18),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.74),
                          ],
                          stops: const [0.0, 0.48, 1],
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
          ),
        ],
      ),
    );
  }
}

List<WatchHistoryItem> _continueWatchingItems(
  AsyncValue<List<WatchHistoryItem>> synced,
  AsyncValue<List<WatchHistoryItem>> local,
) {
  final syncedItems = synced.maybeWhen(
    data: (items) => items,
    orElse: () => const <WatchHistoryItem>[],
  );
  if (syncedItems.isNotEmpty) return syncedItems;
  return local.maybeWhen(
    data: (items) => items,
    orElse: () => const <WatchHistoryItem>[],
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
    required this.items,
    required this.platform,
    required this.cardWidth,
  });
  final List<WatchHistoryItem> items;
  final PlatformInfo platform;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
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
  }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa khỏi Xem tiếp.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa khỏi Xem tiếp.')),
      );
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _openResume() => openWatchHistoryItem(context, widget.item);

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    return TvFocus(
      onTap: _openResume,
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openResume,
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.all(CineVietSpacing.sm),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [CineVietColors.cardHover, CineVietColors.card],
            ),
            borderRadius: BorderRadius.circular(CineVietRadius.lg),
            border: Border.all(color: CineVietColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
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
                            imageUrl:
                                widget.item.backdropUrl?.isNotEmpty == true
                                ? widget.item.backdropUrl!
                                : widget.item.posterUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: platform.isTv ? 220 : null,
                            maxWidthDiskCache: platform.isTv ? 280 : null,
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
                          minHeight: 5,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
