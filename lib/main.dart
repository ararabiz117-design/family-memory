import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';
import 'cloudflare_auth.dart';
import 'cloudflare_client.dart';
import 'local_reminders.dart';
import 'repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalReminderService.instance.initialize();
  const apiUrl = String.fromEnvironment('CLOUDFLARE_API_URL');
  const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'demo');

  if (appEnv == 'demo') {
    runApp(FamilyMemoryApp(repository: DemoFamilyRepository()));
    return;
  }

  if (!{'staging', 'production'}.contains(appEnv)) {
    runApp(const _StartupBlockedApp(message: 'APP_ENV の値が不正です。'));
    return;
  }
  if (!isValidCloudflareApiUrl(apiUrl, production: appEnv == 'production')) {
    runApp(
      const _StartupBlockedApp(
        message: '家族限定版の接続設定が不足しています。デモへ自動で切り替えず、安全のため起動を停止しました。',
      ),
    );
    return;
  }
  if (kIsWeb &&
      appEnv == 'production' &&
      Uri.parse(apiUrl).origin != Uri.base.origin) {
    runApp(const _StartupBlockedApp(message: 'Web版とAPIを同じ公開先に設定してください。'));
    return;
  }
  runApp(CloudflareFamilyApp(client: CloudflareClient(baseUrl: apiUrl)));
}

bool isDisallowedSupabaseProjectUrl(String url) =>
    url.contains('mwhtnpdmrwtuqfshbcbq.supabase.co');

class MyApp extends FamilyMemoryApp {
  const MyApp({super.key}) : super();
}

class _StartupBlockedApp extends StatelessWidget {
  const _StartupBlockedApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '家族の記憶',
    debugShowCheckedModeBanner: false,
    theme: familyMemoryTheme(),
    themeMode: ThemeMode.light,
    home: Scaffold(
      appBar: AppBar(title: const Text('家族の記憶')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.security_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      '安全確認が必要です',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
