import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('defaultInputHandler', () {
    test('supports numpad enter', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.keyInput(TerminalKey.numpadEnter);
      expect(output, ['\r']);
    });

    test('arrow keys use cursorKeysMode not appKeypadMode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      // Default: both modes off, arrow up should send \x1b[A
      terminal.keyInput(TerminalKey.arrowUp);
      expect(output.last, '\x1b[A');

      // Enable cursor keys mode (DECCKM) via CSI ?1h
      terminal.write('\x1b[?1h');
      expect(terminal.cursorKeysMode, isTrue);
      expect(terminal.appKeypadMode, isFalse);

      // Arrow up should now send \x1bOA (application cursor keys)
      terminal.keyInput(TerminalKey.arrowUp);
      expect(output.last, '\x1bOA');

      // Disable cursor keys mode, enable app keypad mode
      terminal.write('\x1b[?1l'); // DECCKM off
      terminal.write('\x1b='); // DECKPAM on
      expect(terminal.cursorKeysMode, isFalse);
      expect(terminal.appKeypadMode, isTrue);

      // Arrow up should send \x1b[A (normal cursor keys, not app)
      terminal.keyInput(TerminalKey.arrowUp);
      expect(output.last, '\x1b[A');
    });
  });

  group('KeytabInputHandler', () {
    test('can insert modifier code', () {
      final handler = KeytabInputHandler(
        Keytab.parse(r'key Home +AnyMod : "\E[1;*H"'),
      );

      final terminal = Terminal(inputHandler: handler);

      late String output;

      terminal.onOutput = (data) {
        output = data;
      };

      terminal.keyInput(TerminalKey.home, ctrl: true);

      expect(output, '\x1b[1;5H');

      terminal.keyInput(TerminalKey.home, shift: true);

      expect(output, '\x1b[1;2H');
    });
  });
}
