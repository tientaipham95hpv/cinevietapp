import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_history.dart';

final watchHistoryServiceProvider = Provider<WatchHistoryService>(
  (ref) => WatchHistoryService(),
);
final watchHistoryProvider = FutureProvider<List<WatchHistoryItem>>(
  (ref) => ref.watch(watchHistoryServiceProvider).items(),
);

class WatchHistoryService {
  static const _key = 'cineviet_watch_history_v1';

  Future<List<WatchHistoryItem>> items() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = WatchHistoryItem.decodeList(prefs.getString(_key));
      list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return list;
    } catch (_) {
      return const <WatchHistoryItem>[];
    }
  }

  Future<WatchHistoryItem?> find(
    String slug,
    String serverName,
    String episodeName,
  ) async {
    final key = '$slug|$serverName|$episodeName';
    for (final item in await items()) {
      if (item.key == key) return item;
    }
    return null;
  }

  Future<void> upsert(WatchHistoryItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = WatchHistoryItem.decodeList(prefs.getString(_key));
      final filtered = list.where((e) => e.key != item.key).toList();
      filtered.insert(0, item);
      final capped = filtered.take(100).toList();
      await prefs.setString(_key, WatchHistoryItem.encodeList(capped));
    } catch (_) {}
  }

  Future<void> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = WatchHistoryItem.decodeList(
        prefs.getString(_key),
      ).where((e) => e.key != key).toList();
      await prefs.setString(_key, WatchHistoryItem.encodeList(list));
    } catch (_) {}
  }

  Future<void> replaceAll(List<WatchHistoryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, WatchHistoryItem.encodeList(items));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
