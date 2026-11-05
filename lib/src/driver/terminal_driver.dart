import 'dart:async';

import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/terminal.dart';

/// Represents a structured OSC tag received by the terminal.
class TerminalTagEvent {
  TerminalTagEvent({
    required this.code,
    required this.args,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// The OSC command code, such as '133' or '777'.
  final String code;

  /// Arguments provided in the OSC sequence.
  final List<String> args;

  /// The timestamp when the tag was received.
  final DateTime timestamp;

  /// Convenience getter for the first argument, often used as tag name.
  String get tag => args.isNotEmpty ? args.first : '';

  /// Convenience getter for the payload following the tag name.
  String get payload => args.length > 1 ? args.sublist(1).join(';') : '';

  @override
  String toString() =>
      'TerminalTagEvent(code: $code, args: $args, time: $timestamp)';
}

/// A snapshot of the visible terminal grid at a specific point in time.
class TerminalScreenSnapshot {
  TerminalScreenSnapshot({
    required this.lines,
    required this.cursor,
    required this.isAltBuffer,
    this.label,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Lines of text currently visible on the screen.
  final List<String> lines;

  /// Cursor position at the time of the snapshot.
  final CellOffset cursor;

  /// Whether the terminal was using the alternative screen buffer.
  final bool isAltBuffer;

  /// Optional label or reason for the snapshot.
  final String? label;

  /// The timestamp of the snapshot.
  final DateTime timestamp;

  /// Formatted screen text with lines joined by newlines.
  String get text => lines.join('\n');

  @override
  String toString() =>
      'TerminalScreenSnapshot(label: $label, alt: $isAltBuffer, lines: ${lines.length})';
}

/// A driver that runs automation scripts against a [Terminal].
///
/// It supports keystroke injection, output quiet/settle detection,
/// OSC tag detection, bell tracking, and persistent back-buffer capture
/// across both normal and alternative screen (TUI) modes.
class TerminalDriver {
  TerminalDriver(
    this.terminal, {
    this.onSend,
    this.quietPeriod = const Duration(milliseconds: 300),
    this.maxBackBufferLines = 5000,
    bool autoCaptureSnapshots = true,
  }) : _autoCaptureSnapshots = autoCaptureSnapshots {
    _initHooks();
  }

  /// The underlying terminal instance being driven.
  final Terminal terminal;

  /// Optional callback to deliver input strings to the target process (e.g. PTY).
  /// If not provided, inputs are sent directly via [Terminal.textInput].
  final void Function(String text)? onSend;

  /// The duration of silence required to declare the terminal quiet/settled.
  final Duration quietPeriod;

  /// Maximum number of lines to retain in the captured back-buffer.
  final int maxBackBufferLines;

  final bool _autoCaptureSnapshots;

  Timer? _quietTimer;
  bool _isQuiet = true;

  int _bellCount = 0;

  final _tagEvents = <TerminalTagEvent>[];
  final _capturedBackBuffer = <String>[];
  final _altScrolledLines = <String>[];
  final _snapshots = <TerminalScreenSnapshot>[];

  final _quietController = StreamController<void>.broadcast();
  final _bellController = StreamController<int>.broadcast();
  final _tagController = StreamController<TerminalTagEvent>.broadcast();
  final _outputController = StreamController<String>.broadcast();

  void Function()? _prevOnBell;
  void Function(String code, List<String> args)? _prevOnPrivateOsc;
  void Function(String data)? _prevOnWrite;
  void Function(BufferLine line, {required bool isAltBuffer})?
      _prevOnLineScrolledOff;
  void Function({required bool isAltBuffer})? _prevOnScreenCleared;

  void _initHooks() {
    _prevOnBell = terminal.onBell;
    terminal.onBell = _handleBell;

    _prevOnPrivateOsc = terminal.onPrivateOSC;
    terminal.onPrivateOSC = _handlePrivateOsc;

    _prevOnWrite = terminal.onWrite;
    terminal.onWrite = _handleWrite;

    _prevOnLineScrolledOff = terminal.onLineScrolledOff;
    terminal.onLineScrolledOff = _handleLineScrolledOff;

    _prevOnScreenCleared = terminal.onScreenCleared;
    terminal.onScreenCleared = _handleScreenCleared;
  }

  void _handleWrite(String data) {
    _prevOnWrite?.call(data);
    _outputController.add(data);
    _bumpActivity();
  }

  void _handleBell() {
    _bellCount++;
    _bellController.add(_bellCount);
    _prevOnBell?.call();
    _bumpActivity();
  }

  void _handlePrivateOsc(String code, List<String> args) {
    final event = TerminalTagEvent(code: code, args: List.unmodifiable(args));
    _tagEvents.add(event);
    _tagController.add(event);
    _prevOnPrivateOsc?.call(code, args);
    _bumpActivity();
  }

  void _handleLineScrolledOff(BufferLine line, {required bool isAltBuffer}) {
    final lineText = line.toString();
    _appendBackBuffer(lineText);
    if (isAltBuffer) {
      _altScrolledLines.add(lineText);
    }
    _prevOnLineScrolledOff?.call(line, isAltBuffer: isAltBuffer);
    _bumpActivity();
  }

  void _handleScreenCleared({required bool isAltBuffer}) {
    if (_autoCaptureSnapshots) {
      captureSnapshot(label: 'before-clear (alt: $isAltBuffer)');
    }
    _prevOnScreenCleared?.call(isAltBuffer: isAltBuffer);
    _bumpActivity();
  }

  void _bumpActivity() {
    _isQuiet = false;
    _quietTimer?.cancel();
    _quietTimer = Timer(quietPeriod, _onSilenceSettled);
  }

  void _onSilenceSettled() {
    _isQuiet = true;
    if (_autoCaptureSnapshots) {
      captureSnapshot(label: 'settled');
    }
    _quietController.add(null);
  }

  void _appendBackBuffer(String line) {
    _capturedBackBuffer.add(line);
    if (_capturedBackBuffer.length > maxBackBufferLines) {
      _capturedBackBuffer.removeAt(0);
    }
  }

  // --- Public State and Streams ---

  /// Whether the terminal currently has no pending output activity.
  bool get isQuiet => _isQuiet;

  /// Stream that emits whenever the terminal settles into a quiet state.
  Stream<void> get onQuiet => _quietController.stream;

  /// The total number of bell signals received since creation.
  int get bellCount => _bellCount;

  /// Stream of bell count updates.
  Stream<int> get onBell => _bellController.stream;

  /// History of all received OSC tag events.
  List<TerminalTagEvent> get tagEvents => List.unmodifiable(_tagEvents);

  /// Stream of newly arrived OSC tag events.
  Stream<TerminalTagEvent> get onTag => _tagController.stream;

  /// Raw data stream received by the terminal.
  Stream<String> get onOutput => _outputController.stream;

  /// Unified back-buffer containing lines scrolled off the screen.
  List<String> get capturedBackBuffer =>
      List.unmodifiable(_capturedBackBuffer);

  /// All back-buffer lines across main buffer scrollback and alt-buffer scroll-off.
  List<String> get allBackBufferLines {
    if (_capturedBackBuffer.isNotEmpty) {
      return List.unmodifiable(_capturedBackBuffer);
    }
    final result = <String>[];
    final buf = terminal.buffer;
    for (var i = 0; i < buf.scrollBack; i++) {
      result.add(buf.lines[i].toString().trimRight());
    }
    result.addAll(_altScrolledLines);
    return result;
  }

  /// Specifically captured lines that scrolled off during alternative buffer mode.
  List<String> get altScrolledLines => List.unmodifiable(_altScrolledLines);

  /// Saved screen snapshots.
  List<TerminalScreenSnapshot> get snapshots => List.unmodifiable(_snapshots);

  // --- Script Actions ---

  /// Sends raw text input to the terminal or underlying process.
  void send(String text) {
    if (onSend != null) {
      onSend!(text);
    } else {
      terminal.textInput(text);
    }
    _bumpActivity();
  }

  /// Sends text followed by a carriage return.
  void sendLine(String text) {
    send('$text\r');
  }

  /// Sends a specific key input with optional modifiers.
  bool sendKey(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
  }) {
    final handled = terminal.keyInput(
      key,
      shift: shift,
      alt: alt,
      ctrl: ctrl,
    );
    _bumpActivity();
    return handled;
  }

  /// Sends a line of text and waits until the terminal settles.
  Future<void> sendLineAndWait(
    String text, {
    Duration? silence,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    sendLine(text);
    await waitForQuiet(silence: silence, timeout: timeout);
  }

  // --- Automation Expectations ---

  /// Waits for output activity to start arriving, and then waits until the output
  /// stream settles into a quiet state for the duration of [silence].
  Future<void> waitForResponse({
    Duration? silence,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final effectiveSilence = silence ?? quietPeriod;
    final stopwatch = Stopwatch()..start();

    // 1. Wait for activity to start
    await onOutput.first.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for response output to begin',
        timeout,
      ),
    );

    // 2. Wait for quiet period after output begins
    final remainingTimeout = timeout - stopwatch.elapsed;
    if (remainingTimeout <= Duration.zero) {
      throw TimeoutException('Timed out waiting for terminal quiet', timeout);
    }
    await waitForQuiet(silence: effectiveSilence, timeout: remainingTimeout);
  }

  /// Waits until no new output arrives for the given [silence] interval.
  Future<void> waitForQuiet({
    Duration? silence,
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_isQuiet && (silence == null || silence == quietPeriod)) {
      return Future.value();
    }

    if (silence == null || silence == quietPeriod) {
      return onQuiet.first.timeout(timeout, onTimeout: () {
        throw TimeoutException('Timed out waiting for terminal quiet', timeout);
      });
    }

    final effectiveSilence = silence;
    final completer = Completer<void>();

    Timer? timer;
    Timer? timeoutTimer;
    StreamSubscription<String>? sub;

    void resetTimer() {
      timer?.cancel();
      timer = Timer(effectiveSilence, () {
        sub?.cancel();
        timeoutTimer?.cancel();
        _isQuiet = true;
        if (!completer.isCompleted) completer.complete();
      });
    }

    sub = onOutput.listen((_) => resetTimer());
    resetTimer();

    timeoutTimer = Timer(timeout, () {
      sub?.cancel();
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Timed out waiting for terminal quiet', timeout),
        );
      }
    });

    return completer.future;
  }

  /// Waits for the terminal bell to ring.
  Future<int> waitForBell({Duration timeout = const Duration(seconds: 5)}) {
    final initialCount = _bellCount;
    return onBell
        .firstWhere((count) => count > initialCount)
        .timeout(timeout, onTimeout: () {
      throw TimeoutException('Timed out waiting for terminal bell', timeout);
    });
  }

  /// Waits for an OSC tag with the specified [code] and optional [argPattern].
  Future<TerminalTagEvent> waitForTag(
    String code, {
    Pattern? argPattern,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return onTag.firstWhere((event) {
      if (event.code != code) return false;
      if (argPattern == null) return true;
      return event.args.any((arg) => argPattern.allMatches(arg).isNotEmpty);
    }).timeout(timeout, onTimeout: () {
      throw TimeoutException(
        'Timed out waiting for OSC tag $code ($argPattern)',
        timeout,
      );
    });
  }

  /// Waits for visible screen text or back-buffer to match [pattern].
  Future<void> waitForPattern(
    Pattern pattern, {
    Duration timeout = const Duration(seconds: 10),
    bool searchBackBuffer = true,
  }) async {
    final stopwatch = Stopwatch()..start();

    bool checkMatch() {
      final screenText = getScreenText();
      if (pattern.allMatches(screenText).isNotEmpty) return true;

      if (searchBackBuffer) {
        for (var line in _capturedBackBuffer.reversed) {
          if (pattern.allMatches(line).isNotEmpty) return true;
        }
      }
      return false;
    }

    if (checkMatch()) return;

    while (stopwatch.elapsed < timeout) {
      await Future.any([
        onOutput.first,
        Future.delayed(const Duration(milliseconds: 50)),
      ]);
      if (checkMatch()) return;
    }

    throw TimeoutException(
      'Timed out waiting for pattern "$pattern" in terminal',
      timeout,
    );
  }

  // --- Screen Capture and Inspection ---

  /// Captures a snapshot of the current visible screen.
  TerminalScreenSnapshot captureSnapshot({String? label}) {
    final lines = getScreenLines(trimTrailing: true);
    final cursor = CellOffset(terminal.buffer.cursorX, terminal.buffer.cursorY);
    final snapshot = TerminalScreenSnapshot(
      lines: lines,
      cursor: cursor,
      isAltBuffer: terminal.isUsingAltBuffer,
      label: label,
    );
    _snapshots.add(snapshot);
    return snapshot;
  }

  /// Returns lines of text currently visible in the viewport.
  List<String> getScreenLines({bool trimTrailing = true}) {
    final result = <String>[];
    final buffer = terminal.buffer;
    final viewHeight = terminal.viewHeight;
    final scrollBack = buffer.scrollBack;

    for (var i = 0; i < viewHeight; i++) {
      final lineIndex = i + scrollBack;
      if (lineIndex < buffer.lines.length) {
        var line = buffer.lines[lineIndex].toString();
        if (trimTrailing) {
          line = line.trimRight();
        }
        result.add(line);
      } else {
        result.add('');
      }
    }
    return result;
  }

  /// Returns full text of the visible viewport.
  String getScreenText({bool trimTrailing = true}) {
    return getScreenLines(trimTrailing: trimTrailing).join('\n');
  }

  /// Disposes driver resources and restores original callbacks.
  void dispose() {
    _quietTimer?.cancel();

    terminal.onBell = _prevOnBell;
    terminal.onPrivateOSC = _prevOnPrivateOsc;
    terminal.onWrite = _prevOnWrite;
    terminal.onLineScrolledOff = _prevOnLineScrolledOff;
    terminal.onScreenCleared = _prevOnScreenCleared;

    _quietController.close();
    _bellController.close();
    _tagController.close();
    _outputController.close();
  }
}
