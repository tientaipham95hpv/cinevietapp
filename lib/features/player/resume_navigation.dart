import 'package:flutter/material.dart';

import '../../data/models/watch_history.dart';
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
