import 'dart:async';

import 'package:dio/dio.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../data/models/movie.dart';

class WatchTogetherMember {
  const WatchTogetherMember({required this.id, required this.name});
  final String id;
  final String name;

  factory WatchTogetherMember.fromJson(Map<String, dynamic> json) =>
      WatchTogetherMember(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Thành viên'}',
      );
}

class WatchTogetherMessage {
  const WatchTogetherMessage({
    required this.id,
    required this.type,
    required this.payload,
    this.userName,
  });

  final String id;
  final String type;
  final String payload;
  final String? userName;

  bool get isSystem => type == 'system';

  factory WatchTogetherMessage.fromJson(Map<String, dynamic> json) =>
      WatchTogetherMessage(
        id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
        type: '${json['type'] ?? 'text'}',
        payload: '${json['payload'] ?? ''}',
        userName: json['userName']?.toString(),
      );
}

class WatchTogetherState {
  const WatchTogetherState({
    required this.code,
    required this.movieTitle,
    required this.videoUrl,
    required this.hostSocketId,
    required this.members,
    required this.currentTime,
    required this.playing,
    required this.messages,
  });

  final String code;
  final String hostSocketId;
  final String movieTitle;
  final String videoUrl;
  final List<WatchTogetherMember> members;
  final double currentTime;
  final bool playing;
  final List<WatchTogetherMessage> messages;

  bool get isCurrentSocketHost =>
      hostSocketId.isNotEmpty &&
      WatchTogetherService.activeSocketId == hostSocketId;

  factory WatchTogetherState.fromJson(
    Map<String, dynamic> json,
  ) => WatchTogetherState(
    code: '${json['code'] ?? ''}',
    hostSocketId: '${json['hostSocketId'] ?? ''}',
    movieTitle: '${json['movieTitle'] ?? 'Phòng xem chung'}',
    videoUrl: '${json['videoUrl'] ?? ''}',
    members: ((json['members'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => WatchTogetherMember.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    currentTime: double.tryParse('${json['currentTime'] ?? 0}') ?? 0,
    playing: json['playing'] == true,
    messages: ((json['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => WatchTogetherMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

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
  const WatchTogetherCreateResult({required this.code, this.room});
  final String code;
  final WatchTogetherState? room;
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
  static io.Socket? _activeRoomSocket;

  static io.Socket? get activeRoomSocket => _activeRoomSocket;
  static String? get activeSocketId => _activeRoomSocket?.id;

  static void _keepRoomSocket(io.Socket socket) {
    final previous = _activeRoomSocket;
    if (previous != null && previous.id != socket.id) {
      try {
        previous.emit('leave-room');
        previous.disconnect();
      } catch (_) {}
    }
    _activeRoomSocket = socket;
    socket.onDisconnect((_) {
      if (_activeRoomSocket?.id == socket.id) _activeRoomSocket = null;
    });
    socket.on('room-closed', (_) {
      if (_activeRoomSocket?.id == socket.id) _activeRoomSocket = null;
      try {
        socket.disconnect();
      } catch (_) {}
    });
  }

  static Future<List<WatchTogetherRoom>> publicRooms() async {
    final response = await _dio.get('/watch-party/rooms');
    final rooms =
        (response.data is Map ? response.data['rooms'] : null) as List?;
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
          final roomData = map?['room'];
          final room = roomData is Map
              ? WatchTogetherState.fromJson(Map<String, dynamic>.from(roomData))
              : null;
          _keepRoomSocket(socket);
          if (!completer.isCompleted) {
            completer.complete(
              WatchTogetherCreateResult(code: code, room: room),
            );
          }
          timeout?.cancel();
        },
      );
    });

    socket.onConnectError(
      (error) => finishError('Không kết nối được Xem chung.'),
    );
    socket.onError((error) => finishError('Không kết nối được Xem chung.'));
    timeout = Timer(const Duration(seconds: 15), () {
      finishError('Kết nối Xem chung quá thời gian.');
    });
    socket.connect();
    return completer.future;
  }

  static Future<WatchTogetherState?> joinRoom({
    required String code,
    required String userName,
  }) async {
    final socket = _connectSocket();
    final completer = Completer<WatchTogetherState?>();
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
          final roomData = map?['room'];
          final room = roomData is Map
              ? WatchTogetherState.fromJson(Map<String, dynamic>.from(roomData))
              : null;
          _keepRoomSocket(socket);
          if (!completer.isCompleted) completer.complete(room);
          timeout?.cancel();
        },
      );
    });
    socket.onConnectError(
      (error) => finishError('Không kết nối được Xem chung.'),
    );
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

  static void closeActiveRoom() {
    final socket = _activeRoomSocket;
    if (socket == null) return;
    _activeRoomSocket = null;
    try {
      socket.emit('leave-room');
      socket.disconnect();
    } catch (_) {}
  }

  static void sendMessage(String text) {
    final message = text.trim();
    final socket = _activeRoomSocket;
    if (message.isEmpty || socket == null || socket.disconnected == true) {
      return;
    }
    socket.emitWithAck('chat-message', {'text': message});
  }

  static void syncState({required double currentTime, required bool playing}) {
    final socket = _activeRoomSocket;
    if (socket == null || socket.disconnected == true) return;
    socket.emit('sync-state', {'currentTime': currentTime, 'playing': playing});
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
