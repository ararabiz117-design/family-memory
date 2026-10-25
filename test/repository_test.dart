import 'package:flutter_test/flutter_test.dart';

import 'package:family_memory/models.dart';
import 'package:family_memory/repository.dart';

void main() {
  group('人物検索', () {
    late DemoFamilyRepository repository;

    setUp(() {
      repository = DemoFamilyRepository();
    });

    test('読み方、故人との関係、会った場面から探せる', () {
      expect(repository.searchPeople('たなか').single.id, 'tanaka');
      expect(repository.searchPeople('父の従兄').single.id, 'tanaka');
      expect(
        repository.searchPeople('三回忌').map((person) => person.id),
        contains('tanaka'),
      );
    });

    test('関係者だけに絞り込める', () {
      final results = repository.searchPeople('', kind: PersonKind.contact);

      expect(results, isNotEmpty);
      expect(
        results.every((person) => person.kind == PersonKind.contact),
        isTrue,
      );
    });
  });

  group('前回記録の安全な複製', () {
    test('日付、出欠、人数相当、金額を引き継がない', () async {
      final repository = DemoFamilyRepository();
      final source = repository.events.firstWhere(
        (event) => event.id == 'third',
      );

      final draft = await repository.duplicateSafely(source);

      expect(draft.id, isNot(source.id));
      expect(draft.status, EventStatus.planned);
      expect(draft.date, isNull);
      expect(draft.type, source.type);
      expect(draft.subjectPersonId, source.subjectPersonId);
      expect(draft.placeId, source.placeId);
      expect(
        draft.expenses.map((expense) => expense.label),
        source.expenses.map((expense) => expense.label),
      );
      expect(draft.expenses.every((expense) => expense.amount == null), isTrue);
      expect(
        draft.participants.every(
          (participant) => participant.attendance == null,
        ),
        isTrue,
      );
      expect(draft.total, 0);
    });
  });

  group('法要候補', () {
    test('候補は確定記録と分離される', () async {
      final repository = DemoFamilyRepository();
      final candidate = repository.candidates.first;

      expect(candidate.isCandidate, isTrue);
      expect(repository.confirmedEvents, isNot(contains(candidate)));

      await repository.confirmCandidate(candidate);

      expect(candidate.isCandidate, isFalse);
      expect(candidate.status, EventStatus.planned);
      expect(repository.confirmedEvents, contains(candidate));
    });
  });

  test('場所を故人に関連付けて保存できる', () async {
    final repository = DemoFamilyRepository();
    const place = MemoryPlace(
      id: 'new-grave',
      name: '架空の墓所',
      type: '墓所・墓石',
      address: '架空県みどり市',
      section: 'C列 3番',
    );

    await repository.savePlace(place, relatedPersonId: 'father');

    expect(repository.place('new-grave')?.section, 'C列 3番');
    expect(repository.person('father').placeIds, contains('new-grave'));
  });

  test('標準fixtureは架空データであることを表示する', () {
    final repository = DemoFamilyRepository();

    expect(repository.isDemo, isTrue);
    expect(
      repository.places.every((place) => place.address.contains('架空県')),
      isTrue,
    );
    expect(
      repository.people
          .where((person) => person.posthumousName.isNotEmpty)
          .every((person) => person.posthumousName.contains('架空')),
      isTrue,
    );
  });

  test('標準fixtureは家系図用の親子・配偶・関係者リンクを持つ', () {
    final repository = DemoFamilyRepository();
    expect(
      repository.relationships.any(
        (edge) => edge.fromPersonId == 'father' && edge.toPersonId == 'naoto',
      ),
      isTrue,
    );
    expect(
      repository.relationships.any((edge) => edge.label == '父の従兄'),
      isTrue,
    );
  });
}
