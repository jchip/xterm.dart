import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';

void main() {
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
  });
}
