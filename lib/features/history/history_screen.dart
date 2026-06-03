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
import '../../data/services/playlist_service.dart';
import '../movie_detail/movie_detail_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

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
              'Đăng nhập ở tab Cá nhân để xem playlist đã đồng bộ.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CineVietColors.textSoft),
            ),
          ),
        ),
      );
    }

    final playlists = ref.watch(myPlaylistsProvider);
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreatePlaylistDialog(context, ref),
        backgroundColor: CineVietColors.accent,
        foregroundColor: CineVietColors.bg,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tạo playlist'),
      ),
      body: SafeArea(
        child: playlists.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: CineVietColors.accent),
          ),
          error: (e, _) => Center(
            child: Text(
              'Không tải được playlist: $e',
              style: const TextStyle(color: CineVietColors.textSoft),
            ),
          ),
          data: (items) => RefreshIndicator(
            color: CineVietColors.accent,
            backgroundColor: CineVietColors.card,
            onRefresh: () async => ref.refresh(myPlaylistsProvider.future),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.all(padding),
                  sliver: const SliverToBoxAdapter(child: _PlaylistHeader()),
                ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(CineVietSpacing.xl),
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
                              onPressed: () =>
                                  showCreatePlaylistDialog(context, ref),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Tạo playlist mới'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      0,
                      padding,
                      padding + 90,
                    ),
                    sliver: SliverGrid.builder(
                      itemCount: items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: platform.isMobile
                            ? 2
                            : platform.isTablet
                            ? 3
                            : 5,
                        mainAxisSpacing: CineVietSpacing.md,
                        crossAxisSpacing: CineVietSpacing.md,
                        childAspectRatio: platform.isMobile ? .78 : .9,
                      ),
                      itemBuilder: (context, i) => _PlaylistCard(
                        playlist: items[i],
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PlaylistDetailScreen(playlistId: items[i].id),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showCreatePlaylistDialog(
  BuildContext context,
  WidgetRef ref, {
  Movie? movie,
}) async {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  var isPublic = false;
  var saving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
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
                  : (value) => setState(() => isPublic = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tên playlist không được để trống'),
                        ),
                      );
                      return;
                    }
                    setState(() => saving = true);
                    try {
                      final playlist = await ref
                          .read(playlistServiceProvider)
                          .create(
                            name: name,
                            description: descriptionController.text.trim(),
                            isPublic: isPublic,
                          );
                      if (movie != null) {
                        await ref
                            .read(playlistServiceProvider)
                            .addMovie(playlist.id, movie.id);
                      }
                      if (!context.mounted) return;
                      Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            movie == null
                                ? 'Đã tạo playlist "${playlist.name}"'
                                : 'Đã tạo playlist và thêm phim vào "${playlist.name}"',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      setState(() => saving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
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

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Playlist của tôi',
        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
      ),
      SizedBox(height: CineVietSpacing.xs),
      Text(
        'Playlist cá nhân.',
        style: TextStyle(color: CineVietColors.textSoft),
      ),
    ],
  );
}

class _PlaylistCard extends StatefulWidget {
  const _PlaylistCard({required this.playlist, required this.onOpen});

  final CineVietPlaylist playlist;
  final VoidCallback onOpen;

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _focused = false;

