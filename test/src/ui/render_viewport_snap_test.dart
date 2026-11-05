import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Regression: the render box is sized by a tight parent (e.g. `Expanded` /
/// `Positioned.fill`), so its pixel height is rarely an exact multiple of the
/// cell height. The scroll/paint math steps in whole cells while the scroll
/// offset is cell-floored, so a fractional leftover used to push the bottom row
/// a sliver below the painted region — the cursor "hiding beyond the bottom"
/// after pressing Enter, plus a flickering stick-to-bottom. Snapping the
/// viewport height to whole cells keeps the active line fully visible.
void main() {
  RenderTerminal renderOf(WidgetTester tester) {
    return tester.renderObject<RenderTerminal>(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_TerminalView',
      ),
    );
  }

  testWidgets(
    'bottom line stays visible when viewport height is not a cell multiple',
    (tester) async {
      final terminal = Terminal(maxLines: 200);

      // 137px is deliberately not a multiple of any plausible cell height, so a
      // fractional leftover row remains at the bottom edge.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 137,
              child: TerminalView(
                terminal,
                textStyle: const TerminalStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );

      final render = renderOf(tester);
      final cellHeight = render.cellSize.height;

      // Guard: confirm this case actually exercises the fractional-leftover bug.
      // If the constants are ever changed to a cell-aligned height, this fails
      // loudly so the test keeps its teeth.
      final leftover = 137 % cellHeight;
      expect(
        leftover,
        greaterThan(0.01),
        reason: 'pick a height that is NOT a whole number of cells',
      );

      // Fill past the viewport so scrollback exists and the cursor sits on the
      // last line, stuck to the bottom — the case that used to clip.
      for (var i = 0; i < 60; i++) {
        terminal.write('line-$i\r\n');
      }
      await tester.pump();

      expect(
        terminal.buffer.lines.length,
        greaterThan(terminal.viewHeight),
        reason: 'precondition: there must be scrollback to scroll over',
      );

      final cursorTop = render.cursorOffset.dy;
      final cursorBottom = cursorTop + cellHeight;

      expect(cursorTop, greaterThanOrEqualTo(-0.01));
      expect(
        cursorBottom,
        lessThanOrEqualTo(render.size.height + 0.01),
        reason: 'the cursor cell must sit fully within the viewport, not below '
            'the bottom edge',
      );

      // The last buffer line (where the cursor lives when stuck to bottom) must
      // also be fully on-screen.
      final lastLineTop =
          render.getOffset(CellOffset(0, terminal.buffer.lines.length - 1)).dy;
      expect(
        lastLineTop + cellHeight,
        lessThanOrEqualTo(render.size.height + 0.01),
        reason: 'the bottom row must not be painted past the viewport',
      );
    },
  );

  testWidgets(
    'grid snaps to whole lines and columns with a sub-cell remainder',
    (tester) async {
      final terminal = Terminal(maxLines: 200);

      // Neither dimension is a whole number of cells.
      const boxWidth = 323.0;
      const boxHeight = 197.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: boxWidth,
              height: boxHeight,
              child: TerminalView(
                terminal,
                textStyle: const TerminalStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final render = renderOf(tester);
      final cellWidth = render.cellSize.width;
      final cellHeight = render.cellSize.height;

      // The grid reported to the app/PTY is exactly what fits in whole cells.
      expect(terminal.viewWidth, (boxWidth / cellWidth).floor());
      expect(terminal.viewHeight, (boxHeight / cellHeight).floor());

      // The painted grid fits, and the leftover on each axis is a clean
      // letterbox of less than one cell — never a partial row or column.
      final remainderW = render.size.width - terminal.viewWidth * cellWidth;
      final remainderH = render.size.height - terminal.viewHeight * cellHeight;
      expect(remainderW, inInclusiveRange(0, cellWidth));
      expect(remainderH, inInclusiveRange(0, cellHeight));
      expect(remainderW, lessThan(cellWidth));
      expect(remainderH, lessThan(cellHeight));
    },
  );

  testWidgets(
    'the box (including the sub-cell remainder) is filled with terminal background',
    (tester) async {
      final terminal = Terminal(maxLines: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              // Non-cell-multiple on purpose so a letterbox remainder exists.
              width: 251,
              height: 133,
              child: TerminalView(
                terminal,
                textStyle: const TerminalStyle(fontSize: 14),
                theme: TerminalThemes.whiteOnBlack,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The whole box is painted with the terminal background, so the leftover
      // strip on the right/bottom edges reads as an intentional letterbox.
      expect(
        find.byType(TerminalView),
        paints..rect(color: TerminalThemes.whiteOnBlack.background),
      );
    },
  );
}
