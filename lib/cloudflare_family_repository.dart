import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'attachment_image_processor.dart';
import 'attachment_models.dart';
import 'cloudflare_client.dart';
import 'models.dart';
import 'memorial_candidates.dart';
import 'repository.dart';

String cloudflareRecordId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class CloudflareFamilyRepository extends FamilyRepository {
  CloudflareFamilyRepository(this.client);
  final CloudflareClient client;
  @override
  final List<Person> people = [];
  @override
  final List<PersonRelationship> relationships = [];
  @override
  final List<MemoryPlace> places = [];
  @override
  final List<MemorialEvent> events = [];
  @override
  final List<FamilyUser> familyUsers = [];
  @override
  final List<FamilyInvitation> invitations = [];
  @override
  final List<FamilyAttachment> attachments = [];
  @override
  final List<ActivityEntry> activityEntries = [];
  @override
  String centerPersonId = '';
  @override
  bool viewerMode = false;
  @override
  bool get isDemo => false;
  @override
  String familyName = '';
  @override
  String currentRole = 'viewer';
  @override
  String currentUserId = '';

  static Future<CloudflareFamilyRepository> connect(
    CloudflareClient client,
  ) async {
    final repository = CloudflareFamilyRepository(client);
    await repository.reload();
    return repository;
  }

  Future<void> reload() async =>
      applyState(await client.json('GET', '/api/family/state'));

  // Decode the complete response before replacing visible state, so malformed
  // or failed responses cannot partially overwrite the previously loaded family.
  void applyState(Map<String, dynamic> state) {
    List<Map<String, dynamic>> rows(String key) => (state[key] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final nextPeople = rows('people').map(personFromCloudflare).toList();
    final nextRelationships = rows('relationships')
        .map(
          (r) => PersonRelationship(
            id: r['id'],
            fromPersonId: r['fromPersonId'],
            toPersonId: r['toPersonId'],
            kind: RelationshipKind.values.byName(r['kind']),
            label: r['label'] ?? '',
            notes: r['notes'] ?? '',
            version: r['version'] ?? 1,
          ),
        )
        .toList();
    final nextPlaces = rows('places')
        .map(
          (r) => MemoryPlace(
            id: r['id'],
            name: r['name'],
            type: r['type'],
            address: r['address'] ?? '',
            section: r['section'] ?? '',
            landmark: r['landmark'] ?? '',
            directions: r['directions'] ?? '',
            mapUrl: r['mapUrl'] ?? '',
            version: r['version'] ?? 1,
          ),
        )
        .toList();
    final nextEvents = rows('events').map(eventFromCloudflare).toList();
    final nextMembers = rows('members')
        .map(
          (r) => FamilyUser(
            id: r['id'],
            name: r['name'] ?? '',
            role: r['role'],
            state: r['state'] ?? '',
          ),
        )
        .toList();
    final nextInvites = rows('invitations')
        .map(
          (r) => FamilyInvitation(
            id: r['id'],
            role: r['role'],
            status: r['status'],
            expiresAt: DateTime.parse(r['expiresAt']),
            acceptedDisplayName: r['acceptedDisplayName'] ?? '',
          ),
        )
        .toList();
    final nextAttachments = rows(
      'attachments',
    ).map(attachmentFromCloudflare).toList();
    final nextActivities = rows('activities')
        .map(
          (r) => ActivityEntry(
            actorName: r['actorName'] ?? '',
            action: r['action'],
            entityType: r['entityType'],
            occurredAt: DateTime.parse(r['occurredAt']),
            changedFields: List<String>.from(r['changedFields'] ?? []),
          ),
        )
        .toList();
    familyName = state['family']['name'];
    currentRole = state['family']['role'];
    currentUserId = state['user']['id'];
    final requestedCenter = state['centerPersonId'] as String?;
    centerPersonId = nextPeople.any((p) => p.id == requestedCenter)
        ? requestedCenter!
        : (nextPeople.isEmpty ? '' : nextPeople.first.id);
    people
      ..clear()
      ..addAll(nextPeople);
    relationships
      ..clear()
      ..addAll(nextRelationships);
    places
      ..clear()
      ..addAll(nextPlaces);
    events
      ..clear()
      ..addAll(nextEvents);
    familyUsers
      ..clear()
      ..addAll(nextMembers);
    invitations
      ..clear()
      ..addAll(nextInvites);
    attachments
      ..clear()
      ..addAll(nextAttachments);
    activityEntries
      ..clear()
      ..addAll(nextActivities);
    notifyListeners();
  }

  void _editable({bool owner = false}) {
    if (viewerMode ||
        currentRole == 'viewer' ||
        (owner && currentRole != 'owner')) {
      throw const CloudflareApiException(403, 'FORBIDDEN');
    }
  }

  @override
  Person person(String id) => people.firstWhere((p) => p.id == id);
  @override
  MemoryPlace? place(String? id) {
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  List<Person> searchPeople(String query, {PersonKind? kind}) => people
      .where((p) => (kind == null || kind == p.kind) && p.matches(query))
      .toList();
  @override
  List<MemorialEvent> get confirmedEvents =>
      events.where((e) => !e.isCandidate).toList()..sort(
        (a, b) =>
            (b.date ?? DateTime(1900)).compareTo(a.date ?? DateTime(1900)),
      );
  @override
  List<MemorialEvent> get candidates =>
      events.where((e) => e.isCandidate).toList()..sort(
        (a, b) =>
            (a.date ?? DateTime(9999)).compareTo(b.date ?? DateTime(9999)),
      );
  @override
  void setCenter(String id) {
    if (!people.any((p) => p.id == id)) return;
    _saveCenter(id);
  }

  Future<void> _saveCenter(String id) async {
    try {
      await client.json(
        'POST',
        '/api/preferences',
        data: {'centerPersonId': id},
      );
      centerPersonId = id;
      notifyListeners();
    } catch (_) {
      /* Navigation preference failure does not mutate records. */
    }
  }

  @override
  void setViewerMode(bool value) {
    viewerMode = value;
    notifyListeners();
  }

  Future<String> _save(
    String entity,
    String id,
    Map<String, dynamic> data,
    int? version,
  ) async {
    _editable();
    final response = await client.json(
      'PUT',
      '/api/records/$entity/${Uri.encodeComponent(id)}',
      data: {'data': data, 'expectedVersion': version},
    );
    await reload();
    return response['id'] as String;
  }

  @override
  Future<void> savePerson(Person value) async {
    await _save(
      'person',
      value.id,
      personToCloudflare(value),
      people.any((p) => p.id == value.id) ? value.version : null,
    );
    if (value.lifeStatus != LifeStatus.deceased ||
        !RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$').hasMatch(value.died)) {
      return;
    }
    final parts = value.died.split(RegExp('[-/]')).map(int.parse).toList();
    final deathDate = DateTime(parts[0], parts[1], parts[2]);
    if (deathDate.year != parts[0] ||
        deathDate.month != parts[1] ||
        deathDate.day != parts[2]) {
      return;
    }
    for (final candidate in memorialCandidatesFor(value.name, deathDate)) {
      final id =
          'candidate-${value.id}-${candidate.date.toIso8601String().substring(0, 10)}';
      if (events.any(
        (e) =>
            e.id == id ||
            (e.subjectPersonId == value.id && e.date == candidate.date),
      )) {
        continue;
      }
      try {
        await saveEvent(
          MemorialEvent(
            id: id,
            title: candidate.title,
            type: candidate.type,
            subjectPersonId: value.id,
            status: EventStatus.planned,
            date: candidate.date,
            isCandidate: true,
            notificationDays: const [],
          ),
        );
      } on CloudflareApiException catch (error) {
        if (error.status != 409) rethrow;
        await reload();
      }
    }
  }

  @override
  Future<void> saveRelationship(PersonRelationship value) async {
    await _save('relationship', value.id, {
      'id': value.id,
      'fromPersonId': value.fromPersonId,
      'toPersonId': value.toPersonId,
      'kind': value.kind.name,
      'label': value.label,
      'notes': value.notes,
    }, relationships.any((p) => p.id == value.id) ? value.version : null);
  }

  @override
  Future<void> savePlace(MemoryPlace value, {String? relatedPersonId}) async {
    await _save('place', value.id, {
      'id': value.id,
      'name': value.name,
      'type': value.type,
      'address': value.address,
      'section': value.section,
      'landmark': value.landmark,
      'directions': value.directions,
      'mapUrl': value.mapUrl,
      'relatedPersonId': ?relatedPersonId,
    }, places.any((p) => p.id == value.id) ? value.version : null);
    if (relatedPersonId != null) {
      final p = person(relatedPersonId);
      if (!p.placeIds.contains(value.id)) {
        final copy = personFromCloudflare(personToCloudflare(p));
        copy.placeIds = [...p.placeIds, value.id];
        await savePerson(copy);
      }
    }
  }

  @override
  Future<void> saveEvent(MemorialEvent value) async {
    await _save(
      'event',
      value.id,
      eventToCloudflare(value),
      events.any((p) => p.id == value.id) ? value.version : null,
    );
  }

  @override
  Future<String> saveNewEvent(MemorialEvent value) => _save(
    'event',
    cloudflareRecordId(),
    eventToCloudflare(value)..remove('id'),
    null,
  );
  @override
  Future<MemorialEvent> duplicateSafely(MemorialEvent source) async {
    final copy = MemorialEvent(
      id: cloudflareRecordId(),
      title: '${source.title}（次回準備）',
      type: source.type,
      subjectPersonId: source.subjectPersonId,
      status: EventStatus.planned,
      placeId: source.placeId,
      host: source.host,
      nextMemo: source.nextMemo,
      expenses: source.expenses
          .map((e) => Expense(label: e.label, amount: null))
          .toList(),
      participants: source.participants
          .map(
            (e) => EventParticipant(
              name: e.name,
              relationshipAtTime: e.relationshipAtTime,
            ),
          )
          .toList(),
    );
    await saveEvent(copy);
    return events.firstWhere((e) => e.id == copy.id);
  }

  @override
  Future<void> confirmCandidate(MemorialEvent event) async {
    final copy = eventFromCloudflare(eventToCloudflare(event));
    copy.isCandidate = false;
    copy.status = EventStatus.planned;
    await saveEvent(copy);
  }

  @override
  Future<void> dismissCandidate(MemorialEvent event) async {
    _editable();
    await client.json(
      'DELETE',
      '/api/records/event/${Uri.encodeComponent(event.id)}',
      data: {'expectedVersion': event.version},
    );
    await reload();
  }

  @override
  Future<InvitationSecret> createInvitation(String email, String role) async {
    _editable(owner: true);
    final r = await client.json(
      'POST',
      '/api/invitations',
      data: {'email': email, 'role': role},
    );
    await reload();
    return InvitationSecret(
      shortCode: r['shortCode'],
      inviteUrl: r['inviteUrl'],
    );
  }

  @override
  Future<void> approveInvitation(String invitationId) async {
    _editable(owner: true);
    await client.json(
      'POST',
      '/api/invitations/${Uri.encodeComponent(invitationId)}/approve',
    );
    await reload();
  }

  @override
  Future<void> revokeInvitation(String invitationId) async {
    _editable(owner: true);
    await client.json(
      'POST',
      '/api/invitations/${Uri.encodeComponent(invitationId)}/revoke',
    );
    await reload();
  }

  @override
  Future<void> changeMemberRole(String userId, String role) async {
    _editable(owner: true);
    await client.json(
      'PUT',
      '/api/members/${Uri.encodeComponent(userId)}',
      data: {'role': role},
    );
    await reload();
  }

  @override
  List<FamilyAttachment> attachmentsFor(
    AttachmentTargetType targetType,
    String targetId,
  ) => attachments
      .where((a) => a.targetType == targetType && a.targetId == targetId)
      .toList();
  @override
  Future<FamilyAttachment> addImageAttachment({
    required AttachmentTargetType targetType,
    required String targetId,
    required Uint8List sourceBytes,
    String caption = '',
  }) async {
    _editable();
    final image = await compute(sanitizeAttachmentImage, sourceBytes);
    final response = await client.request(
      'POST',
      '/api/attachments?targetType=${targetType.name}&targetId=${Uri.encodeComponent(targetId)}',
      bytes: image.bytes,
      headers: {
        'content-type': image.mimeType,
        'x-caption': base64UrlEncode(utf8.encode(caption)).replaceAll('=', ''),
      },
    );
    final attachment = attachmentFromCloudflare(
      Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      ),
    );
    await reload();
    return attachment;
  }

  @override
  Future<String> createAttachmentSignedUrl(String attachmentId) async {
    final r = await client.json(
      'GET',
      '/api/attachments/${Uri.encodeComponent(attachmentId)}/url',
    );
    final value = r['url'] as String;
    return value.startsWith('/') ? client.uri(value).toString() : value;
  }

  @override
  Future<void> softDeleteAttachment(FamilyAttachment attachment) async {
    _editable();
    await client.json(
      'DELETE',
      '/api/attachments/${Uri.encodeComponent(attachment.id)}',
      data: {'expectedVersion': attachment.version},
    );
    await reload();
  }

  @override
  Future<FamilyExport> exportFamilyData(FamilyExportFormat format) async {
    _editable(owner: true);
    final response = await client.request(
      'GET',
      '/api/export?format=${format.name}',
    );
    return FamilyExport(
      bytes: response.bodyBytes,
      fileName:
          'family-memory-${DateTime.now().toIso8601String().substring(0, 10)}.${format.name}',
      extension: format.name,
      mimeType: format == FamilyExportFormat.json
          ? 'application/json'
          : 'text/csv',
    );
  }

  Future<void> reauthenticateGoogle() => client.startGoogleLogin();
  @override
  Future<void> sendDeletionVerificationCode() => reauthenticateGoogle();
  @override
  Future<void> verifyDeletionVerificationCode(String code) async {
    throw const CloudflareApiException(401, 'GOOGLE_REAUTH_REQUIRED');
  }

  @override
  Future<void> requestAccountDeletion() async {
    await client.json('POST', '/api/deletions/account');
    await client.signOut();
  }

  @override
  Future<void> requestFamilyDeletion() async {
    _editable(owner: true);
    await client.json('POST', '/api/deletions/family');
    await client.signOut();
  }

  @override
  Future<void> signOut() => client.signOut();
  Future<Map<String, dynamic>> suggestInvitation(
    String text, {
    required bool consent,
  }) async {
    if (!consent) {
      throw const CloudflareApiException(400, 'AI_CONSENT_REQUIRED');
    }
    return client.json(
      'POST',
      '/api/ai/invitation',
      data: {'text': text, 'consent': consent},
    );
  }

  Future<String> askGuide(String question, {required bool consent}) async {
    if (!consent) {
      throw const CloudflareApiException(400, 'AI_CONSENT_REQUIRED');
    }
    return (await client.json(
          'POST',
          '/api/ai/guide',
          data: {'question': question, 'consent': consent},
        ))['answer']
        as String;
  }
}

Person personFromCloudflare(Map<String, dynamic> r) => Person(
  id: r['id'],
  name: r['name'],
  kana: r['kana'] ?? '',
  relationship: r['relationship'] ?? '',
  kind: PersonKind.values.byName(r['kind'] ?? 'family'),
  lifeStatus: LifeStatus.values.byName(r['lifeStatus'] ?? 'unknown'),
  nickname: r['nickname'] ?? '',
  born: r['born'] ?? '',
  died: r['died'] ?? '',
  posthumousName: r['posthumousName'] ?? '',
  religion: r['religion'] ?? '',
  lastMet: r['lastMet'] ?? '',
  howToAddress: r['howToAddress'] ?? '',
  notes: r['notes'] ?? '',
  phone: r['phone'] ?? '',
  email: r['email'] ?? '',
  address: r['address'] ?? '',
  initials: r['initials'] ?? '',
  placeIds: List<String>.from(r['placeIds'] ?? []),
  consentConfirmed: r['consentConfirmed'] ?? false,
  version: r['version'] ?? 1,
  deceasedVersion: r['deceasedVersion'],
);
Map<String, dynamic> personToCloudflare(Person p) => {
  'id': p.id,
  'name': p.name,
  'kana': p.kana,
  'relationship': p.relationship,
  'kind': p.kind.name,
  'lifeStatus': p.lifeStatus.name,
  'nickname': p.nickname,
  'born': p.born,
  'died': p.died,
  'posthumousName': p.posthumousName,
  'religion': p.religion,
  'lastMet': p.lastMet,
  'howToAddress': p.howToAddress,
  'notes': p.notes,
  'phone': p.phone,
  'email': p.email,
  'address': p.address,
  'initials': p.initials,
  'placeIds': p.placeIds,
  'consentConfirmed': p.consentConfirmed,
  'version': p.version,
  'deceasedVersion': p.deceasedVersion,
};
MemorialEvent eventFromCloudflare(Map<String, dynamic> r) => MemorialEvent(
  id: r['id'],
  title: r['title'],
  type: r['type'],
  subjectPersonId: r['subjectPersonId'] ?? '',
  status: EventStatus.values.byName(r['status'] ?? 'planned'),
  date: r['date'] == null ? null : DateTime.parse(r['date']),
  placeId: r['placeId'],
  host: r['host'] ?? '',
  notes: r['notes'] ?? '',
  nextMemo: r['nextMemo'] ?? '',
  expenses: (r['expenses'] as List? ?? [])
      .map(
        (e) => Expense(
          label: e['label'],
          amount: e['amount'],
          payer: e['payer'] ?? '',
        ),
      )
      .toList(),
  participants: (r['participants'] as List? ?? [])
      .map(
        (e) => EventParticipant(
          name: e['name'],
          relationshipAtTime: e['relationshipAtTime'] ?? '',
          attendance: e['attendance'],
        ),
      )
      .toList(),
  notificationDays: List<int>.from(r['notificationDays'] ?? [30, 7]),
  isCandidate: r['isCandidate'] ?? false,
  version: r['version'] ?? 1,
);
Map<String, dynamic> eventToCloudflare(MemorialEvent e) => {
  'id': e.id,
  'title': e.title,
  'type': e.type,
  'subjectPersonId': e.subjectPersonId,
  'status': e.status.name,
  'date': e.date?.toIso8601String(),
  'placeId': e.placeId,
  'host': e.host,
  'notes': e.notes,
  'nextMemo': e.nextMemo,
  'expenses': e.expenses
      .map((x) => {'label': x.label, 'amount': x.amount, 'payer': x.payer})
      .toList(),
  'participants': e.participants
      .map(
        (x) => {
          'name': x.name,
          'relationshipAtTime': x.relationshipAtTime,
          'attendance': x.attendance,
        },
      )
      .toList(),
  'notificationDays': e.notificationDays,
  'isCandidate': e.isCandidate,
  'version': e.version,
};
FamilyAttachment attachmentFromCloudflare(Map<String, dynamic> r) =>
    FamilyAttachment(
      id: r['id'],
      targetType: AttachmentTargetType.values.byName(r['targetType']),
      targetId: r['targetId'],
      storagePath: r['storagePath'],
      mimeType: r['mimeType'],
      byteSize: r['byteSize'],
      width: r['width'],
      height: r['height'],
      sha256: r['sha256'],
      version: r['version'] ?? 1,
      caption: r['caption'] ?? '',
    );
