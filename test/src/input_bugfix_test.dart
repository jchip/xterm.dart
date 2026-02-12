import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/core/buffer/cell_flags.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/core/cell.dart';

void main() {
  group('XTD-32: Ctrl and Alt input handlers accept multi-modifier combinations', () {
    test('Ctrl+Shift+C produces Ctrl+C output (0x03)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyC, ctrl: true, shift: true);
      // Ctrl+C = 0x03 (keyC is 3rd letter, so index - keyA.index + 1 = 3)
      expect(output.last, String.fromCharCode(0x03));
    });

    test('Ctrl+Shift+A produces Ctrl+A output (0x01)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyA, ctrl: true, shift: true);
      expect(output.last, String.fromCharCode(0x01));
    });

    test('Ctrl+Shift+Z produces Ctrl+Z output (0x1a)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyZ, ctrl: true, shift: true);
      expect(output.last, String.fromCharCode(0x1a));
    });

    test('Ctrl without Shift still works (regression check)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyC, ctrl: true);
      expect(output.last, String.fromCharCode(0x03));
    });

    test('Alt+Shift+A sends ESC + lowercase a', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyA, alt: true, shift: true);
      // ESC (0x1b) + 'a' (0x61)
      expect(output.last, '\x1ba');
    });

    test('Alt+Shift+Z sends ESC + lowercase z', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyZ, alt: true, shift: true);
      expect(output.last, '\x1bz');
    });

    test('Alt without Shift still works (regression check)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyA, alt: true);
      expect(output.last, '\x1ba');
    });

    test('Ctrl+Shift+L produces form feed (0x0c)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyL, ctrl: true, shift: true);
      // Ctrl+L = 0x0c (L is 12th letter)
      expect(output.last, String.fromCharCode(0x0c));
    });

    test('Ctrl+Shift+D produces EOF (0x04)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyD, ctrl: true, shift: true);
      // Ctrl+D = 0x04 (D is 4th letter)
      expect(output.last, String.fromCharCode(0x04));
    });

    test('Alt+Shift+F sends ESC + f (emacs forward word)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyF, alt: true, shift: true);
      expect(output.last, '\x1bf');
    });

    test('Alt+Shift+B sends ESC + b (emacs backward word)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyB, alt: true, shift: true);
      expect(output.last, '\x1bb');
    });

    test('Ctrl+Alt+A is rejected by CtrlInputHandler (alt guard)', () {
      // CtrlInputHandler has a guard: if (!event.ctrl || event.alt) return null;
      // So Ctrl+Alt combinations should not be handled by CtrlInputHandler.
      final handler = CtrlInputHandler();
      final event = TerminalKeyboardEvent(
        key: TerminalKey.keyA,
        shift: false,
        ctrl: true,
        alt: true,
        state: Terminal(),
        altBuffer: false,
        platform: TerminalTargetPlatform.linux,
      );
      final result = handler.call(event);
      expect(result, isNull,
          reason: 'CtrlInputHandler must reject Ctrl+Alt combinations');
    });
  });

  group('XTD-41: CellFlags includes strikethrough flag', () {
    test('CellFlags.strikethrough constant exists', () {
      expect(CellFlags.strikethrough, isNotNull);
    });

    test('CellFlags.strikethrough equals 1 << 7 (bit 7)', () {
      expect(CellFlags.strikethrough, 1 << 7);
      expect(CellFlags.strikethrough, 128);
    });

    test('strikethrough bit does not overlap with other flags', () {
      final allFlags = [
        CellFlags.bold,
        CellFlags.faint,
        CellFlags.italic,
        CellFlags.underline,
        CellFlags.blink,
        CellFlags.inverse,
        CellFlags.invisible,
        CellFlags.strikethrough,
      ];

      // Each flag should be a unique power of 2
      for (var i = 0; i < allFlags.length; i++) {
        for (var j = i + 1; j < allFlags.length; j++) {
          expect(allFlags[i] & allFlags[j], 0,
              reason:
                  'Flag at index $i (${allFlags[i]}) overlaps with flag at index $j (${allFlags[j]})');
        }
      }
    });

    test('strikethrough can be combined with other flags via bitwise OR', () {
      final combined = CellFlags.bold | CellFlags.strikethrough;
      expect(combined & CellFlags.bold, isNonZero);
      expect(combined & CellFlags.strikethrough, isNonZero);
      expect(combined & CellFlags.italic, 0);
    });

    test('SGR 9 sets strikethrough on cursor attrs', () {
      final terminal = Terminal();
      terminal.write('\x1b[9m');
      expect(terminal.cursor.attrs & CellAttr.strikethrough, isNonZero,
          reason: 'SGR 9 should set strikethrough bit in cursor attrs');
    });

    test('SGR 29 resets strikethrough on cursor attrs', () {
      final terminal = Terminal();
      // First set strikethrough, then reset it
      terminal.write('\x1b[9m');
      expect(terminal.cursor.attrs & CellAttr.strikethrough, isNonZero);

      terminal.write('\x1b[29m');
      expect(terminal.cursor.attrs & CellAttr.strikethrough, 0,
          reason: 'SGR 29 should clear the strikethrough bit');
    });

    test('SGR 0 resets all attributes including strikethrough', () {
      final terminal = Terminal();
      // Set strikethrough and bold
      terminal.write('\x1b[1;9m');
      expect(terminal.cursor.attrs & CellAttr.strikethrough, isNonZero);
      expect(terminal.cursor.attrs & CellAttr.bold, isNonZero);

      // SGR 0 resets everything
      terminal.write('\x1b[0m');
      expect(terminal.cursor.attrs, 0,
          reason: 'SGR 0 should reset all attrs to zero');
    });

    test('SGR 1;9 sets both bold and strikethrough', () {
      final terminal = Terminal();
      terminal.write('\x1b[1;9m');
      expect(terminal.cursor.attrs & CellAttr.bold, isNonZero,
          reason: 'SGR 1 should set bold');
      expect(terminal.cursor.attrs & CellAttr.strikethrough, isNonZero,
          reason: 'SGR 9 should set strikethrough');
      // Other flags should remain unset
      expect(terminal.cursor.attrs & CellAttr.italic, 0);
      expect(terminal.cursor.attrs & CellAttr.underline, 0);
    });

    test('text written with strikethrough preserves flag in buffer cell', () {
      final terminal = Terminal();
      // Set strikethrough then write a character
      terminal.write('\x1b[9mX');

      // The character 'X' should be at column 0 of the current line.
      // After writing 'X', cursor moves to column 1, so the char is at col 0.
      final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
      // cursorX is now 1 (after writing 'X'), so the cell is at index 0
      final cellFlags = line.getAttributes(0);
      expect(cellFlags & CellAttr.strikethrough, isNonZero,
          reason:
              'Cell flags in buffer should preserve strikethrough from cursor attrs');

      // Also verify the character content is 'X'
      final codePoint = line.getCodePoint(0);
      expect(codePoint, 'X'.codeUnitAt(0));
    });
  });
}
