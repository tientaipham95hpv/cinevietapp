import 'dart:async';

import 'package:dio/dio.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../data/models/movie.dart';

class WatchTogetherRoom {
  const WatchTogetherRoom({
    required this.code,
    required this.movieTitle,
    required this.memberCount,
    required this.maxMembers,
  });

  final String code;
  final String movieTitle;
  final int memberCount;
  final int maxMembers;

  factory WatchTogetherRoom.fromJson(Map<String, dynamic> json) =>
      WatchTogetherRoom(
        code: '${json['code'] ?? ''}',
        movieTitle: '${json['movieTitle'] ?? 'Phòng xem chung'}',
        memberCount: int.tryParse('${json['memberCount'] ?? 0}') ?? 0,
        maxMembers: int.tryParse('${json['maxMembers'] ?? 8}') ?? 8,
      );
}

class WatchTogetherCreateResult {
  const WatchTogetherCreateResult({required this.code});
  final String code;
}

class WatchTogetherService {
  WatchTogetherService._();

  static const String baseUrl = 'https://cineviet.live';
  static const String socketPath = '/socket.io';
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: '$baseUrl/api',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  static Future<List<WatchTogetherRoom>> publicRooms() async {
    final response = await _dio.get('/watch-party/rooms');
    final rooms = (response.data is Map ? response.data['rooms'] : null) as List?;
    return (rooms ?? const [])
        .whereType<Map>()
        .map((e) => WatchTogetherRoom.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.code.isNotEmpty)
        .toList();
  }

  static Future<WatchTogetherCreateResult> createRoom({
    required String hostName,
    required String videoUrl,
    required String movieTitle,
    int maxMembers = 8,
    bool isPublic = true,
  }) async {
    final socket = _connectSocket();
    final completer = Completer<WatchTogetherCreateResult>();
    Timer? timeout;

    void finishError(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
      try {
        socket.disconnect();
      } catch (_) {}
      timeout?.cancel();
    }

    socket.onConnect((_) {
      socket.emitWithAck(
        'create-room',
        {
          'hostName': hostName.trim().isEmpty ? 'Chủ phòng' : hostName.trim(),
          'videoUrl': videoUrl,
          'movieTitle': movieTitle.trim().isEmpty ? 'Watch Party' : movieTitle,
          'maxMembers': maxMembers,
          'isPublic': isPublic,
        },
        ack: (data) {
          final map = data is Map ? Map<String, dynamic>.from(data) : null;
          final error = map?['error']?.toString();
          final code = map?['code']?.toString() ?? '';
          if (error != null && error.isNotEmpty) {
            finishError(error);
            return;
          }
          if (code.isEmpty) {
            finishError('Không tạo được phòng xem chung.');
            return;
          }
          if (!completer.isCompleted) {
            completer.complete(WatchTogetherCreateResult(code: code));
          }
          // Giữ socket sống ngắn hạn để phòng không bị xoá ngay khi mở web.
          Future.delayed(const Duration(seconds: 20), () {
            try {
              socket.disconnect();
            } catch (_) {}
          });
          timeout?.cancel();
        },
      );
    });

    socket.onConnectError((error) => finishError('Không kết nối được Xem chung.'));
    socket.onError((error) => finishError('Không kết nối được Xem chung.'));
    timeout = Timer(const Duration(seconds: 15), () {
      finishError('Kết nối Xem chung quá thời gian.');
    });
    socket.connect();
    return completer.future;
  }

  static Future<void> joinRoom({
    required String code,
    required String userName,
  }) async {
    final socket = _connectSocket();
    final completer = Completer<void>();
    Timer? timeout;

    void finishError(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
      try {
        socket.disconnect();
      } catch (_) {}
      timeout?.cancel();
    }

    socket.onConnect((_) {
      socket.emitWithAck(
        'join-room',
        {
          'code': code.trim().toUpperCase(),
          'userName': userName.trim().isEmpty ? 'Thành viên' : userName.trim(),
        },
        ack: (data) {
          final map = data is Map ? Map<String, dynamic>.from(data) : null;
          final error = map?['error']?.toString();
          if (error != null && error.isNotEmpty) {
            finishError(error);
            return;
          }
          if (!completer.isCompleted) completer.complete();
          Future.delayed(const Duration(seconds: 2), () {
            try {
              socket.disconnect();
            } catch (_) {}
          });
          timeout?.cancel();
        },
      );
    });
    socket.onConnectError((error) => finishError('Không kết nối được Xem chung.'));
    socket.onError((error) => finishError('Không kết nối được Xem chung.'));
    timeout = Timer(const Duration(seconds: 12), () {
      finishError('Kết nối Xem chung quá thời gian.');
    });
    socket.connect();
    return completer.future;
  }

  static String roomUrl(String code, {String? userName}) {
    final uri = Uri.parse('$baseUrl/xem-chung/phong/$code');
    if (userName == null || userName.trim().isEmpty) return uri.toString();
    return uri.replace(queryParameters: {'name': userName.trim()}).toString();
  }

  static String? firstPlayableUrl(Movie movie) {
    for (final server in movie.episodes) {
      for (final episode in server.items) {
        final url = episode.linkM3u8 ?? episode.linkEmbed;
        if (url != null && url.trim().isNotEmpty) return url.trim();
      }
    }
    return null;
  }

  static io.Socket _connectSocket() => io.io(
    baseUrl,
    io.OptionBuilder()
        .setPath(socketPath)
        .setTransports(['websocket', 'polling'])
        .disableAutoConnect()
        .enableReconnection()
        .setTimeout(12000)
        .build(),
  );
}
