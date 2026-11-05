import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('BufferLine.copy()', () {
    test('creates an independent copy of cells and wrap flag', () {
      final terminal = Terminal();
      final original = BufferLine(10, isWrapped: true);
      original.setCell(0, 'A'.codeUnitAt(0), 1, terminal.cursor);
      original.setCell(1, 'B'.codeUnitAt(0), 1, terminal.cursor);

      final copy = original.copy();
      expect(copy.length, original.length);
      expect(copy.isWrapped, isTrue);
      expect(copy.getCodePoint(0), 'A'.codeUnitAt(0));
      expect(copy.getCodePoint(1), 'B'.codeUnitAt(0));

      // Mutate original, verify copy remains unchanged
      original.setCell(0, 'Z'.codeUnitAt(0), 1, terminal.cursor);
      expect(copy.getCodePoint(0), 'A'.codeUnitAt(0));
    });
  });

  group('TerminalDriver automation', () {
    test('sends text and key inputs to target', () {
      final terminal = Terminal();
      final sent = <String>[];

      final driver = TerminalDriver(
        terminal,
        onSend: sent.add,
      );

      driver.send('hello');
      driver.sendLine('world');
      driver.sendKey(TerminalKey.enter);

      expect(sent, contains('hello'));
      expect(sent, contains('world\r'));
      expect(driver.isQuiet, isFalse);

      driver.dispose();
    });

    test('detects output quiet / settle periods', () async {
      final terminal = Terminal();
      final driver = TerminalDriver(
        terminal,
        quietPeriod: const Duration(milliseconds: 50),
      );

      var quietFired = false;
      driver.onQuiet.listen((_) => quietFired = true);

      terminal.write('stream 1...');
      expect(driver.isQuiet, isFalse);

      // Wait until quiet
      await driver.waitForQuiet(silence: const Duration(milliseconds: 50));
      expect(driver.isQuiet, isTrue);
      expect(quietFired, isTrue);

      driver.dispose();
    });

    test('detects and counts bell events', () async {
      final terminal = Terminal();
      final driver = TerminalDriver(terminal);

      expect(driver.bellCount, 0);

      final waitFuture = driver.waitForBell();
      terminal.write('\x07');

      final count = await waitFuture;
      expect(count, 1);
      expect(driver.bellCount, 1);

      driver.dispose();
    });

    test('detects semantic and custom OSC tags', () async {
      final terminal = Terminal();
      final driver = TerminalDriver(terminal);

      final tagFuture133 = driver.waitForTag('133', argPattern: 'C');
      terminal.write('\x1b]133;C\x07');

      final tag133 = await tagFuture133;
      expect(tag133.code, '133');
      expect(tag133.args, ['C']);

      final customFuture = driver.waitForTag('777', argPattern: 'ready');
      terminal.write('\x1b]777;tag;step=ready\x07');

      final customTag = await customFuture;
      expect(customTag.code, '777');
      expect(customTag.args, ['tag', 'step=ready']);
      expect(customTag.payload, 'step=ready');

      expect(driver.tagEvents.length, 2);

      driver.dispose();
    });

    test('captures lines scrolled off in alternative buffer mode', () {
      final terminal = Terminal();
      terminal.resize(20, 4);

      final driver = TerminalDriver(terminal);

      // Switch to alternative buffer
      terminal.write('\x1b[?1049h');
      expect(terminal.isUsingAltBuffer, isTrue);

      // Fill alt screen: 4 rows
      terminal.write('alt-row-1\r\n');
      terminal.write('alt-row-2\r\n');
      terminal.write('alt-row-3\r\n');
      terminal.write('alt-row-4');

      // Nothing has scrolled off yet
      expect(driver.altScrolledLines, isEmpty);

      // Cause lines to scroll off by writing more lines at the bottom
      terminal.write('\r\nalt-row-5\r\n');
      terminal.write('alt-row-6');

      // The top 2 rows scrolled off the alt screen!
      expect(driver.altScrolledLines.length, 2);
      expect(driver.altScrolledLines[0], 'alt-row-1');
      expect(driver.altScrolledLines[1], 'alt-row-2');

      // Both are preserved in the unified captured back buffer
      expect(driver.capturedBackBuffer, contains('alt-row-1'));
      expect(driver.capturedBackBuffer, contains('alt-row-2'));

      driver.dispose();
    });

    test('captures screen snapshots before clear and on quiet', () async {
      final terminal = Terminal();
      terminal.resize(20, 3);

      final driver = TerminalDriver(
        terminal,
        quietPeriod: const Duration(milliseconds: 30),
      );

      terminal.write('screen frame 1');
      await driver.waitForQuiet(silence: const Duration(milliseconds: 30));

      expect(driver.snapshots.isNotEmpty, isTrue);
      expect(driver.snapshots.last.text, contains('screen frame 1'));

      // Now clear the screen
      terminal.write('\x1b[2J');

      // A snapshot was captured before the clear
      final clearSnapshots = driver.snapshots
          .where((s) => s.label?.contains('before-clear') ?? false);
      expect(clearSnapshots, isNotEmpty);

      driver.dispose();
    });

    test('waitForPattern matches text on screen and in back buffer', () async {
      final terminal = Terminal();
      terminal.resize(20, 3);

      final driver = TerminalDriver(terminal);

      // Switch to alt screen and scroll out an item
      terminal.write('\x1b[?1049h');
      terminal.write('item-alpha\r\nitem-beta\r\nitem-gamma\r\nitem-delta');

      // item-alpha scrolled off
      expect(driver.altScrolledLines, contains('item-alpha'));

      // waitForPattern should find item-alpha in the back buffer
      await expectLater(
        driver.waitForPattern(RegExp(r'item-alpha')),
        completes,
      );

      // And should find item-delta on the active screen
      await expectLater(
        driver.waitForPattern('item-delta'),
        completes,
      );

      driver.dispose();
    });
  });
}
