import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'supabase_family_repository.dart';

class FamilyMemoryRemoteApp extends StatefulWidget {
  const FamilyMemoryRemoteApp({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<FamilyMemoryRemoteApp> createState() => _FamilyMemoryRemoteAppState();
}

class _FamilyMemoryRemoteAppState extends State<FamilyMemoryRemoteApp> {
  late Session? session = widget.client.auth.currentSession;
  StreamSubscription<AuthState>? subscription;
  StreamSubscription<Uri>? linkSubscription;
  final AppLinks appLinks = AppLinks();
  String? pendingInviteToken;

  @override
  void initState() {
    super.initState();
    subscription = widget.client.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      setState(() => session = event.session);
    });
    _listenForInviteLinks();
  }

  Future<void> _listenForInviteLinks() async {
    try {
      _captureInviteLink(await appLinks.getInitialLink());
      linkSubscription = appLinks.uriLinkStream.listen(_captureInviteLink);
    } catch (_) {
      // A malformed/unavailable link must never prevent secure sign-in.
    }
  }

  void _captureInviteLink(Uri? uri) {
    if (uri == null || !mounted) return;
    final token = inviteTokenFromUri(uri);
    if (token == null) return;
    setState(() => pendingInviteToken = token);
  }

  @override
  void dispose() {
    subscription?.cancel();
    linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (session == null) return OtpSignInApp(client: widget.client);
    return AuthenticatedFamilyGate(
      key: ValueKey(session!.user.id),
      client: widget.client,
      inviteToken: pendingInviteToken,
      onInviteConsumed: () {
        if (mounted) setState(() => pendingInviteToken = null);
      },
    );
  }
}

String? inviteTokenFromUri(Uri uri) {
  final isCustomScheme =
      uri.scheme == 'familymemory' &&
      uri.host == 'invite' &&
      (uri.path.isEmpty || uri.path == '/');
  final isWebLink =
      (uri.scheme == 'https' || uri.scheme == 'http') && uri.path == '/invite';
  if (!isCustomScheme && !isWebLink) return null;
  final token = uri.queryParameters['token'];
  if (token == null || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
    return null;
  }
  return token;
}

