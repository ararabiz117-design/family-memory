import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'attachment_image_processor.dart';
import 'attachment_models.dart';
import 'models.dart';
import 'memorial_candidates.dart';
import 'repository.dart';

class NoActiveFamilyException implements Exception {
  const NoActiveFamilyException();
}

class SupabaseFamilyRepository extends FamilyRepository {
  SupabaseFamilyRepository._(
    this.client,
    this.familyId,
    this._familyName,
    this._currentRole,
  );

  final SupabaseClient client;
  final String familyId;
  final String _familyName;
  final String _currentRole;

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
  String get familyName => _familyName;
  @override
  String get currentRole => _currentRole;
  @override
  String get currentUserId => client.auth.currentUser?.id ?? '';

  static Future<SupabaseFamilyRepository> connect(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');
    final rows = await client
        .from('family_members')
        .select('family_id,role')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .limit(1);
    if (rows.isEmpty) throw const NoActiveFamilyException();
    final member = Map<String, dynamic>.from(rows.first);
    final familyId = member['family_id'] as String;
    final family = await client
        .from('families')
        .select('name')
        .eq('id', familyId)
        .single();
    final repository = SupabaseFamilyRepository._(
      client,
      familyId,
      family['name'] as String,
      member['role'] as String,
    );
    await repository.reload();
    return repository;
  }

