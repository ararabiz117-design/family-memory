enum LifeStatus { living, deceased, unknown }

enum PersonKind { family, contact }

/// A directed relation. For parent/child, [fromPersonId] is the parent and
/// [toPersonId] is the child. Other links are drawn as two-way in the UI.
enum RelationshipKind {
  parentChild,
  adoptedParentChild,
  stepParentChild,
  spouse,
  partner,
  sibling,
  relativeUnknown,
  acquaintance,
  workRelated,
  templeRelated,
  other,
}

class PersonRelationship {
  const PersonRelationship({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.kind,
    this.label = '',
    this.notes = '',
    this.version = 1,
  });
  final String id;
  final String fromPersonId;
  final String toPersonId;
  final RelationshipKind kind;
  final String label;
  final String notes;
  final int version;
}

enum EventStatus { planned, completed, cancelled }

class Person {
  Person({
    required this.id,
    required this.name,
    required this.kana,
    required this.relationship,
    required this.kind,
    this.lifeStatus = LifeStatus.living,
    this.nickname = '',
    this.born = '',
    this.died = '',
    this.posthumousName = '',
    this.religion = '',
    this.lastMet = '',
    this.howToAddress = '',
    this.notes = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.initials = '',
    this.placeIds = const [],
    this.consentConfirmed = false,
    this.version = 1,
    this.deceasedVersion,
  });
  final String id;
  String name;
  String kana;
  String relationship;
  PersonKind kind;
  LifeStatus lifeStatus;
  String nickname;
  String born;
  String died;
  String posthumousName;
  String religion;
  String lastMet;
  String howToAddress;
  String notes;
  String phone;
  String email;
  String address;
  String initials;
  List<String> placeIds;
  bool consentConfirmed;
  int version;
  int? deceasedVersion;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        [
          name,
          kana,
          nickname,
          relationship,
          lastMet,
          notes,
        ].join(' ').toLowerCase().contains(q);
  }
}

class MemoryPlace {
  const MemoryPlace({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    this.section = '',
    this.landmark = '',
    this.directions = '',
    this.mapUrl = '',
    this.version = 1,
  });
  final String id;
  final String name;
  final String type;
  final String address;
  final String section;
  final String landmark;
  final String directions;
  final String mapUrl;
  final int version;
}

class Expense {
  Expense({required this.label, required this.amount, this.payer = ''});
  String label;
  int? amount;
  String payer;
}

class EventParticipant {
  EventParticipant({
    required this.name,
    required this.relationshipAtTime,
    this.attendance,
  });
  String name;
  String relationshipAtTime;
  String? attendance;
}

class MemorialEvent {
  MemorialEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.subjectPersonId,
    required this.status,
    this.date,
    this.placeId,
    this.host = '',
    this.notes = '',
    this.nextMemo = '',
    this.expenses = const [],
    this.participants = const [],
    this.notificationDays = const [30, 7],
    this.isCandidate = false,
    this.version = 1,
  });
  final String id;
  String title;
  String type;
  String subjectPersonId;
  EventStatus status;
  DateTime? date;
  String? placeId;
  String host;
  String notes;
  String nextMemo;
  List<Expense> expenses;
  List<EventParticipant> participants;
  List<int> notificationDays;
  bool isCandidate;
  int version;
  int get total => expenses.fold(0, (sum, item) => sum + (item.amount ?? 0));
}

class FamilyUser {
  const FamilyUser({
    required this.id,
    required this.name,
    required this.role,
    required this.state,
  });
  final String id;
  final String name;
  final String role;
  final String state;
}

class FamilyInvitation {
  const FamilyInvitation({
    required this.id,
    required this.role,
    required this.status,
    required this.expiresAt,
    this.acceptedDisplayName = '',
  });
  final String id;
  final String role;
  final String status;
  final DateTime expiresAt;
  final String acceptedDisplayName;
}

class InvitationSecret {
  const InvitationSecret({required this.shortCode, required this.inviteUrl});
  final String shortCode;
  final String inviteUrl;
}

class ActivityEntry {
  const ActivityEntry({
    required this.actorName,
    required this.action,
    required this.entityType,
    required this.occurredAt,
    this.changedFields = const [],
  });

  final String actorName;
  final String action;
  final String entityType;
  final DateTime occurredAt;
  final List<String> changedFields;
}
