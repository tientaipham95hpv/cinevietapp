import 'package:flutter/material.dart';

import '../../core/platform/platform_detector.dart';
import '../../core/services/watch_together_service.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';
import '../player/cineviet_player_screen.dart';
import '../../data/models/movie.dart';
import '../../data/services/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WatchTogetherScreen extends ConsumerStatefulWidget {
  const WatchTogetherScreen({
    super.key,
    this.prefillMovie,
    this.prefillServer,
    this.prefillEpisode,
  });

  final Movie? prefillMovie;
  final EpisodeServer? prefillServer;
  final EpisodeItem? prefillEpisode;

  @override
  ConsumerState<WatchTogetherScreen> createState() =>
      _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends ConsumerState<WatchTogetherScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _createPublic = true;
  int _maxMembers = 8;
  EpisodeServer? _selectedServer;
  EpisodeItem? _selectedEpisode;
  List<WatchTogetherRoom> _rooms = const [];

  @override
  void initState() {
    super.initState();
    final servers = widget.prefillMovie?.episodes ?? const <EpisodeServer>[];
    _selectedServer =
        widget.prefillServer ?? (servers.isNotEmpty ? servers.first : null);
    final episodes = _selectedServer?.items ?? const <EpisodeItem>[];
    _selectedEpisode =
        widget.prefillEpisode ?? (episodes.isNotEmpty ? episodes.first : null);
    Future.microtask(_loadRooms);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _displayName {
    final user = ref.read(authControllerProvider).user;
    final name = user?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'Thành viên';
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await WatchTogetherService.publicRooms();
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {
      if (mounted) setState(() => _rooms = const []);
    }
  }

  void _openRoom({required WatchTogetherState? room, required String code}) {
    final movie = widget.prefillMovie;
    final server = _selectedServer ?? widget.prefillServer;
    final episode = _selectedEpisode ?? widget.prefillEpisode;
    if (movie != null && server != null && episode != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CineVietPlayerScreen(
            movie: movie,
            server: server,
            episode: episode,
            watchTogetherState: room,
            watchTogetherCode: code,
          ),
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã vào phòng Xem chung $code')));
      return;
    }

    final roomVideoUrl = room?.videoUrl.trim();
    if (room != null && roomVideoUrl != null && roomVideoUrl.isNotEmpty) {
      final roomTitle = room.movieTitle.trim().isNotEmpty
          ? room.movieTitle.trim()
          : 'Phòng xem chung $code';
      final roomMovie = Movie(
        id: 0,
        title: roomTitle,
        slug: 'watch-together-$code',
      );
      final roomEpisode = EpisodeItem(name: 'Đang xem', linkM3u8: roomVideoUrl);
      final roomServer = EpisodeServer(name: 'Xem chung', items: [roomEpisode]);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CineVietPlayerScreen(
            movie: roomMovie,
            server: roomServer,
            episode: roomEpisode,
            watchTogetherState: room,
            watchTogetherCode: code,
          ),
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã vào phòng Xem chung $code')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã vào phòng $code nhưng phòng chưa có video để phát.'),
      ),
    );
  }

  Future<void> _createRoomFromMovie(Movie movie) async {
    final selectedEpisode = _selectedEpisode;
    final selectedServer = _selectedServer;
    final videoUrl = selectedEpisode?.linkM3u8?.trim().isNotEmpty == true
        ? selectedEpisode!.linkM3u8!.trim()
        : selectedEpisode?.linkEmbed?.trim().isNotEmpty == true
        ? selectedEpisode!.linkEmbed!.trim()
        : WatchTogetherService.firstPlayableUrl(movie);
    if (videoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phim này chưa có link phát để tạo phòng.'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await WatchTogetherService.createRoom(
        hostName: _displayName,
        videoUrl: videoUrl,
        movieTitle: selectedEpisode != null
            ? '${movie.title} • ${selectedEpisode.displayName}'
            : movie.title,
        maxMembers: _maxMembers,
        isPublic: _createPublic,
      );
      if (!mounted) return;
      final oldServer = _selectedServer;
      final oldEpisode = _selectedEpisode;
      _selectedServer = selectedServer ?? oldServer;
      _selectedEpisode = selectedEpisode ?? oldEpisode;
      _openRoom(room: result.room, code: result.code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinTypedRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nhập mã phòng.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final room = await WatchTogetherService.joinRoom(
        code: code,
        userName: _displayName,
      );
      if (!mounted) return;
      _openRoom(room: room, code: code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.prefillMovie;
    final platform = PlatformDetector.of(context);
    final horizontalPadding = platform.isDesktop || platform.isTablet
        ? CineVietSpacing.xl
        : CineVietSpacing.lg;
    final maxContentWidth = platform.isDesktop ? 920.0 : double.infinity;
    ref.watch(authControllerProvider);
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRooms,
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: CineVietSpacing.lg,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (movie != null)
                            IconButton.filledTonal(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                          if (movie != null)
                            const SizedBox(width: CineVietSpacing.sm),
                          const Expanded(
                            child: Text(
                              'Xem chung',
                              style: TextStyle(
                                color: CineVietColors.text,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: _loadRooms,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: CineVietSpacing.md),
                      _ReadOnlyInfoField(
                        icon: Icons.person_rounded,
                        label: 'Tên của bạn',
                        value: _displayName,
                      ),
                      const SizedBox(height: CineVietSpacing.lg),
                      if (movie != null) ...[
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tạo phòng từ phim này',
                                style: TextStyle(
                                  color: CineVietColors.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: CineVietSpacing.xs),
                              Text(
                                movie.title,
                                style: const TextStyle(
                                  color: CineVietColors.textSoft,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: CineVietSpacing.md),
                              DropdownButtonFormField<EpisodeServer>(
                                initialValue: _selectedServer,
                                decoration: const InputDecoration(
                                  labelText: 'Server phim',
                                  prefixIcon: Icon(Icons.dns_rounded),
                                ),
                                dropdownColor: CineVietColors.card,
                                items: movie.episodes
                                    .map(
                                      (server) => DropdownMenuItem(
                                        value: server,
                                        child: Text(server.displayName),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _loading
                                    ? null
                                    : (server) {
                                        if (server == null) return;
                                        setState(() {
                                          _selectedServer = server;
                                          _selectedEpisode =
                                              server.items.isNotEmpty
                                              ? server.items.first
                                              : null;
                                        });
                                      },
                              ),
                              const SizedBox(height: CineVietSpacing.md),
                              DropdownButtonFormField<EpisodeItem>(
                                initialValue: _selectedEpisode,
                                decoration: const InputDecoration(
                                  labelText: 'Chọn tập phim',
                                  prefixIcon: Icon(Icons.video_library_rounded),
                                ),
                                dropdownColor: CineVietColors.card,
                                items:
                                    (_selectedServer?.items ??
                                            const <EpisodeItem>[])
                                        .map(
                                          (episode) => DropdownMenuItem(
                                            value: episode,
                                            child: Text(episode.displayName),
                                          ),
                                        )
                                        .toList(),
                                onChanged: _loading
                                    ? null
                                    : (episode) => setState(
                                        () => _selectedEpisode = episode,
                                      ),
                              ),
                              const SizedBox(height: CineVietSpacing.md),
                              Row(
                                children: [
                                  Expanded(
                                    child: SegmentedButton<bool>(
                                      segments: const [
                                        ButtonSegment(
                                          value: true,
                                          icon: Icon(Icons.public_rounded),
                                          label: Text('Công khai'),
                                        ),
                                        ButtonSegment(
                                          value: false,
                                          icon: Icon(Icons.lock_rounded),
                                          label: Text('Riêng tư'),
                                        ),
                                      ],
                                      selected: {_createPublic},
                                      onSelectionChanged: _loading
                                          ? null
                                          : (values) => setState(
                                              () =>
                                                  _createPublic = values.first,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: CineVietSpacing.md),
                              Wrap(
                                spacing: CineVietSpacing.sm,
                                runSpacing: CineVietSpacing.sm,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'Số người:',
                                      style: TextStyle(
                                        color: CineVietColors.textSoft,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  for (final value in const [2, 4, 6, 8])
                                    ChoiceChip(
                                      label: Text('$value'),
                                      selected: _maxMembers == value,
                                      onSelected: _loading
                                          ? null
                                          : (_) => setState(
                                              () => _maxMembers = value,
                                            ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: CineVietSpacing.md),
                              TvFocus(
                                onTap: _loading
                                    ? null
                                    : () => _createRoomFromMovie(movie),
                                borderRadius: BorderRadius.circular(
                                  CineVietRadius.full,
                                ),
                                child: _PrimaryButton(
                                  label: _loading
                                      ? 'Đang tạo...'
                                      : 'Tạo phòng xem chung',
                                  icon: Icons.groups_rounded,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: CineVietSpacing.lg),
                      ],
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Vào phòng bằng mã',
                              style: TextStyle(
                                color: CineVietColors.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: CineVietSpacing.md),
                            TextField(
                              controller: _codeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Mã phòng',
                                hintText: 'CINE-XXXX',
                                prefixIcon: Icon(Icons.meeting_room_rounded),
                              ),
                            ),
                            const SizedBox(height: CineVietSpacing.md),
                            TvFocus(
                              onTap: _loading ? null : _joinTypedRoom,
                              borderRadius: BorderRadius.circular(
                                CineVietRadius.full,
                              ),
                              child: _PrimaryButton(
                                label: _loading ? 'Đang vào...' : 'Vào phòng',
                                icon: Icons.login_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: CineVietSpacing.lg),
                      const Text(
                        'Phòng công khai',
                        style: TextStyle(
                          color: CineVietColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: CineVietSpacing.md),
                      if (_rooms.isEmpty)
                        const Text(
                          'Chưa có phòng công khai nào.',
                          style: TextStyle(color: CineVietColors.textSoft),
                        )
                      else
                        for (final room in _rooms) ...[
                          TvFocus(
                            onTap: () async {
                              final state = await WatchTogetherService.joinRoom(
                                code: room.code,
                                userName: _displayName,
                              );
                              _openRoom(room: state, code: room.code);
                            },
                            borderRadius: BorderRadius.circular(
                              CineVietRadius.lg,
                            ),
                            child: _RoomTile(room: room),
                          ),
                          const SizedBox(height: CineVietSpacing.sm),
                        ],
                    ],
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

class _ReadOnlyInfoField extends StatelessWidget {
  const _ReadOnlyInfoField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CineVietSpacing.md,
      vertical: CineVietSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: CineVietColors.bg2.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      border: Border.all(color: CineVietColors.border),
    ),
    child: Row(
      children: [
        Icon(icon, color: CineVietColors.textSoft),
        const SizedBox(width: CineVietSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: CineVietColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CineVietColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.lock_rounded, color: CineVietColors.muted, size: 16),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CineVietSpacing.lg),
    decoration: BoxDecoration(
      color: CineVietColors.card,
      borderRadius: BorderRadius.circular(CineVietRadius.xl),
      border: Border.all(color: CineVietColors.border),
    ),
    child: child,
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CineVietSpacing.lg,
      vertical: CineVietSpacing.md,
    ),
    decoration: BoxDecoration(
      color: CineVietColors.accent,
      borderRadius: BorderRadius.circular(CineVietRadius.full),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF061A13)),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF061A13),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});
  final WatchTogetherRoom room;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CineVietSpacing.md),
    decoration: BoxDecoration(
      color: CineVietColors.cardHover,
      borderRadius: BorderRadius.circular(CineVietRadius.lg),
      border: Border.all(color: CineVietColors.border),
    ),
    child: Row(
      children: [
        const Icon(Icons.public_rounded, color: CineVietColors.accent),
        const SizedBox(width: CineVietSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.movieTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CineVietColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${room.code} • ${room.memberCount}/${room.maxMembers} người',
                style: const TextStyle(
                  color: CineVietColors.textSoft,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: CineVietColors.textSoft),
      ],
    ),
  );
}
