import 'dart:math' as math;
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/widgets/circular_eq_dial.dart';

void main() {
  testWidgets(
    'vertical adjustment previews locally and commits within bounds',
    (tester) async {
      for (final direction in [-1.0, 1.0]) {
        final updates = <double>[];
        await _showDial(tester, onChanged: updates.add);
        final gesture = await tester.startGesture(tester.getCenter(_knob));
        // A fast first move must still use the original center touch position.
        await gesture.moveBy(Offset(0, direction * 60));
        await gesture.moveBy(Offset(0, direction * 200));
        await tester.pump();

        expect(updates, isEmpty);
        expect(find.text(direction < 0 ? '+12 dB' : '-12 dB'), findsOneWidget);
        await gesture.up();
        await tester.pump();
        expect(updates, [-direction]);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('cancel restores the latest preset without committing a drag', (
    tester,
  ) async {
    final gain = ValueNotifier<double>(0.25);
    addTearDown(gain.dispose);
    final updates = <double>[];
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder<double>(
          valueListenable: gain,
          builder: (context, value, _) => CircularEqDial(
            label: 'Bass',
            value: value,
            onChanged: updates.add,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(_knob));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(find.text('+3 dB'), findsNothing);

    gain.value = -0.5;
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(updates, isEmpty);
    expect(find.text('-6 dB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rim rotation adjusts both directions across the angle boundary',
    (tester) async {
      for (final direction in [-1.0, 1.0]) {
        final updates = <double>[];
        await _showDial(tester, onChanged: updates.add);
        final rect = tester.getRect(_knob);
        final radius = rect.width * 0.42;
        Offset point(double degrees) {
          final angle = degrees * math.pi / 180;
          return rect.center +
              Offset(math.cos(angle), math.sin(angle)) * radius;
        }

        // Both paths cross atan2's -pi/pi boundary on the left of the knob.
        final startAngle = direction > 0 ? 150.0 : 210.0;
        final gesture = await tester.startGesture(point(startAngle));
        for (var step = 1; step <= 5; step++) {
          await gesture.moveTo(point(startAngle + direction * step * 20));
          await tester.pump();
        }
        expect(updates, isEmpty);
        await gesture.up();
        await tester.pump();

        expect(updates, hasLength(1));
        expect(updates.single * direction, greaterThan(0.2));
        expect(updates.single.abs(), lessThan(1));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('preset updates and accessible adjustments share the same gain', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final gain = ValueNotifier<double>(0);
      addTearDown(gain.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<double>(
            valueListenable: gain,
            builder: (context, value, _) => CircularEqDial(
              label: 'Bass',
              value: value,
              onChanged: (value) => gain.value = value,
            ),
          ),
        ),
      );

      gain.value = 0.5;
      await tester.pump();
      final node = tester.getSemantics(find.byType(CircularEqDial));
      final data = node.getSemanticsData();
      expect(data.label, 'Bass gain');
      expect(data.value, '+6 dB');
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;
      owner.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(gain.value, closeTo(0.6, 0.0001));
      expect(find.text('+7 dB'), findsOneWidget);

      owner.performAction(node.id, SemanticsAction.decrease);
      await tester.pump();
      expect(gain.value, closeTo(0.5, 0.0001));

      gain.value = 1;
      await tester.pump();
      owner.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(gain.value, 1);
      expect(find.text('+12 dB'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a larger requested knob fits a narrow available column', (
    tester,
  ) async {
    await _showDial(tester, size: 144, width: 80, onChanged: (_) {});

    final knobSize = tester.getSize(_knob);
    expect(knobSize.width, lessThanOrEqualTo(80));
    expect(knobSize.height, knobSize.width);
    expect(find.text('0 dB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _knob = find.byKey(const ValueKey('eq-dial-Bass'));

Future<void> _showDial(
  WidgetTester tester, {
  double size = 112,
  double width = 144,
  required ValueChanged<double> onChanged,
}) => tester.pumpWidget(
  _host(
    SizedBox(
      width: width,
      child: CircularEqDial(
        label: 'Bass',
        value: 0,
        size: size,
        onChanged: onChanged,
      ),
    ),
  ),
);

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: Center(child: child)),
);
