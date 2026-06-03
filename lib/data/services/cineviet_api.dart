import 'package:dio/dio.dart';

class CineVietApi {
  CineVietApi()
      : dio = Dio(BaseOptions(
          baseUrl: 'https://cineviet.live/api',
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          headers: const {'Accept': 'application/json', 'User-Agent': 'CineVietFlutter/1.0'},
        ));

  final Dio dio;
}
