import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('paints the terminal viewport background before line content', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 50);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 96,
            child: TerminalView(
              terminal,
              textStyle: const TerminalStyle(fontSize: 20),
              theme: TerminalThemes.whiteOnBlack,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byType(TerminalView),
      paints..rect(color: TerminalThemes.whiteOnBlack.background),
    );
  });
}
