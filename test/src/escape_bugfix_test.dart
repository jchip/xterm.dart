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

    test('SGR 38 with unknown mode (e.g. mode 9) does not crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 38;9;1 m — mode 9 is not a valid color mode
      expect(() => terminal.write('\x1b[38;9;1m'), returnsNormally);
    });

    test('Valid 256-color: SGR 38;5;196 sets cursor foreground', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      terminal.write('\x1b[38;5;196m');

      // 196 | CellColor.palette should be the foreground value
      final expected = 196 | CellColor.palette;
      expect(terminal.cursor.foreground, equals(expected));
    });

    test('Valid truecolor: SGR 38;2;255;128;0 sets cursor foreground', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      terminal.write('\x1b[38;2;255;128;0m');

      // (255 << 16) | (128 << 8) | 0 | CellColor.rgb
      final expected = (255 << 16) | (128 << 8) | 0 | CellColor.rgb;
      expect(terminal.cursor.foreground, equals(expected));
    });

    test('Multiple SGR params with malformed 256-color sets bold, no crash', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // CSI 1;38;5 m — bold + truncated 256-color (missing color index)
      expect(() => terminal.write('\x1b[1;38;5m'), returnsNormally);
      // Bold should still be set
      expect(terminal.cursor.isBold, isTrue);
    });

    test('SGR 48;2 valid RGB sets background', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      terminal.write('\x1b[48;2;100;200;50m');

      final expected = (100 << 16) | (200 << 8) | 50 | CellColor.rgb;
      expect(terminal.cursor.background, equals(expected));
    });

    test('SGR followed by text preserves color on written cells', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set foreground to 256-color 196, then write text
      terminal.write('\x1b[38;5;196mHello');

      final line = terminal.buffer.lines[0];
      final expectedFg = 196 | CellColor.palette;
      // Check that each cell of "Hello" has the correct foreground
      for (var i = 0; i < 5; i++) {
        expect(line.getForeground(i), equals(expectedFg),
            reason: 'Cell $i should have 256-color foreground');
      }
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

    test('VPA clamps to bottom margin in origin mode', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Enable origin mode
      terminal.write('\x1b[?6h');

      // VPA Ps=20 (1-based, relative to scroll region)
      // Scroll region is 11 rows (5..15), so max relative row is 11
      // Should clamp to marginBottom = row 14 (0-based)
      terminal.write('\x1b[20d');
      expect(terminal.buffer.cursorY, 14); // marginBottom (row 15, 0-based = 14)

      // Disable origin mode
      terminal.write('\x1b[?6l');
    });

    test('Disabling origin mode does NOT home cursor', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Enable origin mode (this homes cursor to top of scroll region)
      terminal.write('\x1b[?6h');
      expect(terminal.buffer.cursorY, 4); // marginTop

      // Move cursor within scroll region
      terminal.write('\x1b[5;10H'); // row 5, col 10 (relative)
      expect(terminal.buffer.cursorY, 8); // marginTop(4) + 4
      expect(terminal.buffer.cursorX, 9);

      // Disable origin mode — cursor should stay where it is
      terminal.write('\x1b[?6l');
      expect(terminal.buffer.cursorY, 8);
      expect(terminal.buffer.cursorX, 9);
    });

    test('CUD in origin mode clamps at viewport bottom (not marginBottom)', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Enable origin mode
      terminal.write('\x1b[?6h');

      // Move to last row of scroll region
      terminal.write('\x1b[11;1H'); // row 11 relative = marginTop(4) + 10 = 14
      expect(terminal.buffer.cursorY, 14);

      // CUD 5 — moveCursorY clamps at viewHeight-1 (row 23), not marginBottom
      terminal.write('\x1b[5B');
      expect(terminal.buffer.cursorY, 19); // 14 + 5 = 19

      // Disable origin mode
      terminal.write('\x1b[?6l');
    });

    test('CUU in origin mode clamps at viewport top (not marginTop)', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Enable origin mode
      terminal.write('\x1b[?6h');

      // Cursor is at marginTop (row 4, 0-based) after enabling origin mode
      expect(terminal.buffer.cursorY, 4);

      // CUU 5 — moveCursorY clamps at 0 (viewport top), not marginTop
      terminal.write('\x1b[5A');
      expect(terminal.buffer.cursorY, 0); // clamps at viewport top

      // Disable origin mode
      terminal.write('\x1b[?6l');
    });

    test('Origin mode off: VPA uses absolute positioning', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Set scroll region to rows 5-15 (1-based)
      terminal.write('\x1b[5;15r');

      // Origin mode is off (default)
      // VPA Ps=2 should go to absolute row 2 (0-based: 1)
      terminal.write('\x1b[2d');
      expect(terminal.buffer.cursorY, 1);

      // VPA Ps=20 should go to absolute row 20 (0-based: 19)
      terminal.write('\x1b[20d');
      expect(terminal.buffer.cursorY, 19);
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

    test('TBC with default param (no param) clears tab at cursor', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first
      terminal.write('\x1b[3g');

      // Set tab stops at columns 5 and 10
      terminal.write('\x1b[6G'); // col 5
      terminal.write('\x1bH');
      terminal.write('\x1b[11G'); // col 10
      terminal.write('\x1bH');

      // Move to column 5 and clear tab stop with no param (defaults to 0)
      terminal.write('\x1b[6G');
      terminal.write('\x1b[g'); // TBC with no param

      // Tab from column 0 should skip column 5 and go to column 10
      terminal.write('\r');
      terminal.write('\t');
      expect(terminal.buffer.cursorX, 10);
    });

    test('TBC at position without a tab stop is a no-op', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first
      terminal.write('\x1b[3g');

      // Set tab stop at column 10
      terminal.write('\x1b[11G'); // col 10
      terminal.write('\x1bH');

      // Move to column 5 (no tab stop here) and try to clear
      terminal.write('\x1b[6G');
      terminal.write('\x1b[0g'); // Clear tab at cursor (no tab here)

      // Tab from column 0 should still go to column 10
      terminal.write('\r');
      terminal.write('\t');
      expect(terminal.buffer.cursorX, 10);
    });

    test('Multiple tab stops set, clear one, verify others remain', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first
      terminal.write('\x1b[3g');

      // Set tab stops at columns 5, 15, and 25
      terminal.write('\x1b[6G'); // col 5
      terminal.write('\x1bH');
      terminal.write('\x1b[16G'); // col 15
      terminal.write('\x1bH');
      terminal.write('\x1b[26G'); // col 25
      terminal.write('\x1bH');

      // Clear tab stop at column 15
      terminal.write('\x1b[16G');
      terminal.write('\x1b[0g');

      // Tab from column 0: should go to 5
      terminal.write('\r');
      terminal.write('\t');
      expect(terminal.buffer.cursorX, 5);

      // Tab from 5: should skip 15 (cleared) and go to 25
      terminal.write('\t');
      expect(terminal.buffer.cursorX, 25);
    });

    test('Large Ps value (Ps=100) is a no-op', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Clear all tab stops first, then set one
      terminal.write('\x1b[3g');

      // Set tab stop at column 5
      terminal.write('\x1b[6G');
      terminal.write('\x1bH');

      // TBC with Ps=100 — should be a no-op (not 0 or 3)
      terminal.write('\x1b[100g');

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

    test('VPA beyond viewHeight clamps to last row', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // VPA Ps=100 — well beyond 24 rows, should clamp to row 23 (0-based)
      terminal.write('\x1b[100d');
      expect(terminal.buffer.cursorY, 23);
    });

    test('VPA preserves cursor X position', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // Move cursor to column 15
      terminal.write('\x1b[1;16H'); // row 1, col 16 (1-based)
      expect(terminal.buffer.cursorX, 15);

      // VPA to row 10 — cursor X should remain at 15
      terminal.write('\x1b[10d');
      expect(terminal.buffer.cursorY, 9);
      expect(terminal.buffer.cursorX, 15);
    });

    test('VPA with Ps=24 in 24-row terminal goes to row 23', () {
      final terminal = Terminal();
      terminal.resize(80, 24);

      // VPA Ps=24 — last row (0-based: 23)
      terminal.write('\x1b[24d');
      expect(terminal.buffer.cursorY, 23);
    });
  });
}
