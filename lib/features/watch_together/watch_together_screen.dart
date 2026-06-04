import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/watch_together_service.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';
import '../../data/models/movie.dart';
import '../../data/services/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WatchTogetherScreen extends ConsumerStatefulWidget {
  const WatchTogetherScreen({super.key, this.prefillMovie});

  final Movie? prefillMovie;

  @override
  ConsumerState<WatchTogetherScreen> createState() => _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends ConsumerState<WatchTogetherScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  List<WatchTogetherRoom> _rooms = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadRooms);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _displayName {
    final user = ref.read(authControllerProvider).user;
    final typed = _nameController.text.trim();
    return typed.isNotEmpty ? typed : (user?.name.trim().isNotEmpty == true ? user!.name : 'Thành viên');
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await WatchTogetherService.publicRooms();
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {
      if (mounted) setState(() => _rooms = const []);
    }
  }

  Future<void> _openRoom(String code) async {
    final url = WatchTogetherService.roomUrl(code, userName: _displayName);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa mở được phòng Xem chung.')));
    }
  }

  Future<void> _createRoomFromMovie(Movie movie) async {
    final videoUrl = WatchTogetherService.firstPlayableUrl(movie);
    if (videoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phim này chưa có link phát để tạo phòng.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await WatchTogetherService.createRoom(
        hostName: _displayName,
        videoUrl: videoUrl,
        movieTitle: movie.title,
      );
      if (!mounted) return;
      await _openRoom(result.code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinTypedRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nhập mã phòng.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await WatchTogetherService.joinRoom(code: code, userName: _displayName);
      if (!mounted) return;
      await _openRoom(code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.prefillMovie;
    final user = ref.watch(authControllerProvider).user;
    if (_nameController.text.isEmpty && user?.name.trim().isNotEmpty == true) {
      _nameController.text = user!.name;
    }
    return Scaffold(
      backgroundColor: CineVietColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRooms,
          child: ListView(
            padding: const EdgeInsets.all(CineVietSpacing.lg),
            children: [
              Row(
                children: [
                  if (movie != null)
                    IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  if (movie != null) const SizedBox(width: CineVietSpacing.sm),
                  const Expanded(
                    child: Text('Xem chung', style: TextStyle(color: CineVietColors.text, fontSize: 30, fontWeight: FontWeight.w900)),
                  ),
                  IconButton.filledTonal(onPressed: _loadRooms, icon: const Icon(Icons.refresh_rounded)),
                ],
              ),
              const SizedBox(height: CineVietSpacing.md),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Tên của bạn', prefixIcon: Icon(Icons.person_rounded)),
              ),
              const SizedBox(height: CineVietSpacing.lg),
              if (movie != null) ...[
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tạo phòng từ phim này', style: TextStyle(color: CineVietColors.text, fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(height: CineVietSpacing.xs),
                      Text(movie.title, style: const TextStyle(color: CineVietColors.textSoft, fontWeight: FontWeight.w700)),
                      const SizedBox(height: CineVietSpacing.md),
                      TvFocus(
                        onTap: _loading ? null : () => _createRoomFromMovie(movie),
                        borderRadius: BorderRadius.circular(CineVietRadius.full),
                        child: _PrimaryButton(label: _loading ? 'Đang tạo...' : 'Tạo phòng xem chung', icon: Icons.groups_rounded),
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
                    const Text('Vào phòng bằng mã', style: TextStyle(color: CineVietColors.text, fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(height: CineVietSpacing.md),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Mã phòng', hintText: 'CINE-XXXX', prefixIcon: Icon(Icons.meeting_room_rounded)),
                    ),
                    const SizedBox(height: CineVietSpacing.md),
                    TvFocus(
                      onTap: _loading ? null : _joinTypedRoom,
                      borderRadius: BorderRadius.circular(CineVietRadius.full),
                      child: _PrimaryButton(label: _loading ? 'Đang vào...' : 'Vào phòng', icon: Icons.login_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CineVietSpacing.lg),
              const Text('Phòng công khai', style: TextStyle(color: CineVietColors.text, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: CineVietSpacing.md),
              if (_rooms.isEmpty)
                const Text('Chưa có phòng công khai nào.', style: TextStyle(color: CineVietColors.textSoft))
              else
                for (final room in _rooms) ...[
                  TvFocus(
                    onTap: () async {
                      await WatchTogetherService.joinRoom(code: room.code, userName: _displayName);
                      await _openRoom(room.code);
                    },
                    borderRadius: BorderRadius.circular(CineVietRadius.lg),
                    child: _RoomTile(room: room),
                  ),
                  const SizedBox(height: CineVietSpacing.sm),
                ],
            ],
          ),
        ),
      ),
    );
  }
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
    padding: const EdgeInsets.symmetric(horizontal: CineVietSpacing.lg, vertical: CineVietSpacing.md),
    decoration: BoxDecoration(color: CineVietColors.accent, borderRadius: BorderRadius.circular(CineVietRadius.full)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: const Color(0xFF061A13)), const SizedBox(width: 10), Text(label, style: const TextStyle(color: Color(0xFF061A13), fontWeight: FontWeight.w900))]),
  );
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});
  final WatchTogetherRoom room;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CineVietSpacing.md),
    decoration: BoxDecoration(color: CineVietColors.cardHover, borderRadius: BorderRadius.circular(CineVietRadius.lg), border: Border.all(color: CineVietColors.border)),
    child: Row(children: [
      const Icon(Icons.public_rounded, color: CineVietColors.accent),
      const SizedBox(width: CineVietSpacing.md),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(room.movieTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: CineVietColors.text, fontWeight: FontWeight.w900)), Text('${room.code} • ${room.memberCount}/${room.maxMembers} người', style: const TextStyle(color: CineVietColors.textSoft, fontSize: 12))])),
      const Icon(Icons.chevron_right_rounded, color: CineVietColors.textSoft),
    ]),
  );
}
