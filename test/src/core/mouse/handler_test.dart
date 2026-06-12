import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Mode-matrix tests for motion reporting (XTD-80), driven through a real
/// [Terminal] so the DECSET parsing -> mouse handler -> reporter chain is
/// covered end to end.
void main() {
  group('Terminal.mouseInput motion matrix', () {
    Terminal terminalWith(String decset) {
      final terminal = Terminal();
      terminal.write(decset);
      return terminal;
    }

    test('mouseMode none never reports motion', () {
      final terminal = Terminal();
      String? output;
      terminal.onOutput = (data) => output = data;

      final handled = terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.moved,
        CellOffset(0, 0),
      );

      expect(handled, isFalse);
      expect(output, isNull);
    });

    test('clickOnly (DECSET 1000) reports down but not motion', () {
      final terminal = terminalWith('\x1b[?1000h');
      String? output;
      terminal.onOutput = (data) => output = data;

      expect(
        terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.moved,
          CellOffset(0, 0),
        ),
        isFalse,
      );
      expect(output, isNull);

      expect(
        terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          CellOffset(0, 0),
        ),
        isTrue,
      );
      expect(output, isNotNull);
    });

    test('button-event tracking (DECSET 1002) reports held-button motion only',
        () {
      final terminal = terminalWith('\x1b[?1002h\x1b[?1006h');
      String? output;
      terminal.onOutput = (data) => output = data;

      // Motion with a held button is reported...
      expect(
        terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.moved,
          CellOffset(2, 1),
        ),
        isTrue,
      );
      expect(output, equals('\x1b[<32;3;2M'));

      // ...but no-button motion is not.
      output = null;
      expect(
        terminal.mouseInput(
          TerminalMouseButton.none,
          TerminalMouseButtonState.moved,
          CellOffset(2, 1),
        ),
        isFalse,
      );
      expect(output, isNull);
    });

    test('any-event tracking (DECSET 1003) reports no-button motion', () {
      final terminal = terminalWith('\x1b[?1003h\x1b[?1006h');
      String? output;
      terminal.onOutput = (data) => output = data;

      expect(
        terminal.mouseInput(
          TerminalMouseButton.none,
          TerminalMouseButtonState.moved,
          CellOffset(4, 3),
        ),
        isTrue,
      );
      expect(output, equals('\x1b[<35;5;4M'));
    });

    test('wheel buttons never produce motion reports', () {
      final terminal = terminalWith('\x1b[?1003h\x1b[?1006h');
      String? output;
      terminal.onOutput = (data) => output = data;

      expect(
        terminal.mouseInput(
          TerminalMouseButton.wheelUp,
          TerminalMouseButtonState.moved,
          CellOffset(0, 0),
        ),
        isFalse,
      );
      expect(output, isNull);
    });

    test('the none pseudo-button is not reportable as press/release', () {
      final terminal = terminalWith('\x1b[?1003h\x1b[?1006h');
      String? output;
      terminal.onOutput = (data) => output = data;

      expect(
        terminal.mouseInput(
          TerminalMouseButton.none,
          TerminalMouseButtonState.down,
          CellOffset(0, 0),
        ),
        isFalse,
      );
      expect(output, isNull);
    });
  });
}
