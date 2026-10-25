import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'local_reminders.dart';
import 'glass_ui.dart';
import 'repository.dart';
import 'screens.dart';

ThemeData familyMemoryTheme() {
  const seed = Color(0xFF3165A8);
  const ink = Color(0xFF25334A);
  const canvas = Colors.transparent;
  return ThemeData(
    useMaterial3: true,
    // Flutter Web does not bundle Japanese glyphs in the Material font.
    // Prefer fonts available on Japanese Android/iOS/Windows devices so text
    // remains readable in the local preview and in the installed app.
    fontFamilyFallback: const [
      'Noto Sans JP',
      'Yu Gothic UI',
      'Yu Gothic',
      'Meiryo',
      'sans-serif',
    ],
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFFBFCFF),
        ).copyWith(
          secondary: const Color(0xFF367F83),
          secondaryContainer: const Color(0xFFE7F3F2),
          tertiary: const Color(0xFF6A72A5),
          tertiaryContainer: const Color(0xFFF0F0FA),
          onSurface: ink,
        ),
    scaffoldBackgroundColor: canvas,
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      shadowColor: Color(0x0A33405E),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Color(0xFFDCE4EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Color(0xFFDCE4EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: seed, width: 2),
      ),
      filled: true,
      fillColor: Color(0xD9FFFFFF),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: canvas,
      foregroundColor: ink,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      elevation: 0,
      backgroundColor: Colors.transparent,
      indicatorColor: const Color(0xFFDDEBFC),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? const Color(0xFF234F83)
              : const Color(0xFF606F83),
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Color(0xFFDDEBFC),
      selectedIconTheme: IconThemeData(color: Color(0xFF3165A8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(),
      side: BorderSide(color: Color(0xFFDCE4EF)),
    ),
    dividerColor: const Color(0xFFE0E7F1),
  );
}

class RepositoryScope extends InheritedNotifier<FamilyRepository> {
  const RepositoryScope({
    super.key,
    required FamilyRepository repository,
    required super.child,
  }) : super(notifier: repository);
  static FamilyRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'RepositoryScope is missing');
    return scope!.notifier!;
  }
}

class FamilyMemoryApp extends StatefulWidget {
  const FamilyMemoryApp({super.key, this.repository});
  final FamilyRepository? repository;
  @override
  State<FamilyMemoryApp> createState() => _FamilyMemoryAppState();
}

class _FamilyMemoryAppState extends State<FamilyMemoryApp> {
  late final FamilyRepository repository =
      widget.repository ?? DemoFamilyRepository();
  late final GoRouter router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => const AppShell())],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocalReminderService.instance
          .sync(repository.confirmedEvents)
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: RepositoryScope(
        repository: repository,
        child: MaterialApp.router(
          title: '家族の記憶',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: familyMemoryTheme(),
          themeMode: ThemeMode.light,
          builder: (context, child) =>
              GlassBackdrop(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
