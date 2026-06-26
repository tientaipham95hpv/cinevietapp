import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/watch_history.dart';
import '../repositories/movie_repository.dart';
import 'auth_service.dart';
import 'watch_history_service.dart';

final cloudHistoryServiceProvider = Provider<CloudHistoryService>(
  (ref) => CloudHistoryService(ref),
);

final syncedWatchHistoryProvider = FutureProvider<List<WatchHistoryItem>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  final service = ref.watch(cloudHistoryServiceProvider);
  if (auth.loggedIn) {
    return service.sync();
  }
  return const <WatchHistoryItem>[];
});

class CloudHistoryService {
  CloudHistoryService(this.ref);
  final Ref ref;

  Future<List<WatchHistoryItem>> sync() async {
    if (!ref.read(authControllerProvider).loggedIn) {
      return ref.read(watchHistoryServiceProvider).items();
    }
    // Khi đã đăng nhập, cloud/backend là nguồn chuẩn để web và app đồng bộ.
    // Không push local cũ trước khi pull, tránh resurrect phim đã xoá từ web/app khác.
    return pullCloud();
  }

  Future<void> pushLocal() async {
    if (!ref.read(authControllerProvider).loggedIn) return;
    final api = ref.read(cineVietApiProvider);
    final local = await ref.read(watchHistoryServiceProvider).items();
    if (local.isEmpty) return;
    for (final item in local.take(100)) {
      try {
        await api.dio.post('/history', data: item.toCloudJson());
      } catch (_) {}
    }
  }

  Future<List<WatchHistoryItem>> pullCloud() async {
    if (!ref.read(authControllerProvider).loggedIn) {
      return ref.read(watchHistoryServiceProvider).items();
    }
    final api = ref.read(cineVietApiProvider);
    try {
      final res = await api.dio.get(
        '/history',
        queryParameters: {'limit': 100},
      );
      final rows = res.data is Map
          ? (res.data['history'] as List? ?? const [])
          : const [];
      final remote = rows
          .whereType<Map>()
          .map(
            (e) => WatchHistoryItem.fromCloudJson(Map<String, dynamic>.from(e)),
          )
          .where((e) => e.movieId > 0 && e.slug.isNotEmpty)
          .toList();
      final local = await ref.read(watchHistoryServiceProvider).items();
      final result = _mergeHistory(remote, local).take(100).toList();
      await ref.read(watchHistoryServiceProvider).replaceAll(result);
      return result;
    } on DioException {
      // Offline/server error: keep local history.
    } catch (_) {
      // Malformed remote rows should not break local history.
    }
    return ref.read(watchHistoryServiceProvider).items();
  }

  List<WatchHistoryItem> _mergeHistory(
    List<WatchHistoryItem> remote,
    List<WatchHistoryItem> local,
  ) {
    final byKey = <String, WatchHistoryItem>{};
    for (final item in [...remote, ...local]) {
      if (item.movieId <= 0 || item.slug.isEmpty) continue;
      final existing = byKey[item.key];
      if (existing == null || item.updatedAtMs >= existing.updatedAtMs) {
        byKey[item.key] = item;
      }
    }
    final merged = byKey.values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return merged;
  }

  Future<void> save(WatchHistoryItem item) async {
    await ref.read(watchHistoryServiceProvider).upsert(item);
    ref.invalidate(watchHistoryProvider);
    ref.invalidate(syncedWatchHistoryProvider);
    if (!ref.read(authControllerProvider).loggedIn) return;
    try {
      await ref
          .read(cineVietApiProvider)
          .dio
          .post('/history', data: item.toCloudJson());
    } catch (_) {}
  }

  Future<void> remove(WatchHistoryItem item) async {
    final loggedIn = ref.read(authControllerProvider).loggedIn;
    if (loggedIn) {
      await ref
          .read(cineVietApiProvider)
          .dio
          .delete('/history/${item.movieId}');
    }
    // Backend deletes by movie id, so mirror that locally. This also fixes the
    // last-item case where a stale cloud row could be pulled back immediately.
    await ref.read(watchHistoryServiceProvider).removeMovie(item.movieId);
    ref.invalidate(watchHistoryProvider);
    ref.invalidate(syncedWatchHistoryProvider);
  }

  Future<void> clear() async {
    await ref.read(watchHistoryServiceProvider).clear();
    ref.invalidate(watchHistoryProvider);
    ref.invalidate(syncedWatchHistoryProvider);
    if (!ref.read(authControllerProvider).loggedIn) return;
    try {
      await ref.read(cineVietApiProvider).dio.delete('/history');
    } catch (_) {}
  }
}
