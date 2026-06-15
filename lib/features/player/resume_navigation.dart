import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/movie.dart';
import '../../data/models/watch_history.dart';
import '../../data/services/cloud_history_service.dart';
import '../movie_detail/movie_detail_screen.dart';
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
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MovieDetailScreen(
        idOrSlug: movie.slug.isNotEmpty ? movie.slug : movie.id.toString(),
      ),
    ),
  );
}
