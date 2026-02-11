import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextEdit extends StatefulWidget {
  CustomTextEdit({
    super.key,
    required this.child,
    required this.onInsert,
    required this.onDelete,
    required this.onComposing,
    required this.onAction,
    required this.onKeyEvent,
    required this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    // this.initEditingState = TextEditingValue.empty,
    this.inputType = TextInputType.text,
    this.inputAction = TextInputAction.newline,
    this.keyboardAppearance = Brightness.light,
    this.deleteDetection = false,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.enableIMEPersonalizedLearning = false,
  });

  final Widget child;

  final void Function(String) onInsert;

  final void Function() onDelete;

  final void Function(String?) onComposing;

  final void Function(TextInputAction) onAction;

  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  final FocusNode focusNode;

  final bool autofocus;

  final bool readOnly;

  final TextInputType inputType;

  final TextInputAction inputAction;

  final Brightness keyboardAppearance;

  final bool deleteDetection;

  /// Whether to enable autocorrect. Defaults to false for terminal input.
  final bool autocorrect;

  /// Whether to show input suggestions. Defaults to false for terminal input.
  final bool enableSuggestions;

  /// Whether to enable IME personalized learning. Defaults to false.
  final bool enableIMEPersonalizedLearning;

  @override
  CustomTextEditState createState() => CustomTextEditState();
}

class CustomTextEditState extends State<CustomTextEdit> with TextInputClient {
  TextInputConnection? _connection;

  @override
  void initState() {
    widget.focusNode.addListener(_onFocusChange);
    super.initState();
  }

