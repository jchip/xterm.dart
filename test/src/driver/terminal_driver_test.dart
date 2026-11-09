import 'dart:async';

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

      expect(sent, equals(['hello', 'world\r', '\r']));
      expect(driver.isQuiet, isFalse);

      driver.dispose();
    });

    test('detects output quiet / settle periods and handles custom silence', () async {
      final terminal = Terminal();
      final driver = TerminalDriver(
        terminal,
        quietPeriod: const Duration(milliseconds: 80),
      );

      // Already quiet before any activity: custom silence returns immediately
      final sw = Stopwatch()..start();
      await driver.waitForQuiet(silence: const Duration(milliseconds: 500));
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(100));

      var quietFired = false;
      driver.onQuiet.listen((_) => quietFired = true);

      terminal.write('stream 1...');
      expect(driver.isQuiet, isFalse);

      // Shorter custom silence completes before default quietPeriod without
      // prematurely marking driver.isQuiet as true
      await driver.waitForQuiet(silence: const Duration(milliseconds: 20));
      expect(driver.isQuiet, isFalse);

      // Default quietPeriod then settles normally
      await driver.waitForQuiet();
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

    test('captures main buffer scroll-off and preserves unified history across alt buffer', () {
      final terminal = Terminal();
      terminal.resize(20, 3);

      final driver = TerminalDriver(terminal);

      // Write 5 lines in main buffer (3 visible, 2 scrolled off)
      terminal.write('main-1\r\nmain-2\r\nmain-3\r\nmain-4\r\nmain-5');
      expect(driver.capturedBackBuffer, equals(['main-1', 'main-2']));
      expect(driver.altScrolledLines, isEmpty);

      // Enter alt buffer, scroll 1 line off, and exit
      terminal.write('\x1b[?1049h');
      terminal.write('alt-1\r\nalt-2\r\nalt-3\r\nalt-4');
      terminal.write('\x1b[?1049l');

      expect(driver.altScrolledLines, equals(['alt-1']));
      expect(
        driver.allBackBufferLines,
        equals(['main-1', 'main-2', 'alt-1']),
      );

      driver.dispose();
    });

    test('captures screen snapshots before clear, on CSI H CSI J, and on alt-buffer exit', () async {
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

      // Now clear the screen with CSI 2 J
      terminal.write('\x1b[2J');

      // A snapshot was captured before the clear
      final clearSnapshots = driver.snapshots
          .where((s) => s.label?.contains('before-clear') ?? false);
      expect(clearSnapshots, isNotEmpty);

      // Clear via CSI H CSI J (cursor at 0,0 + eraseDisplayBelow)
      terminal.write('\x1b[Hframe before 0J');
      final prevCount = driver.snapshots.length;
      terminal.write('\x1b[H\x1b[J');
      expect(driver.snapshots.length, greaterThan(prevCount));
      expect(driver.snapshots.last.text, contains('frame before 0J'));

      // Enter alt buffer, draw TUI frame, and immediately exit via CSI ? 1049 l
      terminal.write('\x1b[?1049h\x1b[HTUI final frame\x1b[?1049l');
      final altExitSnapshots = driver.snapshots
          .where((s) => s.isAltBuffer && s.text.contains('TUI final frame'));
      expect(altExitSnapshots, isNotEmpty);

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

    test('waitForPattern ignores stale back-buffer lines from before last send', () async {
      final terminal = Terminal();
      terminal.resize(20, 2);

      final driver = TerminalDriver(terminal);

      // Initial prompt scrolls into back-buffer
      terminal.write('PROMPT_READY\r\nline-1\r\nline-2');
      expect(driver.capturedBackBuffer, contains('PROMPT_READY'));

      // Sending new input advances the back-buffer search floor
      driver.sendLine('next-cmd');

      // Stale PROMPT_READY in back-buffer should not satisfy waitForPattern
      await expectLater(
        driver.waitForPattern(
          'PROMPT_READY',
          timeout: const Duration(milliseconds: 60),
        ),
        throwsA(isA<TimeoutException>()),
      );

      // If PROMPT_READY arrives in new output and scrolls off, it IS matched
      terminal.write('\r\nPROMPT_READY\r\ntrailing-1\r\ntrailing-2');
      await expectLater(
        driver.waitForPattern('PROMPT_READY'),
        completes,
      );

      driver.dispose();
    });

    test('waitForResponse handles synchronous output emitted during onSend', () async {
      final terminal = Terminal();
      late final TerminalDriver driver;
      driver = TerminalDriver(
        terminal,
        quietPeriod: const Duration(milliseconds: 30),
        onSend: (text) {
          terminal.write('sync-reply: $text\r\n');
        },
      );

      driver.sendLine('ping');
      await expectLater(
        driver.waitForResponse(
          silence: const Duration(milliseconds: 30),
          timeout: const Duration(milliseconds: 200),
        ),
        completes,
      );
      expect(driver.getScreenText(), contains('sync-reply: ping'));

      driver.dispose();
    });

    test('waitForQuiet waits for chunked writes to drain', () async {
      final terminal = Terminal(writeChunkSize: 4);
      final driver = TerminalDriver(
        terminal,
        quietPeriod: const Duration(milliseconds: 30),
      );

      terminal.write('abcdefghijkl');
      expect(terminal.pendingWriteLength, greaterThan(0));
      expect(driver.isQuiet, isFalse);

      await driver.waitForQuiet();
      expect(terminal.pendingWriteLength, 0);
      expect(driver.isQuiet, isTrue);
      expect(driver.getScreenText(), contains('abcdefghijkl'));

      driver.dispose();
    });

    test('CSI H CSI J evicts bottom viewport line and skips empty before-clear snapshots', () {
      final terminal = Terminal();
      terminal.resize(20, 3);
      final driver = TerminalDriver(terminal);

      // Entering alt screen and immediately clearing blank screen shouldn't add a snapshot
      terminal.write('\x1b[?1049h\x1b[H\x1b[2J\x1b[?1049l');
      expect(driver.snapshots, isEmpty);

      // Fill all 3 rows of main buffer and clear via CSI H CSI J
      terminal.write('row-top\r\nrow-mid\r\nrow-bot');
      terminal.write('\x1b[H\x1b[J');

      expect(
        driver.capturedBackBuffer,
        containsAllInOrder(['row-top', 'row-mid', 'row-bot']),
      );

      driver.dispose();
    });
  });
}
