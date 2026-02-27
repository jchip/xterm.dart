import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets(
    'line picture cache is disabled for correctness under rapid redraw',
    (tester) async {
      final terminal = Terminal(maxLines: 300);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 220,
              child: TerminalView(
                terminal,
                textStyle: TerminalStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 500; i++) {
        terminal.write('line-$i\r\n');
      }
      await tester.pump();

      final renderTerminal = tester.renderObject<RenderTerminal>(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_TerminalView',
        ),
      );

      renderTerminal.markNeedsPaint();
      await tester.pump();

      final targetIndex = terminal.buffer.scrollBack + 2;
      final oldLineRef = terminal.buffer.lines[targetIndex];
      final nextLineRef = terminal.buffer.lines[targetIndex + 1];

      expect(identical(oldLineRef, nextLineRef), isFalse);
      expect(
        renderTerminal.debugIsLineCachedForIndex(targetIndex, oldLineRef),
        isFalse,
      );

      terminal.write('\x1b[1S');
      await tester.pump();

      renderTerminal.markNeedsPaint();
      await tester.pump();

      final newLineRef = terminal.buffer.lines[targetIndex];
      expect(identical(newLineRef, nextLineRef), isTrue);
      expect(
        renderTerminal.debugIsLineCachedForIndex(targetIndex, oldLineRef),
        isFalse,
      );

      renderTerminal.markNeedsPaint();
      await tester.pump();

      expect(
        renderTerminal.debugIsLineCachedForIndex(targetIndex, newLineRef),
        isFalse,
      );
    },
  );
}
