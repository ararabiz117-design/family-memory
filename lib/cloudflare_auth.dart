import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'cloudflare_client.dart';
import 'cloudflare_family_repository.dart';
import 'glass_ui.dart';
import 'cloudflare_platform.dart' as platform;

class CloudflareFamilyApp extends StatefulWidget {
  const CloudflareFamilyApp({super.key, required this.client});
  final CloudflareClient client;
  @override
  State<CloudflareFamilyApp> createState() => _CloudflareFamilyAppState();
}

class _CloudflareFamilyAppState extends State<CloudflareFamilyApp>
    with WidgetsBindingObserver {
  final _links = AppLinks();
  final _familyName = TextEditingController();
  final _displayName = TextEditingController();
  final _invite = TextEditingController();
  StreamSubscription<Uri>? _linkSubscription;
  CloudflareFamilyRepository? _repository;
  bool _loading = true;
  bool _signedIn = false;
  bool _busy = false;
  bool _pendingApproval = false;
  String? _error;
  Timer? _idle;
  DateTime _lastActivity = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.onSignedOut = () {
      if (mounted) {
        _repository?.dispose();
        setState(() {
          _repository = null;
          _signedIn = false;
          _loading = false;
        });
      }
    };
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _invite.text = await platform.readPendingInvite() ?? '';
      if (kIsWeb) {
        _captureInvite(Uri.base);
        await widget.client.consumeCallback(Uri.base);
      } else {
        final initial = await _links.getInitialLink();
        if (initial != null) {
          _captureInvite(initial);
          await widget.client.consumeCallback(initial);
        }
        _linkSubscription = _links.uriLinkStream.listen((uri) async {
          _captureInvite(uri);
          if (uri.scheme == 'familymemory' && uri.host == 'login-callback') {
            try {
              await widget.client.consumeCallback(uri);
              await _load();
            } catch (error) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _busy = false;
                  _error = '$error';
                });
              }
            }
          }
        });
      }
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  void _captureInvite(Uri uri) {
    if (uri.path == '/invite' ||
        (uri.scheme == 'familymemory' && uri.host == 'invite')) {
      final token = uri.queryParameters['token'];
      if (token != null && RegExp(r'^[A-Za-z0-9_-]{20,100}$').hasMatch(token)) {
        _invite.text = token;
        platform.savePendingInvite(token);
      }
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final me = await widget.client.json('GET', '/api/me');
      final user = me['user'] as Map?;
      final repository = me['family'] == null
          ? null
          : await CloudflareFamilyRepository.connect(widget.client);
      if (!mounted) {
        repository?.dispose();
        return;
      }
      _repository?.dispose();
      setState(() {
        _signedIn = user != null;
        _repository = repository;
        _displayName.text = user?['name'] ?? '';
        _pendingApproval = me['pendingApproval'] == true;
      });
      _touch();
    } on CloudflareApiException catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        setState(() {
          _signedIn = false;
          _repository = null;
        });
      } else {
        setState(() => _error = '$error');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '接続できませんでした。通信状態を確認して再試行してください。');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFamily() async {
    if (_familyName.text.trim().isEmpty || _displayName.text.trim().isEmpty) {
      return;
    }
    await _act(() async {
      await widget.client.json(
        'PUT',
        '/api/profile',
        data: {'name': _displayName.text.trim()},
      );
      await widget.client.json(
        'POST',
        '/api/families',
        data: {'name': _familyName.text.trim()},
      );
      await _load();
    });
  }

  Future<void> _acceptInvite() async {
    final value = _invite.text.trim();
    if (value.isEmpty || _displayName.text.trim().isEmpty) return;
    await _act(() async {
      await widget.client.json(
        'PUT',
        '/api/profile',
        data: {'name': _displayName.text.trim()},
      );
      await widget.client.json(
        'POST',
        '/api/invitations/accept',
        data: value.length <= 16 ? {'shortCode': value} : {'token': value},
      );
      _invite.clear();
      await platform.savePendingInvite(null);
      _pendingApproval = true;
      await _load();
    });
  }

  void _touch() {
    if (!kIsWeb || !_signedIn) return;
    _lastActivity = DateTime.now();
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 30), widget.client.signOut);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb &&
        state == AppLifecycleState.resumed &&
        _signedIn &&
        DateTime.now().difference(_lastActivity) >=
            const Duration(minutes: 30)) {
      widget.client.signOut();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _idle?.cancel();
    _repository?.dispose();
    _familyName.dispose();
    _displayName.dispose();
    _invite.dispose();
    widget.client.onSignedOut = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _repository != null) {
      return Listener(
        onPointerDown: (_) => _touch(),
        onPointerSignal: (_) => _touch(),
        child: Focus(
          onKeyEvent: (_, _) {
            _touch();
            return KeyEventResult.ignored;
          },
          child: FamilyMemoryApp(repository: _repository),
        ),
      );
    }
    return MaterialApp(
      title: '家族の記憶',
      debugShowCheckedModeBanner: false,
      theme: familyMemoryTheme(),
      builder: (context, child) =>
          GlassBackdrop(child: child ?? const SizedBox.shrink()),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('家族の記憶'),
          actions: [
            if (_signedIn)
              IconButton(
                tooltip: 'ログアウト',
                onPressed: _busy ? null : widget.client.signOut,
                icon: const Icon(Icons.logout),
              ),
          ],
        ),
        body: _loading || _busy
            ? const GlassScreenSkeleton()
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_error != null) ...[
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _load,
                                child: const Text('再読み込み'),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (!_signedIn)
                              FilledButton.icon(
                                onPressed: () =>
                                    _act(widget.client.startGoogleLogin),
                                icon: const Icon(Icons.login),
                                label: const Text('Googleでログイン'),
                              )
                            else if (_pendingApproval) ...[
                              const Text('家族の承認待ち'),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _load,
                                child: const Text('状態を確認'),
                              ),
                            ] else ...[
                              TextField(
                                controller: _displayName,
                                maxLength: 80,
                                decoration: const InputDecoration(
                                  labelText: '表示名',
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _invite,
                                decoration: const InputDecoration(
                                  labelText: '招待コード',
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _acceptInvite,
                                child: const Text('招待に参加'),
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _familyName,
                                maxLength: 80,
                                decoration: const InputDecoration(
                                  labelText: '家族の名前',
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _createFamily,
                                child: const Text('家族を作成'),
                              ),
                            ],
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
}
