import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('Buffer.getText()', () {
    test('should return the text', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.getText(), startsWith('Hello World'));
    });

    test('can handle line wrap', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      final line1 = 'This is a long line that should wrap';
      final line2 = 'This is a short line';
      final line3 = 'This is a long long long long line that should wrap';
      final line4 = 'Short';

      terminal.write('$line1\r\n');
      terminal.write('$line2\r\n');
      terminal.write('$line3\r\n');
      terminal.write('$line4\r\n');

      final lines = terminal.buffer.getText().split('\n');
      expect(lines[0], line1);
      expect(lines[1], line2);
      expect(lines[2], line3);
      expect(lines[3], line4);
    });

    test('can handle negative start', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(-100, -100), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle invalid end', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(0, 0), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle reversed range', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(5, 5), CellOffset(0, 0)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle block range', () {
      final terminal = Terminal();

      terminal.write('Hello World\r\n');
      terminal.write('Nice to meet you\r\n');

      expect(
        terminal.buffer.getText(
          BufferRangeBlock(CellOffset(2, 0), CellOffset(5, 1)),
        ),
        startsWith('llo\nce '),
      );
    });
  });

  group('Buffer.resize()', () {
    test('should resize the buffer', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      expect(terminal.viewWidth, 10);
      expect(terminal.viewHeight, 10);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 10);
      }

      terminal.resize(20, 20);

      expect(terminal.viewWidth, 20);
      expect(terminal.viewHeight, 20);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 20);
      }
    });
  });

  group('Buffer.deleteLines()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      for (var i = 1; i <= 10; i++) {
        terminal.write('line$i');

        if (i < 10) {
          terminal.write('\r\n');
        }
      }

      terminal.setMargins(3, 7);
      terminal.setCursor(0, 5);

      terminal.buffer.deleteLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line3');
      expect(terminal.buffer.lines[3].toString(), 'line4');
      expect(terminal.buffer.lines[4].toString(), 'line5');
      expect(terminal.buffer.lines[5].toString(), 'line7');
      expect(terminal.buffer.lines[6].toString(), 'line8');
      expect(terminal.buffer.lines[7].toString(), '');
      expect(terminal.buffer.lines[8].toString(), 'line9');
      expect(terminal.buffer.lines[9].toString(), 'line10');
    });
  });

  group('Buffer.insertLines()', () {
    test('works', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      print(terminal.buffer);

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 4);

      print(terminal.buffer.absoluteCursorY);

      terminal.buffer.insertLines(1);

      print(terminal.buffer);

      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), ''); // inserted
      expect(terminal.buffer.lines[5].toString(), 'line4'); // moved
      expect(terminal.buffer.lines[6].toString(), 'line5'); // moved
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });

    test('has no effect if cursor is out of scroll region', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 1);

      terminal.buffer.insertLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line2');
      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), 'line4');
      expect(terminal.buffer.lines[5].toString(), 'line5');
      expect(terminal.buffer.lines[6].toString(), 'line6');
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });
  });

  group('Buffer.getWordBoundary supports custom word separators', () {
    test('can set word separators', () {
      final terminal = Terminal(wordSeparators: {'o'.codeUnitAt(0)});

      terminal.write('Hello World');

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(0, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(4, 0)),
      );

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(5, 0)),
        BufferRangeLine(CellOffset(5, 0), CellOffset(7, 0)),
      );
    });
  });

  test('does not delete lines beyond the scroll region', () {
    final terminal = Terminal();
    terminal.resize(10, 10);

    for (var i = 1; i <= 10; i++) {
      terminal.write('line$i');

      if (i < 10) {
        terminal.write('\r\n');
      }
    }

    terminal.setMargins(3, 7);
    terminal.setCursor(0, 5);

    terminal.buffer.deleteLines(20);

    expect(terminal.buffer.lines[2].toString(), 'line3');
    expect(terminal.buffer.lines[3].toString(), 'line4');
    expect(terminal.buffer.lines[4].toString(), 'line5');
    expect(terminal.buffer.lines[5].toString(), '');
    expect(terminal.buffer.lines[6].toString(), '');
    expect(terminal.buffer.lines[7].toString(), '');
    expect(terminal.buffer.lines[8].toString(), 'line9');
    expect(terminal.buffer.lines[9].toString(), 'line10');
  });

  group('Buffer.eraseDisplayFromCursor()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(3, 3);
      terminal.write('123\r\n456\r\n789');

      terminal.setCursor(1, 1);
      terminal.buffer.eraseDisplayFromCursor();

      expect(terminal.buffer.lines[0].toString(), '123');
      expect(terminal.buffer.lines[1].toString(), '4');
      expect(terminal.buffer.lines[2].toString(), '');
    });
  });

  group('Buffer.eraseDisplay()', () {
    test('pushes viewport lines to scrollback on main buffer', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.resize(10, 5);

      // Write 5 lines to fill the viewport
      terminal.write('line1\r\n');
      terminal.write('line2\r\n');
      terminal.write('line3\r\n');
      terminal.write('line4\r\n');
      terminal.write('line5');

      // Verify initial state - no scrollback yet
      expect(terminal.buffer.scrollBack, 0);
      expect(terminal.buffer.height, 5);

      // Clear the display
      terminal.buffer.eraseDisplay();

      // After clear, should have 5 lines in scrollback and 5 empty viewport lines
      expect(terminal.buffer.scrollBack, 5);
      expect(terminal.buffer.height, 10);

      // Verify the old content is in scrollback
      expect(terminal.buffer.lines[0].toString(), startsWith('line1'));
      expect(terminal.buffer.lines[1].toString(), startsWith('line2'));
      expect(terminal.buffer.lines[2].toString(), startsWith('line3'));
      expect(terminal.buffer.lines[3].toString(), startsWith('line4'));
      expect(terminal.buffer.lines[4].toString(), startsWith('line5'));

      // Verify viewport (lines 5-9) is now empty
      expect(terminal.buffer.lines[5].toString(), '');
      expect(terminal.buffer.lines[6].toString(), '');
      expect(terminal.buffer.lines[7].toString(), '');
      expect(terminal.buffer.lines[8].toString(), '');
      expect(terminal.buffer.lines[9].toString(), '');

      // Cursor should be at top
      expect(terminal.buffer.cursorY, 0);
    });

    test('erases in place on alt buffer', () {
      final terminal = Terminal();
      terminal.resize(10, 3);

      // Write to main buffer first
      terminal.write('main1\r\n');
      terminal.write('main2\r\n');
      terminal.write('main3');

      // Switch to alt buffer and write
      terminal.write('\x1b[?1047h'); // Enable alt screen
      terminal.write('alt1\r\n');
      terminal.write('alt2\r\n');
      terminal.write('alt3');

      final initialHeight = terminal.buffer.height;

      // Clear alt buffer
      terminal.buffer.eraseDisplay();

      // Should not create scrollback on alt buffer
      expect(terminal.buffer.height, initialHeight);

      // Viewport should be cleared
      expect(terminal.buffer.lines[0].toString(), '');
      expect(terminal.buffer.lines[1].toString(), '');
      expect(terminal.buffer.lines[2].toString(), '');
    });

    test('handles multiple clears preserving all content', () {
      final terminal = Terminal(maxLines: 1000);
      terminal.resize(10, 3);

      // First set of content
      terminal.write('first1\r\n');
      terminal.write('first2\r\n');
      terminal.write('first3');

      // First clear
      terminal.buffer.eraseDisplay();
      expect(terminal.buffer.scrollBack, 3);

      // Second set of content
      terminal.write('second1\r\n');
      terminal.write('second2\r\n');
      terminal.write('second3');

      // Second clear
      terminal.buffer.eraseDisplay();
      expect(terminal.buffer.scrollBack, 6);

      // Verify both sets are in scrollback
      expect(terminal.buffer.lines[0].toString(), startsWith('first1'));
      expect(terminal.buffer.lines[1].toString(), startsWith('first2'));
      expect(terminal.buffer.lines[2].toString(), startsWith('first3'));
      expect(terminal.buffer.lines[3].toString(), startsWith('second1'));
      expect(terminal.buffer.lines[4].toString(), startsWith('second2'));
      expect(terminal.buffer.lines[5].toString(), startsWith('second3'));
    });
  });
}
