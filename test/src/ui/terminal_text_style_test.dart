import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalStyle.toTextStyle emoji presentation', () {
    const style = TerminalStyle();

    test('uses the monospace-first font chain by default', () {
      final text = style.toTextStyle();
      expect(text.fontFamily, 'monospace');
      // The default chain lists a color-emoji font so emoji-presentation-default
      // glyphs render in color, but a monospace font still resolves first.
      final fallback = text.fontFamilyFallback!;
      expect(fallback, contains('Apple Color Emoji'));
      expect(
        fallback.indexOf('Menlo'),
        lessThan(fallback.indexOf('Apple Color Emoji')),
      );
    });

    test('resolves through a color-emoji font first when requested', () {
      final text = style.toTextStyle(emojiPresentation: true);
      expect(text.fontFamily, 'Apple Color Emoji');
      // Color-emoji fonts must precede the monospace fonts that ship monochrome
      // glyphs for dual-presentation characters like ⚠ / ✔ / ▶.
      final fallback = text.fontFamilyFallback!;
      expect(fallback.first, 'Apple Color Emoji');
      expect(
        fallback.indexOf('Apple Color Emoji'),
        lessThan(fallback.indexOf('Menlo')),
      );
      // The base monospace family is retained as a fallback so non-emoji text in
      // the same cell still resolves.
      expect(fallback, contains('monospace'));
    });
  });
}
