import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalPainter block cursor glyph', () {
    const cursorTheme = TerminalTheme(
      cursor: ui.Color(0xFFFFFFFF),
      selection: ui.Color(0xFFAEAFAD),
      foreground: ui.Color(0xFFFFFFFF),
      background: ui.Color(0xFF000000),
      black: ui.Color(0xFF000000),
      red: ui.Color(0xFFCD3131),
      green: ui.Color(0xFF0DBC79),
      yellow: ui.Color(0xFFE5E510),
      blue: ui.Color(0xFF2472C8),
      magenta: ui.Color(0xFFBC3FBC),
      cyan: ui.Color(0xFF11A8CD),
      white: ui.Color(0xFFE5E5E5),
      brightBlack: ui.Color(0xFF666666),
      brightRed: ui.Color(0xFFF14C4C),
      brightGreen: ui.Color(0xFF23D18B),
      brightYellow: ui.Color(0xFFF5F543),
      brightBlue: ui.Color(0xFF3B8EEA),
      brightMagenta: ui.Color(0xFFD670D6),
      brightCyan: ui.Color(0xFF29B8DB),
      brightWhite: ui.Color(0xFFFFFFFF),
      searchHitBackground: ui.Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: ui.Color(0xFF31FF26),
      searchHitForeground: ui.Color(0xFF000000),
    );

    test('uses a dark contrasting cursor foreground for a bright cursor', () {
      final painter = TerminalPainter(
        theme: cursorTheme,
        textStyle: const TerminalStyle(fontSize: 18),
        textScaler: TextScaler.linear(1.0),
        cellSizeOverride: const ui.Size(20, 20),
      );

      expect(painter.resolveCursorForegroundColor(), const ui.Color(0xFF000000));
    });

    test('paints dark glyph pixels over a bright block cursor', () async {
      final painter = TerminalPainter(
        theme: cursorTheme,
        textStyle: const TerminalStyle(fontSize: 18),
        textScaler: TextScaler.linear(1.0),
        cellSizeOverride: const ui.Size(20, 20),
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final cellData = CellData(
        foreground: 0,
        background: 0,
        flags: 0,
        content: 'M'.codeUnitAt(0) | (1 << CellContent.widthShift),
      );

      painter.paintCursor(
        canvas,
        ui.Offset.zero,
        cursorType: TerminalCursorType.block,
        hasFocus: true,
      );
      painter.paintCellForegroundWithColor(
        canvas,
        ui.Offset.zero,
        cellData,
        painter.resolveCursorForegroundColor(),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(20, 20);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(byteData, isNotNull);
      final bytes = byteData!.buffer.asUint8List();
      var brightPixels = 0;
      var darkPixels = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
        if (luminance > 0.8) {
          brightPixels++;
        }
        if (luminance < 0.2) {
          darkPixels++;
        }
      }

      expect(brightPixels, greaterThan(0));
      expect(
        darkPixels,
        greaterThan(0),
        reason: 'block cursor should repaint the covered glyph, not only the block fill',
      );

      image.dispose();
      picture.dispose();
    });
  });

  group('cellRequestsEmojiPresentation', () {
    BufferLine lineOf(List<int> codepoints) {
      final line = BufferLine(codepoints.length);
      for (var i = 0; i < codepoints.length; i++) {
        line.setCodePoint(i, codepoints[i]);
      }
      return line;
    }

    int widthOf(BufferLine line, int index) => line.getWidth(index);

    test('detects a VS16 selector after a narrow base char (⚠️)', () {
      // ⚠ U+26A0 (narrow) + U+FE0F lands in the very next cell.
      final line = lineOf([0x26A0, 0xFE0F]);
      expect(
        TerminalPainter.cellRequestsEmojiPresentation(line, 0, widthOf(line, 0)),
        isTrue,
      );
    });

    test('detects a VS16 selector after a wide base char (past the spacer)', () {
      // A width-2 base char occupies its cell plus a zero-codepoint spacer, so
      // the selector sits two cells along, not one.
      final line = BufferLine(3);
      line.setCell(0, 0x1F525, 2, CursorStyle.empty); // 🔥 forced wide
      line.setCodePoint(1, 0); // spacer cell
      line.setCodePoint(2, 0xFE0F);
      expect(
        TerminalPainter.cellRequestsEmojiPresentation(line, 0, 2),
        isTrue,
      );
    });

    test('returns false for a bare base char with no selector', () {
      final line = lineOf([0x26A0, 0x20]);
      expect(
        TerminalPainter.cellRequestsEmojiPresentation(line, 0, widthOf(line, 0)),
        isFalse,
      );
    });

    test('returns false at end of line', () {
      final line = lineOf([0x26A0]);
      expect(
        TerminalPainter.cellRequestsEmojiPresentation(line, 0, widthOf(line, 0)),
        isFalse,
      );
    });
  });
}
