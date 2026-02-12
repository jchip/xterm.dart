import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';
import 'package:xterm/src/core/input/keytab/keytab_escape.dart';
import 'package:xterm/src/core/input/keys.dart';

void main() {
  group('XTD-35: Return vs Enter key identity mismatch', () {
    test('terminal.keyInput(TerminalKey.enter) produces output', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      final result = terminal.keyInput(TerminalKey.enter);
      expect(result, isTrue, reason: 'Enter key should produce output');
      expect(output.last, '\r');
    });

    test('Shift+Enter sends the right sequence (\\EOM)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.enter, shift: true);
      // \EOM unescaped is ESC O M
      expect(output.last, '\x1bOM');
    });

    test('Enter with newline mode sends \\r\\n', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.resize(80, 24);

      // Enable newline mode (LNM): CSI 20 h
      terminal.write('\x1b[20h');

      terminal.keyInput(TerminalKey.enter);
      expect(output.last, '\r\n');
    });

    test('keytab default entries use Enter not Return', () {
      final keytab = Keytab.defaultKeytab;

      // TerminalKey.enter should find a match (previously used returnKey)
      final record = keytab.find(TerminalKey.enter);
      expect(record, isNotNull,
          reason: 'Keytab should have entries for TerminalKey.enter');

      // TerminalKey.returnKey should NOT find a basic match anymore
      final returnRecord = keytab.find(TerminalKey.returnKey);
      expect(returnRecord, isNull,
          reason:
              'Keytab should not have entries for TerminalKey.returnKey (unmapped from Flutter)');
    });

    test('numpadEnter produces \\r (regression)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      final result = terminal.keyInput(TerminalKey.numpadEnter);
      expect(result, isTrue, reason: 'numpadEnter should produce output');
      expect(output.last, '\r');
    });

    test('TerminalKey.returnKey and TerminalKey.enter are distinct enum values',
        () {
      expect(TerminalKey.returnKey, isNot(equals(TerminalKey.enter)),
          reason: 'returnKey and enter must be distinct enum values');
      expect(TerminalKey.returnKey.index, isNot(equals(TerminalKey.enter.index)),
          reason: 'returnKey and enter must have different enum indices');
    });

    test('Enter in newline mode sends \\r\\n (verify still works after change)',
        () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.resize(80, 24);

      // Enable newline mode (LNM): CSI 20 h
      terminal.write('\x1b[20h');

      terminal.keyInput(TerminalKey.enter);
      expect(output.last, '\r\n',
          reason: 'Enter in newline mode must send \\r\\n');
    });
  });

  group('XTD-37: Alt+Backspace sends ESC DEL instead of Ctrl+W', () {
    test('Alt+Backspace sends ESC DEL (\\x1b\\x7f)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace, alt: true);
      // Should be ESC (0x1b) + DEL (0x7f)
      expect(output.last, '\x1b\x7f');
    });

    test('Alt+Backspace does not send Ctrl+W (0x17)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace, alt: true);
      expect(output.last, isNot('\x17'),
          reason: 'Alt+Backspace should not send Ctrl+W');
    });

    test('keytab Alt+Backspace record has correct value', () {
      final keytab = Keytab.defaultKeytab;
      final record = keytab.find(TerminalKey.backspace, alt: true);
      expect(record, isNotNull);
      expect(record!.action.unescapedValue(), '\x1b\x7f');
    });

    test('Regular Backspace sends DEL (0x7f)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace);
      expect(output.last, '\x7f',
          reason: 'Unmodified Backspace should send DEL (0x7f)');
    });

    test('Alt+Backspace output is exactly 2 chars long', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace, alt: true);
      expect(output.last.length, 2,
          reason: 'Alt+Backspace should produce exactly 2 characters');
    });

    test('Alt+Backspace first char is ESC, second is DEL', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace, alt: true);
      expect(output.last.codeUnitAt(0), 0x1b,
          reason: 'First char should be ESC (0x1b)');
      expect(output.last.codeUnitAt(1), 0x7f,
          reason: 'Second char should be DEL (0x7f)');
    });
  });

  group('XTD-38: Modified F1-F4 use CSI format instead of SS3', () {
    test('Ctrl+F1 sends \\x1b[1;5P (CSI format)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f1, ctrl: true);
      expect(output.last, '\x1b[1;5P');
    });

    test('Ctrl+F2 sends \\x1b[1;5Q', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f2, ctrl: true);
      expect(output.last, '\x1b[1;5Q');
    });

    test('Ctrl+F3 sends \\x1b[1;5R', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f3, ctrl: true);
      expect(output.last, '\x1b[1;5R');
    });

    test('Ctrl+F4 sends \\x1b[1;5S', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f4, ctrl: true);
      expect(output.last, '\x1b[1;5S');
    });

    test('Alt+F1 sends \\x1b[1;3P', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f1, alt: true);
      expect(output.last, '\x1b[1;3P');
    });

    test('Shift+F1 sends \\x1b[1;2P', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f1, shift: true);
      expect(output.last, '\x1b[1;2P');
    });

    test('Ctrl+F1 does not use SS3 format', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f1, ctrl: true);
      // Should NOT start with \x1bO (SS3)
      expect(output.last.startsWith('\x1bO'), isFalse,
          reason: 'Modified F1 should use CSI format, not SS3');
    });

    test('unmodified F1 still uses SS3 format', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f1);
      // Unmodified F1 should still use \x1bOP (SS3 format)
      expect(output.last, '\x1bOP');
    });

    test('Shift+F2 sends \\x1b[1;2Q', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f2, shift: true);
      expect(output.last, '\x1b[1;2Q');
    });

    test('Alt+F3 sends \\x1b[1;3R', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f3, alt: true);
      expect(output.last, '\x1b[1;3R');
    });

    test('Ctrl+Shift+F1 sends \\x1b[1;6P (modifier 6)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f1, ctrl: true, shift: true);
      expect(output.last, '\x1b[1;6P');
    });

    test('Unmodified F2=\\x1bOQ, F3=\\x1bOR, F4=\\x1bOS (SS3 preserved)', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f2);
      expect(output.last, '\x1bOQ', reason: 'Unmodified F2 should be SS3 Q');

      terminal.keyInput(TerminalKey.f3);
      expect(output.last, '\x1bOR', reason: 'Unmodified F3 should be SS3 R');

      terminal.keyInput(TerminalKey.f4);
      expect(output.last, '\x1bOS', reason: 'Unmodified F4 should be SS3 S');
    });

    test('F5 unmodified sends \\x1b[15~', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f5);
      expect(output.last, '\x1b[15~');
    });

    test('Ctrl+F5 sends \\x1b[15;5~', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f5, ctrl: true);
      expect(output.last, '\x1b[15;5~');
    });
  });

  group('XTD-44: keytabUnescape processes \\\\ before \\E', () {
    test('\\\\E produces literal backslash + E, not ESC', () {
      // Input: \\E  (raw string: two chars: backslash, E)
      // After fix: \\ → placeholder, \E stays as \E (no match since \\ was consumed),
      // then placeholder → backslash. Result: \E (literal)
      final result = keytabUnescape(r'\\E');
      // Should be literal backslash + 'E'
      expect(result, '\\E');
      // Should NOT be ESC (0x1b)
      expect(result, isNot(String.fromCharCode(0x1b)));
    });

    test('\\E still produces ESC', () {
      final result = keytabUnescape(r'\E');
      expect(result, String.fromCharCode(0x1b));
    });

    test('\\\\ produces single backslash', () {
      final result = keytabUnescape(r'\\');
      expect(result, '\\');
    });

    test('mixed \\\\E and \\E in same string', () {
      // Input: \\E\E (raw: backslash backslash E backslash E)
      // Expected: literal-backslash + 'E' + ESC
      final result = keytabUnescape(r'\\E\E');
      expect(result, '\\E\x1b');
    });

    test('\\E\\x7f produces ESC DEL', () {
      final result = keytabUnescape(r'\E\x7f');
      expect(result, '\x1b\x7f');
    });

    test('keytabUnescape with empty string returns empty', () {
      final result = keytabUnescape('');
      expect(result, '');
    });

    test('keytabUnescape with plain text returns unchanged', () {
      final result = keytabUnescape('hello world');
      expect(result, 'hello world');
    });

    test('Multiple \\E: \\E[1;\\E produces \\x1b[1;\\x1b', () {
      final result = keytabUnescape(r'\E[1;\E');
      expect(result, '\x1b[1;\x1b');
    });

    test(r'\\\\  (four backslashes raw) produces \\ (two backslashes)', () {
      final result = keytabUnescape(r'\\\\');
      expect(result, '\\\\');
    });

    test('\\E at end of string works', () {
      final result = keytabUnescape(r'abc\E');
      expect(result, 'abc\x1b');
    });
  });
}