  Future<void> reload() async {
    final results = await Future.wait([
      client
          .from('people')
          .select()
          .eq('family_id', familyId)
          .order('created_at'),
      client.from('deceased_profiles').select().eq('family_id', familyId),
      client
          .from('places')
          .select()
          .eq('family_id', familyId)
          .order('created_at'),
      client.from('person_places').select().eq('family_id', familyId),
      client.from('person_relationships').select().eq('family_id', familyId),
      client
          .from('events')
          .select()
          .eq('family_id', familyId)
          .order('event_date'),
      client.from('event_people').select().eq('family_id', familyId),
      client.from('event_attendees').select().eq('family_id', familyId),
      client.from('event_expenses').select().eq('family_id', familyId),
      client.from('reminders').select().eq('family_id', familyId),
      client
          .from('family_members')
          .select('user_id,role,status')
          .eq('family_id', familyId),
      client
          .from('user_family_preferences')
          .select('focus_person_id')
          .eq('family_id', familyId)
          .maybeSingle(),
      client
          .from('family_invitations')
          .select('id,role,status,expires_at,accepted_display_name_snapshot')
          .eq('family_id', familyId)
          .inFilter('status', ['active', 'accepted'])
          .order('created_at', ascending: false),
      client
          .from('attachments')
          .select()
          .eq('family_id', familyId)
          .order('created_at', ascending: false),
      client
          .from('activity_logs')
          .select('actor_user_id,action,entity_type,changed_fields,occurred_at')
          .eq('family_id', familyId)
          .order('occurred_at', ascending: false)
          .limit(100),
    ]);

    final personRows = _rows(results[0]);
    final deceasedRows = _rows(results[1]);
    final placeRows = _rows(results[2]);
    final personPlaceRows = _rows(results[3]);
    final relationshipRows = _rows(results[4]);
    final eventRows = _rows(results[5]);
    final eventPeopleRows = _rows(results[6]);
    final attendeeRows = _rows(results[7]);
    final expenseRows = _rows(results[8]);
    final reminderRows = _rows(results[9]);
    final memberRows = _rows(results[10]);
    final preference = results[11] == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(results[11] as Map);
    final invitationRows = _rows(results[12]);
    final attachmentRows = _rows(results[13]);
    final activityRows = _rows(results[14]);

    final focusId = preference['focus_person_id'] as String?;
    final deceasedByPerson = {
      for (final row in deceasedRows) row['person_id'] as String: row,
    };
    final placesByPerson = <String, List<String>>{};
    for (final row in personPlaceRows) {
      placesByPerson
          .putIfAbsent(row['person_id'] as String, () => [])
          .add(row['place_id'] as String);
    }

    people
      ..clear()
      ..addAll(
        personRows.map((row) {
          final id = row['id'] as String;
          final deceased = deceasedByPerson[id];
          final nicknames =
              (row['nicknames'] as List?)?.cast<String>() ?? const [];
          return Person(
            id: id,
            name: row['display_name'] as String,
            kana: row['name_kana'] as String? ?? '',
            relationship: _relationshipLabel(id, focusId, relationshipRows),
            kind: row['kind'] == 'family_relative'
                ? PersonKind.family
                : PersonKind.contact,
            lifeStatus: _lifeStatus(row['life_status'] as String?),
            nickname: nicknames.isEmpty ? '' : nicknames.first,
            born: _partialDate(
              row['birth_date'] as String?,
              row['birth_date_precision'] as String?,
            ),
            died: _partialDate(
              row['death_date'] as String?,
              row['death_date_precision'] as String?,
            ),
            posthumousName: deceased?['posthumous_name'] as String? ?? '',
            religion: [
              deceased?['religious_form'],
              deceased?['denomination'],
            ].whereType<String>().where((value) => value.isNotEmpty).join('・'),
            lastMet: row['contact_note'] as String? ?? '',
            howToAddress: row['how_to_recognize'] as String? ?? '',
            notes: row['notes'] as String? ?? '',
            phone: row['phone'] as String? ?? '',
            email: row['email'] as String? ?? '',
            address: row['contact_address'] as String? ?? '',
            initials: String.fromCharCode(
              (row['display_name'] as String).runes.first,
            ),
            placeIds: placesByPerson[id] ?? const [],
            consentConfirmed:
                row['living_person_consent_confirmed'] as bool? ?? false,
            version: row['version'] as int? ?? 1,
            deceasedVersion: deceased?['version'] as int?,
          );
        }),
      );
    relationships
      ..clear()
      ..addAll(
        relationshipRows.map(
          (row) => PersonRelationship(
            id: row['id'] as String,
            fromPersonId: row['from_person_id'] as String,
            toPersonId: row['to_person_id'] as String,
            kind: _relationshipKind(row['kind'] as String?),
            label: row['custom_label'] as String? ?? '',
            notes: row['notes'] as String? ?? '',
            version: row['version'] as int? ?? 1,
          ),
        ),
      );
    centerPersonId = focusId != null && people.any((p) => p.id == focusId)
        ? focusId
        : (people.where((p) => p.kind == PersonKind.family).firstOrNull?.id ??
              '');

    places
      ..clear()
      ..addAll(
        placeRows.map(
          (row) => MemoryPlace(
            id: row['id'] as String,
            name: row['name'] as String,
            type: _placeKind(row['kind'] as String?),
            address: row['address'] as String? ?? '',
            section: row['block_plot'] as String? ?? '',
            landmark:
                row['landmark'] as String? ?? row['notes'] as String? ?? '',
            directions: row['directions'] as String? ?? '',
            mapUrl: row['external_map_url'] as String? ?? '',
            version: row['version'] as int? ?? 1,
          ),
        ),
      );

    final subjectByEvent = <String, String>{};
    for (final row in eventPeopleRows) {
      subjectByEvent.putIfAbsent(
        row['event_id'] as String,
        () => row['person_id'] as String,
      );
    }
    events
      ..clear()
      ..addAll(
        eventRows.where((row) => subjectByEvent.containsKey(row['id'])).map((
          row,
        ) {
          final id = row['id'] as String;
          final expenses = expenseRows
              .where((item) => item['event_id'] == id)
              .map(
                (item) => Expense(
                  label: _expenseKind(item['kind'] as String?),
                  amount: item['amount_yen'] as int?,
                  payer: item['recipient_label'] as String? ?? '',
                ),
              )
              .toList();
          final attendees = attendeeRows
              .where((item) => item['event_id'] == id)
              .map(
                (item) => EventParticipant(
                  name: item['display_name_snapshot'] as String,
                  relationshipAtTime:
                      item['relationship_snapshot'] as String? ?? '',
                  attendance: _attendance(item['status'] as String?),
                ),
              )
              .toList();
          final notificationDays = reminderRows
              .where(
                (item) => item['event_id'] == id && item['enabled'] == true,
              )
              .map((item) => item['notify_offset_days'] as int)
              .toList();
          return MemorialEvent(
            id: id,
            title: row['title'] as String,
            type: _eventKind(row['kind'] as String?),
            subjectPersonId: subjectByEvent[id]!,
            status: _eventStatus(row['status'] as String?),
            date: DateTime.tryParse(row['event_date'] as String? ?? ''),
            placeId: row['place_id'] as String?,
            host: row['officiant_or_host'] as String? ?? '',
            notes: row['summary'] as String? ?? row['notes'] as String? ?? '',
            nextMemo: row['lessons'] as String? ?? '',
            expenses: expenses,
            participants: attendees,
            notificationDays: notificationDays.isEmpty
                ? const [30, 7]
                : notificationDays,
            isCandidate: row['is_candidate'] as bool? ?? false,
            version: row['version'] as int? ?? 1,
          );
        }),
      );

    final profileByUser = <String, String>{};
    for (final member in memberRows) {
      final userId = member['user_id'] as String;
      final profile = await client
          .from('profiles')
          .select('display_name')
          .eq('id', userId)
          .maybeSingle();
      profileByUser[userId] = profile?['display_name'] as String? ?? '家族メンバー';
    }
    familyUsers
      ..clear()
      ..addAll(
        memberRows.map(
          (row) => FamilyUser(
            id: row['user_id'] as String,
            name: profileByUser[row['user_id']] ?? '家族メンバー',
            role: row['role'] as String,
            state: row['status'] == 'active' ? '参加中' : '承認待ち',
          ),
        ),
      );
    invitations
      ..clear()
      ..addAll(
        invitationRows.map(
          (row) => FamilyInvitation(
            id: row['id'] as String,
            role: row['role'] as String,
            status: row['status'] as String,
            expiresAt: DateTime.parse(row['expires_at'] as String),
            acceptedDisplayName:
                row['accepted_display_name_snapshot'] as String? ?? '',
          ),
        ),
      );
    attachments
      ..clear()
      ..addAll(attachmentRows.map(_attachmentFromRow));
    activityEntries
      ..clear()
      ..addAll(
        activityRows.map(
          (row) => ActivityEntry(
            actorName: profileByUser[row['actor_user_id']] ?? '家族メンバー',
            action: row['action'] as String,
            entityType: row['entity_type'] as String,
            occurredAt: DateTime.parse(row['occurred_at'] as String).toLocal(),
            changedFields:
                (row['changed_fields'] as List?)?.cast<String>() ?? const [],
          ),
        ),
      );
    viewerMode = _currentRole == 'viewer';
    notifyListeners();
  }

