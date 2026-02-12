import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('XTD-17: SGR 38/48 crashes on malformed sequences', () {
    test('SGR 38;5 with missing color index does not crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 38;5 m — missing the color value after "5"
      expect(() => terminal.write('\x1b[38;5m'), returnsNormally);
    });

    test('SGR 48;5 with missing color index does not crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 48;5 m — missing the color value after "5"
      expect(() => terminal.write('\x1b[48;5m'), returnsNormally);
    });

    test('SGR 38;2 with missing RGB values does not crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 38;2 m — missing r, g, b values
      expect(() => terminal.write('\x1b[38;2m'), returnsNormally);

      // CSI 38;2;255 m — missing g, b
      expect(() => terminal.write('\x1b[38;2;255m'), returnsNormally);

      // CSI 38;2;255;128 m — missing b
      expect(() => terminal.write('\x1b[38;2;255;128m'), returnsNormally);
    });

    test('SGR 48;2 with missing RGB values does not crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 48;2 m — missing r, g, b values
      expect(() => terminal.write('\x1b[48;2m'), returnsNormally);

      // CSI 48;2;255 m — missing g, b
      expect(() => terminal.write('\x1b[48;2;255m'), returnsNormally);

      // CSI 48;2;255;128 m — missing b
      expect(() => terminal.write('\x1b[48;2;255;128m'), returnsNormally);
    });

    test('SGR 38 alone (no mode) does not crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 38 m — missing the mode (2 or 5)
      expect(() => terminal.write('\x1b[38m'), returnsNormally);
    });

    test('SGR 48 alone (no mode) does not crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 48 m — missing the mode (2 or 5)
      expect(() => terminal.write('\x1b[48m'), returnsNormally);
    });

    test('SGR 38;5;196 with valid params still works', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Valid 256-color foreground
      terminal.write('\x1b[38;5;196m');
      // Should not crash and cursor style should reflect the color
      expect(terminal.cursor.foreground, isNotNull);
    });

    test('SGR 48;2;255;128;0 with valid params still works', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Valid RGB background
      terminal.write('\x1b[48;2;255;128;0m');
      expect(terminal.cursor.background, isNotNull);
    });
  });

  group('XTD-24: Origin mode (DECOM) issues', () {
    test('VPA respects origin mode (positions relative to scroll region)', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Enable origin mode (DECOM)
      terminal.write('\x1b[?6h');

      // Cursor should be homed to the top of the scroll region
      // In origin mode, cursor Y=0 maps to row 4 (0-based marginTop)
      expect(terminal.buffer.cursorY, 4); // marginTop is row 4 (0-based)

      // VPA to row 3 (1-based, relative to scroll region)
      // Should position at marginTop + 2 = row 6 (0-based)
      terminal.write('\x1b[3d');
      expect(terminal.buffer.cursorY, 6); // marginTop(4) + 2

      // VPA to row 1 (1-based) — top of scroll region
      terminal.write('\x1b[1d');
      expect(terminal.buffer.cursorY, 4); // marginTop(4) + 0

      // Disable origin mode
      terminal.write('\x1b[?6l');
    });

    test('setOriginMode homes cursor when enabled', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Move cursor to a non-home position
      terminal.write('\x1b[10;10H');
      expect(terminal.buffer.cursorY, 9);
      expect(terminal.buffer.cursorX, 9);

      // Enable origin mode - should home cursor to top of scroll region
      terminal.write('\x1b[?6h');
      expect(terminal.buffer.cursorY, 4); // marginTop (row 5, 0-based = 4)
      expect(terminal.buffer.cursorX, 0);
    });

    test('moveCursor does not double-apply origin mode offset', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Enable origin mode
      terminal.write('\x1b[?6h');

      // Move to row 3, col 1 (1-based relative to scroll region)
      terminal.write('\x1b[3;1H');
      expect(terminal.buffer.cursorY, 6); // marginTop(4) + 2

      // Now use relative cursor movement (CUU - cursor up 1)
      terminal.write('\x1b[1A');
      expect(terminal.buffer.cursorY, 5); // Should be 6-1=5, not double-offset

      // Cursor down 2 (CUD)
      terminal.write('\x1b[2B');
      expect(terminal.buffer.cursorY, 7); // 5 + 2 = 7

      // Disable origin mode
      terminal.write('\x1b[?6l');
    });

    test('CUP respects origin mode (positions relative to scroll region)', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Enable origin mode
      terminal.write('\x1b[?6h');

      // CUP to row 1, col 1 (1-based in origin mode)
      terminal.write('\x1b[1;1H');
      expect(terminal.buffer.cursorY, 4); // marginTop(4) + 0
      expect(terminal.buffer.cursorX, 0);

      // CUP to row 5, col 10 (1-based in origin mode)
      terminal.write('\x1b[5;10H');
      expect(terminal.buffer.cursorY, 8); // marginTop(4) + 4
      expect(terminal.buffer.cursorX, 9);

      // Disable origin mode
      terminal.write('\x1b[?6l');
    });
  });

  group('XTD-40: TBC treats all non-zero Ps as clear all', () {
    test('TBC Ps=0 clears tab stop at cursor', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first
      terminal.write('\x1b[3g');

      // Set tab stops at columns 5 and 10
      terminal.write('\x1b[6G'); // Move to column 6 (1-based) = col 5
      terminal.write('\x1bH'); // Set tab stop
      terminal.write('\x1b[11G'); // Move to column 11 (1-based) = col 10
      terminal.write('\x1bH'); // Set tab stop

      // Move to column 5 and clear tab stop at cursor (Ps=0)
      terminal.write('\x1b[6G'); // col 5
      terminal.write('\x1b[0g'); // Clear tab at cursor

      // Move to column 0 and tab
      terminal.write('\r');
      terminal.write('\t');

      // Should skip column 5 (cleared) and go to column 10
      expect(terminal.buffer.cursorX, 10);
    });

    test('TBC Ps=3 clears all tab stops', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Default tab stops exist at every 8 columns
      // Clear all tab stops
      terminal.write('\x1b[3g');

      // Tab from column 0 should go to end of line (no stops)
      terminal.write('\r');
      terminal.write('\t');

      // With no tab stops, tab goes to the last column (pending wrap)
      expect(terminal.buffer.cursorX, 79);
    });

    test('TBC Ps=1 is a no-op (does not clear any tab stops)', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first, then set a specific one
      terminal.write('\x1b[3g');

      // Set tab stop at column 5
      terminal.write('\x1b[6G'); // col 5
      terminal.write('\x1bH');

      // Try to clear with Ps=1 (should be a no-op per spec)
      terminal.write('\x1b[1g');

      // Tab from column 0 should still go to column 5
      terminal.write('\r');
      terminal.write('\t');
      expect(terminal.buffer.cursorX, 5);
    });

    test('TBC Ps=2 is a no-op (does not clear any tab stops)', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first, then set a specific one
      terminal.write('\x1b[3g');

      // Set tab stop at column 5
      terminal.write('\x1b[6G'); // col 5
      terminal.write('\x1bH');

      // Try to clear with Ps=2 (should be a no-op per spec)
      terminal.write('\x1b[2g');

      // Tab from column 0 should still go to column 5
      terminal.write('\r');
      terminal.write('\t');
      expect(terminal.buffer.cursorX, 5);
    });
  });

  group('XTD-46: VPA does not guard against param value 0', () {
    test('VPA with Ps=0 treats it as Ps=1 (row 1)', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Move cursor to row 10 first
      terminal.write('\x1b[10;1H');
      expect(terminal.buffer.cursorY, 9);

      // VPA with Ps=0 should go to row 1 (0-based: 0)
      terminal.write('\x1b[0d');
      expect(terminal.buffer.cursorY, 0);
    });

    test('VPA with Ps=1 goes to row 1', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Move cursor to row 10 first
      terminal.write('\x1b[10;1H');
      expect(terminal.buffer.cursorY, 9);

      // VPA with Ps=1 should go to row 1 (0-based: 0)
      terminal.write('\x1b[1d');
      expect(terminal.buffer.cursorY, 0);
    });

    test('VPA with Ps=5 goes to row 5', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // VPA with Ps=5 should go to row 5 (0-based: 4)
      terminal.write('\x1b[5d');
      expect(terminal.buffer.cursorY, 4);
    });

    test('VPA with no params defaults to row 1', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Move cursor to row 10 first
      terminal.write('\x1b[10;1H');
      expect(terminal.buffer.cursorY, 9);

      // VPA with no params
      terminal.write('\x1b[d');
      expect(terminal.buffer.cursorY, 0);
    });
  });
}
