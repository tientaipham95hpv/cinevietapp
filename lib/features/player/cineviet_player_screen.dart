import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/cineviet_colors.dart';
import '../../core/theme/cineviet_dimensions.dart';
import '../../core/widgets/tv_focus.dart';
import '../../data/models/movie.dart';
import '../../data/models/watch_history.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/services/cloud_history_service.dart';

class CineVietPlayerScreen extends ConsumerStatefulWidget {
  const CineVietPlayerScreen({
    super.key,
    required this.movie,
    required this.server,
    required this.episode,
  });
  final Movie movie;
  final EpisodeServer server;
  final EpisodeItem episode;

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
  bool _fitToScreen = false;
  double _appVolume = 1.0;
  double _screenBrightness = 1.0;
  Timer? _gestureHintTimer;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _seekHintTimer;
  WatchHistoryItem? _resumeItem;

  String get _streamUrl => widget.episode.linkM3u8?.isNotEmpty == true
      ? widget.episode.linkM3u8!
      : widget.episode.linkEmbed?.isNotEmpty == true
      ? widget.episode.linkEmbed!
      : '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);
    _loadScreenBrightness();
    _loadSystemVolume();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (_streamUrl.isEmpty || !_streamUrl.startsWith(RegExp(r'https?://'))) {
      setState(() {
        _loading = false;
        _error = 'Tập này chưa có link m3u8 hợp lệ để phát.';
      });
      return;
    }

    VideoPlayerController controller;
    try {
      // ignore: deprecated_member_use
      controller = VideoPlayerController.network(
        _streamUrl,
        formatHint: VideoFormat.hls,
        httpHeaders: <String, String>{},
      );
      _controller = controller;
      controller.addListener(_syncPlayerState);
      await controller.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không mở được stream: $e';
      });
      return;
    }

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
      await controller.play();
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
    _saveProgress();
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

  void _syncPlayerState() {
    final value = _controller?.value;
    if (!mounted || value == null) return;
    final buffering = value.isBuffering;
    final playbackError = value.errorDescription;
    if (buffering != _buffering ||
        playbackError != _error && playbackError != null) {
      setState(() {
        _buffering = buffering;
        if (playbackError != null) _error = playbackError;
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

  void _showGestureHint(String mode, double value) {
    _gestureHintTimer?.cancel();
    setState(() {
      _gestureMode = mode;
      _gestureValue = value.clamp(0.0, 1.0);
    });
    _gestureHintTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      setState(() {
        _gestureMode = null;
        _gestureValue = null;
      });
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
      setState(() => _screenBrightness = next);
      _setScreenBrightness(next).then((actual) {
        if (!mounted || actual == null) return;
        setState(() => _screenBrightness = actual);
      });
      _showGestureHint('brightness', next);
    } else {
      final next = (_appVolume + change).clamp(0.0, 1.0);
      setState(() => _appVolume = next);
      try {
        controller.setVolume(next);
      } catch (_) {}
      _setSystemVolume(next).then((actual) {
        if (!mounted || actual == null) return;
        setState(() => _appVolume = actual);
        try {
          controller.setVolume(actual);
        } catch (_) {}
      });
      _showGestureHint('volume', next);
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
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
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
    setState(() => _fitToScreen = !_fitToScreen);
    SystemChrome.setEnabledSystemUIMode(
      _fitToScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _revealControls();
  }

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
    } catch (_) {}
    _revealControls();
  }

  void _seekToFraction(double value) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final target = Duration(
      milliseconds: (durationMs * value.clamp(0, 1)).round(),
    );
    try {
      controller.seekTo(target);
    } catch (_) {}
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
              if (_gestureMode != null && _gestureValue != null)
                _buildGestureHint(),
              if (_buffering && !_loading) _buildBufferingBadge(),
              if (!_controlsLocked &&
                  (_showControls || _loading || _error != null))
                _buildOverlay(context),
            ],
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
              TvFocus(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(CineVietRadius.full),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Quay lại'),
                ),
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
    if (_fitToScreen) {
      return Center(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: aspectRatio * 1000,
            height: 1000,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: VideoPlayer(controller),
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

    return Align(
      alignment: isBrightness ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CineVietSpacing.lg),
        child: Container(
          width: 72,
          height: 250,
          padding: const EdgeInsets.symmetric(
            horizontal: CineVietSpacing.sm,
            vertical: CineVietSpacing.md,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(CineVietRadius.full),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            children: [
              Icon(icon, color: CineVietColors.accent, size: 24),
              const SizedBox(height: CineVietSpacing.sm),
              Expanded(
                child: RotatedBox(
                  quarterTurns: -1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(CineVietRadius.full),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: Colors.white24,
                      color: CineVietColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: CineVietSpacing.sm),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
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
                    _seekHint ?? _fmt(position),
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
                        value: progress.clamp(0, 1),
                        onChanged: _seekToFraction,
                        onChangeEnd: (_) => _saveProgress(),
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
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(7),
                        child: _PlayerRoundButton(
                          icon: _fitToScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          label: _fitToScreen ? 'Fit gốc' : 'Fit màn hình',
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

class _ServerEpisodeSheet extends StatelessWidget {
  const _ServerEpisodeSheet({
    required this.movie,
    required this.currentServer,
    required this.currentEpisode,
    required this.onSelect,
  });

  final Movie movie;
  final EpisodeServer currentServer;
  final EpisodeItem currentEpisode;
  final void Function(EpisodeServer server, EpisodeItem episode) onSelect;

  bool _isCurrent(EpisodeServer server, EpisodeItem episode) {
    return server.name == currentServer.name &&
        episode.name == currentEpisode.name &&
        episode.linkM3u8 == currentEpisode.linkM3u8 &&
        episode.linkEmbed == currentEpisode.linkEmbed;
  }

  @override
  Widget build(BuildContext context) {
    final servers = movie.episodes;
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