  @override
  Person person(String id) => people.firstWhere((item) => item.id == id);

  @override
  MemoryPlace? place(String? id) {
    if (id == null) return null;
    return places.where((item) => item.id == id).firstOrNull;
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
    client.from('user_family_preferences').upsert({
      'family_id': familyId,
      'user_id': client.auth.currentUser!.id,
      'focus_person_id': id,
    });
  }

  @override
  void setViewerMode(bool value) {
    viewerMode = _currentRole == 'viewer' ? true : value;
    notifyListeners();
  }

  @override
  Future<void> savePerson(Person value) async {
    if (viewerMode) throw const PostgrestException(message: 'FORBIDDEN');
    final exists = people.any((item) => item.id == value.id);
    final birth = _partialDateToDb(value.born);
    final death = _partialDateToDb(value.died);
    final response = await client.rpc(
      'save_person_v2',
      params: {
        'p_payload': {
          'id': exists ? value.id : null,
          'family_id': familyId,
          'expected_version': exists ? value.version : null,
          'deceased_expected_version': value.deceasedVersion,
          'display_name': value.name,
          'name_kana': value.kana,
          'kind': value.kind == PersonKind.family
              ? 'family_relative'
              : 'related_person',
          'life_status': value.lifeStatus.name,
          'nicknames': value.nickname.isEmpty ? <String>[] : [value.nickname],
          'birth_date': birth.$1,
          'birth_precision': birth.$2,
          'death_date': death.$1,
          'death_precision': death.$2,
          'posthumous_name': value.posthumousName,
          'denomination': value.religion,
          'relationship_label': value.relationship,
          'focus_person_id': centerPersonId.isEmpty ? null : centerPersonId,
          'last_met': value.lastMet,
          'how_to_address': value.howToAddress,
          'notes': value.notes,
          'phone': value.phone,
          'email': value.email,
          'contact_address': value.address,
          'living_person_consent_confirmed': value.consentConfirmed,
        },
      },
    );
    await reload();
    if (value.lifeStatus == LifeStatus.deceased && death.$1 != null) {
      final personId = (response as Map)['id'] as String;
      await _ensureMemorialCandidates(
        personId: personId,
        personName: value.name,
        deathDate: DateTime.parse(death.$1!),
      );
      await reload();
    }
  }

