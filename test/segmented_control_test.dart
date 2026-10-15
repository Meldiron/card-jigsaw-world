import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's segmented control (design QA 071): one glass control for Social, the Account form and
/// Settings > Theme. Taps, drags of the thumb, VoiceOver and a trailing slot without a width.
void main() {
  Future<List<int>> pump(WidgetTester tester, {required Widget Function(int value, ValueChanged<int> onChanged) build}) async {
    final changes = <int>[];
    var value = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => build(value, (v) {
            changes.add(v);
            setState(() => value = v);
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return changes;
  }

  Widget control(int value, ValueChanged<int> onChanged) => AppSegmentedControl<int>(value: value, segments: const {0: 'Leaderboard', 1: 'Friends'}, onChanged: onChanged);

  testWidgets('a tap on a segment selects it; a tap on the selected one changes nothing', (tester) async {
    final changes = await pump(tester, build: (v, on) => Padding(padding: const EdgeInsets.all(20), child: control(v, on)));
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(changes, [1]);
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(changes, [1]);
    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    expect(changes, [1, 0]);
  });

  testWidgets('the thumb can be dragged to the other segment', (tester) async {
    final changes = await pump(tester, build: (v, on) => Padding(padding: const EdgeInsets.all(20), child: control(v, on)));
    final from = tester.getCenter(find.text('Leaderboard'));
    final to = tester.getCenter(find.text('Friends'));
    await tester.dragFrom(from, to - from);
    await tester.pumpAndSettle();
    expect(changes, [1]);
  });

  testWidgets('VoiceOver can pick a segment', (tester) async {
    final handle = tester.ensureSemantics();
    final changes = await pump(tester, build: (v, on) => Padding(padding: const EdgeInsets.all(20), child: control(v, on)));
    tester.semantics.tap(find.semantics.byLabel('Friends'));
    await tester.pumpAndSettle();
    expect(changes, [1]);
    handle.dispose();
  });

  testWidgets('in a row trailing slot it takes the width of its labels, not the row', (tester) async {
    await pump(
      tester,
      build: (v, on) => Row(children: [const Expanded(child: Text('Theme')), AppSegmentedControl<int>(value: v, segments: const {0: 'Auto', 1: 'Light', 2: 'Dark'}, onChanged: on)]),
    );
    expect(tester.takeException(), isNull);
    final width = tester.getSize(find.byType(AppSegmentedControl<int>)).width;
    expect(width, greaterThan(100));
    expect(width, lessThan(260));
  });
}
