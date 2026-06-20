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
import '../../data/models/movie_page.dart';
import '../../data/repositories/movie_repository.dart';
import '../movie_detail/movie_detail_screen.dart';

class SearchBrowseScreen extends ConsumerStatefulWidget {
  const SearchBrowseScreen({super.key, this.initialSearch = ''});
  final String initialSearch;

  @override
  ConsumerState<SearchBrowseScreen> createState() => _SearchBrowseScreenState();
}

class _SearchBrowseScreenState extends ConsumerState<SearchBrowseScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode(debugLabel: 'SearchField');
  final _firstFilterFocusNode = FocusNode(debugLabel: 'FirstFilter');
  final _firstMovieFocusNode = FocusNode(debugLabel: 'FirstMovie');
  Timer? _debounce;
  late String _search = widget.initialSearch.trim();
  String _type = '';
  String _sort = 'created_at';
  int _page = 1;

  BrowseQuery get _query =>
      BrowseQuery(search: _search, type: _type, sort: _sort, page: _page);

  @override
  void initState() {
    super.initState();
    _searchController.text = _search;
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleRemoteKey);
    _debounce?.cancel();
    _searchFocusNode.dispose();
    _firstFilterFocusNode.dispose();
    _firstMovieFocusNode.dispose();
    _searchController.dispose();
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
    if (_searchFocusNode.hasFocus &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter)) {
      _firstFilterFocusNode.requestFocus();
      return true;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _scrollController.animateTo(
        (current + 760).clamp(0.0, max),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return true;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _scrollController.animateTo(
        (current - 760).clamp(0.0, max),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return true;
    }
    return false;
  }

  void _setSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
        _page = 1;
      });
    });
  }

  void _setType(String value) => setState(() {
    _type = value;
    _page = 1;
  });

  void _setSort(String value) => setState(() {
    _sort = value;
    _page = 1;
  });

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    final data = ref.watch(browseMoviesProvider(_query));
    final padding = platform.isMobile ? CineVietSpacing.md : CineVietSpacing.xl;

    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding,
                padding,
                padding,
                CineVietSpacing.md,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Về trang chủ',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.home_rounded),
                        ),
                        const SizedBox(width: CineVietSpacing.sm),
                        Expanded(
                          child: Text(
                            'Tìm kiếm',
                            style: TextStyle(
                              fontSize: platform.isTv ? 42 : 32,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CineVietSpacing.xs),
                    _SearchBox(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      nextFocusNode: _firstFilterFocusNode,
                      onChanged: _setSearch,
                    ),
                    const SizedBox(height: CineVietSpacing.md),
                    _FilterBar(
                      type: _type,
                      sort: _sort,
                      firstFocusNode: _firstFilterFocusNode,
                      resultFocusNode: _firstMovieFocusNode,
                      onType: _setType,
                      onSort: _setSort,
                    ),
                  ],
                ),
              ),
            ),
            data.when(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                    color: CineVietColors.accent,
                  ),
                ),
              ),
              error: (error, stackTrace) => SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverToBoxAdapter(
                  child: _SearchErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(browseMoviesProvider(_query)),
                  ),
                ),
              ),
              data: (page) => _MovieGridSliver(
                page: page,
                platform: platform,
                padding: padding,
                pageIndex: _page,
                onPage: (value) => setState(() => _page = value),
                firstMovieFocusNode: _firstMovieFocusNode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CineVietSpacing.lg),
    decoration: BoxDecoration(
      color: CineVietColors.card,
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      border: Border.all(color: CineVietColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.wifi_off_rounded, color: CineVietColors.accent),
        const SizedBox(height: CineVietSpacing.sm),
        const Text(
          'Không tải được danh sách phim',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: CineVietSpacing.xs),
        Text('$error', style: const TextStyle(color: CineVietColors.textSoft)),
        const SizedBox(height: CineVietSpacing.md),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Thử lại'),
        ),
      ],
    ),
  );
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: true,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => widget.nextFocusNode.requestFocus(),
        onEditingComplete: () => widget.nextFocusNode.requestFocus(),
        style: const TextStyle(
          color: CineVietColors.text,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: 'Nhập tên phim, diễn viên, mô tả...',
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: CineVietColors.accent,
          ),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: CineVietColors.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CineVietRadius.xl),
            borderSide: const BorderSide(color: CineVietColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CineVietRadius.xl),
            borderSide: const BorderSide(color: CineVietColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CineVietRadius.xl),
            borderSide: const BorderSide(
              color: CineVietColors.accent,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.type,
    required this.sort,
    required this.firstFocusNode,
    required this.resultFocusNode,
    required this.onType,
    required this.onSort,
  });
  final String type;
  final String sort;
  final FocusNode firstFocusNode;
  final FocusNode resultFocusNode;
  final ValueChanged<String> onType;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CineVietSpacing.sm,
      runSpacing: CineVietSpacing.sm,
      children: [
        _FilterChipButton(
          label: 'Tất cả',
          selected: type.isEmpty,
          focusNode: firstFocusNode,
          downFocusNode: resultFocusNode,
          onTap: () => onType(''),
        ),
        _FilterChipButton(
          label: 'Phim lẻ',
          selected: type == 'movie',
          onTap: () => onType('movie'),
        ),
        _FilterChipButton(
          label: 'Phim bộ',
          selected: type == 'series',
          onTap: () => onType('series'),
        ),
        _FilterChipButton(
          label: 'Anime',
          selected: type == 'anime',
          onTap: () => onType('anime'),
        ),
        _FilterChipButton(
          label: 'TV Shows',
          selected: type == 'tvshows',
          onTap: () => onType('tvshows'),
        ),
        const SizedBox(width: CineVietSpacing.md),
        _FilterChipButton(
          label: 'Mới cập nhật',
          selected: sort == 'created_at',
          onTap: () => onSort('created_at'),
        ),
        _FilterChipButton(
          label: 'Xem nhiều',
          selected: sort == 'view_count',
          onTap: () => onSort('view_count'),
        ),
        _FilterChipButton(
          label: 'Năm mới',
          selected: sort == 'release_year',
          onTap: () => onSort('release_year'),
        ),
      ],
    );
  }
}

