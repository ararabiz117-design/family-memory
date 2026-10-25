import 'package:family_memory/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('既存の介護アプリ用プロジェクトは家族アプリで拒否する', () {
    expect(
      isDisallowedSupabaseProjectUrl(
        'https://mwhtnpdmrwtuqfshbcbq.supabase.co',
      ),
      isTrue,
    );
  });

  test('家族アプリ専用の別プロジェクトは拒否しない', () {
    expect(
      isDisallowedSupabaseProjectUrl(
        'https://family-memory.example.supabase.co',
      ),
      isFalse,
    );
  });
}