class OtpSignInApp extends StatefulWidget {
  const OtpSignInApp({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<OtpSignInApp> createState() => _OtpSignInAppState();
}

class _OtpSignInAppState extends State<OtpSignInApp> {
  final email = TextEditingController();
  final code = TextEditingController();
  bool emailExpanded = false;
  bool codeSent = false;
  bool busy = false;
  String? busyAction;
  String? error;

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    final value = email.text.trim().toLowerCase();
    if (!value.contains('@')) {
      setState(() => error = 'メールアドレスを確認してください。');
      return;
    }
    setState(() {
      busy = true;
      busyAction = 'email';
      error = null;
    });
    try {
      await widget.client.auth.signInWithOtp(
        email: value,
        emailRedirectTo: googleOAuthRedirect(
          isWeb: kIsWeb,
          currentUri: Uri.base,
        ),
        shouldCreateUser: true,
      );
      if (!mounted) return;
      setState(() => codeSent = true);
    } on AuthException catch (exception) {
      if (!mounted) return;
      setState(() => error = _safeAuthMessage(exception));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      busy = true;
      busyAction = 'google';
      error = null;
    });
    try {
      await widget.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: googleOAuthRedirect(isWeb: kIsWeb, currentUri: Uri.base),
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } on AuthException catch (exception) {
      if (!mounted) return;
      setState(() => error = _safeOAuthMessage(exception));
    } catch (_) {
      if (!mounted) return;
      setState(() => error = 'Googleログインを開けませんでした。メールログインをお試しください。');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  Future<void> verifyCode() async {
    final value = code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      setState(() => error = '6桁の確認コードを入力してください。');
      return;
    }
    setState(() {
      busy = true;
      busyAction = 'email';
      error = null;
    });
    try {
      await widget.client.auth.verifyOTP(
        email: email.text.trim().toLowerCase(),
        token: value,
        type: OtpType.email,
      );
    } on AuthException catch (exception) {
      if (!mounted) return;
      setState(() => error = _safeAuthMessage(exception));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _RemoteMaterialApp(
    child: Scaffold(
      appBar: AppBar(title: const Text('家族の記憶')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.family_restroom_outlined, size: 52),
                    const SizedBox(height: 16),
                    Text(
                      codeSent ? 'メールを確認' : 'かんたんログイン',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      codeSent
                          ? 'メール内のログインリンクを開いてください。6桁コードが記載されている場合は、下の入力でもログインできます。'
                          : 'Googleアカウントで、パスワードや確認コードなしで続けられます。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (!codeSent) ...[
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : signInWithGoogle,
                        icon: const _GoogleMark(),
                        label: Text(
                          busy && busyAction == 'google'
                              ? 'Googleを開いています…'
                              : 'Googleでログイン',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('または'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                emailExpanded = !emailExpanded;
                                error = null;
                              }),
                        icon: const Icon(Icons.mail_outline),
                        label: Text(
                          emailExpanded ? 'メール入力を閉じる' : 'メールでログイン（予備）',
                        ),
                      ),
                    ],
                    if (emailExpanded || codeSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        enabled: !busy && !codeSent,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'メールアドレス'),
                      ),
                    ],
                    if (codeSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: code,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        decoration: const InputDecoration(
                          labelText: '6桁の確認コード',
                          counterText: '',
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (emailExpanded || codeSent) ...[
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : (codeSent ? verifyCode : sendCode),
                        child: Text(
                          busy && busyAction == 'email'
                              ? '処理中…'
                              : (codeSent ? '6桁コードでログイン' : 'ログインメールを送る'),
                        ),
                      ),
                    ],
                    if (codeSent)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                codeSent = false;
                                emailExpanded = true;
                                code.clear();
                                error = null;
                              }),
                        child: const Text('メールアドレスを変更'),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      '確認コードや招待コードを他の人へ転送しないでください。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
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

String googleOAuthRedirect({required bool isWeb, required Uri currentUri}) {
  if (isWeb) return '${currentUri.origin}/';
  return 'familymemory://login-callback/';
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Google',
    child: Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'G',
        style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class AuthenticatedFamilyGate extends StatefulWidget {
  const AuthenticatedFamilyGate({
    super.key,
    required this.client,
    required this.inviteToken,
    required this.onInviteConsumed,
  });

  final SupabaseClient client;
  final String? inviteToken;
  final VoidCallback onInviteConsumed;

  @override
  State<AuthenticatedFamilyGate> createState() =>
      _AuthenticatedFamilyGateState();
}

class _AuthenticatedFamilyGateState extends State<AuthenticatedFamilyGate> {
  late Future<_GateState> gate = load();

  Future<_GateState> load() async {
    final user = widget.client.auth.currentUser!;
    final profile = await widget.client
        .from('profiles')
        .select('display_name')
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null) return const _GateState.needsProfile();
    final members = await widget.client
        .from('family_members')
        .select('status')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1);
    if (members.isEmpty) return const _GateState.needsFamily();
    if (members.first['status'] == 'pending') {
      return const _GateState.pendingApproval();
    }
    return _GateState.ready(
      await SupabaseFamilyRepository.connect(widget.client),
    );
  }

  void refresh() => setState(() => gate = load());

  @override
  Widget build(BuildContext context) => FutureBuilder<_GateState>(
    future: gate,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _RemoteMaterialApp(
          child: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      if (snapshot.hasError) {
        return _RemoteMessageApp(
          icon: Icons.sync_problem_outlined,
          title: '家族データを読み込めませんでした',
          message: _safeFamilyLoadMessage(snapshot.error!),
          primaryLabel: '再試行',
          onPrimary: refresh,
          onSignOut: widget.client.auth.signOut,
        );
      }
      final state = snapshot.requireData;
      if (state.repository != null) {
        return WebIdleSessionLock(
          onTimeout: widget.client.auth.signOut,
          child: FamilyMemoryApp(repository: state.repository),
        );
      }
      if (state.kind == _GateKind.profile) {
        return ProfileSetupApp(client: widget.client, onCompleted: refresh);
      }
      if (state.kind == _GateKind.pending) {
        return _RemoteMessageApp(
          icon: Icons.hourglass_top_outlined,
          title: '家族の承認を待っています',
          message: '招待したownerが表示名を確認して承認すると、家族データを開けます。',
          primaryLabel: '状態を再確認',
          onPrimary: refresh,
          onSignOut: widget.client.auth.signOut,
        );
      }
      return FamilySetupApp(
        client: widget.client,
        onCompleted: refresh,
        inviteToken: widget.inviteToken,
        onInviteConsumed: widget.onInviteConsumed,
      );
    },
  );
}

class WebIdleSessionLock extends StatefulWidget {
  const WebIdleSessionLock({
    super.key,
    required this.child,
    required this.onTimeout,
  });

