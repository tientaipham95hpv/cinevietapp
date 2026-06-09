import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';
import '../../data/models/movie.dart';
import '../../data/models/watch_history.dart';
import '../../data/repositories/movie_repository.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/services/cloud_history_service.dart';
import '../../core/services/watch_together_service.dart';

enum _PlayerFitMode { contain, cover, stretch }

class CineVietPlayerScreen extends ConsumerStatefulWidget {
  const CineVietPlayerScreen({
    super.key,
    required this.movie,
    required this.server,
    required this.episode,
    this.watchTogetherState,
    this.watchTogetherCode,
  });
  final Movie movie;
  final EpisodeServer server;
  final EpisodeItem episode;
  final WatchTogetherState? watchTogetherState;
  final String? watchTogetherCode;

  @override
  ConsumerState<CineVietPlayerScreen> createState() =>
      _CineVietPlayerScreenState();
}

class _CineVietPlayerScreenState extends ConsumerState<CineVietPlayerScreen> {
  VideoPlayerController? _controller;
  bool _showControls = true;
  bool _loading = true;
  bool _buffering = false;
  String? _error;
  String? _seekHint;
  String? _gestureMode;
  double? _gestureValue;
  String? _dragMode;
  Offset? _dragStart;
  Duration? _dragStartPosition;
  Duration? _pendingSeekPosition;
  bool _switchingEpisode = false;
  bool _controlsLocked = false;
  _PlayerFitMode _fitMode = _PlayerFitMode.cover;
  double _appVolume = 1.0;
  double _screenBrightness = 1.0;
  Timer? _gestureHintTimer;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _seekHintTimer;
  Timer? _levelApplyTimer;
  double? _pendingBrightness;
  double? _pendingVolume;
  WatchHistoryItem? _resumeItem;
  bool _watchChatVisible = true;
  final List<WatchTogetherMessage> _watchMessages = [];
  final TextEditingController _watchChatController = TextEditingController();
  WatchTogetherState? _watchRoomState;
  String? _lastWatchRoomFrom;
  int _lastWatchSyncSentAt = 0;
  bool _applyingWatchSync = false;
  bool _recoveringPlaybackError = false;
  static const bool _isAndroidTvBuild = bool.fromEnvironment('APP_IS_TV');
  List<String> _activeCandidateUrls = const [];
  int _activeCandidateIndex = 0;
  double? _scrubProgress;

  bool get _isWatchTogether => _watchRoomCode != null;
  bool get _isWatchHost =>
      _watchRoomState?.isCurrentSocketHost ??
      WatchTogetherService.activeSocketIsHost;
  String? get _watchRoomCode {
    final code = widget.watchTogetherCode?.trim().toUpperCase();
    if (code != null && code.isNotEmpty) return code;
    final stateCode = widget.watchTogetherState?.code.trim().toUpperCase();
    if (stateCode != null && stateCode.isNotEmpty) return stateCode;
    return null;
  }

  String get _rawStreamUrl => widget.episode.linkM3u8?.isNotEmpty == true
      ? widget.episode.linkM3u8!
      : widget.episode.linkEmbed?.isNotEmpty == true
      ? widget.episode.linkEmbed!
      : '';

  String _streamUrlOf(EpisodeItem episode) {
    final m3u8 = episode.linkM3u8?.trim() ?? '';
    if (m3u8.isNotEmpty) return m3u8;
    return episode.linkEmbed?.trim() ?? '';
  }

  String _episodeKey(EpisodeItem episode) {
    final text = episode.name.trim().toLowerCase();
    final numeric = RegExp(r'\d+').firstMatch(text)?.group(0);
    return numeric ?? text.replaceAll(RegExp(r'\s+'), ' ');
  }

  int _androidTvServerPriority(EpisodeServer server) {
    final name = server.name.toLowerCase();
    // Prefer sources that commonly expose HLS variants/CDNs suitable for proxy
    // filtering. Current server gets a small boost separately so user choice is
    // respected unless another source is clearly safer.
    if (name.contains('ophim')) return 0;
    if (name.contains('phimapi') || name.contains('kkphim')) return 1;
    if (name.contains('vietsub')) return 2;
    return 3;
  }

  List<MapEntry<EpisodeServer, EpisodeItem>> get _candidateEpisodesForAndroidTv {
    final currentKey = _episodeKey(widget.episode);
    final out = <MapEntry<EpisodeServer, EpisodeItem>>[];
    for (final server in widget.movie.episodes) {
      for (final episode in server.items) {
        final url = _streamUrlOf(episode);
        if (url.isEmpty || !url.startsWith(RegExp(r'https?://'))) continue;
        final sameEpisode = _episodeKey(episode) == currentKey ||
            episode.displayName == widget.episode.displayName;
        if (!sameEpisode) continue;
        out.add(MapEntry(server, episode));
      }
    }
    if (out.isEmpty) return [MapEntry(widget.server, widget.episode)];

    out.sort((a, b) {
      final aCurrent = identical(a.value, widget.episode) ||
          (_streamUrlOf(a.value) == _rawStreamUrl && a.key.name == widget.server.name);
      final bCurrent = identical(b.value, widget.episode) ||
          (_streamUrlOf(b.value) == _rawStreamUrl && b.key.name == widget.server.name);
      final byServer = _androidTvServerPriority(a.key).compareTo(_androidTvServerPriority(b.key));
      if (byServer != 0) return byServer;
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
      return a.key.name.compareTo(b.key.name);
    });
    return out;
  }