  Future<void> _ensureMemorialCandidates({
    required String personId,
    required String personName,
    required DateTime deathDate,
  }) async {
    final existingDates = events
        .where(
          (event) => event.subjectPersonId == personId && event.isCandidate,
        )
        .map((event) => event.date?.toIso8601String().split('T').first)
        .whereType<String>()
        .toSet();
    for (final candidate in memorialCandidatesFor(personName, deathDate)) {
      final date = candidate.date.toIso8601String().split('T').first;
      if (existingDates.contains(date)) continue;
      await client.rpc(
        'save_event_v1',
        params: {
          'p_payload': {
            'family_id': familyId,
            'title': candidate.title,
            'kind': _eventKindToDb(candidate.type),
            'status': EventStatus.planned.name,
            'event_date': date,
            'subject_person_id': personId,
            'is_candidate': true,
            'notification_days': <int>[],
            'attendees': <Map<String, Object?>>[],
            'expenses': <Map<String, Object?>>[],
          },
        },
      );
    }
  }

  @override
  Future<void> savePlace(MemoryPlace value, {String? relatedPersonId}) async {
    if (viewerMode) throw const PostgrestException(message: 'FORBIDDEN');
    final exists = places.any((item) => item.id == value.id);
    await client.rpc(
      'save_place_v1',
      params: {
        'p_payload': {
          'id': exists ? value.id : null,
          'family_id': familyId,
          'expected_version': exists ? value.version : null,
          'kind': _placeKindToDb(value.type),
          'name': value.name,
          'address': value.address,
          'block_plot': value.section,
          'landmark': value.landmark,
          'directions': value.directions,
          'external_map_url': value.mapUrl,
          'related_person_id': relatedPersonId,
          'person_place_kind': _personPlaceKindToDb(value.type),
        },
      },
    );
    await reload();
  }

  @override
  Future<void> saveRelationship(PersonRelationship value) async {
    if (viewerMode) throw const PostgrestException(message: 'FORBIDDEN');
    final exists = relationships.any((item) => item.id == value.id);
    await client.rpc(
      'save_person_relationship_v1',
      params: {
        'p_payload': {
          'family_id': familyId,
          'id': exists ? value.id : null,
          'expected_version': exists ? value.version : null,
          'from_person_id': value.fromPersonId,
          'to_person_id': value.toPersonId,
          'kind': _relationshipKindToDb(value.kind),
          'custom_label': value.label,
          'notes': value.notes,
        },
      },
    );
    await reload();
  }

  @override
  Future<void> saveEvent(MemorialEvent value) async {
    await _saveEvent(value, forceInsert: false);
  }

  @override
  Future<String> saveNewEvent(MemorialEvent value) =>
      _saveEvent(value, forceInsert: true);

  Future<String> _saveEvent(
    MemorialEvent value, {
    required bool forceInsert,
  }) async {
    if (viewerMode) throw const PostgrestException(message: 'FORBIDDEN');
    final exists = events.any((item) => item.id == value.id);
    final inserting = forceInsert || !exists;
    final response = await client.rpc(
      'save_event_v1',
      params: {
        'p_payload': {
          'id': inserting ? null : value.id,
          'family_id': familyId,
          'expected_version': inserting ? null : value.version,
          'title': value.title,
          'kind': _eventKindToDb(value.type),
          'status': value.status.name,
          'event_date': value.date?.toIso8601String().split('T').first,
          'place_id': value.placeId,
          'subject_person_id': value.subjectPersonId,
          'officiant_or_host': value.host,
          'summary': value.notes,
          'lessons': value.nextMemo,
          'is_candidate': value.isCandidate,
          'notification_days': value.notificationDays,
          'attendees': value.participants
              .map(
                (item) => {
                  'display_name': item.name,
                  'relationship': item.relationshipAtTime,
                  'status': _attendanceToDb(item.attendance),
                },
              )
              .toList(),
          'expenses': value.expenses
              .map(
                (item) => {
                  'kind': _expenseKindToDb(item.label),
                  'amount_yen': item.amount,
                  'payer': item.payer,
                },
              )
              .toList(),
        },
      },
    );
    await reload();
    return inserting ? (response as Map)['id'] as String : value.id;
  }