  String get _cover => normalizeImageUrl(widget.playlist.cover);

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (value) => setState(() => _focused = value),
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        widget.onOpen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: TvFocus(
      enabled: false,
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      onTap: widget.onOpen,
      builder: (context, focused, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _focused ? CineVietColors.cardHover : CineVietColors.card,
          borderRadius: BorderRadius.circular(CineVietRadius.lg),
          border: Border.all(
            color: _focused ? CineVietColors.accent : CineVietColors.border,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _focused
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
        transform: Matrix4.identity()
          ..scaleByDouble(_focused ? 1.025 : 1.0, _focused ? 1.025 : 1.0, 1, 1),
        transformAlignment: Alignment.center,
        child: child,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _cover.isEmpty
              ? const ColoredBox(color: CineVietColors.bg3)
              : CachedNetworkImage(imageUrl: _cover, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: .88),
                ],
              ),
            ),
          ),
          Positioned(
            left: CineVietSpacing.md,
            right: CineVietSpacing.md,
            bottom: CineVietSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: CineVietSpacing.xs),
                Row(
                  children: [
                    const Icon(
                      Icons.playlist_play_rounded,
                      size: 18,
                      color: CineVietColors.accent,
                    ),
                    const SizedBox(width: CineVietSpacing.xs),
                    Text(
                      '${widget.playlist.movieCount} phim',
                      style: const TextStyle(color: CineVietColors.textSoft),
                    ),
                    if (widget.playlist.isPublic) ...[
                      const SizedBox(width: CineVietSpacing.sm),
                      const Icon(
                        Icons.public_rounded,
                        size: 15,
                        color: CineVietColors.textSoft,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _togglePlaylistVisibility(
  BuildContext context,
  WidgetRef ref,
  CineVietPlaylist playlist,
) async {
  final next = !playlist.isPublic;
  try {
    await ref
        .read(playlistServiceProvider)
        .updateVisibility(playlist.id, isPublic: next);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Playlist đã chuyển sang công khai'
              : 'Playlist đã chuyển sang riêng tư',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}

Future<void> _confirmDeletePlaylist(
  BuildContext context,
  WidgetRef ref,
  CineVietPlaylist playlist,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: CineVietColors.bg2,
      title: const Text('Xóa playlist?'),
      content: Text(
        'Playlist "${playlist.name}" sẽ bị xóa khỏi tài khoản. Thao tác này không xóa phim khỏi hệ thống.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Xóa'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref.read(playlistServiceProvider).deletePlaylist(playlist.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa playlist "${playlist.name}"')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = PlatformDetector.of(context);
    final padding = platform.isMobile ? CineVietSpacing.md : CineVietSpacing.xl;
    final detail = ref.watch(playlistMoviesProvider(playlistId));

    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: CineVietColors.accent),
          ),
          error: (e, _) => Center(
            child: Text(
              'Không tải được playlist: $e',
              style: const TextStyle(color: CineVietColors.textSoft),
            ),
          ),
          data: (data) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: CineVietSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.playlist.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: CineVietSpacing.xs),
                            Text(
                              '${data.movies.length} phim trong playlist',
                              style: const TextStyle(
                                color: CineVietColors.textSoft,
                              ),
                            ),
                            const SizedBox(height: CineVietSpacing.sm),
                            Wrap(
                              spacing: CineVietSpacing.sm,
                              runSpacing: CineVietSpacing.xs,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _togglePlaylistVisibility(
                                    context,
                                    ref,
                                    data.playlist,
                                  ),
                                  icon: Icon(
                                    data.playlist.isPublic
                                        ? Icons.public_rounded
                                        : Icons.lock_rounded,
                                  ),
                                  label: Text(
                                    data.playlist.isPublic
                                        ? 'Công khai'
                                        : 'Riêng tư',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _confirmDeletePlaylist(
                                    context,
                                    ref,
                                    data.playlist,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  label: const Text('Xóa playlist'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (data.movies.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Playlist này chưa có phim.',
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
                    padding + 90,
                  ),
                  sliver: SliverGrid.builder(
                    itemCount: data.movies.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: platform.isMobile
                          ? 2
                          : platform.isTablet
                          ? 4
                          : 6,
                      mainAxisSpacing: CineVietSpacing.md,
                      crossAxisSpacing: CineVietSpacing.md,
                      childAspectRatio: platform.isMobile ? .62 : .66,
                    ),
                    itemBuilder: (context, i) => _PlaylistMovieCard(
                      playlistId: playlistId,
                      movie: data.movies[i],
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

class _PlaylistMovieCard extends ConsumerStatefulWidget {
  const _PlaylistMovieCard({required this.playlistId, required this.movie});

  final int playlistId;
  final Movie movie;

  @override
  ConsumerState<_PlaylistMovieCard> createState() => _PlaylistMovieCardState();
}

class _PlaylistMovieCardState extends ConsumerState<_PlaylistMovieCard> {
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

  Future<void> _remove() async {
    await ref
        .read(playlistServiceProvider)
        .removeMovie(widget.playlistId, movie.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã xóa "${movie.title}" khỏi playlist'),
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
      builder: (context, focused, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
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
                        imageUrl: normalizeImageUrl(movie.posterUrl),
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
                          _remove();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: IconButton(
                        tooltip: 'Xóa khỏi playlist',
                        onPressed: _remove,
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
              ],
            ),
          ),
          SizedBox(
            height: 92,
            child: Padding(
              padding: const EdgeInsets.all(CineVietSpacing.sm),
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
                    (movie.titleEn ?? '').isNotEmpty ? movie.titleEn! : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CineVietColors.textSoft,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: CineVietSpacing.xs),
                  Text(
                    movie.releaseYear?.toString() ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CineVietColors.textSoft,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