  String _proxiedStreamUrl(
    String raw, {
    required bool androidTvSafe,
    int? maxHeight,
    int? maxBandwidth,
  }) {
    final encoded = Uri.encodeComponent(raw);
    if (androidTvSafe) {
      final height = maxHeight ?? 720;
      final bandwidth = maxBandwidth ?? (height <= 480 ? 4000000 : 8000000);
      return 'https://cineviet.live/api/stream?maxHeight=$height&maxBandwidth=$bandwidth&url=$encoded';
    }
    return 'https://cineviet.live/api/stream?url=$encoded';
  }

  List<String> get _candidateStreamUrls {
    final raw = _rawStreamUrl.trim();
    if (raw.isEmpty) return const [];
    if (!raw.startsWith(RegExp(r'https?://'))) return [raw];

    if (Platform.isAndroid) {
      final urls = <String>[];
      final seen = <String>{};
      for (final entry in _candidateEpisodesForAndroidTv) {
        final sourceUrl = _streamUrlOf(entry.value);
        if (sourceUrl.isEmpty) continue;
        final parsed = Uri.tryParse(sourceUrl);
        final alreadyProxy = parsed?.host == 'cineviet.live' && parsed?.path == '/api/stream';

        if (_isAndroidTvBuild && !alreadyProxy) {
          // Android TV boxes are more likely to fail on 1080p/high-profile
          // encodes. Try safer renditions first, then original as last resort.
          final safe480 = _proxiedStreamUrl(
            sourceUrl,
            androidTvSafe: true,
            maxHeight: 480,
            maxBandwidth: 4000000,
          );
          final safe720 = _proxiedStreamUrl(
            sourceUrl,
            androidTvSafe: true,
            maxHeight: 720,
            maxBandwidth: 8000000,
          );
          if (seen.add(safe480)) urls.add(safe480);
          if (seen.add(safe720)) urls.add(safe720);
          if (seen.add(sourceUrl)) urls.add(sourceUrl);
          continue;
        }

        final preferred = alreadyProxy ? sourceUrl : _proxiedStreamUrl(sourceUrl, androidTvSafe: true);
        // Keep fallback per source: Ophim proxy -> Ophim direct -> PhimAPI proxy
        // -> PhimAPI direct -> others. If the proxy is blocked by a CDN, we do
        // not skip the preferred source entirely.
        if (seen.add(preferred)) urls.add(preferred);
        if (!alreadyProxy && seen.add(sourceUrl)) urls.add(sourceUrl);
      }
      return urls;
    }

    final parsed = Uri.tryParse(raw);
    final alreadyProxy = parsed?.host == 'cineviet.live' && parsed?.path == '/api/stream';
    if (!Platform.isWindows || alreadyProxy) return [raw];

    final proxy = _proxiedStreamUrl(raw, androidTvSafe: false);
    // Windows keeps original-first behavior; Android TV uses safer proxy-first
    // multi-source logic above.
    return [raw, proxy];
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);
    _watchRoomState = widget.watchTogetherState;
    _watchMessages.addAll(widget.watchTogetherState?.messages ?? const []);
    _bindWatchTogetherSocket();
    _loadScreenBrightness();
    _loadSystemVolume();
    _initPlayer();
  }

  void _bindWatchTogetherSocket() {
    final socket = WatchTogetherService.activeRoomSocket;
    if (!_isWatchTogether || socket == null) return;
    socket.off('room-state');
    socket.off('chat-message');
    socket.on('room-state', (data) {
      if (!mounted || data is! Map) return;
      final state = WatchTogetherState.fromJson(
        Map<String, dynamic>.from(data),
      );
      _lastWatchRoomFrom = data['_from']?.toString();
      setState(() {
        _watchRoomState = state;
        _watchMessages
          ..clear()
          ..addAll(state.messages);
      });
      _applyWatchRoomSync(state);
    });
    socket.on('chat-message', (data) {
      if (!mounted || data is! Map) return;
      final message = WatchTogetherMessage.fromJson(
        Map<String, dynamic>.from(data),
      );
      setState(() {
        final exists = _watchMessages.any((m) => m.id == message.id);
        if (!exists) _watchMessages.add(message);
      });
    });
  }

  void _sendWatchMessage() {
    final text = _watchChatController.text.trim();
    if (text.isEmpty) return;
    WatchTogetherService.sendMessage(text);
    _watchChatController.clear();
    _revealControls();
  }

  Future<void> _applyWatchRoomSync(WatchTogetherState state) async {
    if (!_isWatchTogether || _isWatchHost) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final from = _lastWatchRoomFrom;
    final activeId = WatchTogetherService.activeSocketId;
    if (from != null && activeId != null && from == activeId) return;

    final target = Duration(milliseconds: (state.currentTime * 1000).round());
    final current = controller.value.position;
    final diffMs = (target - current).inMilliseconds.abs();
    _applyingWatchSync = true;
    try {
      if (diffMs > 3000) {
        await controller.seekTo(target);
      }
      if (state.playing && !controller.value.isPlaying) {
        await controller.play();
      } else if (!state.playing && controller.value.isPlaying) {
        await controller.pause();
      }
    } catch (_) {
      // Watch Together sync should never break playback controls.
    } finally {
      _applyingWatchSync = false;
    }
  }

  void _emitWatchSync({bool force = false}) {
    if (!_isWatchTogether || !_isWatchHost || _applyingWatchSync) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastWatchSyncSentAt < 1500) return;
    _lastWatchSyncSentAt = now;
    WatchTogetherService.syncState(
      currentTime: controller.value.position.inMilliseconds / 1000,
      playing: controller.value.isPlaying,
    );
  }

  Future<void> _initPlayer() async {
    final candidateUrls = _candidateStreamUrls;
    _activeCandidateUrls = candidateUrls;
    _activeCandidateIndex = 0;
    if (candidateUrls.isEmpty ||
        !candidateUrls.first.startsWith(RegExp(r'https?://'))) {
      setState(() {
        _loading = false;
        _error = 'Tập này chưa có link m3u8 hợp lệ để phát.';
      });
      return;
    }

    VideoPlayerController? controller;
    Object? lastError;
    for (var i = 0; i < candidateUrls.length; i++) {
      final streamUrl = candidateUrls[i];
      _activeCandidateIndex = i;
      try {
        // ignore: deprecated_member_use
        final nextController = VideoPlayerController.network(
          streamUrl,
          formatHint: VideoFormat.hls,
          httpHeaders: const <String, String>{},
        );
        _controller = nextController;
        nextController.addListener(_syncPlayerState);
        await nextController.initialize().timeout(
          Platform.isWindows
              ? const Duration(seconds: 12)
              : const Duration(seconds: 30),
        );
        controller = nextController;
        _activeCandidateIndex = i;
        break;
      } catch (e) {
        lastError = e;
        try {
          _controller?.removeListener(_syncPlayerState);
          await _controller?.dispose();
        } catch (_) {}
        _controller = null;
      }
    }

    if (controller == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyPlaybackError(lastError);
      });
      return;
    }

    try {
      final roomState = _watchRoomState;
      if (_isWatchTogether && !_isWatchHost && roomState != null) {
        final target = Duration(
          milliseconds: (roomState.currentTime * 1000).round(),
        );
        await controller.seekTo(target);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = null;
    });

    try {
      _resumeItem = await ref
          .read(watchHistoryServiceProvider)
          .find(widget.movie.slug, widget.server.name, widget.episode.name);
      final resume = _resumeItem;
      if (resume != null &&
          !resume.completed &&
          resume.positionMs > 10000 &&
          resume.durationMs > 0) {
        final safeMax = (resume.durationMs - 5000).clamp(0, resume.durationMs);
        final target = Duration(
          milliseconds: resume.positionMs.clamp(0, safeMax).toInt(),
        );
        await controller.seekTo(target);
      }
    } catch (_) {
      // Resume/history must never block playback.
    }

    try {
      await controller.setVolume(_appVolume);
      final roomState = _watchRoomState;
      if (_isWatchTogether &&
          !_isWatchHost &&
          roomState != null &&
          !roomState.playing) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (_) {
      // Some devices require the user to press play manually.
    }

    _startProgressTimer();
    _armHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _seekHintTimer?.cancel();
    _gestureHintTimer?.cancel();
    _levelApplyTimer?.cancel();
    _watchChatController.dispose();
    _saveProgress();
    if (_isWatchTogether && _isWatchHost) {
      WatchTogetherService.closeActiveRoom(forceDelete: true);
    }
    HardwareKeyboard.instance.removeHandler(_handleRemoteKey);
    _controller?.removeListener(_syncPlayerState);
    _controller?.dispose();
    if (!_switchingEpisode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    super.dispose();
  }

  bool _handleRemoteKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      _togglePlay();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -10));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 10));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _revealControls();
      return true;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return true;
    }
    return false;
  }

  void _revealControls() {
    if (!mounted || _controlsLocked) return;
    setState(() => _showControls = true);
    _armHideTimer();
  }

  Future<void> _openExternalPlayer() async {
    if (!Platform.isAndroid) return;
    final url = _rawStreamUrl.trim();
    if (url.isEmpty) return;
    bool? opened;
    try {
      opened = await _brightnessChannel.invokeMethod<bool>(
        'openExternalPlayer',
        {'url': url, 'title': widget.movie.title},
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted || opened == true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chưa tìm thấy VLC/MX Player hoặc trình phát ngoài.'),
      ),
    );
  }

  String _friendlyPlaybackError(Object? error) {
    final text = '$error';
    final lower = text.toLowerCase();
    if (lower.contains('mediacodec') ||
        lower.contains('decoder') ||
        lower.contains('exoplaybackexception') ||
        lower.contains('videoerror')) {
      return _isAndroidTvBuild
          ? 'Thiết bị đã thử các nguồn an toàn 480p/720p nhưng vẫn không giải mã được video này. Có thể nguồn phim dùng codec/profile không tương thích TV box.'
          : 'Thiết bị không giải mã được video này. Thường do Android TV/TV box không hỗ trợ codec/profile của nguồn phim 1080p. Hãy thử tập/nguồn khác hoặc bản 720p nếu có.';
    }
    return 'Không mở được stream. Vui lòng thử lại hoặc chọn nguồn khác nếu có.';
  }

  bool _isCodecOrStreamPlaybackError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('mediacodec') ||
        lower.contains('decoder') ||
        lower.contains('exoplaybackexception') ||
        lower.contains('videoerror') ||
        lower.contains('source error') ||
        lower.contains('behindlivewindow');
  }

  Future<void> _tryNextCandidateAfterPlaybackError(String playbackError) async {
    if (_recoveringPlaybackError || !_isCodecOrStreamPlaybackError(playbackError)) return;
    final nextIndex = _activeCandidateIndex + 1;
    if (nextIndex >= _activeCandidateUrls.length) return;

    _recoveringPlaybackError = true;
    setState(() {
      _loading = true;
      _buffering = false;
      _error = null;
    });

    try {
      _controller?.removeListener(_syncPlayerState);
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;

    Object? lastError;
    for (var i = nextIndex; i < _activeCandidateUrls.length; i++) {
      final streamUrl = _activeCandidateUrls[i];
      try {
        // ignore: deprecated_member_use
        final nextController = VideoPlayerController.network(
          streamUrl,
          formatHint: VideoFormat.hls,
          httpHeaders: const <String, String>{},
        );
        _controller = nextController;
        _activeCandidateIndex = i;
        nextController.addListener(_syncPlayerState);
        await nextController.initialize().timeout(
          Platform.isWindows ? const Duration(seconds: 12) : const Duration(seconds: 30),
        );
        await nextController.setVolume(_appVolume);
        if (mounted) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }
        try { await nextController.play(); } catch (_) {}
        _recoveringPlaybackError = false;
        return;
      } catch (e) {
        lastError = e;
        try {
          _controller?.removeListener(_syncPlayerState);
          await _controller?.dispose();
        } catch (_) {}
        _controller = null;
      }
    }

    _recoveringPlaybackError = false;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = _friendlyPlaybackError(lastError ?? playbackError);
    });
  }

  void _syncPlayerState() {
    final value = _controller?.value;
    if (!mounted || value == null) return;
    final buffering = value.isBuffering;
    final playbackError = value.errorDescription;
    if (playbackError != null && _activeCandidateIndex + 1 < _activeCandidateUrls.length) {
      unawaited(_tryNextCandidateAfterPlaybackError(playbackError));
      if (buffering != _buffering) {
        setState(() => _buffering = buffering);
      }
      return;
    }
    final friendlyError = playbackError == null
        ? null
        : _friendlyPlaybackError(playbackError);
    if (buffering != _buffering ||
        friendlyError != null && friendlyError != _error) {
      setState(() {
        _buffering = buffering;
        if (friendlyError != null) _error = friendlyError;
      });
    }
  }

  static const _brightnessChannel = MethodChannel('live.cineviet/brightness');

  Future<void> _loadScreenBrightness() async {
    try {
      final brightness = await _brightnessChannel.invokeMethod<double>('get');
      if (mounted && brightness != null) {
        setState(() => _screenBrightness = brightness.clamp(0.05, 1.0));
      }
    } catch (_) {}
  }

  Future<double?> _setScreenBrightness(double value) async {
    try {
      final actual = await _brightnessChannel.invokeMethod<double>('set', {
        'value': value,
      });
      return actual?.clamp(0.05, 1.0);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSystemVolume() async {
    try {
      final volume = await _brightnessChannel.invokeMethod<double>('getVolume');
      if (mounted && volume != null) {
        setState(() => _appVolume = volume.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  Future<double?> _setSystemVolume(double value) async {
    try {
      final actual = await _brightnessChannel.invokeMethod<double>(
        'setVolume',
        {'value': value},
      );
      return actual?.clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  void _scheduleLevelApply() {
    if (_levelApplyTimer?.isActive ?? false) return;
    _levelApplyTimer = Timer(
      const Duration(milliseconds: 70),
      _applyPendingLevels,
    );
  }

  Future<void> _applyPendingLevels({bool settle = false}) async {
    _levelApplyTimer?.cancel();
    _levelApplyTimer = null;

    final brightness = _pendingBrightness;
    final volume = _pendingVolume;
    _pendingBrightness = null;
    _pendingVolume = null;

    if (brightness != null) {
      final actual = await _setScreenBrightness(brightness);
      if (settle && mounted && actual != null) {
        setState(() {
          _screenBrightness = actual;
          if (_gestureMode == 'brightness') _gestureValue = actual;
        });
      }
    }

    if (volume != null) {
      try {
        _controller?.setVolume(volume);
      } catch (_) {}
      final actual = await _setSystemVolume(volume);
      if (settle && mounted && actual != null) {
        setState(() {
          _appVolume = actual;
          if (_gestureMode == 'volume') _gestureValue = actual;
        });
        try {
          _controller?.setVolume(actual);
        } catch (_) {}
      }
    }
  }

  void _showSeekHint(Duration delta, {Duration? target}) {
    _seekHintTimer?.cancel();
    final sign = delta.isNegative ? '−' : '+';
    final seconds = delta.inSeconds.abs();
    final text = target == null
        ? '$sign${seconds}s'
        : '$sign${seconds}s  •  ${_fmt(target)}';
    setState(() => _seekHint = text);
    _seekHintTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _armGestureHideTimer() {
    _gestureHintTimer?.cancel();
    _gestureHintTimer = Timer(const Duration(milliseconds: 820), () {
      if (!mounted) return;
      setState(() => _gestureMode = null);
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (_controlsLocked) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _dragMode = null;
    _dragStart = details.localPosition;
    _dragStartPosition = controller.value.position;
    _pendingSeekPosition = null;
    _gestureHintTimer?.cancel();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_controlsLocked) return;
    final controller = _controller;
    final start = _dragStart;
    if (controller == null ||
        !controller.value.isInitialized ||
        start == null) {
      return;
    }

    final size = MediaQuery.of(context).size;
    final dx = details.localPosition.dx - start.dx;
    final dy = details.localPosition.dy - start.dy;

    _dragMode ??= dx.abs() > 18 || dy.abs() > 18
        ? (dx.abs() > dy.abs() ? 'seek' : 'level')
        : null;
    if (_dragMode == null) return;

    if (_dragMode == 'seek') {
      final duration = controller.value.duration;
      if (duration.inMilliseconds <= 0) return;
      final startPosition = _dragStartPosition ?? controller.value.position;
      final deltaSeconds = (dx / size.width * 180).round();
      final targetMs = (startPosition.inMilliseconds + deltaSeconds * 1000)
          .clamp(0, duration.inMilliseconds);
      final target = Duration(milliseconds: targetMs);
      _pendingSeekPosition = target;
      _showSeekHint(Duration(seconds: deltaSeconds), target: target);
      return;
    }

    final change = -dy / size.height * 1.35;
    final isLeft = start.dx < size.width / 2;
    if (isLeft) {
      final next = (_screenBrightness + change).clamp(0.05, 1.0);
      setState(() {
        _screenBrightness = next;
        _gestureMode = 'brightness';
        _gestureValue = next;
      });
      _pendingBrightness = next;
      _scheduleLevelApply();
      _armGestureHideTimer();
    } else {
      final next = (_appVolume + change).clamp(0.0, 1.0);
      setState(() {
        _appVolume = next;
        _gestureMode = 'volume';
        _gestureValue = next;
      });
      try {
        controller.setVolume(next);
      } catch (_) {}
      _pendingVolume = next;
      _scheduleLevelApply();
      _armGestureHideTimer();
    }
    _dragStart = details.localPosition;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_controlsLocked) return;
    final target = _pendingSeekPosition;
    if (_dragMode == 'seek' && target != null) {
      try {
        _controller?.seekTo(target);
      } catch (_) {}
      _saveProgress();
    }
    unawaited(_applyPendingLevels(settle: true));
    _dragMode = null;
    _dragStart = null;
    _dragStartPosition = null;
    _pendingSeekPosition = null;
    _revealControls();
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveProgress();
      _emitWatchSync();
    });
  }

  Future<void> _saveProgress() async {
    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
      final duration = controller.value.duration;
      final position = controller.value.position;
      if (duration.inMilliseconds <= 0 || position.inMilliseconds < 3000) {
        return;
      }
      final item = WatchHistoryItem.fromPlayback(
        movie: widget.movie,
        server: widget.server,
        episode: widget.episode,
        position: position,
        duration: duration,
      );
      await ref.read(cloudHistoryServiceProvider).save(item);
    } catch (_) {
      // Progress persistence must never interrupt playback.
    }
  }

  void _toggleLock() {
    if (!mounted) return;
    setState(() {
      _controlsLocked = !_controlsLocked;
      _showControls = !_controlsLocked;
    });
    if (!_controlsLocked) _armHideTimer();
  }

  void _toggleFullscreenFit() {
    if (!mounted) return;
    setState(() {
      _fitMode = switch (_fitMode) {
        _PlayerFitMode.contain => _PlayerFitMode.cover,
        _PlayerFitMode.cover => _PlayerFitMode.stretch,
        _PlayerFitMode.stretch => _PlayerFitMode.contain,
      };
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _revealControls();
  }

  String get _fitLabel => switch (_fitMode) {
    _PlayerFitMode.contain => 'Gốc',
    _PlayerFitMode.cover => 'Fit đầy',
    _PlayerFitMode.stretch => 'Kéo đầy',
  };

  IconData get _fitIcon => switch (_fitMode) {
    _PlayerFitMode.contain => Icons.fit_screen_rounded,
    _PlayerFitMode.cover => Icons.fullscreen_rounded,
    _PlayerFitMode.stretch => Icons.open_in_full_rounded,
  };

  Future<void> _showServerEpisodeSheet() async {
    if (_controlsLocked) return;
    _revealControls();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ServerEpisodeSheet(
        movie: widget.movie,
        currentServer: widget.server,
        currentEpisode: widget.episode,
        onSelect: (server, episode) {
          _switchingEpisode = true;
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CineVietPlayerScreen(
                movie: widget.movie,
                server: server,
                episode: episode,
              ),
            ),
          );
        },
        onSelectPart: _switchMoviePart,
      ),
    );
  }

  Future<void> _switchMoviePart(MoviePart part) async {
    if (_controlsLocked || part.id == widget.movie.id) return;
    _revealControls();
    Movie nextMovie;
    try {
      nextMovie = await ref
          .read(movieRepositoryProvider)
          .detail(part.id.toString());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa tải được phần phim này.')),
      );
      return;
    }
    if (!mounted || nextMovie.episodes.isEmpty) return;
    final server = nextMovie.episodes.first;
    if (server.items.isEmpty) return;
    _switchingEpisode = true;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CineVietPlayerScreen(
          movie: nextMovie,
          server: server,
          episode: server.items.first,
        ),
      ),
    );
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
      _emitWatchSync(force: true);
    } catch (_) {}
    _revealControls();
  }

  void _previewSeekToFraction(double value) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final progress = value.clamp(0.0, 1.0);
    final target = Duration(milliseconds: (durationMs * progress).round());
    setState(() {
      _scrubProgress = progress;
      _pendingSeekPosition = target;
      _seekHint = _fmt(target);
    });
    _seekHintTimer?.cancel();
    _revealControls();
  }

  Future<void> _commitSeekToFraction(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final progress = value.clamp(0.0, 1.0);
    final target = Duration(milliseconds: (durationMs * progress).round());
    setState(() {
      _scrubProgress = progress;
      _pendingSeekPosition = target;
      _seekHint = _fmt(target);
    });
    try {
      await controller.seekTo(target);
      _emitWatchSync(force: true);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _scrubProgress = null;
      _pendingSeekPosition = null;
    });
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _seekHint = null);
    });
    _revealControls();
    _saveProgress();
  }

  void _seekBy(Duration delta) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final current = controller.value.position;
    final duration = controller.value.duration;
    final targetMs = (current + delta).inMilliseconds.clamp(
      0,
      duration.inMilliseconds,
    );
    try {
      controller.seekTo(Duration(milliseconds: targetMs));
      _emitWatchSync(force: true);
    } catch (_) {}
    _showSeekHint(delta);
    _revealControls();
    _saveProgress();
  }

  int get _currentEpisodeIndex {
    final items = widget.server.items;
    final byLink = items.indexWhere(
      (item) =>
          item.linkM3u8 == widget.episode.linkM3u8 &&
          item.linkEmbed == widget.episode.linkEmbed,
    );
    if (byLink >= 0) return byLink;
    return items.indexWhere((item) => item.name == widget.episode.name);
  }

  void _playSiblingEpisode(int offset) {
    final items = widget.server.items;
    if (items.isEmpty) return;
    final current = _currentEpisodeIndex;
    if (current < 0) return;
    final next = current + offset;
    if (next < 0 || next >= items.length) return;
    _switchingEpisode = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CineVietPlayerScreen(
          movie: widget.movie,
          server: widget.server,
          episode: items[next],
        ),
      ),
    );
  }

  void _playPreviousEpisode() => _playSiblingEpisode(-1);

  void _playNextEpisode() => _playSiblingEpisode(1);

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!mounted || _controlsLocked) return;
            setState(() => _showControls = !_showControls);
            if (_showControls) _armHideTimer();
          },
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onDoubleTapDown: (details) {
            if (_controlsLocked) return;
            final width = MediaQuery.of(context).size.width;
            _seekBy(
              Duration(
                seconds: details.localPosition.dx < width / 2 ? -10 : 10,
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildVideo(),
              if (_screenBrightness < 0.99)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha: (1 - _screenBrightness).clamp(0.0, 0.72),
                    ),
                  ),
                ),
              if (_controlsLocked) _buildLockedButton(),
              _buildGestureHint(),
              if (_buffering && !_loading) _buildBufferingBadge(),
              if (_isWatchTogether) _buildWatchTogetherChatPanel(),
              if (!_controlsLocked &&
                  (_showControls || _loading || _error != null))
                _buildOverlay(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWatchTogetherChatPanel() {
    final code = _watchRoomCode ?? '';
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 720;
    final panelWidth = isCompact ? width * 0.48 : 360.0;
    final top = isCompact ? 16.0 : 24.0;
    final right = isCompact ? 12.0 : 24.0;

    return Positioned(
      top: top,
      right: right,
      bottom: isCompact ? 84.0 : 110.0,
      width: panelWidth.clamp(260.0, 380.0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _watchChatVisible
            ? _WatchTogetherChatPanel(
                key: const ValueKey('watch-chat-panel'),
                code: code,
                messages: _watchMessages,
                inputController: _watchChatController,
                onSend: _sendWatchMessage,
                onHide: () => setState(() => _watchChatVisible = false),
              )
            : Align(
                key: const ValueKey('watch-chat-toggle'),
                alignment: Alignment.topRight,
                child: _WatchChatToggleButton(
                  code: code,
                  count: _watchMessages.length,
                  onTap: () => setState(() => _watchChatVisible = true),
                ),
              ),
      ),
    );
  }

  Widget _buildVideo() {
    final controller = _controller;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: CineVietColors.accent),
      );
    }
    if (_error != null &&
        (controller == null || !controller.value.isInitialized)) {
      return Center(
        child: Container(
          width: 520,
          margin: const EdgeInsets.all(CineVietSpacing.xl),
          padding: const EdgeInsets.all(CineVietSpacing.xl),
          decoration: BoxDecoration(
            color: CineVietColors.card.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(CineVietRadius.xl),
            border: Border.all(color: CineVietColors.borderLight),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 40,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: CineVietColors.accent,
                size: 48,
              ),
              const SizedBox(height: CineVietSpacing.md),
              const Text(
                'Không phát được phim',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: CineVietSpacing.sm),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CineVietColors.textSoft,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: CineVietSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: CineVietSpacing.sm,
                runSpacing: CineVietSpacing.sm,
                children: [
                  if (Platform.isAndroid && _rawStreamUrl.trim().isNotEmpty)
                    TvFocus(
                      onTap: _openExternalPlayer,
                      borderRadius: BorderRadius.circular(CineVietRadius.full),
                      child: FilledButton.icon(
                        onPressed: _openExternalPlayer,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Mở bằng VLC/MX'),
                      ),
                    ),
                  TvFocus(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(CineVietRadius.full),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Quay lại'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final aspectRatio = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    final fit = switch (_fitMode) {
      _PlayerFitMode.contain => BoxFit.contain,
      _PlayerFitMode.cover => BoxFit.cover,
      _PlayerFitMode.stretch => BoxFit.fill,
    };
    return SizedBox.expand(
      child: FittedBox(
        fit: fit,
        alignment: Alignment.center,
        child: SizedBox(
          width: aspectRatio * 1000,
          height: 1000,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildGestureHint() {
    final mode = _gestureMode ?? '';
    final value = (_gestureValue ?? 0).clamp(0.0, 1.0);
    final isBrightness = mode == 'brightness';
    final icon = isBrightness
        ? Icons.brightness_6_rounded
        : value <= 0.02
        ? Icons.volume_off_rounded
        : Icons.volume_up_rounded;
    final label = isBrightness ? 'Độ sáng' : 'Âm lượng';

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _gestureMode == null ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Align(
          alignment: isBrightness
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CineVietSpacing.lg),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CineVietRadius.full),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  width: 78,
                  height: 268,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CineVietSpacing.sm,
                    vertical: CineVietSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.46),
                    borderRadius: BorderRadius.circular(CineVietRadius.full),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CineVietColors.accent.withValues(alpha: 0.18),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          icon,
                          key: ValueKey(icon),
                          color: CineVietColors.accent,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: CineVietSpacing.sm),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Container(
                                width: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(
                                    CineVietRadius.full,
                                  ),
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 110),
                                curve: Curves.easeOutCubic,
                                width: 12,
                                height: constraints.maxHeight * value,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    CineVietRadius.full,
                                  ),
                                  gradient: const LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      CineVietColors.accent,
                                      Color(0xFF7FFFD4),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: CineVietSpacing.sm),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 140),
                        child: Text(
                          '${(value * 100).round()}%',
                          key: ValueKey((value * 100).round()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CineVietColors.textSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockedButton() => SafeArea(
    child: Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: TvFocus(
          onTap: _toggleLock,
          autofocus: true,
          borderRadius: BorderRadius.circular(CineVietRadius.full),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              shape: BoxShape.circle,
              border: Border.all(
                color: CineVietColors.accent.withValues(alpha: 0.55),
              ),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              color: CineVietColors.accent,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildBufferingBadge() => const Center(
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(CineVietSpacing.lg),
        child: CircularProgressIndicator(color: CineVietColors.accent),
      ),
    ),
  );

  Widget _buildOverlay(BuildContext context) {
    return AnimatedOpacity(
      opacity: _showControls || _loading || _error != null ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.42),
              Colors.black.withValues(alpha: 0.02),
              Colors.black.withValues(alpha: 0.52),
            ],
            stops: const [0, 0.48, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CineVietSpacing.lg,
              CineVietSpacing.md,
              CineVietSpacing.lg,
              CineVietSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlayerTopBar(
                  title: widget.movie.title,
                  subtitle:
                      '${widget.server.displayName} • ${widget.episode.displayName}',
                  resumeText: _resumeItem != null && !_resumeItem!.completed
                      ? 'Tiếp tục từ ${_fmt(_resumeItem!.position)}'
                      : null,
                  onBack: () => Navigator.of(context).maybePop(),
                  onLock: _toggleLock,
                ),
                const Spacer(),
                _buildControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final duration = value.duration;
        final position = value.position > duration ? duration : value.position;
        final progress = duration.inMilliseconds <= 0
            ? 0.0
            : position.inMilliseconds / duration.inMilliseconds;
        final displayProgress = (_scrubProgress ?? progress).clamp(0.0, 1.0);
        final displayPosition = _pendingSeekPosition ?? position;
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 34,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    _seekHint ?? _fmt(displayPosition),
                    style: const TextStyle(
                      color: CineVietColors.accent,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 6,
                        activeTrackColor: CineVietColors.accent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: CineVietColors.accent,
                        overlayColor: CineVietColors.accentGlow,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: displayProgress,
                        onChangeStart: _previewSeekToFraction,
                        onChanged: _previewSeekToFraction,
                        onChangeEnd: _commitSeekToFraction,
                      ),
                    ),
                  ),
                  Text(
                    _fmt(duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width - 56,
                  child: Row(
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: _PlayerRoundButton(
                          icon: Icons.playlist_play_rounded,
                          label: 'Server / Tập',
                          onTap: () => _showServerEpisodeSheet(),
                        ),
                      ),
                      const Spacer(),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: _PlayerRoundButton(
                          icon: Icons.skip_previous_rounded,
                          label: 'Tập trước',
                          onTap: _playPreviousEpisode,
                        ),
                      ),
                      const SizedBox(width: CineVietSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: _PlayerRoundButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Lùi 10s',
                          onTap: () => _seekBy(const Duration(seconds: -10)),
                        ),
                      ),
                      const SizedBox(width: CineVietSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(4),
                        child: _PlayerRoundButton(
                          icon: value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          label: value.isPlaying ? 'Tạm dừng' : 'Phát',
                          primary: true,
                          large: true,
                          autofocus: true,
                          onTap: _togglePlay,
                        ),
                      ),
                      const SizedBox(width: CineVietSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(5),
                        child: _PlayerRoundButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Tới 10s',
                          onTap: () => _seekBy(const Duration(seconds: 10)),
                        ),
                      ),
                      const SizedBox(width: CineVietSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(6),
                        child: _PlayerRoundButton(
                          icon: Icons.skip_next_rounded,
                          label: 'Tập sau',
                          onTap: _playNextEpisode,
                        ),
                      ),
                      const Spacer(),
                      if (Platform.isAndroid && _rawStreamUrl.trim().isNotEmpty)
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(7),
                          child: _PlayerRoundButton(
                            icon: Icons.open_in_new_rounded,
                            label: 'VLC/MX',
                            onTap: _openExternalPlayer,
                          ),
                        ),
                      if (Platform.isAndroid && _rawStreamUrl.trim().isNotEmpty)
                        const SizedBox(width: CineVietSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(8),
                        child: _PlayerRoundButton(
                          icon: _fitIcon,
                          label: _fitLabel,
                          onTap: _toggleFullscreenFit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WatchTogetherChatPanel extends StatelessWidget {
  const _WatchTogetherChatPanel({
    super.key,
    required this.code,
    required this.messages,
    required this.inputController,
    required this.onSend,
    required this.onHide,
  });

  final String code;
  final List<WatchTogetherMessage> messages;
  final TextEditingController inputController;
  final VoidCallback onSend;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final recentMessages = messages.length > 80
        ? messages.sublist(messages.length - 80)
        : messages;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 32,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: CineVietColors.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: CineVietColors.accent,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chat xem chung',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Mã phòng: $code',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CineVietColors.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onHide,
                      icon: const Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Ẩn chat',
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
              Expanded(
                child: recentMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có tin nhắn',
                          style: TextStyle(color: CineVietColors.textSoft),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        itemCount: recentMessages.length,
                        itemBuilder: (context, index) {
                          final message =
                              recentMessages[recentMessages.length - 1 - index];
                          return _WatchMessageBubble(message: message);
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inputController,
                        minLines: 1,
                        maxLines: 2,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Nhắn tin...',
                          hintStyle: const TextStyle(
                            color: CineVietColors.textSoft,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: FilledButton(
                        onPressed: onSend,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: CineVietColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Icon(Icons.send_rounded, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchMessageBubble extends StatelessWidget {
  const _WatchMessageBubble({required this.message});

  final WatchTogetherMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          message.payload,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: CineVietColors.textSoft,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.userName?.trim().isNotEmpty == true
                ? message.userName!.trim()
                : 'Thành viên',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CineVietColors.accent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            message.payload,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchChatToggleButton extends StatelessWidget {
  const _WatchChatToggleButton({
    required this.code,
    required this.count,
    required this.onTap,
  });

  final String code;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.chat_bubble_rounded, size: 18),
      label: Text('Chat • $code${count > 0 ? ' ($count)' : ''}'),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.62),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CineVietRadius.full),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
    );
  }
}

class _ServerEpisodeSheet extends StatelessWidget {
  const _ServerEpisodeSheet({
    required this.movie,
    required this.currentServer,
    required this.currentEpisode,
    required this.onSelect,
    required this.onSelectPart,
  });

  final Movie movie;
  final EpisodeServer currentServer;
  final EpisodeItem currentEpisode;
  final void Function(EpisodeServer server, EpisodeItem episode) onSelect;
  final void Function(MoviePart part) onSelectPart;

  bool _isCurrent(EpisodeServer server, EpisodeItem episode) {
    return server.name == currentServer.name &&
        episode.name == currentEpisode.name &&
        episode.linkM3u8 == currentEpisode.linkM3u8 &&
        episode.linkEmbed == currentEpisode.linkEmbed;
  }

  @override
  Widget build(BuildContext context) {
    final servers = movie.episodes;
    final parts = movie.parts;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: CineVietColors.bg.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Server & danh sách tập',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
            if (parts.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                'Phần phim',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final part in parts) ...[
                      _EpisodeChip(
                        label: 'Phần ${part.partNumber}',
                        selected: part.id == movie.id,
                        onTap: () => onSelectPart(part),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: servers.length,
                separatorBuilder: (_, index) => const SizedBox(height: 16),
                itemBuilder: (context, serverIndex) {
                  final server = servers[serverIndex];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.displayName,
                        style: const TextStyle(
                          color: CineVietColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final episode in server.items)
                            _EpisodeChip(
                              label: episode.displayName,
                              selected: _isCurrent(server, episode),
                              onTap: () => onSelect(server, episode),
                            ),
                        ],
                      ),
                    ],
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

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onTap: selected ? null : onTap,
      borderRadius: BorderRadius.circular(CineVietRadius.full),
      enabled: !selected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? CineVietColors.accent
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(CineVietRadius.full),
          border: Border.all(
            color: selected
                ? CineVietColors.accent
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF061A13) : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onLock,
    this.resumeText,
  });

  final String title;
  final String subtitle;
  final String? resumeText;
  final VoidCallback onBack;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CineVietSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(CineVietRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          TvFocus(
            onTap: onBack,
            borderRadius: BorderRadius.circular(CineVietRadius.full),
            child: _PlayerIconPill(icon: Icons.arrow_back_rounded),
          ),
          const SizedBox(width: CineVietSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: CineVietSpacing.sm,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CineVietColors.textSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (resumeText != null)
                      Text(
                        resumeText!,
                        style: const TextStyle(
                          color: CineVietColors.accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CineVietSpacing.sm),
          TvFocus(
            onTap: onLock,
            borderRadius: BorderRadius.circular(CineVietRadius.full),
            child: _PlayerIconPill(icon: Icons.lock_rounded),
          ),
        ],
      ),
    );
  }
}

class _PlayerIconPill extends StatelessWidget {
  const _PlayerIconPill({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }
}

class _PlayerRoundButton extends StatelessWidget {
  const _PlayerRoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.large = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool large;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final size = large ? 58.0 : 48.0;
    return TvFocus(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CineVietRadius.full),
      scale: 1.07,
      autofocus: autofocus,
      child: Tooltip(
        message: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: primary
                ? CineVietColors.accent
                : Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: primary
                  ? CineVietColors.accent
                  : Colors.white.withValues(alpha: 0.18),
            ),
            boxShadow: primary
                ? const [
                    BoxShadow(color: CineVietColors.accentGlow, blurRadius: 22),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: primary ? CineVietColors.bg : Colors.white,
            size: large ? 34 : 26,
          ),
        ),
      ),
    );
  }
}