  @override
  void didUpdateWidget(CustomTextEdit oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else {
      if (oldWidget.readOnly && widget.focusNode.hasFocus) {
        _openInputConnection();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }

  bool get hasInputConnection => _connection != null && _connection!.attached;

  void requestKeyboard() {
    if (widget.focusNode.hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void closeKeyboard() {
    if (hasInputConnection) {
      _connection?.close();
    }
  }

  void setEditingState(TextEditingValue value) {
    _currentEditingState = value;
    _connection?.setEditingState(value);
  }

  void setEditableRect(Rect rect, Rect caretRect) {
    if (!hasInputConnection) {
      return;
    }

    _connection?.setEditableSizeAndTransform(
      rect.size,
      Matrix4.translationValues(0, 0, 0),
    );

    _connection?.setCaretRect(caretRect);
  }

  void _onFocusChange() {
    _openOrCloseInputConnectionIfNeeded();
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (_currentEditingState.composing.isCollapsed) {
      final result = widget.onKeyEvent(focusNode, event);

      // Some virtual keyboards send backspace as a key event instead of
      // through updateEditingValue.  When that happens the editing buffer
      // keeps growing while the terminal deletes the character, causing the
      // suggestion strip to accumulate stale text.  Trim the buffer and
      // push the corrected state back to the keyboard.
      if (result == KeyEventResult.handled &&
          event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _syncBufferAfterKeyDelete();
      }

      return result;
    }

    return KeyEventResult.skipRemainingHandlers;
  }

  /// Remove the last character from the editing buffer and tell the keyboard
  /// so its suggestion strip stays in sync.
  void _syncBufferAfterKeyDelete() {
    final text = _initEditingState.text;
    if (text.isEmpty) return;
    final shortened = text.substring(0, text.length - 1);
    _initEditingState = TextEditingValue(
      text: shortened,
      selection: TextSelection.collapsed(offset: shortened.length),
    );
    _currentEditingState = _initEditingState.copyWith();
    _connection?.setEditingState(_initEditingState);
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!widget.focusNode.hasFocus) {
      _closeInputConnectionIfNeeded();
    }
  }

  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  void _openInputConnection() {
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (hasInputConnection) {
      _connection!.show();
    } else {
      final config = TextInputConfiguration(
        inputType: widget.inputType,
        inputAction: widget.inputAction,
        keyboardAppearance: widget.keyboardAppearance,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
        enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
      );

      _connection = TextInput.attach(this, config);

      _connection!.show();

      // setEditableRect(Rect.zero, Rect.zero);

      // Reset to default on new connection
      _initEditingState = _defaultEditingState;
      _currentEditingState = _defaultEditingState.copyWith();
      _connection!.setEditingState(_initEditingState);
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_connection != null && _connection!.attached) {
      _connection!.close();
      _connection = null;
    }
  }

  TextEditingValue get _defaultEditingState => widget.deleteDetection
      ? const TextEditingValue(
          text: '  ',
          selection: TextSelection.collapsed(offset: 2),
        )
      : const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );

  // Mutable baseline for calculating text deltas
  late TextEditingValue _initEditingState = _defaultEditingState;
  late var _currentEditingState = _defaultEditingState.copyWith();

  void _resetEditingBuffer() {
    _initEditingState = _defaultEditingState;
    _currentEditingState = _defaultEditingState.copyWith();
    _connection?.setEditingState(_initEditingState);
  }

  @override
  TextEditingValue? get currentTextEditingValue {
    return _currentEditingState;
  }

  @override
  AutofillScope? get currentAutofillScope {
    return null;
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    _currentEditingState = value;

    // Get input after composing is done
    if (!_currentEditingState.composing.isCollapsed) {
      final text = _currentEditingState.text;
      final composingText = _currentEditingState.composing.textInside(text);
      widget.onComposing(composingText);
      return;
    }

    widget.onComposing(null);

    if (_currentEditingState.text.length < _initEditingState.text.length) {
      // Deletion
      widget.onDelete();
    } else if (_currentEditingState.text.startsWith(_initEditingState.text)) {
      // Simple append - send only the new characters
      final textDelta = _currentEditingState.text.substring(
        _initEditingState.text.length,
      );
      if (textDelta.isNotEmpty) {
        widget.onInsert(textDelta);
      }
    } else {
      // Text was replaced (autocorrect/suggestion accepted)
      // Find common prefix to minimize backspaces
      int commonPrefixLen = 0;
      while (commonPrefixLen < _initEditingState.text.length &&
             commonPrefixLen < _currentEditingState.text.length &&
             _initEditingState.text[commonPrefixLen] == _currentEditingState.text[commonPrefixLen]) {
        commonPrefixLen++;
      }

      // Delete characters after common prefix
      final charsToDelete = _initEditingState.text.length - commonPrefixLen;
      for (int i = 0; i < charsToDelete; i++) {
        widget.onDelete();
      }

      // Insert the replacement text
      final newText = _currentEditingState.text.substring(commonPrefixLen);
      if (newText.isNotEmpty) {
        widget.onInsert(newText);
      }
    }

    // Update baseline for delta computation.
    if (_currentEditingState.composing.isCollapsed &&
        _currentEditingState.text != _initEditingState.text) {
      final delta = _currentEditingState.text.length >
              _initEditingState.text.length
          ? _currentEditingState.text.substring(_initEditingState.text.length)
          : '';

      if (delta.contains('\n')) {
        // Enter — clear buffer between commands
        _resetEditingBuffer();
      } else if (delta.endsWith(' ')) {
        // Word boundary — clear buffer so backspace history doesn't pile up.
        // Brief keyboard reinit is masked by the natural pause between words.
        _resetEditingBuffer();
      } else {
        // Mid-word — track internally only, don't echo back to keyboard
        _initEditingState = TextEditingValue(
          text: _currentEditingState.text,
          selection: TextSelection.collapsed(
              offset: _currentEditingState.text.length),
        );
      }
    }
  }

  @override
  void performAction(TextInputAction action) {
    widget.onAction(action);
    if (action == TextInputAction.newline) {
      _resetEditingBuffer();
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // print('updateFloatingCursor $point');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // print('showAutocorrectionPromptRect');
  }

  @override
  void connectionClosed() {
    // print('connectionClosed');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // print('performPrivateCommand $action');
  }

  @override
  void insertTextPlaceholder(Size size) {
    // print('insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    // print('removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    // print('showToolbar');
  }
}
