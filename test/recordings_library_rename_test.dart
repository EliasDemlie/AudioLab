import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/widgets/recordings_list.dart';
import 'package:voicerec/widgets/rename_recording_sheet.dart';

final _recording = Recording(
  file: File('/recordings/Meeting.m4a'),
  createdAt: DateTime(2026, 10, 29),
  sizeBytes: 1024,
  duration: const Duration(minutes: 2),
);

Future<void> _openRenameSheet(
  WidgetTester tester,
  Future<void> Function(String) onRename,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => RenameRecordingSheet(
                recording: _recording,
                onRename: onRename,
              ),
            ),
            child: const Text('Open rename'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open rename'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('library offers Rename alongside Share and Delete', (
    tester,
  ) async {
    Recording? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingsList(
            recordings: [_recording],
            onOpen: (_) {},
            onRename: (recording) => selected = recording,
            onShare: (_) {},
            onDelete: (_) {},
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Recording actions'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(selected, same(_recording));
  });

  testWidgets('rename submits the trimmed title and closes after saving', (
    tester,
  ) async {
    final saved = Completer<void>();
    final names = <String>[];
    await _openRenameSheet(tester, (title) {
      names.add(title);
      return saved.future;
    });

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Meeting',
    );
    expect(find.text('.m4a'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Project notes  ');
    await tester.tap(find.text('Save name'));
    await tester.pump();

    expect(names, ['Project notes']);
    expect(find.byType(RenameRecordingSheet), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    saved.complete();
    await tester.pumpAndSettle();

    expect(find.byType(RenameRecordingSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rename retains the entered name after failure and allows retry',
    (tester) async {
      var attempts = 0;
      await _openRenameSheet(tester, (_) async {
        attempts++;
        if (attempts == 1) {
          throw PlatformException(
            code: 'exists',
            message: 'Name already exists.',
          );
        }
      });
      await tester.enterText(find.byType(TextField), 'Project notes');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();

      expect(find.text('Name already exists.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Project notes',
      );
      await tester.enterText(find.byType(TextField), 'Project notes 2');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.byType(RenameRecordingSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty names stay editable and Cancel makes no rename call', (
    tester,
  ) async {
    var attempts = 0;
    await _openRenameSheet(tester, (_) async {
      attempts++;
    });
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a file name.'), findsOneWidget);
    expect(attempts, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(attempts, 0);
    expect(find.byType(RenameRecordingSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