  @override
  Future<MemorialEvent> duplicateSafely(MemorialEvent source) async {
    final copy = MemorialEvent(
      id: 'new',
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
    await saveEvent(copy);
    return events.firstWhere((item) => item.title == copy.title);
  }

  @override
  Future<void> confirmCandidate(MemorialEvent event) async {
    event.isCandidate = false;
    event.status = EventStatus.planned;
    await saveEvent(event);
  }

  @override
  Future<void> dismissCandidate(MemorialEvent event) async {
    await client.rpc(
      'soft_delete_event_v1',
      params: {
        'p_family_id': familyId,
        'p_event_id': event.id,
        'p_expected_version': event.version,
      },
    );
    await reload();
  }

  @override
  Future<InvitationSecret> createInvitation(String email, String role) async {
    if (_currentRole != 'owner') {
      throw const PostgrestException(message: 'FORBIDDEN');
    }
    final response = await client.functions.invoke(
      'create-family-invite',
      body: {
        'familyId': familyId,
        'invitedEmail': email.trim().toLowerCase(),
        'role': role,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final code = data['shortCode'] as String?;
    final url = data['inviteUrl'] as String?;
    if (code == null || url == null) {
      throw const PostgrestException(message: 'BACKEND_UNAVAILABLE');
    }
    await reload();
    return InvitationSecret(shortCode: code, inviteUrl: url);
  }

  @override
  Future<void> approveInvitation(String invitationId) async {
    await client.rpc(
      'approve_family_member',
      params: {'p_invitation_id': invitationId},
    );
    await reload();
  }

  @override
  Future<void> revokeInvitation(String invitationId) async {
    await client.rpc(
      'revoke_family_invitation',
      params: {'p_invitation_id': invitationId},
    );
    await reload();
  }

  @override
  Future<void> changeMemberRole(String userId, String role) async {
    await client.rpc(
      'change_family_member_role',
      params: {'p_family_id': familyId, 'p_user_id': userId, 'p_role': role},
    );
    await reload();
  }

  @override
  List<FamilyAttachment> attachmentsFor(
    AttachmentTargetType targetType,
    String targetId,
  ) => attachments
      .where(
        (item) => item.targetType == targetType && item.targetId == targetId,
      )
      .toList(growable: false);

  @override
  Future<FamilyAttachment> addImageAttachment({
    required AttachmentTargetType targetType,
    required String targetId,
    required Uint8List sourceBytes,
    String caption = '',
  }) async {
    if (viewerMode) throw const PostgrestException(message: 'FORBIDDEN');
    if (!_targetExists(targetType, targetId)) {
      throw const PostgrestException(message: 'INVALID_ATTACHMENT_TARGET');
    }
    final cleanCaption = caption.trim();
    if (cleanCaption.length > 300) {
      throw const AttachmentImageException(
        'CAPTION_TOO_LONG',
        '写真の説明は300文字以内にしてください。',
      );
    }

    // CPU-heavy decode/re-encode is moved off the UI isolate on native builds.
    final sanitized = await compute(sanitizeAttachmentImage, sourceBytes);
    final objectId = _secureUuidV4();
    final path =
        '$familyId/${targetType.storageSegment}/$targetId/'
        '$objectId.${sanitized.extension}';

    // upsert=false is essential: attachment object paths are immutable.
    await client.storage
        .from('family-private')
        .uploadBinary(
          path,
          sanitized.bytes,
          fileOptions: FileOptions(
            contentType: sanitized.mimeType,
            cacheControl: 'private, max-age=300',
            upsert: false,
          ),
        );

    final response = await client.rpc(
      'create_attachment_v1',
      params: {
        'p_payload': {
          'family_id': familyId,
          'target_type': targetType.storageSegment,
          'target_id': targetId,
          'storage_path': path,
          'mime_type': sanitized.mimeType,
          'byte_size': sanitized.byteSize,
          'width': sanitized.width,
          'height': sanitized.height,
          'sha256': sanitized.sha256Hex,
          'caption': cleanCaption,
        },
      },
    );
    final created = Map<String, dynamic>.from(response as Map);
    await reload();
    return attachments.firstWhere(
      (item) => item.id == created['id'] || item.storagePath == path,
    );
  }

  @override
  Future<String> createAttachmentSignedUrl(String attachmentId) async {
    final attachment = attachments
        .where((item) => item.id == attachmentId)
        .firstOrNull;
    if (attachment == null) {
      throw const PostgrestException(message: 'ATTACHMENT_NOT_FOUND');
    }
    // Do not accept a raw caller-supplied path. Only a currently visible DB
    // record may be exchanged for a short-lived URL.
    return client.storage
        .from('family-private')
        .createSignedUrl(attachment.storagePath, 300);
  }

  @override
  Future<void> softDeleteAttachment(FamilyAttachment attachment) async {
    if (viewerMode) throw const PostgrestException(message: 'FORBIDDEN');
    if (!attachments.any((item) => item.id == attachment.id)) {
      throw const PostgrestException(message: 'ATTACHMENT_NOT_FOUND');
    }
    await client.rpc(
      'soft_delete_attachment_v1',
      params: {
        'p_family_id': familyId,
        'p_attachment_id': attachment.id,
        'p_expected_version': attachment.version,
      },
    );
    // Storage is intentionally not physically deleted by the client. The
    // audited cleanup worker purges soft-deleted objects after the retention
    // window.
    await reload();
  }

  @override
  Future<FamilyExport> exportFamilyData(FamilyExportFormat format) async {
    if (_currentRole != 'owner' || viewerMode) {
      throw const PostgrestException(message: 'FORBIDDEN');
    }
    final wireFormat = switch (format) {
      FamilyExportFormat.json => 'json_v1',
      FamilyExportFormat.csv => 'csv_v1',
    };
    final response = await client.functions.invoke(
      'export-family-data',
      body: {'familyId': familyId, 'format': wireFormat},
    );
    final data = response.data;
    final bytes = switch (data) {
      Uint8List value => value,
      String value => Uint8List.fromList(utf8.encode(value)),
      _ => Uint8List.fromList(utf8.encode(jsonEncode(data))),
    };
    final extension = format == FamilyExportFormat.json ? 'json' : 'csv';
    final day = DateTime.now();
    final stamp =
        '${day.year.toString().padLeft(4, '0')}'
        '${day.month.toString().padLeft(2, '0')}'
        '${day.day.toString().padLeft(2, '0')}';
    return FamilyExport(
      bytes: bytes,
      fileName: 'family-memory-$stamp',
      extension: extension,
      mimeType: format == FamilyExportFormat.json
          ? 'application/json'
          : 'text/csv',
    );
  }

  @override
  Future<void> sendDeletionVerificationCode() async {
    final email = client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw const AuthException('AUTH_REQUIRED');
    }
    await client.auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  @override
  Future<void> verifyDeletionVerificationCode(String code) async {
    final email = client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw const AuthException('AUTH_REQUIRED');
    }
    final normalized = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(normalized)) {
      throw const FormatException('認証コードは6桁の数字で入力してください。');
    }
    await client.auth.verifyOTP(
      email: email,
      token: normalized,
      type: OtpType.email,
    );
  }

  @override
  Future<void> requestAccountDeletion() async {
    await client.functions.invoke(
      'request-account-deletion',
      body: {'confirmation': 'DELETE_MY_ACCOUNT'},
    );
    await client.auth.signOut();
  }

  @override
  Future<void> requestFamilyDeletion() async {
    if (_currentRole != 'owner' || viewerMode) {
      throw const PostgrestException(message: 'FORBIDDEN');
    }
    await client.functions.invoke(
      'request-family-deletion',
      body: {'familyId': familyId, 'confirmation': 'DELETE_FAMILY'},
    );
    await client.auth.signOut();
  }

  @override
  Future<void> signOut() => client.auth.signOut();

  bool _targetExists(AttachmentTargetType type, String id) => switch (type) {
    AttachmentTargetType.person => people.any((item) => item.id == id),
    AttachmentTargetType.place => places.any((item) => item.id == id),
    AttachmentTargetType.event => events.any((item) => item.id == id),
  };
}

FamilyAttachment _attachmentFromRow(Map<String, dynamic> row) {
  final (targetType, targetId) = switch (row) {
    {'person_id': final String id} => (AttachmentTargetType.person, id),
    {'place_id': final String id} => (AttachmentTargetType.place, id),
    {'event_id': final String id} => (AttachmentTargetType.event, id),
    _ => throw const FormatException('Invalid attachment target'),
  };
  return FamilyAttachment(
    id: row['id'] as String,
    targetType: targetType,
    targetId: targetId,
    storagePath: row['storage_path'] as String,
    mimeType: row['mime_type'] as String,
    byteSize: row['byte_size'] as int,
    width: row['width'] as int,
    height: row['height'] as int,
    sha256: row['sha256'] as String,
    caption: row['caption'] as String? ?? '',
    version: row['version'] as int? ?? 1,
  );
}

String _secureUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
  final values = hex.toList(growable: false);
  return '${values.sublist(0, 4).join()}'
      '-${values.sublist(4, 6).join()}'
      '-${values.sublist(6, 8).join()}'
      '-${values.sublist(8, 10).join()}'
      '-${values.sublist(10, 16).join()}';
}

