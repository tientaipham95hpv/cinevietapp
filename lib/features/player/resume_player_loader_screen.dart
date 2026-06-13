import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/cineviet_colors.dart';
import '../../data/models/movie.dart';
import '../../data/models/watch_history.dart';
import '../../data/repositories/movie_repository.dart';
import 'cineviet_player_screen.dart';

class ResumePlayerLoaderScreen extends ConsumerStatefulWidget {
  const ResumePlayerLoaderScreen({super.key, required this.item});

  final WatchHistoryItem item;

  @override
  ConsumerState<ResumePlayerLoaderScreen> createState() =>
      _ResumePlayerLoaderScreenState();
}

class _ResumePlayerLoaderScreenState
    extends ConsumerState<ResumePlayerLoaderScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPlayer());
  }

  Future<void> _openPlayer() async {
    final ids = <String>[
      if (widget.item.slug.trim().isNotEmpty) widget.item.slug.trim(),
      if (widget.item.movieId > 0) widget.item.movieId.toString(),
    ];

    Movie? movie;
    Object? lastError;
    for (final id in ids) {
      try {
        movie = await ref.read(movieRepositoryProvider).detail(id);
        break;
      } catch (error) {
        lastError = error;
      }
    }

    if (!mounted) return;
    if (movie == null || movie.episodes.isEmpty) {
      setState(() => _error = lastError ?? 'Không tìm thấy phim/tập đã xem.');
      return;
    }

    final resolved = _resolve(movie, widget.item);
    if (resolved == null) {
      setState(() => _error = 'Phim này chưa có nguồn phát để xem tiếp.');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CineVietPlayerScreen(
          movie: movie!,
          server: resolved.server,
          episode: resolved.episode,
          initialResumeItem: widget.item,
        ),
      ),
    );
  }

  _ResolvedResume? _resolve(Movie movie, WatchHistoryItem item) {
    final savedUrl = item.streamUrl.trim();
    if (savedUrl.isNotEmpty) {
      for (final server in movie.episodes) {
        for (final episode in server.items) {
          if (episode.linkM3u8 == savedUrl || episode.linkEmbed == savedUrl) {
            return _ResolvedResume(server, episode);
          }
        }
      }
    }

    EpisodeServer? server;
    final savedIndex = item.serverIndex;
    if (savedIndex >= 0 && savedIndex < movie.episodes.length) {
      server = movie.episodes[savedIndex];
    }
    final savedServer = item.serverName.trim().toLowerCase();
    if (server == null && savedServer.isNotEmpty) {
      for (final candidate in movie.episodes) {
        final name = candidate.name.trim().toLowerCase();
        if (name == savedServer || name.contains(savedServer) || savedServer.contains(name)) {
          server = candidate;
          break;
        }
      }
    }
    server ??= movie.episodes.cast<EpisodeServer?>().firstWhere(
      (s) => s != null && s.items.isNotEmpty,
      orElse: () => movie.episodes.isNotEmpty ? movie.episodes.first : null,
    );
    if (server == null || server.items.isEmpty) return null;

    EpisodeItem? episode;
    final savedEpisode = item.episodeName.trim().toLowerCase();
    if (savedEpisode.isNotEmpty) {
      for (final candidate in server.items) {
        final name = candidate.name.trim().toLowerCase();
        final display = candidate.displayName.trim().toLowerCase();
        if (name == savedEpisode || display == savedEpisode ||
            name.contains(savedEpisode) || display.contains(savedEpisode) ||
            savedEpisode.contains(name) || savedEpisode.contains(display)) {
          episode = candidate;
          break;
        }
      }
    }
    if (episode == null && item.episodeNumber > 0) {
      for (final candidate in server.items) {
        final haystack = '${candidate.name} ${candidate.displayName} ${candidate.filename ?? ''}';
        final nums = RegExp(r'\d+')
            .allMatches(haystack)
            .map((m) => int.tryParse(m.group(0) ?? ''))
            .whereType<int>();
        if (nums.contains(item.episodeNumber)) {
          episode = candidate;
          break;
        }
      }
    }
    episode ??= server.items.first;
    return _ResolvedResume(server, episode);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CineVietColors.bg,
        body: Center(
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: CineVietColors.accent),
                    SizedBox(height: 16),
                    Text(
                      'Đang mở tập đang xem...',
                      style: TextStyle(color: CineVietColors.text),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: CineVietColors.accent, size: 42),
                      const SizedBox(height: 14),
                      Text(
                        'Không mở được Xem tiếp\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: CineVietColors.text),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Quay lại'),
                      ),
                    ],
                  ),
                ),
        ),
      );
}

class _ResolvedResume {
  const _ResolvedResume(this.server, this.episode);
  final EpisodeServer server;
  final EpisodeItem episode;
}
