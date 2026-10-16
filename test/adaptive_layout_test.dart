// Wider windows (the web on a tablet or desktop): the layout helpers in widgets/adaptive.dart and
// the sheets that open as centred panels there. A phone keeps its layout exactly.
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/widgets/glass.dart';
import 'package:carden/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a phone keeps its margins, a desktop centres a column', () {
    for (final w in [320.0, 375.0, 402.0, 440.0, 599.0]) {
      expect(pageInset(w), 0, reason: 'phone width $w');
    }
    expect(pageInset(1440), 120);
    expect(pageInset(1440, maxWidth: PageWidth.reading), 360);
    // Narrower than the column: a small margin, never a negative one.
    expect(pageInset(1000), 12);
    expect(pageInset(700), 4);
  });

  test('grids: two columns on every phone, more on wider windows', () {
    for (final w in [280.0, 335.0, 362.0, 400.0, 520.0]) {
      expect(gridColumns(w), 2, reason: 'content width $w');
    }
    expect(gridColumns(680), 3);
    expect(gridColumns(1160), 5);
    expect(gridColumns(4000), 8);
  });

  testWidgets('window classes follow the breakpoints', (tester) async {
    final seen = <double, WindowClass>{};
    for (final w in [390.0, 768.0, 1440.0]) {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(w, 900)),
        child: Builder(builder: (context) {
          seen[w] = context.windowClass;
          return const SizedBox();
        }),
      ));
    }
    expect(seen, {390.0: WindowClass.compact, 768.0: WindowClass.medium, 1440.0: WindowClass.expanded});
  });

  Future<void> openSheet(WidgetTester tester, Size window) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(context, builder: (_) => const Padding(padding: EdgeInsets.all(20), child: Text('Sheet body'))),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('on a phone a sheet comes up from the bottom edge', (tester) async {
    await openSheet(tester, const Size(390, 844));
    final sheet = tester.widget<GlassSheet>(find.byType(GlassSheet));
    expect(sheet.panel, isFalse);
    expect(tester.getRect(find.byType(GlassSheet)).bottom, 844);
  });

  testWidgets('on a desktop a sheet is a centred panel', (tester) async {
    await openSheet(tester, const Size(1440, 900));
    final sheet = tester.widget<GlassSheet>(find.byType(GlassSheet));
    expect(sheet.panel, isTrue);
    final rect = tester.getRect(find.byType(GlassSheet));
    expect(rect.width, PageWidth.sheet);
    expect(rect.center.dx, closeTo(720, 1));
    expect(rect.center.dy, closeTo(450, 1));
    // Inside, the screen sees the panel, not the window: it keeps its phone layout.
    final inner = tester.element(find.text('Sheet body'));
    expect(MediaQuery.sizeOf(inner).width, PageWidth.sheet);
    expect(inner.isWide, isFalse);
    // A tap outside closes it.
    await tester.tapAt(const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsNothing);
  });
}