List<Map<String, dynamic>> _rows(Object? value) => (value as List)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

LifeStatus _lifeStatus(String? value) => switch (value) {
  'deceased' => LifeStatus.deceased,
  'unknown' => LifeStatus.unknown,
  _ => LifeStatus.living,
};

EventStatus _eventStatus(String? value) => switch (value) {
  'completed' => EventStatus.completed,
  'cancelled' => EventStatus.cancelled,
  _ => EventStatus.planned,
};

String _partialDate(String? value, String? precision) {
  if (value == null || precision == 'unknown') return '';
  final date = DateTime.tryParse(value);
  if (date == null) return '';
  if (precision == 'year') return '${date.year}年';
  if (precision == 'month') return '${date.year}年${date.month}月';
  return '${date.year}年${date.month}月${date.day}日';
}

String _relationshipLabel(
  String id,
  String? focusId,
  List<Map<String, dynamic>> rows,
) {
  if (id == focusId) return 'あなた';
  for (final row in rows) {
    if ((row['from_person_id'] == focusId && row['to_person_id'] == id) ||
        (row['to_person_id'] == focusId && row['from_person_id'] == id)) {
      final label = row['custom_label'] as String?;
      if (label != null && label.isNotEmpty) return label;
    }
  }
  return '関係を確認';
}

