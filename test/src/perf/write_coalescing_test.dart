import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';

void main() {
  Future<void> pumpEventTurn() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.microtask(() {});
  }

  group('Terminal.write() coalescing', () {
    test('multiple rapid writes coalesce into a single notification', () async {
      final terminal = Terminal();
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      // Issue multiple writes synchronously — these should coalesce
      terminal.write('Hello');
      terminal.write(' ');
      terminal.write('World');

      // No notification yet (scheduled via microtask)
      expect(notifyCount, 0);

      // Allow the microtask to run
      await Future.microtask(() {});

      // All three writes should have coalesced into one notification
      expect(notifyCount, 1);

      // Verify all data was written correctly
      final line = terminal.buffer.lines[0].toString();
      expect(line, contains('Hello World'));
    });

    test('writes in separate microtask turns produce separate notifications',
        () async {
      final terminal = Terminal();
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.write('First');
      await Future.microtask(() {});
      expect(notifyCount, 1);

      terminal.write('Second');
      await Future.microtask(() {});
      expect(notifyCount, 2);
    });

    test('single write still triggers a notification', () async {
      final terminal = Terminal();
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.write('Hello');
      await Future.microtask(() {});

      expect(notifyCount, 1);
    });

    test('flush timer still works correctly with coalesced notifications',
        () async {
      final terminal = Terminal();
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      // Write a lone ESC byte (incomplete escape sequence)
      terminal.write('\x1b');
      await Future.microtask(() {});
      expect(notifyCount, 1);

      // Wait for the 100ms flush timer to fire
      await Future.delayed(const Duration(milliseconds: 200));

      // The flush timer should have triggered another notification
      expect(notifyCount, 2);

      // Write normal text after flush and verify it still works
      terminal.write('hello');
      await Future.microtask(() {});
      expect(notifyCount, 3);

      final line = terminal.buffer.lines[terminal.buffer.cursorY].toString();
      expect(line, contains('hello'));
    });

    test('flush timer notification coalesces with concurrent write', () async {
      final terminal = Terminal();
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      // Write incomplete sequence, then immediately write more data
      // The second write cancels the flush timer from the first write
      terminal.write('\x1b');
      terminal.write('[31m'); // Complete the sequence: ESC[31m (red color)
      await Future.microtask(() {});

      // Both writes should coalesce into one notification
      expect(notifyCount, 1);
    });

    test('chunked writes drain across event turns', () async {
      final terminal = Terminal(writeChunkSize: 5);
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.write('Hello World');

      expect(terminal.buffer.lines[0].toString(), isEmpty);
      expect(notifyCount, 0);
      expect(terminal.pendingWriteLength, 11);

      await pumpEventTurn();
      expect(terminal.buffer.lines[0].toString(), contains('Hello'));
      expect(notifyCount, 1);
      expect(terminal.pendingWriteLength, 6);

      await pumpEventTurn();
      expect(terminal.buffer.lines[0].toString(), contains('Hello Worl'));
      expect(notifyCount, 2);
      expect(terminal.pendingWriteLength, 1);

      await pumpEventTurn();
      expect(terminal.buffer.lines[0].toString(), contains('Hello World'));
      expect(notifyCount, 3);
      expect(terminal.pendingWriteLength, 0);
    });

    test('chunked writes still flush pending escape bytes', () async {
      final terminal = Terminal(writeChunkSize: 1);
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.write('\x1b');

      await pumpEventTurn();
      expect(notifyCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifyCount, 2);
    });

    test('alt buffer chunked writes drain a bounded batch per event turn',
        () async {
      final terminal = Terminal(writeChunkSize: 5);
      terminal.useAltBuffer();
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.write('Hello World');

      expect(terminal.buffer.lines[0].toString(), isEmpty);
      expect(notifyCount, 0);
      expect(terminal.pendingWriteLength, 11);

      await pumpEventTurn();
      expect(terminal.buffer.lines[0].toString(), contains('Hello Worl'));
      expect(notifyCount, 1);
      expect(terminal.pendingWriteLength, 1);

      await pumpEventTurn();
      expect(terminal.buffer.lines[0].toString(), contains('Hello World'));
      expect(notifyCount, 2);
      expect(terminal.pendingWriteLength, 0);
    });

    test('alt buffer drain batch is capped for large chunk sizes', () async {
      final terminal = Terminal(writeChunkSize: 9000);
      terminal.useAltBuffer();
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.write(List.filled(20000, 'A').join());

      expect(terminal.pendingWriteLength, 20000);
      expect(notifyCount, 0);

      await pumpEventTurn();
      expect(terminal.pendingWriteLength, 3616);
      expect(notifyCount, 1);

      await pumpEventTurn();
      expect(terminal.pendingWriteLength, 0);
      expect(notifyCount, 2);
    });

    test('alt buffer notifications throttle to latest state', () async {
      final terminal = Terminal(
        altBufferNotifyInterval: const Duration(milliseconds: 40),
      );
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.useAltBuffer();
      terminal.write('A');
      await Future<void>.microtask(() {});
      expect(notifyCount, 1);

      terminal.write('B');
      terminal.write('C');
      await Future<void>.microtask(() {});
      expect(notifyCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifyCount, 2);
      expect(terminal.buffer.lines[0].toString(), contains('ABC'));
    });

    test('main buffer notifications stay immediate when alt throttle exists',
        () async {
      final terminal = Terminal(
        altBufferNotifyInterval: const Duration(milliseconds: 40),
      );
      var notifyCount = 0;
      terminal.addListener(() {
        notifyCount++;
      });

      terminal.write('Hello');
      await Future<void>.microtask(() {});

      expect(notifyCount, 1);
      expect(terminal.buffer.lines[0].toString(), contains('Hello'));
    });
  });
}
