import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'od_service.dart';

/// Firebase Cloud Messaging.
///
/// The server sends a push whenever an OD changes hands. Android shows it
/// itself when the app is in the background or closed; when the app is in the
/// foreground it does not, so the message is handed to the local notification
/// plugin to display.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // Runs in its own isolate with no access to app state. Android has already
  // shown the notification by this point, so there is nothing to do here
  // beyond existing - registering a handler is what allows data messages to
  // wake the app at all.
  debugPrint('background push: ${message.messageId}');
}

class PushService {
  static bool _started = false;

  /// Asks for permission, wires up the handlers, and registers this device
  /// with the server so it can be pushed to.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

      // Foreground: Android suppresses the system notification, so raise it
      // locally and refresh the list behind it.
      FirebaseMessaging.onMessage.listen((message) async {
        final n = message.notification;
        if (n != null) {
          await NotificationService.show(
            id: message.messageId ?? DateTime.now().toIso8601String(),
            title: n.title ?? 'SMVEC-IT OD',
            body: n.body ?? '',
          );
        }
        await ODService().refresh();
      });

      // Tapped from the shade: make sure the data behind it is current.
      FirebaseMessaging.onMessageOpenedApp.listen((_) => ODService().refresh());

      await _registerToken(messaging);
      messaging.onTokenRefresh.listen((token) => ODService().registerDevice(token));
    } catch (err) {
      // Push is a convenience. A device without Play Services, or one that
      // refuses permission, must still be able to use the app.
      debugPrint('push unavailable: $err');
    }
  }

  static Future<void> _registerToken(FirebaseMessaging messaging) async {
    final token = await messaging.getToken();
    if (token != null) await ODService().registerDevice(token);
  }

  /// Detaches this device so the next person signing in on the same phone does
  /// not receive the previous user's notifications.
  static Future<void> stop() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (err) {
      debugPrint('could not clear push token: $err');
    }
  }
}
