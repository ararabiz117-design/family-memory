import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'cloudflare_platform.dart' as platform;

class CloudflareApiException implements Exception {
  const CloudflareApiException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => code.contains('REAUTH')
      ? 'Googleで本人確認してから、もう一度実行してください。 ($code)'
      : switch (status) {
          401 => 'Googleアカウントで再ログインしてください。',
          403 => 'この操作を行う権限がありません。',
          409 => '別の変更が保存されています。再読み込みしてから編集してください。',
          429 => 'しばらく待ってから、もう一度お試しください。',
          _ => '保存先に接続できませんでした。もう一度お試しください。',
        };
}

bool isValidCloudflareApiUrl(String value, {required bool production}) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  if (uri.host.endsWith('.supabase.co')) return false;
  return uri.scheme == 'https' ||
      (!production &&
          uri.scheme == 'http' &&
          {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host));
}

class CloudflareClient {
  CloudflareClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.onSignedOut,
  }) : httpClient = httpClient ?? platform.createCloudflareHttpClient();
  final String baseUrl;
  final http.Client httpClient;
  VoidCallback? onSignedOut;

  Uri uri(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');

  Future<http.Response> request(
    String method,
    String path, {
    Object? data,
    Uint8List? bytes,
    Map<String, String> headers = const {},
  }) async {
    final token = await platform.readSessionToken();
    final request = http.Request(method, uri(path));
    request.headers.addAll({
      'accept': 'application/json',
      'x-requested-with': 'family-memory',
      if (token != null && !kIsWeb) 'authorization': 'Bearer $token',
      ...headers,
    });
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (data != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(data);
    }
    final response = await http.Response.fromStream(
      await httpClient.send(request).timeout(const Duration(seconds: 30)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String code = 'REQUEST_FAILED';
      try {
        final body = jsonDecode(response.body);
        code = body is Map
            ? (body['code'] ?? body['error'] ?? code).toString()
            : code;
      } catch (_) {}
      throw CloudflareApiException(response.statusCode, code);
    }
    return response;
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, {
    Object? data,
  }) async {
    final response = await request(method, path, data: data);
    if (response.body.isEmpty) return {};
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map,
    );
  }

  Future<void> startGoogleLogin({String? returnTo}) async {
    final verifier = base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    await platform.saveLoginVerifier(verifier);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final response = await json(
      'POST',
      '/api/auth/start',
      data: {
        'returnTo':
            returnTo ??
            (kIsWeb ? '${Uri.base.origin}/' : 'familymemory://login-callback/'),
        'challenge': challenge,
      },
    );
    final url = Uri.parse(response['url'] as String);
    final sameApiOrigin = url.origin == uri('/').origin;
    final localApi =
        {'localhost', '127.0.0.1'}.contains(url.host) && url.scheme == 'http';
    if (!((url.scheme == 'https' &&
            (url.host == 'accounts.google.com' || sameApiOrigin)) ||
        (sameApiOrigin && localApi))) {
      throw const CloudflareApiException(400, 'INVALID_LOGIN_URL');
    }
    if (!await launchUrl(
      url,
      webOnlyWindowName: '_self',
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    )) {
      throw const CloudflareApiException(503, 'LOGIN_UNAVAILABLE');
    }
  }

  Future<void> consumeCallback(Uri uri) async {
    final ticket = uri.queryParameters['login_ticket'];
    if (ticket == null) return;
    final verifier = await platform.readLoginVerifier();
    if (verifier == null) {
      throw const CloudflareApiException(401, 'LOGIN_EXPIRED');
    }
    try {
      final response = await json(
        'POST',
        '/api/auth/exchange',
        data: {
          'ticket': ticket,
          'verifier': verifier,
          'client': kIsWeb ? 'web' : 'native',
        },
      );
      if (!kIsWeb) {
        final token = response['token'] as String?;
        if (token == null || token.isEmpty) {
          throw const CloudflareApiException(401, 'MISSING_SESSION');
        }
        await platform.saveSessionToken(token);
      }
    } finally {
      await platform.saveLoginVerifier(null);
      platform.clearLoginCallbackUrl();
    }
  }

  Future<void> signOut() async {
    try {
      await json('POST', '/api/auth/logout');
    } on CloudflareApiException catch (error) {
      // Account deletion can already have revoked this session.
      if (error.status != 401) rethrow;
    }
    await platform.saveSessionToken(null);
    await platform.saveLoginVerifier(null);
    await platform.savePendingInvite(null);
    onSignedOut?.call();
  }
}
