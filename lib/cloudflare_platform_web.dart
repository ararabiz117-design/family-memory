import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

http.Client createCloudflareHttpClient() =>
    BrowserClient()..withCredentials = true;
// Web sessions stay in the API's Secure HttpOnly cookie, never JS storage.
Future<String?> readSessionToken() async => null;
Future<void> saveSessionToken(String? value) async {}
Future<String?> readPendingInvite() async =>
    web.window.sessionStorage.getItem('cf_pending_invite');
Future<void> savePendingInvite(String? value) async {
  if (value == null) {
    web.window.sessionStorage.removeItem('cf_pending_invite');
  } else {
    web.window.sessionStorage.setItem('cf_pending_invite', value);
  }
}

Future<String?> readLoginVerifier() async =>
    web.window.sessionStorage.getItem('cf_verifier');
Future<void> saveLoginVerifier(String? value) async {
  if (value == null) {
    web.window.sessionStorage.removeItem('cf_verifier');
  } else {
    web.window.sessionStorage.setItem('cf_verifier', value);
  }
}

void clearLoginCallbackUrl() {
  final uri = Uri.base;
  final query = Map<String, String>.from(uri.queryParameters)
    ..remove('login_ticket')
    ..remove('error');
  web.window.history.replaceState(
    null,
    '',
    uri
        .replace(queryParameters: query.isEmpty ? null : query, fragment: '')
        .toString(),
  );
}
