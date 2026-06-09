import 'dart:convert';

String normalizeImageUrl(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty || raw == 'null') return '';
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('//')) return 'https:$raw';
  if (raw.startsWith('/')) return 'https://cineviet.live$raw';
  return 'https://cineviet.live/$raw';
}

class MoviePerson {
  const MoviePerson({required this.name, this.avatar});
  final String name;
  final String? avatar;

  String get avatarUrl => normalizeImageUrl(avatar);

  factory MoviePerson.fromJson(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      return MoviePerson(
        name: '${map['name'] ?? map['title'] ?? ''}'.trim(),
        avatar: (map['avatar'] ?? map['photo'] ?? map['profile_path'])
            ?.toString(),
      );
    }
    return MoviePerson(name: value.toString().trim());
  }
}

class EpisodeSubtitle {
  const EpisodeSubtitle({required this.label, required this.url});
  final String label;
  final String url;

  factory EpisodeSubtitle.fromJson(Map<String, dynamic> json) => EpisodeSubtitle(
    label: '${json['label'] ?? json['lang'] ?? json['name'] ?? 'Phụ đề'}'.trim(),
    url: '${json['url'] ?? json['subtitle_url'] ?? json['src'] ?? ''}'.trim(),
  );
}

class EpisodeItem {
  const EpisodeItem({
    required this.name,
    this.filename,
    this.linkM3u8,
    this.linkEmbed,
    this.subtitles = const [],
  });
  final String name;
  final String? filename;
  final String? linkM3u8;
  final String? linkEmbed;
  final List<EpisodeSubtitle> subtitles;

  String get displayName => _normalizeEpisodeName(name);