class _FilterChipButton extends StatefulWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    this.focusNode,
    this.downFocusNode,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final FocusNode? focusNode;
  final FocusNode? downFocusNode;
  final VoidCallback onTap;

  @override
  State<_FilterChipButton> createState() => _FilterChipButtonState();
}

class _FilterChipButtonState extends State<_FilterChipButton> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.selected || focused;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.downFocusNode != null) {
          widget.downFocusNode!.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (value) => setState(() => focused = value),
      child: ActionChip(
        onPressed: widget.onTap,
        label: Text(widget.label),
        labelStyle: TextStyle(
          color: active ? CineVietColors.accent : CineVietColors.textSoft,
          fontWeight: FontWeight.w800,
        ),
        backgroundColor: active
            ? CineVietColors.accentSoft
            : CineVietColors.card,
        side: BorderSide(
          color: active ? CineVietColors.accent : CineVietColors.border,
          width: active ? 2 : 1,
        ),
      ),
    );
  }
}

class _MovieGridSliver extends StatelessWidget {
  const _MovieGridSliver({
    required this.page,
    required this.platform,
    required this.padding,
    required this.pageIndex,
    required this.onPage,
    required this.firstMovieFocusNode,
  });
  final MoviePage page;
  final PlatformInfo platform;
  final double padding;
  final int pageIndex;
  final ValueChanged<int> onPage;
  final FocusNode firstMovieFocusNode;

  @override
  Widget build(BuildContext context) {
    if (page.movies.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'Không tìm thấy phim phù hợp.',
            style: TextStyle(color: CineVietColors.textSoft),
          ),
        ),
      );
    }
    final columns = platform.isMobile
        ? 2
        : platform.isTablet
        ? 4
        : 5;
    final aspect = platform.isMobile ? 0.52 : 0.56;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, padding + 90),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: CineVietSpacing.md),
              child: Text(
                '${page.total} phim',
                style: const TextStyle(
                  color: CineVietColors.textSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: CineVietSpacing.md,
              crossAxisSpacing: CineVietSpacing.md,
              childAspectRatio: aspect,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _BrowseMovieCard(
                movie: page.movies[index],
                platform: platform,
                focusNode: index == 0 ? firstMovieFocusNode : null,
              ),
              childCount: page.movies.length,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: CineVietSpacing.xl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: pageIndex <= 1
                        ? null
                        : () => onPage(pageIndex - 1),
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Trang trước'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CineVietSpacing.md,
                    ),
                    child: Text(
                      'Trang $pageIndex',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: page.hasMore
                        ? () => onPage(pageIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('Trang sau'),
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

class _BrowseMovieCard extends StatelessWidget {
  const _BrowseMovieCard({
    required this.movie,
    required this.platform,
    this.focusNode,
  });
  final Movie movie;
  final PlatformInfo platform;
  final FocusNode? focusNode;

  void _openMovie(BuildContext context) {
    final idOrSlug = movie.slug.isNotEmpty ? movie.slug : movie.id.toString();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MovieDetailScreen(idOrSlug: idOrSlug)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      focusNode: focusNode,
      onTap: () => _openMovie(context),
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      scale: 1.04,
      builder: (context, focused, child) => AnimatedScale(
        scale: focused ? 1.04 : 1,
        duration: const Duration(milliseconds: 140),
        child: Container(
          decoration: BoxDecoration(
            color: CineVietColors.card,
            borderRadius: BorderRadius.circular(CineVietRadius.lg),
            border: Border.all(
              color: focused ? CineVietColors.accent : CineVietColors.border,
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: CineVietColors.accent.withValues(alpha: 0.22),
                      blurRadius: 22,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
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
                            memCacheWidth: platform.isTv ? 420 : 320,
                            maxWidthDiskCache: platform.isTv ? 520 : 420,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                          ),
                    Positioned(
                      left: CineVietSpacing.xs,
                      top: CineVietSpacing.xs,
                      child: _Badge(
                        text: movie.quality ?? movie.episodeCurrent ?? 'HD',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(CineVietSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: CineVietSpacing.xs),
                    Text(
                      movie.englishTitleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CineVietColors.textSoft,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: CineVietSpacing.xs),
                    Text(
                      movie.yearLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CineVietColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CineVietSpacing.xs,
      vertical: 3,
    ),
    decoration: BoxDecoration(
      color: CineVietColors.accent,
      borderRadius: BorderRadius.circular(CineVietRadius.sm),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: CineVietColors.bg,
        fontWeight: FontWeight.w900,
        fontSize: 10,
      ),
    ),
  );
}
