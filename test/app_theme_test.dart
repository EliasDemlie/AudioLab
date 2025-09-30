import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/main.dart';

void main() {
  const methods = MethodChannel('com.beamlinetech.audiolab/recorder');
  const events = MethodChannel('com.beamlinetech.audiolab/recorder_state');

  testWidgets('follows system appearance and switches themes on drawer pages', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
      expect(
        tester.getRect(find.byType(Drawer)).right,
        tester.view.physicalSize.width,
      );
    }

    Future<void> switchTheme(String label) async {
      await openMenu();
      await tester.tap(find.widgetWithText(ListTile, label));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, label), findsNothing);
    }

    expect(appearance(), Brightness.dark);
    expect(find.byType(NavigationBar), findsNothing);
    final appBar = find.byType(AppBar);
    final logo = find.descendant(
      of: appBar,
      matching: find.image(
        const AssetImage('play_store_assets/icon/logo_transparent.png'),
      ),
    );
    final appName = find.descendant(
      of: appBar,
      matching: find.text('AudioLab'),
    );
    final menu = find.byTooltip('Open navigation menu');
    expect(logo, findsOneWidget);
    expect(appName, findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'AudioLab',
    );
    expect(tester.getRect(logo).right, lessThan(tester.getRect(appName).left));
    expect(tester.getRect(appName).right, lessThan(tester.getRect(menu).left));
    expect(tester.getRect(menu).right, greaterThan(280));
    expect(
      find.descendant(
        of: appBar,
        matching: find.byIcon(Icons.light_mode_outlined),
      ),
      findsNothing,
    );
    expect(find.text('Switch to light mode'), findsNothing);
    await openMenu();
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('by beamlineTech'),
      ),
      findsOneWidget,
    );
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
      find.descendant(of: appBar, matching: find.text('AudioLab')),
      findsOneWidget,
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
      find.descendant(of: appBar, matching: find.text('AudioLab')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
