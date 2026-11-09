import 'dart:async';
import 'dart:collection';

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
///
/// Input is injected through [Terminal.textInput] and [Terminal.keyInput], so
/// it reaches the target process through [Terminal.onOutput] exactly like
/// keyboard input from a [TerminalView] would. Wire [Terminal.onOutput] to the
/// PTY (or a simulated responder) before driving the terminal.
class TerminalDriver {
  TerminalDriver(
    this.terminal, {
    this.quietPeriod = const Duration(milliseconds: 300),
    this.maxBackBufferLines = 5000,
    this.maxSnapshots = 500,
    this.maxTagEvents = 1000,
    bool autoCaptureSnapshots = true,
  }) : _autoCaptureSnapshots = autoCaptureSnapshots {
    _initHooks();
  }

  /// The underlying terminal instance being driven.
  final Terminal terminal;

  /// The duration of silence required to declare the terminal quiet/settled.
  final Duration quietPeriod;

  /// Maximum number of lines to retain in the captured back-buffer.
  final int maxBackBufferLines;

  /// Maximum number of screen snapshots to retain.
  final int maxSnapshots;

  /// Maximum number of OSC tag events to retain.
  final int maxTagEvents;

  final bool _autoCaptureSnapshots;

  Timer? _quietTimer;
  bool _isQuiet = true;
  bool _hasUnsettledOutput = false;
  DateTime? _lastActivityAt;

  int _bellCount = 0;
  int _bellFloor = 0;
  int _writeSeq = 0;
  int _writeSeqAtLastSend = 0;
  int _totalBackBufferAppended = 0;
  int _backBufferFloor = 0;
  int _totalTagsAppended = 0;
  int _tagFloor = 0;
  List<String>? _screenAtLastSend;

  final _tagEvents = ListQueue<TerminalTagEvent>();
  final _capturedBackBuffer = ListQueue<String>();
  final _altScrolledLines = ListQueue<String>();
  final _snapshots = ListQueue<TerminalScreenSnapshot>();

  final _activityController = StreamController<void>.broadcast();
  final _quietController = StreamController<void>.broadcast();
  final _bellController = StreamController<int>.broadcast();
  final _tagController = StreamController<TerminalTagEvent>.broadcast();
  final _writeController = StreamController<String>.broadcast();

  void Function()? _prevOnBell;
  void Function(String code, List<String> args)? _prevOnPrivateOsc;
  void Function(String data)? _prevOnWrite;
  void Function(BufferLine line, {required bool isAltBuffer})?
      _prevOnLineScrolledOff;
  void Function({required bool isAltBuffer})? _prevOnScreenCleared;

  void _initHooks() {
    final buf = terminal.mainBuffer;
    for (var i = 0; i < buf.scrollBack; i++) {
      _appendBackBuffer(buf.lines[i].toString().trimRight());
    }
    _backBufferFloor = _totalBackBufferAppended;

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
    _writeSeq++;
    _hasUnsettledOutput = true;
    _prevOnWrite?.call(data);
    _writeController.add(data);
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
    _totalTagsAppended++;
    _tagEvents.addLast(event);
    while (_tagEvents.length > maxTagEvents) {
      _tagEvents.removeFirst();
    }
    _tagController.add(event);
    _prevOnPrivateOsc?.call(code, args);
    _bumpActivity();
  }

  void _handleLineScrolledOff(BufferLine line, {required bool isAltBuffer}) {
    final lineText = line.toString().trimRight();
    _hasUnsettledOutput = true;
    _appendBackBuffer(lineText);
    if (isAltBuffer) {
      _altScrolledLines.addLast(lineText);
      while (_altScrolledLines.length > maxBackBufferLines) {
        _altScrolledLines.removeFirst();
      }
    }
    _prevOnLineScrolledOff?.call(line, isAltBuffer: isAltBuffer);
    _bumpActivity();
  }

  void _handleScreenCleared({required bool isAltBuffer}) {
    _hasUnsettledOutput = true;
    if (_autoCaptureSnapshots) {
      final lines = getScreenLines(trimTrailing: true);
      if (lines.any((line) => line.isNotEmpty)) {
        captureSnapshot(label: 'before-clear (alt: $isAltBuffer)');
      }
    }
    _prevOnScreenCleared?.call(isAltBuffer: isAltBuffer);
    _bumpActivity();
  }

  void _bumpActivity() {
    _lastActivityAt = DateTime.now();
    _isQuiet = false;
    _activityController.add(null);
    _quietTimer?.cancel();
    _quietTimer = Timer(quietPeriod, _onSilenceSettled);
  }

  void _onSilenceSettled() {
    if (terminal.pendingWriteLength > 0) {
      _quietTimer = Timer(quietPeriod, _onSilenceSettled);
      return;
    }
    _isQuiet = true;
    if (_autoCaptureSnapshots && _hasUnsettledOutput) {
      _hasUnsettledOutput = false;
      captureSnapshot(label: 'settled');
    }
    _quietController.add(null);
  }

