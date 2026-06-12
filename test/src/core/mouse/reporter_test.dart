import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/mouse/reporter.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('MouseReporter', () {
    test('report() supports normal mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.normal,
      );

      expect(output, equals('\x1B[M !!'));
    });

    test('report() supports utf mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.utf,
      );

      expect(output, equals('\x1B[M !!'));
    });

    test('report() supports sgr mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.sgr,
      );

      expect(output, equals('\x1B[<0;1;1M'));
    });

    test('report() supports urxvt mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.urxvt,
      );

      expect(output, equals('\x1B[32;1;1M'));
    });

    group('motion (+32 button-motion flag)', () {
      test('report() encodes left-button motion in normal mode', () {
        final output = MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.moved,
          CellOffset(0, 0),
          MouseReportMode.normal,
        );

        // 32 (base) + 32 (motion) + 0 (left) = 64 = '@'
        expect(output, equals('\x1B[M@!!'));
      });

      test('report() encodes no-button motion (AnyEvent) in normal mode', () {
        final output = MouseReporter.report(
          TerminalMouseButton.none,
          TerminalMouseButtonState.moved,
          CellOffset(0, 0),
          MouseReportMode.normal,
        );

        // 32 (base) + 32 (motion) + 3 (none) = 67 = 'C'
        expect(output, equals('\x1B[MC!!'));
      });

      test('report() encodes left-button motion in sgr mode with trailing M',
          () {
        final output = MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.moved,
          CellOffset(0, 0),
          MouseReportMode.sgr,
        );

        expect(output, equals('\x1B[<32;1;1M'));
      });

      test('report() encodes no-button motion (AnyEvent) in sgr mode', () {
        final output = MouseReporter.report(
          TerminalMouseButton.none,
          TerminalMouseButtonState.moved,
          CellOffset(0, 0),
          MouseReportMode.sgr,
        );

        expect(output, equals('\x1B[<35;1;1M'));
      });

      test('report() keeps sgr release as lowercase m', () {
        final output = MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.up,
          CellOffset(0, 0),
          MouseReportMode.sgr,
        );

        expect(output, equals('\x1B[<0;1;1m'));
      });

      test('report() encodes motion in urxvt mode', () {
        final output = MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.moved,
          CellOffset(0, 0),
          MouseReportMode.urxvt,
        );

        expect(output, equals('\x1B[64;1;1M'));
      });
    });
  });
}
