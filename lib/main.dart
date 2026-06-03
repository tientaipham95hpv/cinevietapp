import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'core/services/desktop_oauth_service.dart';
import 'core/theme/cineviet_theme.dart';
import 'core/widgets/adaptive_scaffold.dart';
import 'core/widgets/desktop_drag_scroll.dart';
import 'core/widgets/update_prompt.dart';
import 'features/home/home_screen.dart';
import 'features/search/search_browse_screen.dart';
import 'features/my/my_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/history/history_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  VideoPlayerMediaKit.ensureInitialized(windows: true);
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await Firebase.initializeApp();
      await FirebaseAnalytics.instance.logAppOpen();
    } catch (_) {
      // Keep the app usable; analytics will simply be disabled.
    }
  }
  runApp(const ProviderScope(child: CineVietApp()));
}

class CineVietApp extends StatelessWidget {
  const CineVietApp({super.key});

  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CineViet',
      debugShowCheckedModeBanner: false,
      theme: CineVietTheme.dark(),
      scrollBehavior: const DesktopDragScrollBehavior(),
      navigatorObservers:
          !kIsWeb && Platform.isAndroid && Firebase.apps.isNotEmpty
          ? [FirebaseAnalyticsObserver(analytics: _analytics)]
          : const [],
      home: const DesktopOAuthHandler(
        child: UpdatePrompt(
          child: AdaptiveScaffold(
            children: [
              HomeScreen(),
              SearchBrowseScreen(),
              MyScreen(),
              HistoryScreen(),
              ProfileScreen(),
            ],
          ),
        ),
      ),
    );
  }
}
