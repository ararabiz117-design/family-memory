import 'package:family_memory/auth_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Google OAuth redirect', () {
    test('Webは現在のoriginへ戻る', () {
      expect(
        googleOAuthRedirect(
          isWeb: true,
          currentUri: Uri.parse('http://127.0.0.1:8764/invite?token=dummy'),
        ),
        'http://127.0.0.1:8764/',
      );
    });

    test('Android/iPhoneはアプリ専用schemeへ戻る', () {
      expect(
        googleOAuthRedirect(
          isWeb: false,
          currentUri: Uri.parse('https://example.invalid/'),
        ),
        'familymemory://login-callback/',
      );
    });
  });
}
