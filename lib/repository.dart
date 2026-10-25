import 'package:flutter/foundation.dart';

import 'attachment_models.dart';
import 'models.dart';

enum FamilyExportFormat { json, csv }

class FamilyExport {
  const FamilyExport({
    required this.bytes,
    required this.fileName,
    required this.extension,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String extension;
  final String mimeType;
}

abstract class FamilyRepository extends ChangeNotifier {
  List<Person> get people;
  List<PersonRelationship> get relationships;
  List<MemoryPlace> get places;
  List<MemorialEvent> get events;
  List<FamilyUser> get familyUsers;
  List<FamilyInvitation> get invitations;
  List<FamilyAttachment> get attachments;
  List<ActivityEntry> get activityEntries;
  String get centerPersonId;
  bool get viewerMode;
  bool get isDemo;
  String get familyName;
  String get currentRole;
  String get currentUserId;
  Person person(String id);
  MemoryPlace? place(String? id);
  List<Person> searchPeople(String query, {PersonKind? kind});
  List<MemorialEvent> get confirmedEvents;
  List<MemorialEvent> get candidates;
  void setCenter(String id);
  void setViewerMode(bool value);
  Future<void> savePerson(Person value);
  Future<void> saveRelationship(PersonRelationship value);
  Future<void> savePlace(MemoryPlace value, {String? relatedPersonId});
  Future<void> saveEvent(MemorialEvent value);
  Future<String> saveNewEvent(MemorialEvent value);
  Future<MemorialEvent> duplicateSafely(MemorialEvent source);
  Future<void> confirmCandidate(MemorialEvent event);
  Future<void> dismissCandidate(MemorialEvent event);
  Future<InvitationSecret> createInvitation(String email, String role);
  Future<void> approveInvitation(String invitationId);
  Future<void> revokeInvitation(String invitationId);
  Future<void> changeMemberRole(String userId, String role);
  List<FamilyAttachment> attachmentsFor(
    AttachmentTargetType targetType,
    String targetId,
  );
  Future<FamilyAttachment> addImageAttachment({
    required AttachmentTargetType targetType,
    required String targetId,
    required Uint8List sourceBytes,
    String caption = '',
  });
  Future<String> createAttachmentSignedUrl(String attachmentId);
  Future<void> softDeleteAttachment(FamilyAttachment attachment);
  Future<FamilyExport> exportFamilyData(FamilyExportFormat format);
  Future<void> sendDeletionVerificationCode();
  Future<void> verifyDeletionVerificationCode(String code);
  Future<void> requestAccountDeletion();
  Future<void> requestFamilyDeletion();
  Future<void> signOut();
}

class DemoFamilyRepository extends FamilyRepository {
  DemoFamilyRepository() {
    _seed();
  }
  @override
  final List<Person> people = [];
  @override
  final List<PersonRelationship> relationships = [];
  @override
  final List<MemoryPlace> places = [];
  @override
  final List<MemorialEvent> events = [];
  @override
  final List<FamilyUser> familyUsers = const [
    FamilyUser(
      id: 'demo-owner',
      name: '青葉 直人（あなた）',
      role: 'owner',
      state: 'この端末のデモ利用者',
    ),
    FamilyUser(
      id: 'demo-editor',
      name: '青葉 美咲',
      role: 'editor',
      state: '架空メンバー',
    ),
    FamilyUser(
      id: 'demo-viewer',
      name: '青葉 湊',
      role: 'viewer',
      state: '架空メンバー',
    ),
  ];
  @override
  final List<FamilyInvitation> invitations = const [];
  @override
  final List<FamilyAttachment> attachments = [];
  @override
  final List<ActivityEntry> activityEntries = [];
  @override
  String centerPersonId = 'naoto';
  @override
  bool viewerMode = false;
  @override
  bool get isDemo => true;
  @override
  String get familyName => '青葉家（架空）';
  @override
  String get currentRole => viewerMode ? 'viewer' : 'owner';
  @override
  String get currentUserId => 'demo-owner';

  @override
  Person person(String id) => people.firstWhere((item) => item.id == id);
  @override
  MemoryPlace? place(String? id) {
    if (id == null) return null;
    for (final value in places) {
      if (value.id == id) return value;
    }
    return null;
  }

  @override
  List<Person> searchPeople(String query, {PersonKind? kind}) => people
      .where(
        (item) => (kind == null || item.kind == kind) && item.matches(query),
      )
      .toList();
  @override
  List<MemorialEvent> get confirmedEvents =>
      events.where((item) => !item.isCandidate).toList()..sort(
        (a, b) =>
            (b.date ?? DateTime(1900)).compareTo(a.date ?? DateTime(1900)),
      );
  @override
  List<MemorialEvent> get candidates =>
      events.where((item) => item.isCandidate).toList()..sort(
        (a, b) =>
            (a.date ?? DateTime(9999)).compareTo(b.date ?? DateTime(9999)),
      );
  @override
  void setCenter(String id) {
    centerPersonId = id;
    notifyListeners();
  }

  @override
  void setViewerMode(bool value) {
    viewerMode = value;
    notifyListeners();
  }

  @override
  Future<void> savePerson(Person value) async {
    final index = people.indexWhere((item) => item.id == value.id);
    index < 0 ? people.add(value) : people[index] = value;
    notifyListeners();
  }

  @override
  Future<void> saveRelationship(PersonRelationship value) async {
    final index = relationships.indexWhere((item) => item.id == value.id);
    if (index < 0) {
      relationships.add(value);
    } else {
      relationships[index] = value;
    }
    notifyListeners();
  }

  @override
  Future<void> savePlace(MemoryPlace value, {String? relatedPersonId}) async {
    final index = places.indexWhere((item) => item.id == value.id);
    index < 0 ? places.add(value) : places[index] = value;
    if (relatedPersonId != null) {
      final personIndex = people.indexWhere(
        (item) => item.id == relatedPersonId,
      );
      if (personIndex >= 0 &&
          !people[personIndex].placeIds.contains(value.id)) {
        final target = people[personIndex];
        target.placeIds = [...target.placeIds, value.id];
      }
    }
    notifyListeners();
  }

  @override
  Future<void> saveEvent(MemorialEvent value) async {
    final index = events.indexWhere((item) => item.id == value.id);
    value.version += 1;
    index < 0 ? events.add(value) : events[index] = value;
    notifyListeners();
  }

  @override
  Future<String> saveNewEvent(MemorialEvent value) async {
    await saveEvent(value);
    return value.id;
  }

  @override
  Future<MemorialEvent> duplicateSafely(MemorialEvent source) async {
    final copy = MemorialEvent(
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      title: '${source.title}（次回準備）',
      type: source.type,
      subjectPersonId: source.subjectPersonId,
      status: EventStatus.planned,
      placeId: source.placeId,
      host: source.host,
      nextMemo: source.nextMemo,
      expenses: source.expenses
          .map((item) => Expense(label: item.label, amount: null))
          .toList(),
      participants: source.participants
          .map(
            (item) => EventParticipant(
              name: item.name,
              relationshipAtTime: item.relationshipAtTime,
            ),
          )
          .toList(),
    );
    events.add(copy);
    notifyListeners();
    return copy;
  }

  @override
  Future<void> confirmCandidate(MemorialEvent event) async {
    event.isCandidate = false;
    event.status = EventStatus.planned;
    notifyListeners();
  }

  @override
  Future<void> dismissCandidate(MemorialEvent event) async {
    events.remove(event);
    notifyListeners();
  }

  @override
  Future<InvitationSecret> createInvitation(String email, String role) =>
      throw UnsupportedError('デモモードでは招待できません。');
  @override
  Future<void> approveInvitation(String invitationId) =>
      throw UnsupportedError('デモモードでは承認できません。');
  @override
  Future<void> revokeInvitation(String invitationId) =>
      throw UnsupportedError('デモモードでは招待を取り消せません。');
  @override
  Future<void> changeMemberRole(String userId, String role) =>
      throw UnsupportedError('デモモードでは権限を変更できません。');
  @override
  List<FamilyAttachment> attachmentsFor(
    AttachmentTargetType targetType,
    String targetId,
  ) => const [];
  @override
  Future<FamilyAttachment> addImageAttachment({
    required AttachmentTargetType targetType,
    required String targetId,
    required Uint8List sourceBytes,
    String caption = '',
  }) => throw UnsupportedError('デモモードでは写真を追加できません。');
  @override
  Future<String> createAttachmentSignedUrl(String attachmentId) =>
      throw UnsupportedError('デモモードでは写真を表示できません。');
  @override
  Future<void> softDeleteAttachment(FamilyAttachment attachment) =>
      throw UnsupportedError('デモモードでは写真を削除できません。');
  @override
  Future<FamilyExport> exportFamilyData(FamilyExportFormat format) =>
      throw UnsupportedError('デモモードではデータを出力できません。');
  @override
  Future<void> sendDeletionVerificationCode() =>
      throw UnsupportedError('デモモードでは削除できません。');
  @override
  Future<void> verifyDeletionVerificationCode(String code) =>
      throw UnsupportedError('デモモードでは削除できません。');
  @override
  Future<void> requestAccountDeletion() =>
      throw UnsupportedError('デモモードでは削除できません。');
  @override
  Future<void> requestFamilyDeletion() =>
      throw UnsupportedError('デモモードでは削除できません。');
  @override
  Future<void> signOut() async {}

  void _seed() {
    places.addAll(const [
      MemoryPlace(
        id: 'temple',
        name: '光明寺（架空）',
        type: '寺院・法要会場',
        address: '架空県みどり市若葉一丁目',
        landmark: '山門右手の受付',
        directions: '南側入口から石段を上がり、本堂右手へ。',
        mapUrl: 'https://maps.google.com/',
      ),
      MemoryPlace(
        id: 'grave',
        name: 'みどり霊園（架空）',
        type: '霊園・墓地',
        address: '架空県みどり市青空二丁目',
        section: 'やすらぎ区・B列・12番',
        landmark: '大きな桜の木の向かい',
        directions: '東入口から2本目を左折。水場を過ぎて右側。',
        mapUrl: 'https://maps.google.com/',
      ),
      MemoryPlace(
        id: 'hall',
        name: '若葉会館（架空）',
        type: '会食会場',
        address: '架空県みどり市若葉三丁目',
        landmark: '1階さくらの間',
      ),
    ]);
    people.addAll([
      Person(
        id: 'naoto',
        name: '青葉 直人',
        kana: 'あおば なおと',
        relationship: 'あなた',
        kind: PersonKind.family,
        born: '1985年',
        initials: '直',
      ),
      Person(
        id: 'mother',
        name: '青葉 和子',
        kana: 'あおば かずこ',
        relationship: '母',
        kind: PersonKind.family,
        born: '1958年4月',
        initials: '和',
        consentConfirmed: true,
      ),
      Person(
        id: 'wife',
        name: '青葉 美咲',
        kana: 'あおば みさき',
        relationship: '配偶者',
        kind: PersonKind.family,
        born: '1987年',
        initials: '美',
        consentConfirmed: true,
      ),
      Person(
        id: 'son',
        name: '青葉 湊',
        kana: 'あおば みなと',
        relationship: '息子',
        kind: PersonKind.family,
        born: '2012年',
        initials: '湊',
        consentConfirmed: true,
      ),
      Person(
        id: 'daughter',
        name: '青葉 結衣',
        kana: 'あおば ゆい',
        relationship: '娘',
        kind: PersonKind.family,
        born: '2015年',
        initials: '結',
        consentConfirmed: true,
      ),
      Person(
        id: 'father',
        name: '青葉 正一',
        kana: 'あおば しょういち',
        relationship: '父',
        kind: PersonKind.family,
        lifeStatus: LifeStatus.deceased,
        born: '1955年',
        died: '2023年5月18日',
        posthumousName: '清光院釋正道（架空）',
        religion: '仏教・宗派は家族で確認済み（架空）',
        initials: '正',
        placeIds: const ['grave', 'temple'],
      ),
      Person(
        id: 'grandfather',
        name: '青葉 源一',
        kana: 'あおば げんいち',
        relationship: '祖父',
        kind: PersonKind.family,
        lifeStatus: LifeStatus.deceased,
        died: '2009年11月',
        posthumousName: '慈雲院釋源明（架空）',
        initials: '源',
        placeIds: const ['grave'],
      ),
      Person(
        id: 'grandmother',
        name: '青葉 春江',
        kana: 'あおば はるえ',
        relationship: '祖母',
        kind: PersonKind.family,
        lifeStatus: LifeStatus.deceased,
        died: '2016年2月7日',
        posthumousName: '春光院妙華（架空）',
        initials: '春',
        placeIds: const ['grave'],
      ),
      Person(
        id: 'tanaka',
        name: '田中 隆',
        kana: 'たなか たかし',
        relationship: '父の従兄',
        kind: PersonKind.contact,
        nickname: '隆さん',
        lastMet: '父の三回忌で会った',
        howToAddress: '「隆さん」と呼ぶ',
        notes: '青い眼鏡。父の子どもの頃の話に詳しい。',
        initials: '隆',
      ),
      Person(
        id: 'aunt',
        name: '森川 幸子',
        kana: 'もりかわ さちこ',
        relationship: '祖母の妹',
        kind: PersonKind.contact,
        nickname: '幸子おばさん',
        lastMet: '祖母の七回忌で会った',
        howToAddress: '「幸子おばさん」',
        notes: '写真を多く保管している。',
        initials: '幸',
      ),
      Person(
        id: 'monk',
        name: '山本さん（架空）',
        kana: 'やまもと',
        relationship: '光明寺の担当者',
        kind: PersonKind.contact,
        lastMet: '父の三回忌',
        howToAddress: '「山本さん」',
        notes: '連絡は寺院の代表窓口へ。',
        initials: '山',
      ),
    ]);
    relationships.addAll(const [
      PersonRelationship(
        id: 'r-grandfather-father',
        fromPersonId: 'grandfather',
        toPersonId: 'father',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-grandmother-father',
        fromPersonId: 'grandmother',
        toPersonId: 'father',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-grandparents',
        fromPersonId: 'grandfather',
        toPersonId: 'grandmother',
        kind: RelationshipKind.spouse,
      ),
      PersonRelationship(
        id: 'r-father-naoto',
        fromPersonId: 'father',
        toPersonId: 'naoto',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-mother-naoto',
        fromPersonId: 'mother',
        toPersonId: 'naoto',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-parents',
        fromPersonId: 'father',
        toPersonId: 'mother',
        kind: RelationshipKind.spouse,
      ),
      PersonRelationship(
        id: 'r-naoto-wife',
        fromPersonId: 'naoto',
        toPersonId: 'wife',
        kind: RelationshipKind.spouse,
      ),
      PersonRelationship(
        id: 'r-naoto-son',
        fromPersonId: 'naoto',
        toPersonId: 'son',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-wife-son',
        fromPersonId: 'wife',
        toPersonId: 'son',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-naoto-daughter',
        fromPersonId: 'naoto',
        toPersonId: 'daughter',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-wife-daughter',
        fromPersonId: 'wife',
        toPersonId: 'daughter',
        kind: RelationshipKind.parentChild,
      ),
      PersonRelationship(
        id: 'r-naoto-tanaka',
        fromPersonId: 'naoto',
        toPersonId: 'tanaka',
        kind: RelationshipKind.acquaintance,
        label: '父の従兄',
      ),
      PersonRelationship(
        id: 'r-naoto-aunt',
        fromPersonId: 'naoto',
        toPersonId: 'aunt',
        kind: RelationshipKind.acquaintance,
        label: '祖母の妹',
      ),
    ]);
    events.addAll([
      MemorialEvent(
        id: 'third',
        title: '父の三回忌',
        type: '法事・法要',
        subjectPersonId: 'father',
        status: EventStatus.completed,
        date: DateTime(2025, 5, 17),
        placeId: 'temple',
        host: '青葉 直人',
        notes: '本堂で法要後、若葉会館で会食。案内状は6週間前に発送した。',
        nextMemo: '足の悪い親族向けに椅子席と送迎を早めに確認する。',
        expenses: [
          Expense(label: 'お布施', amount: 50000, payer: '青葉 直人'),
          Expense(label: '御車代', amount: 10000, payer: '青葉 直人'),
          Expense(label: '会食', amount: 96000, payer: '青葉家'),
        ],
        participants: [
          EventParticipant(
            name: '田中 隆',
            relationshipAtTime: '父の従兄',
            attendance: '出席',
          ),
          EventParticipant(
            name: '森川 幸子',
            relationshipAtTime: '父の叔母',
            attendance: '出席',
          ),
          EventParticipant(
            name: '青葉家',
            relationshipAtTime: '遺族',
            attendance: '出席',
          ),
        ],
      ),
      MemorialEvent(
        id: 'gift',
        title: '田中家へのお中元',
        type: 'お中元・お歳暮',
        subjectPersonId: 'tanaka',
        status: EventStatus.completed,
        date: DateTime(2026, 7, 8),
        notes: '果汁ジュース詰め合わせを配送。お礼の電話あり。',
        nextMemo: '次回も常温保存できる品を選ぶ。',
        expenses: [Expense(label: '品物・送料', amount: 5400, payer: '青葉家')],
        participants: [
          EventParticipant(
            name: '田中 隆',
            relationshipAtTime: '贈答先',
            attendance: '受取済み',
          ),
        ],
      ),
      MemorialEvent(
        id: 'anniversary',
        title: '父の七回忌候補',
        type: '法事・法要',
        subjectPersonId: 'father',
        status: EventStatus.planned,
        date: DateTime(2029, 5, 18),
        isCandidate: true,
      ),
      MemorialEvent(
        id: 'obon',
        title: '父の新盆候補',
        type: '新盆・初盆',
        subjectPersonId: 'father',
        status: EventStatus.planned,
        date: DateTime(2023, 8, 13),
        isCandidate: true,
      ),
    ]);
  }
}
