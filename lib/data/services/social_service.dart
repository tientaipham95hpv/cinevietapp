import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/social.dart';
import '../repositories/movie_repository.dart';
import 'cineviet_api.dart';

final movieCommentsProvider = FutureProvider.family<List<MovieComment>, int>((
  ref,
  movieId,
) async {
  return ref.read(socialServiceProvider).comments(movieId);
});

final movieRatingStatsProvider = FutureProvider.family<MovieRatingStats, int>((
  ref,
  movieId,
) async {
  return ref.read(socialServiceProvider).ratingStats(movieId);
});

final socialServiceProvider = Provider<SocialService>((ref) {
  return SocialService(ref.read(cineVietApiProvider));
});

class SocialService {
  const SocialService(this._api);
  final CineVietApi _api;

  Future<List<MovieComment>> comments(int movieId) async {
    final res = await _api.dio.get('/movies/$movieId/comments');
    final list = res.data is List ? res.data as List : const [];
    return list
        .whereType<Map>()
        .map((e) => MovieComment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<MovieComment> addComment(
    int movieId,
    String content, {
    bool isSpoiler = false,
  }) async {
    final res = await _api.dio.post(
      '/movies/$movieId/comments',
      data: <String, dynamic>{
        'content': content.trim(),
        'is_spoiler': isSpoiler,
      },
    );
    return MovieComment.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<MovieRatingStats> ratingStats(int movieId) async {
    final res = await _api.dio.get('/movies/$movieId/rating-stats');
    return MovieRatingStats.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  Future<MovieRatingStats> rateMovie(int movieId, int rating) async {
    await _api.dio.post('/movies/$movieId/rate', data: {'rating': rating});
    return ratingStats(movieId);
  }

  Future<void> toggleLike(int movieId, int commentId) async {
    await _api.dio.post('/movies/$movieId/comments/$commentId/like');
  }
}

class MovieRatingStats {
  const MovieRatingStats({
    required this.average,
    required this.total,
    required this.userRating,
  });

  final double average;
  final int total;
  final int? userRating;

  factory MovieRatingStats.fromJson(Map<String, dynamic> json) {
    final rawUserRating = json['userRating'];
    return MovieRatingStats(
      average: double.tryParse('${json['average'] ?? 0}') ?? 0,
      total: int.tryParse('${json['total'] ?? 0}') ?? 0,
      userRating: rawUserRating == null
          ? null
          : int.tryParse('${double.tryParse('$rawUserRating')?.round() ?? ''}'),
    );
  }
}