  void _appendBackBuffer(String line) {
    _totalBackBufferAppended++;
    _capturedBackBuffer.addLast(line);
    while (_capturedBackBuffer.length > maxBackBufferLines) {
      _capturedBackBuffer.removeFirst();
    }
  }

  // --- Public State and Streams ---

  /// Whether the terminal currently has no pending output activity.
  bool get isQuiet => _isQuiet && terminal.pendingWriteLength == 0;

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

  /// Stream of raw program output as it is written to the terminal, mirroring
  /// [Terminal.onWrite]. Not to be confused with [Terminal.onOutput], which
  /// carries input from the terminal to the program.
  Stream<String> get onWrite => _writeController.stream;

  /// Unified back-buffer: main-buffer scrollback present at construction plus
  /// every line that has since left the viewport in either buffer.
  List<String> get capturedBackBuffer =>
      List.unmodifiable(_capturedBackBuffer);

  /// Specifically captured lines that scrolled off during alternative buffer mode.
  List<String> get altScrolledLines => List.unmodifiable(_altScrolledLines);

  /// Saved screen snapshots.
  List<TerminalScreenSnapshot> get snapshots => List.unmodifiable(_snapshots);

  // --- Script Actions ---

  /// Sends raw text input to the program via [Terminal.textInput].
  void send(String text) {
    _markSend();
    terminal.textInput(text);
    _bumpActivity();
  }

  /// Records the output sequence, back-buffer position and screen contents at
  /// the moment of a send so later waits can ignore pre-existing content.
  void _markSend() {
    _writeSeqAtLastSend = _writeSeq;
    _backBufferFloor = _totalBackBufferAppended;
    _bellFloor = _bellCount;
    _tagFloor = _totalTagsAppended;
    _screenAtLastSend = getScreenLines(trimTrailing: true);
  }

  /// Sends text followed by a carriage return.
  void sendLine(String text) {
    send('$text\r');
  }

