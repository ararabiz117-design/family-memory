/// Candidate dates are only prompts for family confirmation.  They never
/// represent a religious or regional determination.
class MemorialCandidateSpec {
  const MemorialCandidateSpec({
    required this.title,
    required this.type,
    required this.date,
  });

  final String title;
  final String type;
  final DateTime date;
}

/// Builds the standard, editable candidate set from a date of death.
///
/// New-bon timing is deliberately omitted: it varies by region and family.
List<MemorialCandidateSpec> memorialCandidatesFor(
  String personName,
  DateTime deathDate,
) {
  final memorialYears = <(int, String)>[
    (1, '一周忌'),
    (3, '三回忌'),
    (7, '七回忌'),
    (13, '十三回忌'),
    (17, '十七回忌'),
    (23, '二十三回忌'),
    (27, '二十七回忌'),
    (33, '三十三回忌'),
    (37, '三十七回忌'),
    (50, '五十回忌'),
  ];

  return [
    MemorialCandidateSpec(
      title: '$personNameの四十九日候補',
      type: '四十九日',
      date: deathDate.add(const Duration(days: 49)),
    ),
    ...memorialYears.map(
      (entry) => MemorialCandidateSpec(
        title: '$personNameの${entry.$2}候補',
        type: '法事・法要',
        // The first memorial is the first death anniversary; later Japanese
        // nth memorials are held n - 1 years after the death.
        date: DateTime(
          deathDate.year + (entry.$1 == 1 ? 1 : entry.$1 - 1),
          deathDate.month,
          deathDate.day,
        ),
      ),
    ),
  ];
}
