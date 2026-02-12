import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/core/buffer/cell_flags.dart';
import 'package:xterm/src/core/input/keys.dart';

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
  });
}
