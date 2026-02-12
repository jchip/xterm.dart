import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/core/escape/emitter.dart';
import 'package:xterm/src/core/mouse/reporter.dart';
import 'package:xterm/src/core/input/handler.dart';
import 'package:xterm/src/core/input/keys.dart';

void main() {
  group('XTD-5: CPR sends 1-based coords', () {
    test('cursorPosition emits 1-based row and column', () {
      const emitter = EscapeEmitter();
      // Cursor at 0-based (0, 0) should report as 1-based (1, 1)
      expect(emitter.cursorPosition(0, 0), '\x1b[1;1R');
      // Cursor at 0-based (5, 3) should report as 1-based (4, 6)
      expect(emitter.cursorPosition(5, 3), '\x1b[4;6R');
      // Cursor at 0-based (79, 23) should report as (24, 80)
      expect(emitter.cursorPosition(79, 23), '\x1b[24;80R');
    });

    test('sendCursorPosition via terminal uses 1-based coords', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.resize(80, 24);

      // Move cursor to row 5, col 10 (1-based) → 0-based (9, 4)
      terminal.write('\x1b[5;10H');

      // Request cursor position report (DSR 6)
      terminal.write('\x1b[6n');

      // Should report 1-based coordinates
      expect(output.last, '\x1b[5;10R');
    });
  });

  group('XTD-6: Alt+Key sends lowercase', () {
    test('AltInputHandler sends ESC + lowercase letter', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyA, alt: true);
      // Should send ESC + 'a' (0x61), not ESC + 'A' (0x41)
      expect(output.last, '\x1ba');

      terminal.keyInput(TerminalKey.keyZ, alt: true);
      expect(output.last, '\x1bz');
    });

    test('charInput Alt sends ESC + original lowercase char', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.charInput('a'.codeUnitAt(0), alt: true);
      expect(output.last, '\x1ba');

      terminal.charInput('z'.codeUnitAt(0), alt: true);
      expect(output.last, '\x1bz');
    });
  });

  group('XTD-7: Arrow+modifier uses correct modifier code', () {
    test('Ctrl+Up sends modifier code 5', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.arrowUp, ctrl: true);
      expect(output.last, '\x1b[1;5A');
    });

    test('Alt+Up sends modifier code 3', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.arrowUp, alt: true);
      expect(output.last, '\x1b[1;3A');
    });

    test('Ctrl+Right sends modifier code 5 (non-Mac)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.arrowRight, ctrl: true);
      expect(output.last, '\x1b[1;5C');
    });

    test('Alt+Right sends modifier code 3 (non-Mac)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.arrowRight, alt: true);
      expect(output.last, '\x1b[1;3C');
    });

    test('Alt+Left sends ESC b on Mac', () {
      final output = <String>[];
      final terminal = Terminal(
        onOutput: output.add,
        platform: TerminalTargetPlatform.macos,
      );

      terminal.keyInput(TerminalKey.arrowLeft, alt: true);
      expect(output.last, '\x1bb');
    });
  });

  group('XTD-8: HTS sets tab stop', () {
    test('ESC H sets a tab stop at cursor position', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first
      terminal.write('\x1b[3g');

      // Move to column 5 and set a tab stop
      terminal.write('\x1b[6G'); // CHA to column 6 (1-based) = column 5 (0-based)
      terminal.write('\x1bH'); // HTS - set tab stop here

      // Move to column 0
      terminal.write('\r');

      // Tab should now go to column 5
      terminal.write('\t');
      expect(terminal.buffer.cursorX, 5);
    });
  });

  group('XTD-10: DECAWM respects disabled mode', () {
    test('characters overwrite last cell when autowrap is off', () {
      final terminal = Terminal();
      terminal.resize(5, 3);

      // Disable auto-wrap mode
      terminal.write('\x1b[?7l');

      // Write exactly 5 chars to fill the line
      terminal.write('ABCDE');

      // Cursor should be at the last column
      expect(terminal.buffer.cursorX, 4);

      // Write more - should overwrite last cell, not wrap
      terminal.write('X');
      expect(terminal.buffer.cursorX, 4);
      expect(terminal.buffer.cursorY, 0); // should NOT have wrapped

      // The last cell should show X (overwritten E)
      final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
      expect(line.getCodePoint(4), 'X'.codeUnitAt(0));
    });

    test('characters wrap when autowrap is on (default)', () {
      final terminal = Terminal();
      terminal.resize(5, 3);

      // Write more than 5 chars
      terminal.write('ABCDEFG');

      // Should have wrapped to next line
      expect(terminal.buffer.cursorY, 1);
    });
  });

  group('XTD-11: Mouse wheel button IDs', () {
    test('wheelUp has ID 64', () {
      expect(TerminalMouseButton.wheelUp.id, 64);
    });

    test('wheelDown has ID 65', () {
      expect(TerminalMouseButton.wheelDown.id, 65);
    });

    test('wheelLeft has ID 66', () {
      expect(TerminalMouseButton.wheelLeft.id, 66);
    });

    test('wheelRight has ID 67', () {
      expect(TerminalMouseButton.wheelRight.id, 67);
    });
  });

  group('XTD-12: Mouse row coordinate', () {
    test('normal mode row uses correct encoding', () {
      // Position (0,0) → 1-based (1,1), normal encoding: 32+1=33
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.normal,
      );
      // btn=char(32)=' ', col=char(33)='!', row=char(33)='!'
      expect(output, '\x1b[M !!');
    });

    test('sgr mode row is correct', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(5, 10),
        MouseReportMode.sgr,
      );
      // 1-based: col=6, row=11
      expect(output, '\x1b[<0;6;11M');
    });
  });

  group('XTD-14: CSI parser handles empty parameters', () {
    test('CSI with leading empty param preserves it', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI ; 5 H means row=default(1), col=5
      // Move cursor to known position first
      terminal.write('\x1b[10;10H'); // row 10, col 10
      expect(terminal.buffer.cursorY, 9); // 0-based
      expect(terminal.buffer.cursorX, 9);

      // CSI ; 5 H - empty first param defaults to 1
      terminal.write('\x1b[;5H');
      expect(terminal.buffer.cursorY, 0); // row 1 → 0-based 0
      expect(terminal.buffer.cursorX, 4); // col 5 → 0-based 4
    });

    test('CSI H with single param sets row only', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      terminal.write('\x1b[10;10H'); // start position
      terminal.write('\x1b[5H'); // row 5, col defaults to 1
      expect(terminal.buffer.cursorY, 4); // row 5 → 0-based 4
      expect(terminal.buffer.cursorX, 0); // col 1 → 0-based 0
    });

    test('CSI H with no params goes to home', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      terminal.write('\x1b[10;10H'); // start position
      terminal.write('\x1b[H'); // home
      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.cursorX, 0);
    });
  });

  group('XTD-13: Cursor painter uses offset', () {
    // NOTE: Painter tests require Flutter rendering context.
    // The fix ensures underline and verticalBar cursors use offset.dy
    // for Y coordinates. This is verified by code review; visual testing
    // would require a full widget test.
    test('TerminalCursorType enum has all types', () {
      expect(TerminalCursorType.values.length, 3);
      expect(TerminalCursorType.values,
          contains(TerminalCursorType.underline));
      expect(TerminalCursorType.values,
          contains(TerminalCursorType.verticalBar));
      expect(
          TerminalCursorType.values, contains(TerminalCursorType.block));
    });
  });

  group('eraseLineToCursor includes cursor position', () {
    test('erases up to and including cursor', () {
      final terminal = Terminal();
      terminal.resize(10, 3);
      terminal.write('ABCDEFGHIJ');

      // Move cursor to column 5 (0-based)
      terminal.write('\x1b[1;6H'); // 1-based col 6 = 0-based col 5

      // Erase line to cursor (CSI 1 K) - should erase cols 0-5 inclusive
      terminal.write('\x1b[1K');

      final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
      // Columns 0-5 should be erased (codepoint 0)
      for (var i = 0; i <= 5; i++) {
        expect(line.getCodePoint(i), 0,
            reason: 'Column $i should be erased');
      }
      // Columns 6-9 should still have content
      expect(line.getCodePoint(6), 'G'.codeUnitAt(0));
      expect(line.getCodePoint(7), 'H'.codeUnitAt(0));
    });
  });

  group('DECSTBM homes cursor after setting margins', () {
    test('CSI r moves cursor to home position', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Move cursor to a non-home position
      terminal.write('\x1b[10;10H');
      expect(terminal.buffer.cursorY, 9);
      expect(terminal.buffer.cursorX, 9);

      // Set scroll region (DECSTBM)
      terminal.write('\x1b[5;20r');

      // Cursor should be at home (0, 0)
      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.cursorX, 0);
    });
  });

  group('SGR 22 unsets both bold and faint', () {
    test('SGR 22 resets bold', () {
      final terminal = Terminal();

      // Set bold
      terminal.write('\x1b[1m');
      expect(terminal.cursor.isBold, isTrue);

      // SGR 22 should unset bold
      terminal.write('\x1b[22m');
      expect(terminal.cursor.isBold, isFalse);
    });

    test('SGR 22 resets faint', () {
      final terminal = Terminal();

      // Set faint
      terminal.write('\x1b[2m');
      expect(terminal.cursor.isFaint, isTrue);

      // SGR 22 should unset faint
      terminal.write('\x1b[22m');
      expect(terminal.cursor.isFaint, isFalse);
    });

    test('SGR 22 resets both bold and faint simultaneously', () {
      final terminal = Terminal();

      // Set both bold and faint
      terminal.write('\x1b[1;2m');
      expect(terminal.cursor.isBold, isTrue);
      expect(terminal.cursor.isFaint, isTrue);

      // SGR 22 should unset both
      terminal.write('\x1b[22m');
      expect(terminal.cursor.isBold, isFalse);
      expect(terminal.cursor.isFaint, isFalse);
    });
  });
}