  factory EpisodeItem.fromJson(Map<String, dynamic> json) => EpisodeItem(
    name: '${json['name'] ?? json['slug'] ?? 'Tập'}',
    filename: json['filename']?.toString(),
    linkM3u8: json['link_m3u8']?.toString(),
    linkEmbed: json['link_embed']?.toString(),
    subtitles: ((json['subtitles'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => EpisodeSubtitle.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.url.isNotEmpty)
        .toList(),
  );
}

String _normalizeEpisodeName(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'Tập';
  if (RegExp(r'^tập\s+', caseSensitive: false).hasMatch(text)) return text;
  if (RegExp(r'^\d+$').hasMatch(text)) return 'Tập $text';
  return text;
}

class MoviePart {
  const MoviePart({required this.id, required this.title, this.partNumber = 1});

  final int id;
  final String title;
  final int partNumber;

  factory MoviePart.fromJson(Map<String, dynamic> json) => MoviePart(
    id: int.tryParse('${json['id'] ?? 0}') ?? 0,
    title: '${json['title'] ?? ''}',
    partNumber: int.tryParse('${json['part_number'] ?? 1}') ?? 1,
  );
}

class EpisodeServer {
  const EpisodeServer({required this.name, required this.items});
  final String name;
  final List<EpisodeItem> items;

  String get displayName => name
      .replaceAll(
        RegExp(r'\s*\[(ophim|phimapi)\]\s*', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  factory EpisodeServer.fromJson(Map<String, dynamic> json) => EpisodeServer(
    name: '${json['server_name'] ?? json['name'] ?? 'Server'}',
    items: ((json['server_data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => EpisodeItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.slug,
    this.titleEn,
    this.description,
    this.poster,
    this.backdrop,
    this.thumbnail,
    this.releaseYear,
    this.duration,
    this.rating,
    this.quality,
    this.language,
    this.country,
    this.type,
    this.episodeCurrent,
    this.totalEpisodes,
    this.genres = const [],
    this.cast = const [],
    this.directors = const [],
    this.episodes = const [],
    this.related = const [],
    this.parts = const [],
  });

  final int id;
  final String title;
  final String slug;
  final String? titleEn;
  final String? description;
  final String? poster;
  final String? backdrop;
  final String? thumbnail;
  final int? releaseYear;
  final int? duration;
  final double? rating;
  final String? quality;
  final String? language;
  final String? country;
  final String? type;
  final String? episodeCurrent;
  final int? totalEpisodes;
  final List<String> genres;
  final List<MoviePerson> cast;
  final List<MoviePerson> directors;
  final List<EpisodeServer> episodes;
  final List<Movie> related;
  final List<MoviePart> parts;

  String? get posterUrl => poster?.isNotEmpty == true
      ? poster
      : (thumbnail?.isNotEmpty == true ? thumbnail : backdrop);
  String? get backdropUrl => backdrop?.isNotEmpty == true
      ? backdrop
      : (thumbnail?.isNotEmpty == true ? thumbnail : poster);
  String? get portraitImageUrl => posterUrl;
  String? get landscapeImageUrl => backdropUrl;
  String get englishTitleLine => (titleEn ?? '').trim().isNotEmpty ? titleEn!.trim() : '—';
  String get yearLine => releaseYear?.toString() ?? '—';
  String get metaLine => [
    if (releaseYear != null) '$releaseYear',
    if ((quality ?? '').isNotEmpty) quality!,
    if ((language ?? '').isNotEmpty) language!,
    if (duration != null && duration! > 0) '${duration}p',
  ].join(' • ');

  factory Movie.fromJson(Map<String, dynamic> json) {
    List<String> parseGenres(dynamic value) {
      if (value is List) {
        return value
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (value is String && value.isNotEmpty) {
        return value
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    List<MoviePerson> parsePeople(dynamic value) {
      dynamic decoded = value;
      if (value is String && value.isNotEmpty) {
        final trimmed = value.trim();
        if (trimmed.startsWith('[')) {
          try {
            decoded = jsonDecode(trimmed);
          } catch (_) {
            decoded = trimmed.split(',');
          }
        } else {
          decoded = trimmed.split(',');
        }
      }
      if (decoded is List) {
        return decoded
            .map(MoviePerson.fromJson)
            .where((e) => e.name.isNotEmpty)
            .toList();
      }
      if (decoded != null && decoded.toString().trim().isNotEmpty) {
        return [MoviePerson.fromJson(decoded)];
      }
      return const [];
    }

    List<EpisodeServer> parseEpisodes(dynamic value) {
      dynamic decoded = value;
      if (value is String && value.isNotEmpty) {
        try {
          decoded = jsonDecode(value);
        } catch (_) {
          decoded = const [];
        }
      }
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => EpisodeServer.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    int? asInt(dynamic v) => v == null ? null : int.tryParse(v.toString());
    double? asDouble(dynamic v) =>
        v == null ? null : double.tryParse(v.toString());

    return Movie(
      id: asInt(json['id']) ?? 0,
      title: '${json['title'] ?? 'Không tên'}',
      slug: '${json['slug'] ?? json['id'] ?? ''}',
      titleEn: json['title_en']?.toString(),
      description: json['description']?.toString(),
      poster: json['poster']?.toString(),
      backdrop: json['backdrop']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      releaseYear: asInt(json['release_year']),
      duration: asInt(json['duration']),
      rating: asDouble(json['rating']) ?? asDouble(json['tmdb_vote_average']),
      quality: json['quality']?.toString(),
      language: json['language']?.toString(),
      country: json['country']?.toString(),
      type: json['type']?.toString(),
      episodeCurrent: json['episode_current']?.toString(),
      totalEpisodes: asInt(json['total_episodes']),
      genres: parseGenres(json['genres']),
      cast: parsePeople(json['cast'] ?? json['actors']),
      directors: parsePeople(json['director'] ?? json['directors']),
      episodes: parseEpisodes(json['episodes']),
      related: ((json['related'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      parts: ((json['parts'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => MoviePart.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id > 0)
          .toList(),
    );
  }
}
