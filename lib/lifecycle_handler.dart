
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LifecycleEventHandler extends WidgetsBindingObserver {
  final VoidCallback? onResumed;
  final VoidCallback? onPaused;

  LifecycleEventHandler({this.onResumed, this.onPaused});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (onResumed != null) onResumed!();
        break;
      case AppLifecycleState.paused:
        if (onPaused != null) onPaused!();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> recordPauseTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_pause_time', DateTime.now().millisecondsSinceEpoch);
  }

  Future<int?> getLastPauseTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('last_pause_time');
  }

  Future<bool> shouldNotifyAgain({int cooldownMinutes = 5}) async {
    final last = await getLastPauseTimestamp();
    if (last == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMinutes = (now - last) ~/ 60000;
    return diffMinutes >= cooldownMinutes;
  }
}
