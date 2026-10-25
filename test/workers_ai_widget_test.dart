import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:family_memory/app.dart';
import 'package:family_memory/repository.dart';
import 'package:family_memory/workers_ai_screen.dart';

void main() {
  testWidgets('AI screen remains usable at 320px and does not send demo data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepositoryScope(
        repository: DemoFamilyRepository(),
        child: MaterialApp(
          theme: familyMemoryTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: const WorkersAiScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('AI補助'), findsOneWidget);
    expect(find.text('デモではAIへの送信は行いません。'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '三回忌の準備');
    await tester.pump();
    final send = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(send.onPressed, isNull);
  });
}
