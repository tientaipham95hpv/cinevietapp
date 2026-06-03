import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import '../repositories/movie_repository.dart';
import 'auth_service.dart';
import 'cineviet_api.dart';

final myPlaylistsProvider = FutureProvider<List<CineVietPlaylist>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.loggedIn) return const <CineVietPlaylist>[];
  return ref.watch(playlistServiceProvider).my();
});

final playlistMoviesProvider = FutureProvider.family<PlaylistDetail, int>((
  ref,
  id,
) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.loggedIn) {
    return PlaylistDetail(
      playlist: CineVietPlaylist.empty(id),
      movies: const <Movie>[],
    );
  }
  return ref.watch(playlistServiceProvider).movies(id);
});

final playlistServiceProvider = Provider<PlaylistService>(
  (ref) => PlaylistService(ref),
);

class CineVietPlaylist {
  const CineVietPlaylist({
    required this.id,
    required this.name,
    required this.slug,
    this.description = '',
    this.cover,
    this.movieCount = 0,
    this.isPublic = false,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final String? cover;
  final int movieCount;
  final bool isPublic;

  factory CineVietPlaylist.empty(int id) =>
      CineVietPlaylist(id: id, name: 'Playlist', slug: '$id');

  factory CineVietPlaylist.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) => int.tryParse('${value ?? 0}') ?? 0;
    return CineVietPlaylist(
      id: asInt(json['id']),
      name: '${json['name'] ?? 'Playlist'}',
      slug: '${json['slug'] ?? json['id'] ?? ''}',
      description: '${json['description'] ?? ''}',
      cover: (json['cover'] ?? json['poster'] ?? json['backdrop'])?.toString(),
      movieCount: asInt(json['movie_count'] ?? json['movieCount']),
      isPublic: asInt(json['is_public'] ?? json['isPublic']) == 1,
    );
  }
}

class PlaylistDetail {
  const PlaylistDetail({required this.playlist, required this.movies});

  final CineVietPlaylist playlist;
  final List<Movie> movies;
}

class PlaylistService {
  PlaylistService(this.ref);
  final Ref ref;

  CineVietApi get _api => ref.read(cineVietApiProvider);

  Future<List<CineVietPlaylist>> my() async {
    final res = await _api.dio.get('/playlists/my');
    final rows = res.data is List ? res.data as List : const [];
    return rows
        .whereType<Map>()
        .map((e) => CineVietPlaylist.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0)
        .toList();
  }

  Future<PlaylistDetail> movies(int playlistId) async {
    final res = await _api.dio.get('/playlists/$playlistId/movies');
    final data = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    final playlist = data['playlist'] is Map
        ? CineVietPlaylist.fromJson(
            Map<String, dynamic>.from(data['playlist'] as Map),
          )
        : CineVietPlaylist.empty(playlistId);
    final rows = data['movies'] is List ? data['movies'] as List : const [];
    final movies = rows
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0 && e.slug.isNotEmpty)
        .toList();
    return PlaylistDetail(playlist: playlist, movies: movies);
  }

  Future<CineVietPlaylist> create({
    required String name,
    String description = '',
    bool isPublic = false,
  }) async {
    final res = await _api.dio.post(
      '/playlists',
      data: {'name': name, 'description': description, 'is_public': isPublic},
    );
    ref.invalidate(myPlaylistsProvider);
    return CineVietPlaylist.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  Future<CineVietPlaylist> updateVisibility(
    int playlistId, {
    required bool isPublic,
  }) async {
    final res = await _api.dio.patch(
      '/playlists/$playlistId',
      data: {'is_public': isPublic},
    );
    ref.invalidate(myPlaylistsProvider);
    ref.invalidate(playlistMoviesProvider(playlistId));
    return CineVietPlaylist.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  Future<void> deletePlaylist(int playlistId) async {
    await _api.dio.delete('/playlists/$playlistId');
    ref.invalidate(myPlaylistsProvider);
    ref.invalidate(playlistMoviesProvider(playlistId));
  }

  Future<void> addMovie(int playlistId, int movieId) async {
    await _api.dio.post(
      '/playlists/$playlistId/movies',
      data: {'movie_id': movieId},
    );
    ref.invalidate(myPlaylistsProvider);
    ref.invalidate(playlistMoviesProvider(playlistId));
  }

  Future<void> removeMovie(int playlistId, int movieId) async {
    await _api.dio.delete('/playlists/$playlistId/movies/$movieId');
    ref.invalidate(myPlaylistsProvider);
    ref.invalidate(playlistMoviesProvider(playlistId));
  }
}
