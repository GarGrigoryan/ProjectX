import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase (safe if already initialized)
    try {
      await Firebase.initializeApp();
    } catch (e) {
      print('Firebase already initialized or failed: $e');
    }

    final notifications = FlutterLocalNotificationsPlugin();

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await notifications.initialize(initSettings);

    // Firebase Database
    const deviceId = 'dAxXdU5e4PVqpvre1iXZWIWRl5k1'; // Replace with dynamic if needed
    final ref = FirebaseDatabase.instance.ref('devices/$deviceId/sensors/timestamp');

    final snapshot = await ref.get();

    if (!snapshot.exists) {
      print('❌ Timestamp does not exist.');
      return true;
    }

    final timestamp = int.tryParse(snapshot.value.toString());

    if (timestamp == null || timestamp == 0) {
      print('❌ Invalid timestamp: $timestamp');
      return true;
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final diffMinutes = (now - timestamp) / 60000;

    print('✅ Timestamp: $timestamp');
    print('🕒 Now: $now');
    print('📊 Diff in minutes: $diffMinutes');

    if (diffMinutes > 5) {
      await _showNotification(
        notifications,
        'Device has not reported data in over 5 minutes.',
      );
    } else {
      print('✅ Device is active. No notification sent.');
    }

    return true;
  });
}

@pragma('vm:entry-point')
Future<void> _showNotification(
  FlutterLocalNotificationsPlugin notifications,
  String message,
) async {
  const channelId = 'background_channel';

  // Create notification channel (required on Android 8+)
  const androidChannel = AndroidNotificationChannel(
    channelId,
    'Device Status',
    description: 'Device status notifications',
    importance: Importance.high,
  );

  final androidImplementation = notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidImplementation?.createNotificationChannel(androidChannel);

  const androidDetails = AndroidNotificationDetails(
    channelId,
    'Device Status',
    channelDescription: 'Device status notifications',
    importance: Importance.max,
    priority: Priority.high,
    icon: 'ic_stat_notify',
    enableVibration: true,
    playSound: true,
  );

  await notifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    '⚠️ Project X Status',
    message,
    const NotificationDetails(android: androidDetails),
  );
}
