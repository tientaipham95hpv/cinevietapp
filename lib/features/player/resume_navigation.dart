import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/platform_detector.dart';
import '../../data/models/movie.dart';
import '../../data/models/watch_history.dart';
import '../../data/repositories/movie_repository.dart';
import '../../data/services/cloud_history_service.dart';
import '../movie_detail/movie_detail_screen.dart';
import 'cineviet_player_screen.dart';
import 'resume_player_loader_screen.dart';

Future<void> openWatchHistoryItem(
  BuildContext context,
  WatchHistoryItem item,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ResumePlayerLoaderScreen(item: item),
    ),
  );
}


Future<void> openMovieOrResume(
  BuildContext context,
  WidgetRef ref,
  Movie movie,
) async {
  WatchHistoryItem? resume;
  try {
    final history = await ref.read(syncedWatchHistoryProvider.future);
    for (final item in history) {
      if (item.movieId == movie.id ||
          (movie.slug.isNotEmpty && item.slug == movie.slug)) {
        resume = item;
        break;
      }
    }
  } catch (_) {
    resume = null;
  }
  if (!context.mounted) return;
  if (resume != null) {
    await openWatchHistoryItem(context, resume);
    return;
  }

  // TV: vào thẳng player tập 1, không qua trang detail
  final platform = PlatformDetector.of(context);
  if (platform.isTv) {
    await _openDirectPlayer(context, ref, movie);
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MovieDetailScreen(
        idOrSlug: movie.slug.isNotEmpty ? movie.slug : movie.id.toString(),
      ),
    ),
  );
}

/// Load movie detail và vào player ngay tập 1 (dùng cho TV "Xem ngay").
Future<void> _openDirectPlayer(
  BuildContext context,
  WidgetRef ref,
  Movie movie,
) async {
  // Thử dùng data đã có sẵn trước, fetch detail nếu cần
  Movie? detail;
  try {
    final id = movie.slug.isNotEmpty ? movie.slug : movie.id.toString();
    detail = await ref.read(movieRepositoryProvider).detail(id);
  } catch (_) {
    detail = null;
  }

  if (!context.mounted) return;

  // Nếu fetch fail hoặc không có episodes → fallback sang trang detail
  if (detail == null || detail.episodes.isEmpty) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(
          idOrSlug: movie.slug.isNotEmpty ? movie.slug : movie.id.toString(),
        ),
      ),
    );
    return;
  }

  // Chọn server đầu tiên có tập
  final server = detail.episodes.cast<EpisodeServer?>().firstWhere(
    (s) => s != null && s.items.isNotEmpty,
    orElse: () => detail!.episodes.isNotEmpty ? detail.episodes.first : null,
  );
  if (server == null || server.items.isEmpty) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(
          idOrSlug: movie.slug.isNotEmpty ? movie.slug : movie.id.toString(),
        ),
      ),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CineVietPlayerScreen(
        movie: detail!,
        server: server,
        episode: server.items.first,
      ),
    ),
  );
}
