import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _storage = FlutterSecureStorage();
http.Client createCloudflareHttpClient() => http.Client();
Future<String?> readSessionToken() => _storage.read(key: 'cf_session');
Future<void> saveSessionToken(String? value) => value == null
    ? _storage.delete(key: 'cf_session')
    : _storage.write(key: 'cf_session', value: value);
Future<String?> readLoginVerifier() => _storage.read(key: 'cf_verifier');
Future<void> saveLoginVerifier(String? value) => value == null
    ? _storage.delete(key: 'cf_verifier')
    : _storage.write(key: 'cf_verifier', value: value);
void clearLoginCallbackUrl() {}
Future<String?> readPendingInvite() => _storage.read(key: 'cf_pending_invite');
Future<void> savePendingInvite(String? value) => value == null
    ? _storage.delete(key: 'cf_pending_invite')
    : _storage.write(key: 'cf_pending_invite', value: value);