RelationshipKind _relationshipKind(String? value) => switch (value) {
  'parent_child' => RelationshipKind.parentChild,
  'adopted_parent_child' => RelationshipKind.adoptedParentChild,
  'step_parent_child' => RelationshipKind.stepParentChild,
  'spouse' => RelationshipKind.spouse,
  'partner' => RelationshipKind.partner,
  'sibling' => RelationshipKind.sibling,
  'acquaintance' => RelationshipKind.acquaintance,
  'work_related' => RelationshipKind.workRelated,
  'temple_related' => RelationshipKind.templeRelated,
  'other' => RelationshipKind.other,
  _ => RelationshipKind.relativeUnknown,
};

String _relationshipKindToDb(RelationshipKind value) => switch (value) {
  RelationshipKind.parentChild => 'parent_child',
  RelationshipKind.adoptedParentChild => 'adopted_parent_child',
  RelationshipKind.stepParentChild => 'step_parent_child',
  RelationshipKind.spouse => 'spouse',
  RelationshipKind.partner => 'partner',
  RelationshipKind.sibling => 'sibling',
  RelationshipKind.relativeUnknown => 'relative_unknown',
  RelationshipKind.acquaintance => 'acquaintance',
  RelationshipKind.workRelated => 'work_related',
  RelationshipKind.templeRelated => 'temple_related',
  RelationshipKind.other => 'other',
};

