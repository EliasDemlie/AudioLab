import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/main.dart';

void main() {
  const methods = MethodChannel('com.example.voicerec/recorder');
  const events = MethodChannel('com.example.voicerec/recorder_state');

  testWidgets('follows system appearance and allows switching on either tab', (
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
        Theme.of(tester.element(find.byType(NavigationBar))).brightness;
    expect(appearance(), Brightness.dark);
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);

    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(appearance(), Brightness.light);
    expect(find.byTooltip('Switch to dark mode'), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();
    expect(appearance(), Brightness.dark);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.byTooltip('Switch to light mode'));
    await tester.pumpAndSettle();
    expect(appearance(), Brightness.light);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
