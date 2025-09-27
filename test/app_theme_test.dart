import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/main.dart';

void main() {
  const methods = MethodChannel('com.example.voicerec/recorder');
  const events = MethodChannel('com.example.voicerec/recorder_state');

  testWidgets('follows system appearance and switches themes on drawer pages', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'listRecordings') return <Object>[];
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    final platform = tester.binding.platformDispatcher;
    platform.platformBrightnessTestValue = Brightness.dark;
    addTearDown(platform.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const VoiceRecApp());
    await tester.pumpAndSettle();

    Brightness appearance() =>
        Theme.of(tester.element(find.byType(AppBar))).brightness;
    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
    }

    Future<void> switchTheme(String label) async {
      await openMenu();
      await tester.tap(find.widgetWithText(ListTile, label));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, label), findsNothing);
    }

    expect(appearance(), Brightness.dark);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<AppBar>(find.byType(AppBar)).actions, isNull);
    expect(find.text('Switch to light mode'), findsNothing);
    await openMenu();
    expect(
      find.widgetWithText(ListTile, 'Switch to light mode'),
      findsOneWidget,
    );

    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(appearance(), Brightness.light);
    expect(
      find.widgetWithText(ListTile, 'Switch to dark mode'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ListTile, 'Library'));
    await tester.pumpAndSettle();
    await switchTheme('Switch to dark mode');
    expect(appearance(), Brightness.dark);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);

    await switchTheme('Switch to light mode');
    expect(appearance(), Brightness.light);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).title,
      isA<Text>().having((title) => title.data, 'data', 'Library'),
    );
    await openMenu();
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Library'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Record'));
    await tester.pumpAndSettle();
    await switchTheme('Switch to dark mode');
    expect(appearance(), Brightness.dark);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).title,
      isA<Text>().having((title) => title.data, 'data', 'VoicePro'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
