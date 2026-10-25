import 'package:flutter_test/flutter_test.dart';
import 'package:family_memory/invitation_draft.dart';
import 'package:family_memory/models.dart';

void main() {
  group('parseInvitationText', () {
    test(
      'Japanese era dates, time and labeled venue become review candidates',
      () {
        final draft = parseInvitationText('令和９年 ５月１８日\n午後１時３０分\n会場：さくら会館');

        expect(draft.date, DateTime(2027, 5, 18));
        expect(draft.time, '13:30');
        expect(draft.place, 'さくら会館');
        expect(draft.notes, contains('要確認'));
      },
    );

    test('unsupported or ambiguous dates are left blank', () {
      expect(parseInvitationText('日時は後日ご案内します').date, isNull);
      expect(parseInvitationText('2027年2月30日').date, isNull);
    });
  });

  test(
    'badge counts planned non-candidate events from today through day seven',
    () {
      final now = DateTime(2027, 5, 10, 20);
      MemorialEvent event(
        String id,
        DateTime? date, {
        EventStatus status = EventStatus.planned,
        bool candidate = false,
      }) => MemorialEvent(
        id: id,
        title: id,
        type: '法事・法要',
        subjectPersonId: 'person',
        status: status,
        date: date,
        isCandidate: candidate,
      );

      expect(
        memorialEventsWithinDays([
          event('today', DateTime(2027, 5, 10)),
          event('day-seven', DateTime(2027, 5, 17, 23)),
          event('tomorrow-after-window', DateTime(2027, 5, 18)),
          event('past', DateTime(2027, 5, 9)),
          event('candidate', DateTime(2027, 5, 11), candidate: true),
          event(
            'cancelled',
            DateTime(2027, 5, 11),
            status: EventStatus.cancelled,
          ),
          event('unknown-date', null),
        ], now),
        2,
      );
    },
  );
}
