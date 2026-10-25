import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_memory/app.dart';
import 'package:family_memory/repository.dart';

void main() {
  testWidgets('4タブと主要な2つの検索入口を表示する', (tester) async {
    await tester.pumpWidget(
      FamilyMemoryApp(repository: DemoFamilyRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('ホーム'), findsWidgets);
    expect(find.text('家系図'), findsOneWidget);
    expect(find.text('記録'), findsOneWidget);
    expect(find.text('人物'), findsOneWidget);
    expect(find.text('誰だっけ？'), findsOneWidget);
    expect(find.text('前回どうした？'), findsOneWidget);
    expect(find.textContaining('架空の青葉家'), findsOneWidget);
  });

  testWidgets('誰だっけ検索で関係と最後に会った場面へ到達できる', (tester) async {
    await tester.pumpWidget(
      FamilyMemoryApp(repository: DemoFamilyRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('誰だっけ？'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'たなか');
    await tester.pump();

    expect(find.text('田中 隆'), findsOneWidget);
    expect(find.textContaining('父の従兄'), findsWidgets);
    expect(find.textContaining('父の三回忌で会った'), findsOneWidget);

    await tester.tap(find.text('田中 隆'));
    await tester.pumpAndSettle();
    expect(find.text('人物情報'), findsOneWidget);
    expect(find.text('どう呼べばよいか'), findsOneWidget);
    expect(find.text('最後に会った場面'), findsOneWidget);
  });

  testWidgets('家系図タブに中心人物の関係図を表示する', (tester) async {
    await tester.pumpWidget(
      FamilyMemoryApp(repository: DemoFamilyRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('家系図'));
    await tester.pumpAndSettle();

    expect(find.text('家族関係図'), findsOneWidget);
    expect(find.textContaining('青葉 直人を中心に'), findsOneWidget);
    expect(find.text('人物どうしの関係を登録'), findsOneWidget);
  });

  testWidgets('320px幅・文字200%でもホームの主要操作を表示できる', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      FamilyMemoryApp(repository: DemoFamilyRepository()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('誰だっけ？'), findsOneWidget);
    expect(find.text('前回どうした？'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
