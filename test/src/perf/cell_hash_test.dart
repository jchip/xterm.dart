import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/cell.dart';

void main() {
  group('CellData.getHash() inline Jenkins', () {
    test('produces consistent hash for same data', () {
      final cell = CellData(foreground: 10, background: 20, flags: 1, content: 65);
      final hash1 = cell.getHash();
      final hash2 = cell.getHash();
      expect(hash1, hash2);
    });

    test('produces different hashes for different data', () {
      final cell1 = CellData(foreground: 10, background: 20, flags: 1, content: 65);
      final cell2 = CellData(foreground: 10, background: 20, flags: 1, content: 66);
      expect(cell1.getHash(), isNot(cell2.getHash()));
    });

    test('produces different hashes when foreground differs', () {
      final cell1 = CellData(foreground: 10, background: 20, flags: 1, content: 65);
      final cell2 = CellData(foreground: 11, background: 20, flags: 1, content: 65);
      expect(cell1.getHash(), isNot(cell2.getHash()));
    });

    test('produces different hashes when background differs', () {
      final cell1 = CellData(foreground: 10, background: 20, flags: 1, content: 65);
      final cell2 = CellData(foreground: 10, background: 21, flags: 1, content: 65);
      expect(cell1.getHash(), isNot(cell2.getHash()));
    });

    test('produces different hashes when flags differ', () {
      final cell1 = CellData(foreground: 10, background: 20, flags: 1, content: 65);
      final cell2 = CellData(foreground: 10, background: 20, flags: 2, content: 65);
      expect(cell1.getHash(), isNot(cell2.getHash()));
    });

    test('handles zero values', () {
      final cell = CellData(foreground: 0, background: 0, flags: 0, content: 0);
      final hash = cell.getHash();
      expect(hash, isA<int>());
    });

    test('handles large values', () {
      final cell = CellData(
        foreground: 0xFFFFFF | (3 << 25),
        background: 0xFFFFFF | (3 << 25),
        flags: 0xFF,
        content: 0x1fffff | (2 << 22),
      );
      final hash = cell.getHash();
      expect(hash, isA<int>());
      // Hash should be within 30-bit range
      expect(hash, lessThanOrEqualTo(0x1fffffff));
    });
  });
}
