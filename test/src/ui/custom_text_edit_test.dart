import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

void main() {
  group('CustomTextEdit buffer management (TXM-57)', () {
    late FocusNode focusNode;
    late List<String> insertedTexts;
    late int deleteCount;
    late String? lastComposing;
    late List<TextInputAction> actions;

    setUp(() {
      focusNode = FocusNode();
      insertedTexts = [];
      deleteCount = 0;
      lastComposing = null;
      actions = [];
    });

    tearDown(() {
      focusNode.dispose();
    });

    Widget buildWidget({bool deleteDetection = false}) {
      return MaterialApp(
        home: Scaffold(
          body: CustomTextEdit(
            focusNode: focusNode,
            autofocus: true,
            deleteDetection: deleteDetection,
            onInsert: (text) => insertedTexts.add(text),
            onDelete: () => deleteCount++,
            onComposing: (text) => lastComposing = text,
            onAction: (action) => actions.add(action),
            onKeyEvent: (_, __) => KeyEventResult.ignored,
            child: const SizedBox(),
          ),
        ),
      );
    }

    CustomTextEditState getState(WidgetTester tester) {
      return tester.state<CustomTextEditState>(
        find.byType(CustomTextEdit),
      );
    }

    testWidgets('delta computation works within a word', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'hel',
        selection: TextSelection.collapsed(offset: 3),
      ));

      state.updateEditingValue(const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      ));

      expect(insertedTexts, equals(['hel', 'lo']));
    });

    testWidgets('resets buffer on word boundary (space)', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      ));

      // Space ends the word — buffer should reset
      state.updateEditingValue(const TextEditingValue(
        text: 'hello ',
        selection: TextSelection.collapsed(offset: 6),
      ));

      expect(insertedTexts, equals(['hello', ' ']));
      expect(state.currentTextEditingValue!.text, equals(''));
    });

    testWidgets('typing resumes after word boundary reset', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      ));

      // Space resets
      state.updateEditingValue(const TextEditingValue(
        text: 'hello ',
        selection: TextSelection.collapsed(offset: 6),
      ));

      insertedTexts.clear();

      // Next word starts fresh
      state.updateEditingValue(const TextEditingValue(
        text: 'world',
        selection: TextSelection.collapsed(offset: 5),
      ));

      expect(insertedTexts, equals(['world']));
    });

    testWidgets('resets on performAction newline', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'ls -la',
        selection: TextSelection.collapsed(offset: 6),
      ));

      state.performAction(TextInputAction.newline);

      expect(state.currentTextEditingValue!.text, equals(''));
      expect(actions, contains(TextInputAction.newline));
    });

    testWidgets('resets on newline in text', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'ls -la',
        selection: TextSelection.collapsed(offset: 6),
      ));

      state.updateEditingValue(const TextEditingValue(
        text: 'ls -la\n',
        selection: TextSelection.collapsed(offset: 7),
      ));

      expect(state.currentTextEditingValue!.text, equals(''));
      expect(insertedTexts, contains('\n'));
    });

    testWidgets('resets to deleteDetection default on Enter', (tester) async {
      await tester.pumpWidget(buildWidget(deleteDetection: true));
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: '  ls -la',
        selection: TextSelection.collapsed(offset: 8),
      ));

      state.performAction(TextInputAction.newline);

      expect(state.currentTextEditingValue!.text, equals('  '));
    });

    testWidgets('typing works after Enter reset', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'first',
        selection: TextSelection.collapsed(offset: 5),
      ));
      state.performAction(TextInputAction.newline);
      insertedTexts.clear();

      state.updateEditingValue(const TextEditingValue(
        text: 'second',
        selection: TextSelection.collapsed(offset: 6),
      ));

      expect(insertedTexts, equals(['second']));
    });

    testWidgets('non-newline actions do not reset', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      ));

      state.performAction(TextInputAction.done);

      expect(state.currentTextEditingValue!.text, equals('hello'));
    });

    testWidgets('composing text bypasses buffer logic', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      final state = getState(tester);

      state.updateEditingValue(const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ));

      expect(lastComposing, equals('ni'));
      expect(insertedTexts, isEmpty);
    });
  });
}
