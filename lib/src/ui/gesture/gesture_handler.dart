import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

enum _SelectionMode { character, word, line }

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  _SelectionMode? _dragSelectionMode;

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onTertiaryTapDown,
      onTertiaryTapUp: onTertiaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      // onLongPressUp: onLongPressUp,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDoubleTapDown: onDoubleTapDown,
      onTripleTapDown: onTripleTapDown,
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  bool get _shouldSendDragEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.drag);

  /// Whether the terminal owns the current drag (motion-tracking mouse mode
  /// active and drag forwarding enabled) — local selection is skipped then.
  bool _dragReportsToTerminal = false;

  /// Last drag position, so the terminating button-release report (which
  /// carries no position of its own) lands on the right cell.
  Offset? _lastDragPosition;

  /// Whether the current pointer interaction already reported a button press
  /// to the terminal. A fast drag never fires onTapDown (the pan recognizer
  /// wins the arena first), so onDragStart must supply the press itself —
  /// but only when the tap path hasn't already done so.
  bool _downReportedToTerminal = false;

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
      _downReportedToTerminal = handled;
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
      _downReportedToTerminal = false;
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.middle);
  }

  void onDoubleTapDown(TapDownDetails details) {
    _dragSelectionMode = _SelectionMode.word;
    renderTerminal.selectWord(details.localPosition);
  }

  void onTripleTapDown(TapDownDetails details) {
    _dragSelectionMode = _SelectionMode.line;
    renderTerminal.selectLine(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  void onDragStart(DragStartDetails details) {
    _lastDragStartDetails = details;
    _lastDragPosition = details.localPosition;

    // When the application opted into drag forwarding and the terminal is in
    // a motion-tracking mouse mode (DECSET 1002/1003), the terminal owns the
    // drag: report motion instead of extending the local selection. The
    // initial button press was already reported by the tap-down path.
    final mouseMode = terminalView.widget.terminal.mouseMode;
    _dragReportsToTerminal = _shouldSendDragEvent &&
        (mouseMode == MouseMode.upDownScrollDrag ||
            mouseMode == MouseMode.upDownScrollMove);
    if (_dragReportsToTerminal) {
      // A fast drag wins the gesture arena before onTapDown can fire, so the
      // press may not have been reported yet.
      if (!_downReportedToTerminal) {
        _downReportedToTerminal = renderTerminal.mouseEvent(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          details.localPosition,
        );
      }
      return;
    }

    if (_dragSelectionMode == null) {
      _dragSelectionMode = details.kind == PointerDeviceKind.mouse
          ? _SelectionMode.character
          : _SelectionMode.word;
    }

    switch (_dragSelectionMode!) {
      case _SelectionMode.word:
        renderTerminal.selectWord(details.localPosition);
        break;
      case _SelectionMode.line:
        renderTerminal.selectLine(details.localPosition);
        break;
      case _SelectionMode.character:
        renderTerminal.selectCharacters(details.localPosition);
        break;
    }
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragPosition = details.localPosition;

    if (_dragReportsToTerminal) {
      renderTerminal.mouseEvent(
        TerminalMouseButton.left,
        TerminalMouseButtonState.moved,
        details.localPosition,
      );
      return;
    }

    switch (_dragSelectionMode!) {
      case _SelectionMode.word:
        renderTerminal.selectWord(
          _lastDragStartDetails!.localPosition,
          details.localPosition,
        );
        break;
      case _SelectionMode.line:
        renderTerminal.selectLine(
          _lastDragStartDetails!.localPosition,
          details.localPosition,
        );
        break;
      case _SelectionMode.character:
        renderTerminal.selectCharacters(
          _lastDragStartDetails!.localPosition,
          details.localPosition,
        );
        break;
    }
  }

  void onDragEnd(DragEndDetails details) {
    if (_dragReportsToTerminal) {
      // Close the terminal-owned drag with a release on the last known cell
      // (DragEndDetails carries no position).
      if (_lastDragPosition != null) {
        renderTerminal.mouseEvent(
          TerminalMouseButton.left,
          TerminalMouseButtonState.up,
          _lastDragPosition!,
        );
      }
      _dragReportsToTerminal = false;
      _downReportedToTerminal = false;
    }
    _dragSelectionMode = null;
  }
}
