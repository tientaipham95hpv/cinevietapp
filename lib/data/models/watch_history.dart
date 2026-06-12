import 'dart:convert';
import 'movie.dart';

String? _cleanMediaUrl(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('//')) return 'https:$raw';
  return raw;
}

String _bestServerName(Map<String, dynamic> json) {
  final raw = '${json['server_name'] ?? json['serverName'] ?? ''}'.trim();
  if (raw.isEmpty || raw.toLowerCase() == 'server') {
    final stream = '${json['stream_url'] ?? json['streamUrl'] ?? ''}'
        .toLowerCase();
    if (stream.contains('m3u8')) return 'HLS';
    if (stream.contains('embed')) return 'Embed';
    return 'Nguồn phát';
  }
  return raw;
}

class WatchHistoryItem {
  const WatchHistoryItem({
    required this.movieId,
    required this.slug,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    required this.serverName,
    required this.serverIndex,
    required this.episodeName,
    required this.streamUrl,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
  });

  final int movieId;
  final String slug;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final String serverName;
  final int serverIndex;
  final String episodeName;
  final String streamUrl;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;

  String get key => '$slug|$serverName|$episodeName';
  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1);
  bool get completed => durationMs > 0 && progress >= 0.95;
  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  WatchHistoryItem copyWith({
    int? positionMs,
    int? durationMs,
    int? updatedAtMs,
  }) => WatchHistoryItem(
    movieId: movieId,
    slug: slug,
    title: title,
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,
    serverName: serverName,
    serverIndex: serverIndex,
    episodeName: episodeName,
    streamUrl: streamUrl,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  factory WatchHistoryItem.fromPlayback({
    required Movie movie,
    required EpisodeServer server,
    required EpisodeItem episode,
    required Duration position,
    required Duration duration,
  }) {
    final streamUrl = episode.linkM3u8?.isNotEmpty == true
        ? episode.linkM3u8!
        : (episode.linkEmbed ?? '');
    return WatchHistoryItem(
      movieId: movie.id,
      slug: movie.slug,
      title: movie.title,
      posterUrl: movie.posterUrl,
      backdropUrl: movie.backdropUrl,
      serverName: server.name,
      serverIndex: movie.episodes.indexOf(server).clamp(0, 1 << 30),
      episodeName: episode.name,
      streamUrl: streamUrl,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory WatchHistoryItem.fromCloudJson(Map<String, dynamic> json) {
    final progressPercent = double.tryParse('${json['progress'] ?? 0}') ?? 0;
    final positionSeconds =
        double.tryParse(
          '${json['position_seconds'] ?? json['positionSeconds'] ?? 0}',
        ) ??
        0;
    final durationSecondsRaw =
        double.tryParse(
          '${json['duration_seconds'] ?? json['durationSeconds'] ?? 0}',
        ) ??
        0;
    final fallbackDurationSeconds = progressPercent > 0 && positionSeconds > 0
        ? positionSeconds / (progressPercent / 100)
        : 0;
    final durationSeconds = durationSecondsRaw > 0
        ? durationSecondsRaw
        : fallbackDurationSeconds;
    final watchedAt = DateTime.tryParse('${json['watched_at'] ?? ''}');
    final serverIndex = int.tryParse('${json['server_index'] ?? json['serverIndex'] ?? 0}') ?? 0;
    final episodeName = '${json['episode_name'] ?? json['episodeName'] ?? ''}'
        .trim();
    final episodeRaw = '${json['episode'] ?? ''}'.trim();
    final poster = (json['posterUrl'] ?? json['poster'] ?? json['thumbnail'])
        ?.toString();
    final backdrop =
        (json['backdropUrl'] ?? json['backdrop'] ?? json['thumbnail'] ?? poster)
            ?.toString();
    return WatchHistoryItem(
      movieId: int.tryParse('${json['movie_id'] ?? json['movieId'] ?? 0}') ?? 0,
      slug: '${json['slug'] ?? ''}',
      title: '${json['title'] ?? 'Không tên'}',
      posterUrl: _cleanMediaUrl(poster),
      backdropUrl: _cleanMediaUrl(backdrop),
      serverName: _bestServerName(json),
      serverIndex: serverIndex < 0 ? 0 : serverIndex,
      episodeName: episodeName.isNotEmpty ? episodeName : 'Tập $episodeRaw',
      streamUrl: '${json['stream_url'] ?? json['streamUrl'] ?? ''}',
      positionMs: (positionSeconds * 1000).round(),
      durationMs: (durationSeconds * 1000).round(),
      updatedAtMs:
          watchedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) =>
      WatchHistoryItem(
        movieId: int.tryParse('${json['movieId'] ?? 0}') ?? 0,
        slug: '${json['slug'] ?? ''}',
        title: '${json['title'] ?? 'Không tên'}',
        posterUrl: json['posterUrl']?.toString(),
        backdropUrl: json['backdropUrl']?.toString(),
        serverName: '${json['serverName'] ?? 'Server'}',
        serverIndex: int.tryParse('${json['serverIndex'] ?? json['server_index'] ?? 0}') ?? 0,
        episodeName: '${json['episodeName'] ?? 'Tập'}',
        streamUrl: '${json['streamUrl'] ?? ''}',
        positionMs: int.tryParse('${json['positionMs'] ?? 0}') ?? 0,
        durationMs: int.tryParse('${json['durationMs'] ?? 0}') ?? 0,
        updatedAtMs: int.tryParse('${json['updatedAtMs'] ?? 0}') ?? 0,
      );

  Map<String, dynamic> toCloudJson() => {
    'movie_id': movieId,
    'episode': _episodeNumber,
    'progress': (progress * 100).round().clamp(0, 100),
    'completed': completed ? 1 : 0,
    'position_seconds': positionMs / 1000,
    'duration_seconds': durationMs / 1000,
    'server_name': serverName,
    'server_index': serverIndex,
    'episode_name': episodeName,
    'stream_url': streamUrl,
  };

  int get episodeNumber => _episodeNumber;

  int get _episodeNumber {
    final matches = RegExp(r'\d+').allMatches(episodeName).toList();
    if (matches.isEmpty) return 1;
    return int.tryParse(matches.last.group(0) ?? '1') ?? 1;
  }

  Map<String, dynamic> toJson() => {
    'movieId': movieId,
    'slug': slug,
    'title': title,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'serverName': serverName,
    'serverIndex': serverIndex,
    'episodeName': episodeName,
    'streamUrl': streamUrl,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAtMs': updatedAtMs,
  };

  static List<WatchHistoryItem> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <WatchHistoryItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <WatchHistoryItem>[];
      return decoded
          .whereType<Map>()
          .map((e) => WatchHistoryItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <WatchHistoryItem>[];
    }
  }

  static String encodeList(List<WatchHistoryItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}