(String?, String) _partialDateToDb(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return (null, 'unknown');
  final day = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日$').firstMatch(normalized);
  if (day != null) {
    return (
      '${day.group(1)}-${day.group(2)!.padLeft(2, '0')}-${day.group(3)!.padLeft(2, '0')}',
      'day',
    );
  }
  final month = RegExp(r'^(\d{4})年(\d{1,2})月$').firstMatch(normalized);
  if (month != null) {
    return ('${month.group(1)}-${month.group(2)!.padLeft(2, '0')}-01', 'month');
  }
  final year = RegExp(r'^(\d{4})年$').firstMatch(normalized);
  if (year != null) {
    return ('${year.group(1)}-01-01', 'year');
  }
  throw const FormatException('日付は「2025年」「2025年5月」「2025年5月18日」の形式で入力してください。');
}

String _placeKind(String? value) =>
    const {
      'cemetery': '霊園・墓地',
      'grave_site': '墓所・墓石',
      'temple': '寺院',
      'ossuary': '納骨堂',
      'funeral_hall': '葬儀会場',
      'memorial_venue': '法要会場',
      'restaurant': '会食会場',
      'remains_storage': '遺骨保管場所',
      'altar_memorial_storage': '仏壇・位牌保管場所',
      'hospital_care_facility': '亡くなった場所',
      'home': '自宅',
    }[value] ??
    'その他';

String _placeKindToDb(String value) => switch (value) {
  '亡くなった場所' => 'hospital_care_facility',
  '霊園・墓地' => 'cemetery',
  '墓所・墓石' => 'grave_site',
  '納骨堂' => 'ossuary',
  '仏壇・位牌保管場所' => 'altar_memorial_storage',
  '遺骨保管場所' => 'remains_storage',
  '寺院' => 'temple',
  '葬儀会場' => 'funeral_hall',
  '法要会場' => 'memorial_venue',
  '会食会場' => 'restaurant',
  '自宅' => 'home',
  _ => 'other',
};

String _personPlaceKindToDb(String value) => switch (value) {
  '亡くなった場所' => 'death_place',
  '霊園・墓地' => 'cemetery',
  '墓所・墓石' => 'grave',
  '納骨堂' => 'ossuary',
  '仏壇・位牌保管場所' => 'altar_memorial_tablet',
  '遺骨保管場所' => 'remains',
  '寺院' => 'temple',
  '葬儀会場' => 'funeral_venue',
  '法要会場' => 'memorial_venue',
  _ => 'other',
};

String _eventKind(String? value) =>
    const {
      'funeral': '葬儀',
      'wake': '通夜',
      'cremation': '火葬',
      'forty_ninth_day': '四十九日',
      'memorial_service': '法事・法要',
      'first_bon': '新盆・初盆',
      'grave_visit': '墓参り',
      'chugen': 'お中元・お歳暮',
      'seibo': 'お中元・お歳暮',
      'return_gift': '返礼',
    }[value] ??
    'その他';

String _eventKindToDb(String value) => switch (value) {
  '葬儀' => 'funeral',
  '通夜' => 'wake',
  '火葬' => 'cremation',
  '四十九日' => 'forty_ninth_day',
  '法事・法要' => 'memorial_service',
  '新盆・初盆' => 'first_bon',
  '墓参り' => 'grave_visit',
  'お中元・お歳暮' => 'chugen',
  '返礼' => 'return_gift',
  _ => 'other',
};

String _expenseKind(String? value) =>
    const {
      'offering': 'お布施',
      'priest_transport': '御車代',
      'meal': '会食',
      'return_gift': '返礼品',
      'venue': '会場',
      'flowers': '供花',
      'transport': '交通',
      'lodging': '宿泊',
    }[value] ??
    'その他';

String _expenseKindToDb(String value) => switch (value) {
  'お布施' => 'offering',
  '御車代' => 'priest_transport',
  '会食' => 'meal',
  '返礼品' => 'return_gift',
  '会場' => 'venue',
  '供花' => 'flowers',
  '交通' => 'transport',
  '宿泊' => 'lodging',
  _ => 'other',
};

String? _attendance(String? value) => const {
  'invited': '招待',
  'attending': '出席予定',
  'attended': '出席',
  'absent': '欠席',
  'unanswered': '未回答',
}[value];

String _attendanceToDb(String? value) => switch (value) {
  '招待' => 'invited',
  '出席予定' => 'attending',
  '出席' => 'attended',
  '欠席' => 'absent',
  _ => 'unanswered',
};

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
