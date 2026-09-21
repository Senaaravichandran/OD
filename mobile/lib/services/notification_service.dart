import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Raises a device notification when something happens to an OD request.
///
/// These are local notifications: the app raises them itself when a sync finds
/// a notification it has not shown before. That covers the app being open or
/// resumed, which is when students and staff actually check. It does not cover
/// the app being fully closed - that needs a push service (FCM), which in turn
/// needs a Firebase project. See NOTIFICATIONS.md.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _seenKey = 'smvec_seen_notif_ids_v1';
  static const _channelId = 'smvec_od_updates';

  static bool _ready = false;
  static Set<String> _seen = {};

  static Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );

      final android13 = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android13?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'OD updates',
          description: 'Approvals, rejections and new OD requests.',
          importance: Importance.high,
        ),
      );
      await android13?.requestNotificationsPermission();

      final prefs = await SharedPreferences.getInstance();
      _seen = (prefs.getStringList(_seenKey) ?? <String>[]).toSet();
      _ready = true;
    } catch (err) {
      // A device that refuses notifications must not break sign-in.
      debugPrint('Notifications unavailable: $err');
    }
  }

  /// Shows anything in [items] that has not been shown on this device before.
  ///
  /// [items] is the notification list from a SYNC, newest first. On the very
  /// first sync after signing in, everything is marked as seen without being
  /// shown, so a new user is not buried under their whole history.
  static Future<void> showNew(
    List<({String id, String title, String body})> items, {
    bool silent = false,
  }) async {
    if (!_ready || items.isEmpty) return;

    final fresh = items.where((n) => n.id.isNotEmpty && !_seen.contains(n.id)).toList();
    if (fresh.isEmpty) return;

    if (!silent) {
      // Oldest first, so the newest ends up on top of the shade.
      for (final n in fresh.reversed) {
        try {
          await _plugin.show(
            n.id.hashCode & 0x7fffffff,
            n.title,
            n.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                'OD updates',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
          );
        } catch (err) {
          debugPrint('Could not show notification: $err');
        }
      }
    }

    _seen.addAll(fresh.map((n) => n.id));
    // Keep the seen-list from growing without bound.
    if (_seen.length > 300) {
      _seen = _seen.toList().sublist(_seen.length - 300).toSet();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey, _seen.toList());
    } catch (_) {
      // Non-fatal: at worst a notification is shown twice.
    }
  }

  /// Shows a single notification immediately. Used for foreground pushes,
  /// which Android does not display on the app's behalf.
  static Future<void> show({
    required String id,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id.hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'OD updates',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      _seen.add(id);
    } catch (err) {
      debugPrint('Could not show notification: $err');
    }
  }

  /// Forgets what has been shown, so a new account starts clean.
  static Future<void> reset() async {
    _seen = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_seenKey);
    } catch (_) {}
  }
}