  /// Sends a key with optional modifiers via [Terminal.keyInput]. Returns
  /// whether the terminal's input handler produced a sequence for it; an
  /// unhandled key leaves the driver's send watermarks untouched.
  bool sendKey(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
  }) {
    final prevSeq = _writeSeqAtLastSend;
    final prevBackBufferFloor = _backBufferFloor;
    final prevBellFloor = _bellFloor;
    final prevTagFloor = _tagFloor;
    final prevScreen = _screenAtLastSend;
    _markSend();
    final handled = terminal.keyInput(
      key,
      shift: shift,
      alt: alt,
      ctrl: ctrl,
    );
    if (handled) {
      _bumpActivity();
    } else {
      _writeSeqAtLastSend = prevSeq;
      _backBufferFloor = prevBackBufferFloor;
      _bellFloor = prevBellFloor;
      _tagFloor = prevTagFloor;
      _screenAtLastSend = prevScreen;
    }
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

    // 1. Wait for activity to start if none has arrived since the last send
    if (_writeSeq <= _writeSeqAtLastSend) {
      await onWrite.first.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for response output to begin',
          timeout,
        ),
      );
    }

    // 2. Wait for quiet period after output begins
    final remainingTimeout = timeout - stopwatch.elapsed;
    if (remainingTimeout <= Duration.zero) {
      throw TimeoutException('Timed out waiting for terminal quiet', timeout);
    }
    await waitForQuiet(silence: effectiveSilence, timeout: remainingTimeout);
    _writeSeqAtLastSend = _writeSeq;
  }

  /// Waits until no new output arrives for the given [silence] interval.
  Future<void> waitForQuiet({
    Duration? silence,
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (silence == null || silence == quietPeriod) {
      if (isQuiet) {
        return Future.value();
      }
      return onQuiet
          .firstWhere((_) => isQuiet)
          .timeout(timeout, onTimeout: () {
        throw TimeoutException('Timed out waiting for terminal quiet', timeout);
      });
    }

    final effectiveSilence = silence;
    final lastActivity = _lastActivityAt;
    if (lastActivity == null && terminal.pendingWriteLength == 0) {
      return Future.value();
    }

    final elapsed = lastActivity != null
        ? DateTime.now().difference(lastActivity)
        : Duration.zero;
    if (lastActivity != null &&
        elapsed >= effectiveSilence &&
        terminal.pendingWriteLength == 0) {
      return Future.value();
    }

    final completer = Completer<void>();

    Timer? timer;
    Timer? timeoutTimer;
    StreamSubscription<void>? sub;

    void scheduleTimer(Duration delay) {
      timer?.cancel();
      timer = Timer(delay, () {
        if (terminal.pendingWriteLength > 0) {
          scheduleTimer(effectiveSilence);
          return;
        }
        sub?.cancel();
        timeoutTimer?.cancel();
        if (!completer.isCompleted) completer.complete();
      });
    }

    sub = _activityController.stream.listen((_) => scheduleTimer(effectiveSilence));
    final initialDelay = lastActivity != null && elapsed < effectiveSilence
        ? effectiveSilence - elapsed
        : effectiveSilence;
    scheduleTimer(initialDelay);

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
    if (_bellCount > _bellFloor) {
      _bellFloor = _bellCount;
      return Future.value(_bellCount);
    }
    final initialCount = _bellFloor;
    return onBell
        .firstWhere((count) => count > initialCount)
        .then((count) {
      if (_bellFloor < count) _bellFloor = count;
      return count;
    }).timeout(timeout, onTimeout: () {
      throw TimeoutException('Timed out waiting for terminal bell', timeout);
    });
  }

  /// Waits for an OSC tag with the specified [code] and optional [argPattern].
  Future<TerminalTagEvent> waitForTag(
    String code, {
    Pattern? argPattern,
    Duration timeout = const Duration(seconds: 10),
  }) {
    bool matchesTag(TerminalTagEvent event) {
      if (event.code != code) return false;
      if (argPattern == null) return true;
      return event.args.any((arg) => argPattern.allMatches(arg).isNotEmpty) ||
          argPattern.allMatches(event.args.join(';')).isNotEmpty;
    }

    final unconsumed = _totalTagsAppended - _tagFloor;
    if (unconsumed > 0 && _tagEvents.isNotEmpty) {
      final length = _tagEvents.length;
      final count = unconsumed < length ? unconsumed : length;
      final startIndex = length - count;
      for (var i = startIndex; i < length; i++) {
        final event = _tagEvents.elementAt(i);
        if (matchesTag(event)) {
          _tagFloor = _totalTagsAppended - (length - 1 - i);
          return Future.value(event);
        }
      }
    }

    return onTag.firstWhere(matchesTag).then((event) {
      _tagFloor = _totalTagsAppended;
      return event;
    }).timeout(timeout, onTimeout: () {
      throw TimeoutException(
        'Timed out waiting for OSC tag $code ($argPattern)',
        timeout,
      );
    });
  }

  /// Waits for visible screen text or back-buffer to match [pattern].
  ///
  /// By default only content produced since the last [send] or [sendKey] is
  /// considered: back-buffer lines captured before the send are skipped, and
  /// screen rows whose text is unchanged since the send (after accounting for
  /// lines that scrolled off in between) are treated as stale and ignored.
  /// Pass [sinceLastSend] as false to match against everything on screen.
  Future<void> waitForPattern(
    Pattern pattern, {
    Duration timeout = const Duration(seconds: 10),
    bool searchBackBuffer = true,
    bool sinceLastSend = true,
  }) {
    var checkedBackBufferSeq = sinceLastSend ? _backBufferFloor : 0;

    bool checkMatch() {
      if (sinceLastSend && checkedBackBufferSeq < _backBufferFloor) {
        checkedBackBufferSeq = _backBufferFloor;
      }
      final screenText = sinceLastSend
          ? _freshScreenLines().join('\n')
          : getScreenText();
      if (pattern.allMatches(screenText).isNotEmpty) return true;

      if (searchBackBuffer && _capturedBackBuffer.isNotEmpty) {
        final length = _capturedBackBuffer.length;
        final searchableCount = _totalBackBufferAppended - checkedBackBufferSeq;
        if (searchableCount > 0) {
          final count = searchableCount < length ? searchableCount : length;
          // ListQueue.elementAt is O(1); walk newest-first without copying.
          for (var i = length - 1; i >= length - count; i--) {
            if (pattern.allMatches(_capturedBackBuffer.elementAt(i)).isNotEmpty) {
              return true;
            }
          }
          checkedBackBufferSeq = _totalBackBufferAppended;
        }
      }
      return false;
    }

    if (checkMatch()) return Future.value();

    final completer = Completer<void>();
    StreamSubscription<void>? sub;
    Timer? timeoutTimer;

    void cleanup() {
      sub?.cancel();
      timeoutTimer?.cancel();
    }

    sub = _activityController.stream.listen((_) {
      if (!completer.isCompleted && checkMatch()) {
        cleanup();
        completer.complete();
      }
    });

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        cleanup();
        if (checkMatch()) {
          completer.complete();
        } else {
          completer.completeError(
            TimeoutException(
              'Timed out waiting for pattern "$pattern" in terminal',
              timeout,
            ),
          );
        }
      }
    });

    return completer.future;
  }

  /// Returns the current screen rows with rows that are unchanged since the
  /// last send blanked out. Row `i` is compared against the row that occupied
  /// `i + shift` at send time, where `shift` is the number of lines evicted
  /// since; rows with no counterpart (new output, or a cleared screen) count
  /// as fresh. Before any send every row is fresh.
  List<String> _freshScreenLines() {
    final current = getScreenLines(trimTrailing: true);
    final previous = _screenAtLastSend;
    if (previous == null) return current;

    final shift = _totalBackBufferAppended - _backBufferFloor;
    for (var i = 0; i < current.length; i++) {
      final previousIndex = i + shift;
      if (previousIndex < previous.length &&
          previous[previousIndex] == current[i]) {
        current[i] = '';
      }
    }
    return current;
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
    _snapshots.addLast(snapshot);
    while (_snapshots.length > maxSnapshots) {
      _snapshots.removeFirst();
    }
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

    _activityController.close();
    _quietController.close();
    _bellController.close();
    _tagController.close();
    _writeController.close();
  }
}
