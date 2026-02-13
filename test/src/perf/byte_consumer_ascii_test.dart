import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/utils/byte_consumer.dart';

void main() {
  group('ByteConsumer ASCII fast path', () {
    test('handles pure ASCII data correctly', () {
      final consumer = ByteConsumer();
      consumer.add('hello world');
      expect(consumer.length, 11);

      final chars = <int>[];
      while (consumer.isNotEmpty) {
        chars.add(consumer.consume());
      }
      expect(String.fromCharCodes(chars), 'hello world');
    });

    test('handles non-ASCII data correctly', () {
      final consumer = ByteConsumer();
      consumer.add('héllo wörld');

      final chars = <int>[];
      while (consumer.isNotEmpty) {
        chars.add(consumer.consume());
      }
      expect(String.fromCharCodes(chars), 'héllo wörld');
    });

    test('handles emoji/surrogate pairs correctly', () {
      final consumer = ByteConsumer();
      consumer.add('hello 🌍');

      final chars = <int>[];
      while (consumer.isNotEmpty) {
        chars.add(consumer.consume());
      }
      expect(String.fromCharCodes(chars), 'hello 🌍');
    });

    test('handles escape sequences (ASCII) correctly', () {
      final consumer = ByteConsumer();
      consumer.add('\x1b[31mred\x1b[0m');
      expect(consumer.length, 12);

      final chars = <int>[];
      while (consumer.isNotEmpty) {
        chars.add(consumer.consume());
      }
      expect(String.fromCharCodes(chars), '\x1b[31mred\x1b[0m');
    });

    test('handles mixed ASCII and non-ASCII adds', () {
      final consumer = ByteConsumer();
      consumer.add('hello');
      consumer.add('wörld');

      final chars = <int>[];
      while (consumer.isNotEmpty) {
        chars.add(consumer.consume());
      }
      expect(String.fromCharCodes(chars), 'hellowörld');
    });

    test('rollback works with ASCII fast path', () {
      final consumer = ByteConsumer();
      consumer.add('abcdef');

      consumer.consume(); // a
      consumer.consume(); // b
      consumer.consume(); // c
      consumer.rollback(2);

      expect(consumer.consume(), 'b'.codeUnitAt(0));
      expect(consumer.consume(), 'c'.codeUnitAt(0));
    });
  });
}