  final Widget child;
  final Future<void> Function() onTimeout;

  @override
  State<WebIdleSessionLock> createState() => _WebIdleSessionLockState();
}

class _WebIdleSessionLockState extends State<WebIdleSessionLock>
    with WidgetsBindingObserver {
  static const timeout = Duration(minutes: 30);
  Timer? timer;
  DateTime lastActivity = DateTime.now();
  bool signingOut = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      _restartTimer();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    if (kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb || state != AppLifecycleState.resumed) return;
    if (DateTime.now().difference(lastActivity) >= timeout) {
      _lock();
    } else {
      _restartTimer();
    }
  }

  void _touch() {
    if (!kIsWeb || signingOut) return;
    lastActivity = DateTime.now();
    _restartTimer();
  }

  void _restartTimer() {
    timer?.cancel();
    timer = Timer(timeout, _lock);
  }

  Future<void> _lock() async {
    if (signingOut) return;
    signingOut = true;
    timer?.cancel();
    await widget.onTimeout();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return Focus(
      onKeyEvent: (_, _) {
        _touch();
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touch(),
        onPointerSignal: (_) => _touch(),
        onPointerHover: (_) => _touch(),
        child: widget.child,
      ),
    );
  }
}

class ProfileSetupApp extends StatefulWidget {
  const ProfileSetupApp({
    super.key,
    required this.client,
    required this.onCompleted,
  });
  final SupabaseClient client;
  final VoidCallback onCompleted;

  @override
  State<ProfileSetupApp> createState() => _ProfileSetupAppState();
}

class _ProfileSetupAppState extends State<ProfileSetupApp> {
  final name = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final value = name.text.trim();
    if (value.isEmpty || value.length > 80) {
      setState(() => error = '家族が確認できる表示名を1〜80文字で入力してください。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.client.from('profiles').insert({
        'id': widget.client.auth.currentUser!.id,
        'display_name': value,
      });
      widget.onCompleted();
    } on PostgrestException {
      if (mounted) setState(() => error = '表示名を保存できませんでした。再試行してください。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _RemoteFormApp(
    title: '家族に表示する名前',
    description: '招待した家族が本人確認に使える名前を入力してください。',
    controller: name,
    label: '表示名',
    error: error,
    busy: busy,
    onSave: save,
    onSignOut: widget.client.auth.signOut,
  );
}

class FamilySetupApp extends StatefulWidget {
  const FamilySetupApp({
    super.key,
    required this.client,
    required this.onCompleted,
    required this.inviteToken,
    required this.onInviteConsumed,
  });
  final SupabaseClient client;
  final VoidCallback onCompleted;
  final String? inviteToken;
  final VoidCallback onInviteConsumed;

  @override
  State<FamilySetupApp> createState() => _FamilySetupAppState();
}

