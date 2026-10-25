import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

const reminderNotificationBody = '家族の予定を確認してください';
const _reminderPayload = 'family-memory/reminder';
const _enabledPreference = 'local_reminders_enabled_v1';

class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.scheduledAt,
    required this.daysBefore,
  });

  final int id;
  final DateTime scheduledAt;
  final int daysBefore;
}

/// Pure planning logic kept separate so privacy and candidate filtering can be
/// covered without loading a platform notification implementation.
List<ReminderPlan> planLocalReminders(
  Iterable<MemorialEvent> events, {
  required DateTime now,
}) {
  final plans = <ReminderPlan>[];
  for (final event in events) {
    if (event.isCandidate ||
        event.status != EventStatus.planned ||
        event.date == null) {
      continue;
    }
    for (final days in event.notificationDays.toSet()) {
      if (days != 30 && days != 7) continue;
      final eventDate = event.date!;
      final scheduledAt = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        9,
      ).subtract(Duration(days: days));
      if (!scheduledAt.isAfter(now)) continue;
      plans.add(
        ReminderPlan(
          id: _stableNotificationId(event.id, days),
          scheduledAt: scheduledAt,
          daysBefore: days,
        ),
      );
    }
  }
  plans.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return plans;
}

int _stableNotificationId(String eventId, int daysBefore) {
  var hash = 0x811c9dc5;
  for (final unit in '$eventId:$daysBefore'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? daysBefore : hash;
}

class LocalReminderService {
  LocalReminderService._();

  static final instance = LocalReminderService._();
  static const supportedPlatforms = {
    TargetPlatform.android,
    TargetPlatform.iOS,
  };

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb && supportedPlatforms.contains(defaultTargetPlatform);

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledPreference) ?? false;
  }

  Future<bool> setEnabled(bool enabled, Iterable<MemorialEvent> events) async {
    if (!isSupported) return false;
    await initialize();
    final preferences = await SharedPreferences.getInstance();
    if (!enabled) {
      await preferences.setBool(_enabledPreference, false);
      await _cancelFamilyReminders();
      return false;
    }

    if (!await _requestPermission()) {
      await preferences.setBool(_enabledPreference, false);
      return false;
    }
    await preferences.setBool(_enabledPreference, true);
    await sync(events);
    return true;
  }

  Future<void> sync(Iterable<MemorialEvent> events) async {
    if (!isSupported || !await isEnabled()) return;
    await initialize();
    await _cancelFamilyReminders();
    final now = tz.TZDateTime.now(tz.local);
    for (final plan in planLocalReminders(events, now: now)) {
      final at = tz.TZDateTime(
        tz.local,
        plan.scheduledAt.year,
        plan.scheduledAt.month,
        plan.scheduledAt.day,
        plan.scheduledAt.hour,
      );
      await _plugin.zonedSchedule(
        plan.id,
        '家族の記憶',
        reminderNotificationBody,
        at,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'family_schedule_reminders',
            '家族の予定',
            channelDescription: '確定した家族の予定を30日前と7日前に通知します',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: _reminderPayload,
      );
    }
  }

  Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }
    return false;
  }

  Future<void> _cancelFamilyReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload == _reminderPayload) {
        await _plugin.cancel(request.id);
      }
    }
  }
}
