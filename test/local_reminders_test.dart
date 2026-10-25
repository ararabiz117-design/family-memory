import 'package:flutter_test/flutter_test.dart';

import 'package:family_memory/local_reminders.dart';
import 'package:family_memory/models.dart';

MemorialEvent _event({
  required String id,
  required DateTime date,
  EventStatus status = EventStatus.planned,
  bool isCandidate = false,
  List<int> days = const [30, 7],
}) => MemorialEvent(
  id: id,
  title: 'テスト予定（通知へ出さない）',
  type: '法事・法要',
  subjectPersonId: 'person-private',
  status: status,
  date: date,
  isCandidate: isCandidate,
  notificationDays: days,
);

void main() {
  test('確定した予定だけを30日前と7日前の9時に計画する', () {
    final plans = planLocalReminders([
      _event(id: 'event-a', date: DateTime(2027, 5, 18)),
    ], now: DateTime(2027, 1, 1));

    expect(plans, hasLength(2));
    expect(plans.map((plan) => plan.daysBefore), [30, 7]);
    expect(plans[0].scheduledAt, DateTime(2027, 4, 18, 9));
    expect(plans[1].scheduledAt, DateTime(2027, 5, 11, 9));
    expect(plans[0].id, isNot(plans[1].id));
    expect(reminderNotificationBody, '家族の予定を確認してください');
    expect(reminderNotificationBody, isNot(contains('テスト予定')));
  });

  test('候補・実施済み・過去時刻・30日前/7日前以外は通知しない', () {
    final now = DateTime(2027, 5, 1, 10);
    final plans = planLocalReminders([
      _event(id: 'candidate', date: DateTime(2027, 8), isCandidate: true),
      _event(
        id: 'completed',
        date: DateTime(2027, 8),
        status: EventStatus.completed,
      ),
      _event(id: 'past', date: DateTime(2027, 5, 8)),
      _event(
        id: 'unsupported-offset',
        date: DateTime(2027, 8),
        days: const [14],
      ),
    ], now: now);

    expect(plans, isEmpty);
  });

  test('同じ予定と日数から毎回同じ通知IDを作る', () {
    final event = _event(id: 'stable-event', date: DateTime(2028, 1, 1));

    final first = planLocalReminders([event], now: DateTime(2027, 1, 1));
    final second = planLocalReminders([event], now: DateTime(2027, 1, 1));

    expect(first.map((plan) => plan.id), second.map((plan) => plan.id));
  });
}
