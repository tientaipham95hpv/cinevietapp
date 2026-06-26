import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpHeaders, Platform;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
    this.initialResumeItem,
  });
  final Movie movie;
  final EpisodeServer server;
  final EpisodeItem episode;
  final WatchTogetherState? watchTogetherState;
  final String? watchTogetherCode;
  final WatchHistoryItem? initialResumeItem;

  @override
  ConsumerState<CineVietPlayerScreen> createState() =>
      _CineVietPlayerScreenState();
}

class _CineVietPlayerScreenState extends ConsumerState<CineVietPlayerScreen>
    with WidgetsBindingObserver {
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
  _PlayerFitMode _fitMode = _PlayerFitMode.contain;
  double _appVolume = 1.0;
  double _screenBrightness = 1.0;
  Timer? _gestureHintTimer;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _videoOutputWatchdogTimer;
  Timer? _seekHintTimer;
  Timer? _levelApplyTimer;
  double? _pendingBrightness;
  double? _pendingVolume;
  WatchHistoryItem? _resumeItem;
  int? _resumeTargetMs;
  bool _watchChatVisible = true;
  final List<WatchTogetherMessage> _watchMessages = [];
  final TextEditingController _watchChatController = TextEditingController();
  WatchTogetherState? _watchRoomState;
  String? _lastWatchRoomFrom;
  int _lastWatchSyncSentAt = 0;
  bool _applyingWatchSync = false;
  bool _recoveringPlaybackError = false;
  static const bool _isAndroidTvBuild = bool.fromEnvironment('APP_IS_TV');
  EpisodeSubtitle? _selectedSubtitle;
  List<_SubtitleCue> _subtitleCues = const [];
  bool _subtitleLoading = false;
  String? _subtitleError;
  double _playbackSpeed = 1.0;
  bool _autoNextEpisode = true;
  bool _autoNextTriggered = false;
  static const String _autoNextPrefKey = 'player_auto_next_episode';
  List<String> _activeCandidateUrls = const [];
  int _activeCandidateIndex = 0;

  VideoPlayerController _createVideoController(String streamUrl) {
    // Android texture rendering is fragile on some TV boxes/tablets: ExoPlayer
    // can keep audio playing while Flutter's texture stays blank. PlatformView
    // uses the native video surface and is more reliable for these devices.
    // ignore: deprecated_member_use
    return VideoPlayerController.network(
      streamUrl,
      formatHint: VideoFormat.hls,
      httpHeaders: _headersForStreamUrl(streamUrl),
      viewType: Platform.isAndroid
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    );
  }
  WebViewController? _embedController;
  double? _scrubProgress;
  final FocusNode _progressFocusNode = FocusNode(debugLabel: 'PlayerProgress');
  final FocusNode _playControlFocusNode = FocusNode(
    debugLabel: 'PlayerPlayControl',
  );
  bool _progressFocused = false;

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

  bool get _supportsEmbedFallback =>
      !_isAndroidTvBuild && (Platform.isAndroid || Platform.isIOS);

  String _embedUrlOf(EpisodeItem episode) {
    return (episode.linkEmbed ?? '').trim();
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

  // Classify a server by its audio/subtitle variant so cross-source fallback
  // never silently switches between Vietsub / Thuyết Minh / Lồng Tiếng. The
  // canonical names from ophim/kkphim are full words ("Vietsub", "Thuyết
  // Minh", "Lồng Tiếng"), optionally tagged with the source in brackets.
  String _serverAudioType(String serverName) {
    final n = serverName.toLowerCase();
    if (n.contains('thuyết minh') ||
        n.contains('thuyet minh') ||
        n.contains('thuyetminh')) {
      return 'tm';
    }
    if (n.contains('lồng tiếng') ||
        n.contains('long tieng') ||
        n.contains('longtieng')) {
      return 'lt';
    }
    if (n.contains('vietsub') || n.contains('viet sub') || n.contains('vsub')) {
      return 'vs';
    }
    return 'unknown';
  }

  List<MapEntry<EpisodeServer, EpisodeItem>>
  get _candidateEpisodesForAndroidTv {
    final currentKey = _episodeKey(widget.episode);
    final selectedAudio = _serverAudioType(widget.server.name);
    final out = <MapEntry<EpisodeServer, EpisodeItem>>[];
    for (final server in widget.movie.episodes) {
      for (final episode in server.items) {
        final url = _streamUrlOf(episode);
        if (url.isEmpty || !url.startsWith(RegExp(r'https?://'))) continue;
        final sameEpisode =
            _episodeKey(episode) == currentKey ||
            episode.displayName == widget.episode.displayName;
        if (!sameEpisode) continue;
        // Never fall back across audio variants: a Thuyết Minh pick must not
        // resolve to a Vietsub stream (and vice-versa). Only the exact chosen
        // server is exempt so the user's selection is always playable.
        final isExactChoice =
            server.name == widget.server.name &&
            _streamUrlOf(episode) == _rawStreamUrl;
        if (!isExactChoice && _serverAudioType(server.name) != selectedAudio) {
          continue;
        }
        out.add(MapEntry(server, episode));
      }
    }
    if (out.isEmpty) return [MapEntry(widget.server, widget.episode)];

    out.sort((a, b) {
      // The user's chosen server+episode always wins. Source priority only
      // decides ordering among the remaining same-audio fallbacks.
      final aCurrent =
          identical(a.value, widget.episode) ||
          (_streamUrlOf(a.value) == _rawStreamUrl &&
              a.key.name == widget.server.name);
      final bCurrent =
          identical(b.value, widget.episode) ||
          (_streamUrlOf(b.value) == _rawStreamUrl &&
              b.key.name == widget.server.name);
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
      final byServer = _androidTvServerPriority(
        a.key,
      ).compareTo(_androidTvServerPriority(b.key));
      if (byServer != 0) return byServer;
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

  Map<String, String> _headersForStreamUrl(String streamUrl) {
    final uri = Uri.tryParse(streamUrl);
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isEmpty || host == 'cineviet.live') {
      return const <String, String>{};
    }
    if (host.contains('opstream')) {
      return const <String, String>{
        'Referer': 'https://ophim1.com/',
        'Origin': 'https://ophim1.com',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 12; Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
    }
    if (host.contains('phim1280') ||
        host.contains('kkphimplayer') ||
        host.contains('phimapi')) {
      return const <String, String>{
        'Referer': 'https://phimapi.com/',
        'Origin': 'https://phimapi.com',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 12; Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
    }
    return const <String, String>{};
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
        final alreadyProxy =
            parsed?.host == 'cineviet.live' && parsed?.path == '/api/stream';

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

        final preferred = alreadyProxy
            ? sourceUrl
            : _proxiedStreamUrl(sourceUrl, androidTvSafe: true);
        // Keep fallback per source: Ophim proxy -> Ophim direct -> PhimAPI proxy
        // -> PhimAPI direct -> others. If the proxy is blocked by a CDN, we do
        // not skip the preferred source entirely.
        if (seen.add(preferred)) urls.add(preferred);
        if (!alreadyProxy && seen.add(sourceUrl)) urls.add(sourceUrl);
      }
      return urls;
    }

    final parsed = Uri.tryParse(raw);
    final alreadyProxy =
        parsed?.host == 'cineviet.live' && parsed?.path == '/api/stream';
    if (!Platform.isWindows || alreadyProxy) return [raw];

    final proxy = _proxiedStreamUrl(raw, androidTvSafe: false);
    // Windows keeps original-first behavior; Android TV uses safer proxy-first
    // multi-source logic above.
    return [raw, proxy];
  }

  List<String> get _candidateEmbedUrls {
    if (!_supportsEmbedFallback) return const [];
    final urls = <String>[];
    final seen = <String>{};
    for (final entry in _candidateEpisodesForAndroidTv) {
      final embed = _embedUrlOf(entry.value);
      if (embed.isEmpty || !embed.startsWith(RegExp(r'https?://'))) continue;
      if (seen.add(embed)) urls.add(embed);
    }
    return urls;
  }

  bool _activateEmbedFallback({String? reason}) {
    final embedUrl = _candidateEmbedUrls.firstOrNull;
    if (embedUrl == null || embedUrl.isEmpty) return false;

    try {
      _controller?.removeListener(_syncPlayerState);
      _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _progressTimer?.cancel();

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(Uri.parse(embedUrl));

    if (!mounted) return true;
    setState(() {
      _embedController = controller;
      _loading = false;
      _buffering = false;
      _error = null;
      _showControls = true;
    });
    _armHideTimer();
    return true;
  }

  List<_SubtitleCue> _parseWebVtt(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n\s*\n'));
    final cues = <_SubtitleCue>[];
    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((e) => e.trim())
          .where(
            (e) =>
                e.isNotEmpty &&
                !e.startsWith('WEBVTT') &&
                !e.startsWith('NOTE'),
          )
          .toList();
      if (lines.isEmpty) continue;
      final timeIndex = lines.indexWhere((l) => l.contains('-->'));
      if (timeIndex < 0) continue;
      final parts = lines[timeIndex].split('-->');
      if (parts.length < 2) continue;
      final start = _parseSubtitleTime(parts[0]);
      final end = _parseSubtitleTime(parts[1].split(RegExp(r'\s+')).first);
      if (start == null || end == null || end <= start) continue;
      final body = lines
          .skip(timeIndex + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
      if (body.isEmpty) continue;
      cues.add(_SubtitleCue(start: start, end: end, text: body));
    }
    return cues;
  }

  Duration? _parseSubtitleTime(String raw) {
    final clean = raw.trim().replaceAll(',', '.');
    final match = RegExp(
      r'(?:(\d+):)?(\d{2}):(\d{2})\.(\d{1,3})',
    ).firstMatch(clean);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final millis =
        int.tryParse(
          (match.group(4) ?? '0').padRight(3, '0').substring(0, 3),
        ) ??
        0;
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  Future<void> _loadSelectedSubtitle() async {
    final subtitle = _selectedSubtitle;
    if (subtitle == null) {
      if (!mounted) return;
      setState(() {
        _subtitleCues = const [];
        _subtitleError = null;
        _subtitleLoading = false;
      });
      return;
    }
    if (mounted) {
      setState(() {
        _subtitleLoading = true;
        _subtitleError = null;
      });
    }
    try {
      final uri = Uri.parse(subtitle.url);
      final res = await HttpClient()
          .getUrl(uri)
          .then((req) {
            req.headers.set(HttpHeaders.userAgentHeader, 'CineVietFlutter/1.0');
            req.headers.set(
              HttpHeaders.refererHeader,
              'https://cineviet.live/',
            );
            return req.close();
          })
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final cues = _parseWebVtt(body);
      if (!mounted) return;
      setState(() {
        _subtitleCues = cues;
        _subtitleLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _subtitleCues = const [];
        _subtitleLoading = false;
        _subtitleError = 'Không tải được phụ đề';
      });
    }
  }

  Future<void> _selectSubtitle(EpisodeSubtitle? subtitle) async {
    setState(() {
      _selectedSubtitle = subtitle;
      _subtitleCues = const [];
      _subtitleError = null;
    });
    await _loadSelectedSubtitle();
  }

  String _activeSubtitleText(Duration position) {
    for (final cue in _subtitleCues) {
      if (position >= cue.start && position <= cue.end) return cue.text;
    }
    return '';
  }

  Future<void> _showSubtitleSheet() async {
    final subtitles = widget.episode.subtitles;
    if (subtitles.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SubtitleSheet(
        subtitles: subtitles,
        selected: _selectedSubtitle,
        onSelect: (subtitle) {
          Navigator.of(context).pop();
          unawaited(_selectSubtitle(subtitle));
        },
      ),
    );
  }

  String _formatSpeed(double speed) {
    return speed == speed.truncateToDouble()
        ? '${speed.toStringAsFixed(0)}x'
        : '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')}x';
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final nextSpeed = speed.clamp(0.25, 3.0);
    setState(() {
      _playbackSpeed = nextSpeed;
    });
    try {
      await controller.setPlaybackSpeed(nextSpeed);
    } catch (_) {
      // Playback speed should never block viewing.
    }
    _revealControls();
  }

  Future<void> _showSettingsSheet() async {
    const speeds = <double>[
      0.25,
      0.5,
      0.75,
      1.0,
      1.25,
      1.5,
      1.75,
      2.0,
      2.5,
      3.0,
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        // StatefulBuilder so the auto-next toggle / selected speed update
        // instantly inside the sheet without closing it.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: CineVietColors.card.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CineVietColors.borderLight),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.settings_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Cài đặt',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _autoNextEpisode,
                      activeThumbColor: CineVietColors.accent,
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        Icons.playlist_play_rounded,
                        color: Colors.white70,
                      ),
                      title: const Text(
                        'Tự chuyển tập',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: const Text(
                        'Tự phát tập tiếp theo khi hết tập',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      onChanged: (value) {
                        setSheetState(() {});
                        unawaited(_setAutoNextEpisode(value));
                      },
                    ),
                    const Divider(color: CineVietColors.borderLight),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Tốc độ phát',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final speed in speeds)
                              _SubtitleTile(
                                label: speed == 1.0
                                    ? 'Bình thường 1x'
                                    : _formatSpeed(speed),
                                selected: _playbackSpeed == speed,
                                onTap: () {
                                  setSheetState(() {});
                                  unawaited(_setPlaybackSpeed(speed));
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(WakelockPlus.enable());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);
    _watchRoomState = widget.watchTogetherState;
    _watchMessages.addAll(widget.watchTogetherState?.messages ?? const []);
    _bindWatchTogetherSocket();
    _syncBrightnessWithDevice();
    _loadSystemVolume();
    _selectedSubtitle = widget.episode.subtitles.isNotEmpty
        ? widget.episode.subtitles.first
        : null;
    unawaited(_loadSelectedSubtitle());
    unawaited(_loadAutoNextPref());
    _initPlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      try {
        _controller?.pause();
      } catch (_) {}
      unawaited(_saveProgress());
    }
  }

  Future<void> _loadAutoNextPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_autoNextPrefKey);
      if (value != null && mounted) {
        setState(() => _autoNextEpisode = value);
      }
    } catch (_) {
      // Preference read must never block playback.
    }
  }

  Future<void> _setAutoNextEpisode(bool value) async {
    if (mounted) setState(() => _autoNextEpisode = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoNextPrefKey, value);
    } catch (_) {
      // Preference write must never block playback.
    }
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
      if (_activateEmbedFallback(reason: 'no-hls-candidate')) return;
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
        final nextController = _createVideoController(streamUrl);
        _controller = nextController;
        nextController.addListener(_syncPlayerState);
        await nextController.initialize().timeout(
          Platform.isWindows
              ? const Duration(seconds: 12)
              : const Duration(seconds: 30),
        );
        try {
          await nextController.setPlaybackSpeed(_playbackSpeed);
        } catch (_) {}
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
      if (_activateEmbedFallback(reason: '$lastError')) return;
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
      _resumeItem =
          widget.initialResumeItem ??
          await ref
              .read(watchHistoryServiceProvider)
              .find(widget.movie.slug, widget.server.name, widget.episode.name);
      final resume = _resumeItem;
      if (resume != null &&
          !resume.completed &&
          resume.positionMs > 10000 &&
          resume.durationMs > 0) {
        _resumeTargetMs = resume.positionMs;
        await _applyResumeSeek(controller);
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
    _startVideoOutputWatchdog();
    _armHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _videoOutputWatchdogTimer?.cancel();
    _seekHintTimer?.cancel();
    _gestureHintTimer?.cancel();
    _levelApplyTimer?.cancel();
    _saveProgress();
    if (_isWatchTogether && _isWatchHost) {
      WatchTogetherService.closeActiveRoom(forceDelete: true);
    }
    HardwareKeyboard.instance.removeHandler(_handleRemoteKey);
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        controller.removeListener(_syncPlayerState);
        unawaited(controller.pause());
        unawaited(controller.setVolume(0));
        unawaited(controller.dispose());
      } catch (_) {}
    }
    _embedController = null;
    unawaited(WakelockPlus.disable());
    unawaited(_resetScreenBrightness());
    if (!_switchingEpisode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _watchChatController.dispose();
    _progressFocusNode.dispose();
    _playControlFocusNode.dispose();
    super.dispose();
  }

  bool _handleRemoteKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Khi đang gõ vào ô nhập liệu (vd chat Xem chung trên iPad + Magic
    // Keyboard), không nuốt phím space/enter/mũi tên cho điều khiển player.
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.widget is EditableText ||
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    final key = event.logicalKey;
    final focusContext = focus?.context;
    final focusInPlayerChrome =
        _showControls &&
        focusContext != null &&
        focusContext.findAncestorWidgetOfExactType<_PlayerChromeFocusRoot>() !=
            null;
    if (focusInPlayerChrome &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      return false;
    }
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
        lower.contains('behindlivewindow') ||
        lower.contains('blank video') ||
        lower.contains('no video output');
  }

  Future<void> _tryNextCandidateAfterPlaybackError(String playbackError) async {
    if (_recoveringPlaybackError ||
        !_isCodecOrStreamPlaybackError(playbackError)) {
      return;
    }
    final nextIndex = _activeCandidateIndex + 1;
    if (nextIndex >= _activeCandidateUrls.length) {
      if (_activateEmbedFallback(reason: playbackError)) return;
      if (mounted) {
        setState(() {
          _loading = false;
          _buffering = false;
          _error = _friendlyPlaybackError(playbackError);
        });
      }
      return;
    }

    _recoveringPlaybackError = true;
    _videoOutputWatchdogTimer?.cancel();
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
        final nextController = _createVideoController(streamUrl);
        _controller = nextController;
        _activeCandidateIndex = i;
        nextController.addListener(_syncPlayerState);
        await nextController.initialize().timeout(
          Platform.isWindows
              ? const Duration(seconds: 12)
              : const Duration(seconds: 30),
        );
        await nextController.setVolume(_appVolume);
        await _applyResumeSeek(nextController);
        if (mounted) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }
        try {
          await nextController.play();
        } catch (_) {}
        _startVideoOutputWatchdog();
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
    if (_activateEmbedFallback(reason: '$lastError')) return;
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
    if (playbackError != null &&
        _activeCandidateIndex + 1 < _activeCandidateUrls.length) {
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
    _maybeAutoNextEpisode(value);
  }

  void _startVideoOutputWatchdog() {
    if (!_isAndroidTvBuild) return;
    _videoOutputWatchdogTimer?.cancel();
    _videoOutputWatchdogTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkVideoOutput();
    });
  }

  void _checkVideoOutput() {
    if (!mounted || _recoveringPlaybackError || _loading) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized || value.hasError) return;
    if (!value.isPlaying || value.position.inMilliseconds < 3000) return;

    final size = value.size;
    final hasVideoSize = size.width > 1 && size.height > 1;
    final hasAspectRatio = value.aspectRatio.isFinite && value.aspectRatio > 0;
    if (hasVideoSize && hasAspectRatio) {
      _videoOutputWatchdogTimer?.cancel();
      _videoOutputWatchdogTimer = null;
      return;
    }

    unawaited(
      _tryNextCandidateAfterPlaybackError(
        'blank video output: size=${size.width}x${size.height}',
      ),
    );
  }

  // Auto-advance to the next episode when the current one is (almost) finished.
  // Guarded by [_autoNextEpisode] preference and [_autoNextTriggered] so it
  // fires at most once per episode and never while switching/seeking.
  void _maybeAutoNextEpisode(VideoPlayerValue value) {
    if (!_autoNextEpisode || _autoNextTriggered || _switchingEpisode) return;
    if (!value.isInitialized || value.hasError) return;
    final duration = value.duration;
    final position = value.position;
    if (duration.inMilliseconds <= 0) return;
    // Only consider real end-of-stream, not an unseeked fresh controller.
    final remaining = duration - position;
    final ended =
        value.isCompleted ||
        (position > Duration.zero &&
            remaining <= const Duration(milliseconds: 800) &&
            position >= duration * 0.95);
    if (!ended) return;
    // Make sure there is a next episode before flipping the guard.
    final current = _currentEpisodeIndex;
    if (current < 0 || current + 1 >= widget.server.items.length) return;
    _autoNextTriggered = true;
    _playNextEpisode();
  }

  static const _brightnessChannel = MethodChannel('live.cineviet/brightness');

  Future<void> _syncBrightnessWithDevice() async {
    try {
      final brightness = await _brightnessChannel.invokeMethod<double>('get');
      if (mounted && brightness != null) {
        setState(() => _screenBrightness = brightness.clamp(0.0, 1.0));
      }
    } catch (_) {
      if (mounted) setState(() => _screenBrightness = 1.0);
    }
  }

  Future<void> _resetScreenBrightness() async {
    try {
      await _brightnessChannel.invokeMethod<double>('reset');
    } catch (_) {}
  }

  Future<double?> _setScreenBrightness(double value) async {
    try {
      final actual = await _brightnessChannel.invokeMethod<double>('set', {
        'value': value,
      });
      return actual?.clamp(0.0, 1.0);
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
      final next = (_screenBrightness + change).clamp(0.0, 1.0);
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

  // Re-applies the saved resume position to [controller]. Used both on first
  // load and after a candidate-source switch (e.g. kkphim proxy -> direct),
  // which previously restarted playback from the beginning because the new
  // controller was never seeked back to the resume point.
  Future<void> _applyResumeSeek(VideoPlayerController controller) async {
    final targetMs = _resumeTargetMs;
    if (targetMs == null || targetMs <= 0) return;
    try {
      // Some HLS sources (kkphim/phimapi) report duration a beat after
      // initialize(); wait briefly so seekTo lands instead of being ignored.
      var duration = controller.value.duration;
      for (
        var attempt = 0;
        attempt < 10 && duration.inMilliseconds <= 0;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!mounted || _controller != controller) return;
        duration = controller.value.duration;
      }
      var seekMs = targetMs;
      final durMs = duration.inMilliseconds;
      if (durMs > 0) {
        final safeMax = (durMs - 5000).clamp(0, durMs);
        seekMs = targetMs.clamp(0, safeMax);
      }
      await controller.seekTo(Duration(milliseconds: seekMs));
    } catch (_) {
      // Seeking must never break playback.
    }
  }

  Future<void> _saveProgress() async {
    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
      var duration = controller.value.duration;
      final position = controller.value.position;
      if (position.inMilliseconds < 3000) return;
      if (duration.inMilliseconds <= 0) {
        duration = position + const Duration(hours: 1);
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
    if (_embedController != null) {
      _revealControls();
      return;
    }
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

  KeyEventResult _handleTvProgressKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _playControlFocusNode.requestFocus();
      _revealControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    final embedController = _embedController;
    if (embedController != null) {
      return _buildEmbedFallback(embedController);
    }
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
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final maxHeight = constraints.maxHeight;
              var width = maxWidth;
              var height = maxWidth / aspectRatio;
              if (_fitMode == _PlayerFitMode.stretch) {
                width = maxWidth;
                height = maxHeight;
              } else if (_fitMode == _PlayerFitMode.contain &&
                  height > maxHeight) {
                height = maxHeight;
                width = maxHeight * aspectRatio;
              } else if (_fitMode == _PlayerFitMode.cover &&
                  height < maxHeight) {
                height = maxHeight;
                width = maxHeight * aspectRatio;
              }
              return ClipRect(
                child: Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: VideoPlayer(controller),
                  ),
                ),
              );
            },
          ),
          _buildSubtitleOverlay(controller),
        ],
      ),
    );
  }

  Widget _buildEmbedFallback(WebViewController controller) {
    return ColoredBox(
      color: Colors.black,
      child: WebViewWidget(controller: controller),
    );
  }

  Widget _buildSubtitleOverlay(VideoPlayerController controller) {
    if (_selectedSubtitle == null) return const SizedBox.shrink();
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final text = _activeSubtitleText(value.position);
        if (text.isEmpty && !_subtitleLoading && _subtitleError == null) {
          return const SizedBox.shrink();
        }
        final label = text.isNotEmpty
            ? text
            : _subtitleLoading
            ? 'Đang tải phụ đề...'
            : (_subtitleError ?? '');
        if (label.isEmpty) return const SizedBox.shrink();
        return IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
            child: _PlayerChromeFocusRoot(
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
      ),
    );
  }

  Widget _buildProgressControl(double displayProgress) {
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        activeTrackColor: CineVietColors.accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: CineVietColors.accent,
        overlayColor: CineVietColors.accentGlow,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      child: Slider(
        value: displayProgress,
        onChangeStart: _previewSeekToFraction,
        onChanged: _previewSeekToFraction,
        onChangeEnd: _commitSeekToFraction,
      ),
    );

    if (!_isAndroidTvBuild) return slider;

    return Focus(
      focusNode: _progressFocusNode,
      onKeyEvent: (_, event) => _handleTvProgressKey(event),
      onFocusChange: (focused) {
        if (!mounted) return;
        setState(() => _progressFocused = focused);
        if (focused) _revealControls();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CineVietRadius.full),
          border: Border.all(
            color: _progressFocused
                ? CineVietColors.accent
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: _progressFocused
              ? const [
                  BoxShadow(color: CineVietColors.accentGlow, blurRadius: 20),
                ]
              : null,
        ),
        child: ExcludeFocus(child: slider),
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
                  Expanded(child: _buildProgressControl(displayProgress)),
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
                          focusNode: _playControlFocusNode,
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
                      if (widget.episode.subtitles.isNotEmpty)
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(7),
                          child: _PlayerRoundButton(
                            icon: Icons.subtitles_rounded,
                            label: _selectedSubtitle?.label ?? 'Phụ đề',
                            onTap: _showSubtitleSheet,
                          ),
                        ),
                      if (widget.episode.subtitles.isNotEmpty)
                        const SizedBox(width: CineVietSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(8),
                        child: _PlayerRoundButton(
                          icon: Icons.settings_rounded,
                          label: 'Cài đặt',
                          onTap: _showSettingsSheet,
                        ),
                      ),
                      const SizedBox(width: CineVietSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(10),
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

class _SubtitleCue {
  const _SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
  final Duration start;
  final Duration end;
  final String text;
}

class _SubtitleSheet extends StatelessWidget {
  const _SubtitleSheet({
    required this.subtitles,
    required this.selected,
    required this.onSelect,
  });

  final List<EpisodeSubtitle> subtitles;
  final EpisodeSubtitle? selected;
  final ValueChanged<EpisodeSubtitle?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CineVietColors.card.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: CineVietColors.borderLight),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn phụ đề',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            _SubtitleTile(
              label: 'Tắt phụ đề',
              selected: selected == null,
              onTap: () => onSelect(null),
            ),
            for (final subtitle in subtitles)
              _SubtitleTile(
                label: subtitle.label,
                selected: selected?.url == subtitle.url,
                onTap: () => onSelect(subtitle),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubtitleTile extends StatelessWidget {
  const _SubtitleTile({
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_off_rounded,
          color: selected ? CineVietColors.accent : Colors.white70,
        ),
        title: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
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

class _ServerEpisodeSheet extends StatefulWidget {
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

  @override
  State<_ServerEpisodeSheet> createState() => _ServerEpisodeSheetState();
}

class _ServerEpisodeSheetState extends State<_ServerEpisodeSheet> {
  late int _selectedServerIndex;

  @override
  void initState() {
    super.initState();
    _selectedServerIndex = widget.movie.episodes.indexWhere(
      (server) => server.name == widget.currentServer.name,
    );
    if (_selectedServerIndex < 0) _selectedServerIndex = 0;
  }

  @override
  void didUpdateWidget(covariant _ServerEpisodeSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedServerIndex >= widget.movie.episodes.length) {
      _selectedServerIndex = 0;
    }
  }

  bool _isCurrent(EpisodeServer server, EpisodeItem episode) {
    return server.name == widget.currentServer.name &&
        episode.name == widget.currentEpisode.name &&
        episode.linkM3u8 == widget.currentEpisode.linkM3u8 &&
        episode.linkEmbed == widget.currentEpisode.linkEmbed;
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.movie.episodes;
    final parts = widget.movie.parts;
    final selectedServer = servers.isNotEmpty
        ? servers[_selectedServerIndex]
        : null;
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
                        selected: part.id == widget.movie.id,
                        onTap: () => widget.onSelectPart(part),
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
              child: ListView(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        for (
                          var serverIndex = 0;
                          serverIndex < servers.length;
                          serverIndex++
                        ) ...[
                          _ServerChip(
                            label: servers[serverIndex].displayName,
                            selected: serverIndex == _selectedServerIndex,
                            onTap: () {
                              setState(() {
                                _selectedServerIndex = serverIndex;
                              });
                            },
                          ),
                          if (serverIndex < servers.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  if (selectedServer != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final episode in selectedServer.items)
                          _EpisodeChip(
                            label: episode.displayName,
                            selected: _isCurrent(selectedServer, episode),
                            onTap: () =>
                                widget.onSelect(selectedServer, episode),
                          ),
                      ],
                    ),
                  ] else
                    Text(
                      'Chưa có dữ liệu tập.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
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
}

class _ServerChip extends StatelessWidget {
  const _ServerChip({
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(CineVietRadius.full),
      scale: 1.04,
      builder: (context, tvFocused, child) {
        final active = selected || tvFocused;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? CineVietColors.accent
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(CineVietRadius.full),
            border: Border.all(
              color: active
                  ? CineVietColors.accent
                  : Colors.white.withValues(alpha: 0.14),
              width: active ? 2 : 1,
            ),
            boxShadow: tvFocused
                ? [
                    BoxShadow(
                      color: CineVietColors.accent.withValues(alpha: 0.24),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dns_rounded,
                size: 16,
                color: selected ? const Color(0xFF061A13) : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFF061A13) : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
      child: const SizedBox.shrink(),
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

class _PlayerChromeFocusRoot extends StatelessWidget {
  const _PlayerChromeFocusRoot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
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
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool large;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final size = large ? 58.0 : 48.0;
    return TvFocus(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CineVietRadius.full),
      scale: 1.07,
      autofocus: autofocus,
      focusNode: focusNode,
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
