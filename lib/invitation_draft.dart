import 'models.dart';

/// Small, deliberately conservative parser for Japanese memorial invitations.
/// OCR is only a suggestion: no field is persisted until the user reviews it.
class InvitationDraft {
  const InvitationDraft({this.date, this.time, this.place});

  final DateTime? date;
  final String? time;
  final String? place;

  String get notes {
    final values = <String>[];
    if (time != null) values.add('招待状の時刻候補：$time（要確認）');
    if (place != null) values.add('招待状の会場候補：$place（要確認）');
    return values.join('\n');
  }
}

InvitationDraft parseInvitationText(String text) {
  final normalized = _normalizeDigits(text).replaceAll(' ', '');
  final date = _extractDate(normalized);
  final timeMatch = RegExp(
    r'(?:午前|午後)?\s*([01]?\d|2[0-3])\s*時(?:\s*([0-5]?\d)\s*分|半)?',
  ).firstMatch(normalized);
  String? time;
  if (timeMatch != null) {
    var hour = int.tryParse(timeMatch.group(1)!);
    final meridiem = timeMatch.group(0)!.startsWith('午後');
    final am = timeMatch.group(0)!.startsWith('午前');
    if (meridiem && hour != null && hour < 12) hour += 12;
    if (am && hour == 12) hour = 0;
    final minute = timeMatch.group(0)!.contains('半')
        ? 30
        : int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
    if (hour != null) {
      time =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }
  }

  String? place;
  for (final line in text.split(RegExp(r'[\r\n]'))) {
    final trimmed = line.trim();
    if (trimmed.length < 3 || trimmed.length > 80) continue;
    final label = RegExp(
      r'^(?:会場|場所|於|会場住所|寺院)\s*[:：]?\s*',
    ).firstMatch(trimmed);
    if (label != null) {
      final candidate = trimmed.substring(label.end).trim();
      if (candidate.isNotEmpty) {
        place = candidate;
        break;
      }
    }
  }
  return InvitationDraft(date: date, time: time, place: place);
}

DateTime? _extractDate(String text) {
  final era = RegExp(
    r'令和\s*(\d{1,2})年\s*(\d{1,2})月\s*(\d{1,2})日?',
  ).firstMatch(text);
  if (era != null) {
    return _safeDate(
      2018 + int.parse(era.group(1)!),
      int.parse(era.group(2)!),
      int.parse(era.group(3)!),
    );
  }
  final japanese = RegExp(
    r'(20\d{2})年\s*(\d{1,2})月\s*(\d{1,2})日?',
  ).firstMatch(text);
  final slash = RegExp(
    r'(20\d{2})[./年-](\d{1,2})[./月-](\d{1,2})日?',
  ).firstMatch(text);
  final match = japanese ?? slash;
  if (match == null) return null;
  return _safeDate(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

DateTime? _safeDate(int year, int month, int day) {
  if (year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

String _normalizeDigits(String text) {
  const full = '０１２３４５６７８９';
  var result = text;
  for (var i = 0; i < full.length; i++) {
    result = result.replaceAll(full[i], '$i');
  }
  return result;
}

int memorialEventsWithinDays(
  Iterable<MemorialEvent> events,
  DateTime now, {
  int days = 7,
}) {
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(Duration(days: days));
  return events.where((event) {
    if (event.isCandidate || event.status != EventStatus.planned) return false;
    final date = event.date;
    if (date == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }).length;
}
