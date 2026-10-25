import 'package:flutter_test/flutter_test.dart';
import 'package:family_memory/memorial_candidates.dart';

void main() {
  test('法要候補は四十九日と回忌を候補として生成する', () {
    final candidates = memorialCandidatesFor('智', DateTime(2025, 6, 29));

    expect(candidates.first.title, '智の四十九日候補');
    expect(candidates.first.date, DateTime(2025, 8, 17));
    expect(
      candidates.where((candidate) => candidate.title == '智の一周忌候補').single.date,
      DateTime(2026, 6, 29),
    );
    expect(
      candidates.where((candidate) => candidate.title == '智の三回忌候補').single.date,
      DateTime(2027, 6, 29),
    );
  });
}
