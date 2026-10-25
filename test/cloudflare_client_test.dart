import 'dart:convert';
import 'package:family_memory/cloudflare_client.dart';
import 'package:family_memory/cloudflare_family_repository.dart';
import 'package:family_memory/models.dart';
import 'package:family_memory/cloudflare_platform_native.dart' as native;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> fixture({
  List<Map<String, dynamic>> events = const [],
}) => {
  'family': {'id': 'family-a', 'name': 'テスト家', 'role': 'owner'},
  'user': {'id': 'user-a', 'name': '利用者', 'email': 'example@example.invalid'},
  'people': [
    {
      'id': 'person-a',
      'name': 'テスト',
      'kana': '',
      'relationship': '',
      'kind': 'family',
      'lifeStatus': 'living',
      'version': 3,
    },
  ],
  'events': events,
  'centerPersonId': 'person-a',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('empty or missing center falls back to an existing person', () {
    final repo = CloudflareFamilyRepository(
      CloudflareClient(baseUrl: 'https://family.example.com'),
    );
    repo.applyState({...fixture(), 'centerPersonId': ''});
    expect(repo.centerPersonId, 'person-a');
    expect(repo.person(repo.centerPersonId).name, 'テスト');
    repo.applyState({...fixture(), 'centerPersonId': 'removed-person'});
    expect(repo.centerPersonId, 'person-a');
  });

  test(
    'AI request requires explicit consent before sending any network request',
    () async {
      var requests = 0;
      final client = CloudflareClient(
        baseUrl: 'https://family.example.com',
        httpClient: MockClient((request) async {
          requests++;
          expect(jsonDecode(request.body)['consent'], isTrue);
          return http.Response('{"answer":"guide","draft":{}}', 200);
        }),
      );
      final repo = CloudflareFamilyRepository(client);
      await expectLater(
        repo.askGuide('question', consent: false),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.code,
            'code',
            'AI_CONSENT_REQUIRED',
          ),
        ),
      );
      await expectLater(
        repo.suggestInvitation('letter', consent: false),
        throwsA(isA<CloudflareApiException>()),
      );
      expect(requests, 0);
      expect(await repo.askGuide('question', consent: true), 'guide');
      await repo.suggestInvitation('letter', consent: true);
      expect(requests, 2);
    },
  );

  test('production only permits HTTPS and rejects legacy Supabase', () {
    expect(
      isValidCloudflareApiUrl('http://127.0.0.1:8787', production: false),
      isTrue,
    );
    expect(
      isValidCloudflareApiUrl('http://127.0.0.1:8787', production: true),
      isFalse,
    );
    expect(
      isValidCloudflareApiUrl('https://family.example.com', production: true),
      isTrue,
    );
    expect(
      isValidCloudflareApiUrl('https://old.supabase.co', production: true),
      isFalse,
    );
    expect(
      isValidCloudflareApiUrl(
        'https://user:secret@family.example.com',
        production: true,
      ),
      isFalse,
    );
  });

  test(
    'native ticket exchange binds verifier and stores token in secure storage',
    () async {
      await native.saveLoginVerifier('test-verifier');
      Map<String, dynamic>? sent;
      final client = CloudflareClient(
        baseUrl: 'https://family.example.com',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body);
          return http.Response(
            '{"token":"test-session","user":{"id":"user-a"}}',
            200,
          );
        }),
      );
      await client.consumeCallback(
        Uri.parse(
          'familymemory://login-callback/?login_ticket=single-use-ticket',
        ),
      );
      expect(sent!['verifier'], 'test-verifier');
      expect(sent!['client'], 'native');
      expect(await native.readSessionToken(), 'test-session');
      expect(await native.readLoginVerifier(), isNull);
      await expectLater(
        client.consumeCallback(
          Uri.parse('familymemory://login-callback/?login_ticket=replayed'),
        ),
        throwsA(isA<CloudflareApiException>()),
      );
    },
  );

  test(
    'save uses loaded optimistic version and reloads authoritative state',
    () async {
      Map<String, dynamic>? payload;
      final client = CloudflareClient(
        baseUrl: 'https://family.example.com',
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            payload = jsonDecode(request.body);
            return http.Response(
              jsonEncode({'id': 'person-a', 'version': 4}),
              200,
            );
          }
          final state = fixture();
          (state['people'] as List).first['version'] = 4;
          return http.Response.bytes(utf8.encode(jsonEncode(state)), 200);
        }),
      );
      final repo = CloudflareFamilyRepository(client)..applyState(fixture());
      final value = personFromCloudflare(personToCloudflare(repo.people.single))
        ..name = '変更';
      await repo.savePerson(value);
      expect(payload!['expectedVersion'], 3);
      expect(repo.people.single.version, 4);
    },
  );

  test(
    'conflict is surfaced and does not silently replace family state',
    () async {
      final client = CloudflareClient(
        baseUrl: 'https://family.example.com',
        httpClient: MockClient(
          (request) async => http.Response('{"code":"VERSION_CONFLICT"}', 409),
        ),
      );
      final repo = CloudflareFamilyRepository(client)..applyState(fixture());
      await expectLater(
        repo.savePerson(repo.people.single),
        throwsA(
          isA<CloudflareApiException>().having((e) => e.status, 'status', 409),
        ),
      );
      expect(repo.people.single.version, 3);
    },
  );

  test('viewer cannot send mutation request', () async {
    var requests = 0;
    final client = CloudflareClient(
      baseUrl: 'https://family.example.com',
      httpClient: MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    final state = fixture();
    state['family']['role'] = 'viewer';
    final repo = CloudflareFamilyRepository(client)..applyState(state);
    await expectLater(
      repo.savePerson(repo.people.single),
      throwsA(isA<CloudflareApiException>()),
    );
    expect(requests, 0);
  });

  test(
    'malformed complete snapshot does not partially clear loaded people',
    () {
      final repo = CloudflareFamilyRepository(
        CloudflareClient(baseUrl: 'https://family.example.com'),
      )..applyState(fixture());
      expect(
        () => repo.applyState({
          ...fixture(),
          'events': [
            {'id': 'bad'},
          ],
        }),
        throwsA(anything),
      );
      expect(repo.people.single.name, 'テスト');
    },
  );

  test(
    'duplicate resets date, expenses, attendance and candidate state',
    () async {
      Map<String, dynamic>? saved;
      final source = MemorialEvent(
        id: 'old',
        title: '法要',
        type: '法要',
        subjectPersonId: 'person-a',
        status: EventStatus.completed,
        date: DateTime(2026, 5, 1),
        isCandidate: true,
        expenses: [Expense(label: 'お布施', amount: 10000)],
        participants: [
          EventParticipant(
            name: '親戚',
            relationshipAtTime: '従兄',
            attendance: '出席',
          ),
        ],
      );
      final client = CloudflareClient(
        baseUrl: 'https://family.example.com',
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            saved = Map<String, dynamic>.from(jsonDecode(request.body)['data']);
            return http.Response(
              jsonEncode({'id': saved!['id'], 'version': 1}),
              200,
            );
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode(fixture(events: [saved!]))),
            200,
          );
        }),
      );
      final repo = CloudflareFamilyRepository(client)..applyState(fixture());
      final result = await repo.duplicateSafely(source);
      expect(result.date, isNull);
      expect(result.expenses.single.amount, isNull);
      expect(result.participants.single.attendance, isNull);
      expect(result.isCandidate, isFalse);
      expect(result.status, EventStatus.planned);
    },
  );
}
