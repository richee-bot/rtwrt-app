import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Shows the event feed's findings as system notifications.
///
/// The feed itself is derived locally from polling the router
/// ([EventDeriver]); nothing is sent anywhere. That matters: the privacy
/// policy promises all communication stays between the device and the
/// router, which rules out any push service.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const channelId = 'router_events';
  static const channelIdCall = 'rtwrt_telephony_calls';
  static const channelIdSms = 'rtwrt_telephony_sms';

  /// Only a fallback. Android shows this in system settings as the label of
  /// the category the user can switch off, so the caller passes the
  /// localized name; this is what is left if none was given.
  static const channelName = 'Router events';
  static const channelNameCall = 'Phone Calls';
  static const channelNameSms = 'SMS Messages';
  static const int callNotificationId = 999901;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks for permission, returning whether it was granted.
  ///
  /// Android 13+ needs a runtime grant; older versions answer null, which
  /// means "already allowed" rather than "refused".
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? true;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
    } catch (e, stack) {
      Logger.exception('Requesting notification permission failed', e, stack);
    }
    return false;
  }

  /// Posts one notification per event.
  ///
  /// Each uses the event's own id so the same event arriving twice — a
  /// re-run of the same poll window — replaces rather than stacks.
  Future<void> show(
    List<({RouterEvent event, String text})> items, {
    String channelName = NotificationService.channelName,
  }) async {
    if (items.isEmpty) return;
    await init();
    for (final item in items) {
      try {
        await _plugin.show(
          id: notificationId(item.event),
          title: item.text,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              importance: _importance(item.event.severity),
              priority: _priority(item.event.severity),
              // A router event is information, not an alarm; waking the
              // screen for "a laptop joined" would be indefensible.
              category: AndroidNotificationCategory.status,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      } catch (e, stack) {
        Logger.exception('Showing a notification failed', e, stack);
      }
    }
  }

  /// High-priority ringing alert for an incoming telephone call
  Future<void> showIncomingCall({required String callerNumber}) async {
    await init();
    try {
      await _plugin.show(
        id: callNotificationId,
        title: 'Incoming Call',
        body: callerNumber.isNotEmpty ? callerNumber : 'Unknown Caller',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelIdCall,
            channelNameCall,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e, stack) {
      Logger.exception('Showing incoming call notification failed', e, stack);
    }
  }

  /// Clears active incoming call notification once answered or declined
  Future<void> cancelIncomingCall() async {
    try {
      await _plugin.cancel(id: callNotificationId);
    } catch (_) {}
  }

  /// High-priority notification when a new SMS message arrives
  Future<void> showNewSms({
    required String sender,
    required String message,
    int? messageId,
  }) async {
    await init();
    try {
      final id = messageId ?? (DateTime.now().millisecondsSinceEpoch & 0x7fffffff);
      await _plugin.show(
        id: id,
        title: 'SMS from $sender',
        body: message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelIdSms,
            channelNameSms,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
      );
    } catch (e, stack) {
      Logger.exception('Showing SMS notification failed', e, stack);
    }
  }

  /// A stable id per event, so repeats replace instead of piling up.
  @visibleForTesting
  static int notificationId(RouterEvent event) =>
      event.dedupeKey.hashCode & 0x7fffffff;

  static Importance _importance(EventSeverity severity) => switch (severity) {
    EventSeverity.problem => Importance.high,
    EventSeverity.warning => Importance.defaultImportance,
    EventSeverity.info => Importance.low,
  };

  static Priority _priority(EventSeverity severity) => switch (severity) {
    EventSeverity.problem => Priority.high,
    EventSeverity.warning => Priority.defaultPriority,
    EventSeverity.info => Priority.low,
  };
}