class _FamilySetupAppState extends State<FamilySetupApp> {
  final familyName = TextEditingController();
  final inviteCode = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    familyName.dispose();
    inviteCode.dispose();
    super.dispose();
  }

  Future<void> createFamily() async {
    final value = familyName.text.trim();
    if (value.isEmpty || value.length > 80) {
      setState(() => error = '家族名を1〜80文字で入力してください。');
      return;
    }
    await _run(() async {
      await widget.client.rpc('create_family', params: {'p_name': value});
      widget.onCompleted();
    });
  }

  Future<void> acceptInvite() async {
    final value = inviteCode.text.trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{12}$').hasMatch(value)) {
      setState(() => error = '12文字の招待コードを確認してください。');
      return;
    }
    await _run(() async {
      await widget.client.functions.invoke(
        'accept-family-invite',
        body: {'shortCode': value},
      );
      widget.onCompleted();
    });
  }

  Future<void> acceptInviteLink() async {
    final token = widget.inviteToken;
    if (token == null) return;
    await _run(() async {
      await widget.client.functions.invoke(
        'accept-family-invite',
        body: {'token': token},
      );
      widget.onInviteConsumed();
      widget.onCompleted();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => error = '処理できませんでした。入力内容と通信状態を確認してください。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _RemoteMaterialApp(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('家族スペースを設定'),
        actions: [
          IconButton(
            onPressed: widget.client.auth.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.inviteToken != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '家族からの招待リンクを受け取りました',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '参加申請後も、ownerが表示名を確認して承認するまで家族データは表示されません。',
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: busy ? null : acceptInviteLink,
                            child: const Text('この招待で参加申請する'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                const Text(
                  '最初の家族スペースを作る',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('家族の代表者だけが作成します。'),
                const SizedBox(height: 12),
                TextField(
                  controller: familyName,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: '家族名'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : createFamily,
                  child: const Text('家族スペースを作る'),
                ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 20),
                const Text(
                  '家族から招待されている',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: inviteCode,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: '12文字の招待コード',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy ? null : acceptInvite,
                  child: const Text('招待を受ける'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _RemoteFormApp extends StatelessWidget {
  const _RemoteFormApp({
    required this.title,
    required this.description,
    required this.controller,
    required this.label,
    required this.error,
    required this.busy,
    required this.onSave,
    required this.onSignOut,
  });
  final String title;
  final String description;
  final TextEditingController controller;
  final String label;
  final String? error;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => _RemoteMaterialApp(
    child: Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(description),
                    const SizedBox(height: 20),
                    TextField(
                      controller: controller,
                      enabled: !busy,
                      decoration: InputDecoration(labelText: label),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: busy ? null : onSave,
                      child: Text(busy ? '保存中…' : '保存する'),
                    ),
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

class _RemoteMessageApp extends StatelessWidget {
  const _RemoteMessageApp({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSignOut,
  });
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => _RemoteMaterialApp(
    child: Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onPrimary,
                      child: Text(primaryLabel),
                    ),
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

class _RemoteMaterialApp extends StatelessWidget {
  const _RemoteMaterialApp({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '家族の記憶',
    debugShowCheckedModeBanner: false,
    theme: familyMemoryTheme(),
    themeMode: ThemeMode.light,
    home: child,
  );
}

enum _GateKind { profile, family, pending, ready }

class _GateState {
  const _GateState._(this.kind, this.repository);
  const _GateState.needsProfile() : this._(_GateKind.profile, null);
  const _GateState.needsFamily() : this._(_GateKind.family, null);
  const _GateState.pendingApproval() : this._(_GateKind.pending, null);
  const _GateState.ready(SupabaseFamilyRepository repository)
    : this._(_GateKind.ready, repository);
  final _GateKind kind;
  final SupabaseFamilyRepository? repository;
}

String _safeAuthMessage(AuthException exception) {
  if (exception.statusCode == '429') return '試行回数が多すぎます。時間を置いて再試行してください。';
  return 'ログインできませんでした。メールアドレスと確認コードを確認してください。';
}

String _safeOAuthMessage(AuthException exception) {
  final message = exception.message.toLowerCase();
  if (message.contains('provider') &&
      (message.contains('disabled') || message.contains('not enabled'))) {
    return 'Googleログインは現在設定中です。メールログインをお試しください。';
  }
  return 'Googleログインを完了できませんでした。もう一度お試しください。';
}

String _safeFamilyLoadMessage(Object error) {
  const base = '通信状態を確認して再試行してください。別家族の情報は表示しません。';
  // ステージングだけに、個人情報や認証情報を含まない障害コードを出す。
  // 本番では常に利用者向けの案内だけにする。
  if (const String.fromEnvironment('APP_ENV') == 'staging') {
    if (error is PostgrestException) {
      return '$base\n\n開発診断コード: ${error.code ?? 'POSTGREST'}';
    }
    if (error is AuthException) {
      return '$base\n\n開発診断コード: ${error.statusCode ?? 'AUTH'}';
    }
    return '$base\n\n開発診断コード: FAMILY_LOAD';
  }
  return base;
}
