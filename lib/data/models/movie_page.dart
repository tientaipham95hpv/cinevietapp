import 'movie.dart';

class MoviePage {
  const MoviePage({
    required this.movies,
    required this.total,
    required this.page,
    required this.limit,
  });
  final List<Movie> movies;
  final int total;
  final int page;
  final int limit;

  bool get hasMore => page * limit < total;

  factory MoviePage.fromJson(Map<String, dynamic> json) {
    final list = (json['movies'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return MoviePage(
      movies: list,
      total: int.tryParse('${json['total'] ?? list.length}') ?? list.length,
      page: int.tryParse('${json['page'] ?? 1}') ?? 1,
      limit: int.tryParse('${json['limit'] ?? list.length}') ?? list.length,
    );
  }
}

class BrowseQuery {
  const BrowseQuery({
    this.search = '',
    this.type = '',
    this.genre = '',
    this.country = '',
    this.year = '',
    this.page = 1,
    this.sort = 'created_at',
  });
  final String search;
  final String type;
  final String genre;
  final String country;
  final String year;
  final int page;
  final String sort;

  BrowseQuery copyWith({
    String? search,
    String? type,
    String? genre,
    String? country,
    String? year,
    int? page,
    String? sort,
  }) => BrowseQuery(
    search: search ?? this.search,
    type: type ?? this.type,
    genre: genre ?? this.genre,
    country: country ?? this.country,
    year: year ?? this.year,
    page: page ?? this.page,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowseQuery &&
          other.search == search &&
          other.type == type &&
          other.genre == genre &&
          other.country == country &&
          other.year == year &&
          other.page == page &&
          other.sort == sort;

  @override
  int get hashCode =>
      Object.hash(search, type, genre, country, year, page, sort);
}
