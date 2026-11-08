@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

String _findAgy() {
  final home = Platform.environment['HOME'] ?? '';
  final candidates = [
    if (home.isNotEmpty) '$home/.local/bin/agy',
    '/usr/local/bin/agy',
    '/opt/homebrew/bin/agy',
    'agy',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return 'agy';
}

String _getPtyBridge() {
  const candidates = [
    'example/pty_bridge.py',
    '.temp/pty_bridge.py',
    '../example/pty_bridge.py',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return 'example/pty_bridge.py';
}

void main() {
  test('Live agy interaction with TerminalDriver', () async {
    print('========================================================');
    print('  xterm.dart TerminalDriver Live agy Interaction Test');
    print('========================================================\n');

    final terminal = Terminal(maxLines: 10000);
    terminal.resize(80, 24);

    final agyPath = _findAgy();
    final ptyBridgePath = _getPtyBridge();
    print('[DRIVER] Spawning agy ($agyPath) with Gemini 3.8 Flash (Medium) in 80x24 PTY via $ptyBridgePath...');

    final proc = await Process.start(
      'python3',
      [
        ptyBridgePath,
        '80',
        '24',
        agyPath,
        '--model',
        'gemini-3.8-flash-medium',
      ],
      environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );

    final driver = TerminalDriver(
      terminal,
      quietPeriod: const Duration(seconds: 4),
      onSend: (text) {
        proc.stdin.write(text);
        proc.stdin.flush();
      },
    );

    // Hook terminal writes from PTY
    proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    driver.onQuiet.listen((_) {
      print('  -> [EVENT] Terminal settled into quiet state.');
    });

    print('[DRIVER] Waiting for agy prompt to appear...');
    await driver.waitForPattern(
      RegExp(r'\? for shortcuts|>'),
      timeout: const Duration(seconds: 30),
    );
    await driver.waitForQuiet(
      silence: const Duration(seconds: 2),
      timeout: const Duration(seconds: 10),
    );
    print('[DRIVER] agy startup completed! Prompt is ready.\n');

    // --- Task 1 ---
    const task1 =
        'Explain how virtual memory, page tables, and TLBs work in operating systems. Output 25 numbered points.';
    print('[DRIVER] Sending Task 1 into agy:');
    print('         "$task1"\n');
    driver.sendLine(task1);

    print('[DRIVER] Waiting for agy response generation to stream and settle...');
    final sw1 = Stopwatch()..start();
    await driver.waitForResponse(
      silence: const Duration(seconds: 4),
      timeout: const Duration(seconds: 90),
    );
    sw1.stop();

    print('[DRIVER] Task 1 completed in ${sw1.elapsed.inSeconds}s!');
    print('=== CURRENT SCREEN ===\n${driver.getScreenText()}\n======================');
    final backBuffer = driver.allBackBufferLines;
    final task1Scrolled = backBuffer.length;
    final task1Visible =
        driver.getScreenLines(trimTrailing: true).where((l) => l.isNotEmpty).length;
    print('         Lines scrolled off screen into back-buffer : $task1Scrolled');
    print('         Lines currently visible on screen          : $task1Visible\n');
    driver.captureSnapshot(label: 'task1-done');

    expect(task1Scrolled, greaterThan(0),
        reason: 'Long output should scroll off the screen into the captured back buffer');

    // Display preview of scrolled-off content
    print('--- Preview of Content Scrolled Off Top of Screen (First 5 lines) ---');
    for (var i = 0; i < task1Scrolled && i < 5; i++) {
      print('  [SCROLLBACK #$i] ${backBuffer[i]}');
    }
    print('  ...');
    print('--- Preview of Visible Screen Lines (Last 5 lines) ---');
    final screenLines =
        driver.getScreenLines(trimTrailing: true).where((l) => l.isNotEmpty).toList();
    for (var i = screenLines.length > 5 ? screenLines.length - 5 : 0;
        i < screenLines.length;
        i++) {
      print('  [VIEWPORT] ${screenLines[i]}');
    }
    print('-----------------------------------------------------\n');

    // --- Task 2: Continue interaction ---
    const task2 =
        'From that explanation, summarize the top 3 key takeaways in 3 short bullet points.';
    print('[DRIVER] Continuing interaction. Sending follow-up Task 2:');
    print('         "$task2"\n');
    driver.sendLine(task2);

    print('[DRIVER] Waiting for agy follow-up response to settle...');
    final sw2 = Stopwatch()..start();
    await driver.waitForResponse(
      silence: const Duration(seconds: 4),
      timeout: const Duration(seconds: 60),
    );
    sw2.stop();

    print('[DRIVER] Task 2 completed in ${sw2.elapsed.inSeconds}s!');
    driver.captureSnapshot(label: 'task2-done');

    final totalBackBuffer = driver.allBackBufferLines;
    final totalScrolled = totalBackBuffer.length;
    final finalScreenLines =
        driver.getScreenLines(trimTrailing: true).where((l) => l.isNotEmpty).toList();
    print('         Total lines scrolled off into back-buffer : $totalScrolled');
    print('         Final visible lines on screen              : ${finalScreenLines.length}\n');

    print('--- Final Screen Content ---');
    for (var line in finalScreenLines) {
      print('  $line');
    }
    print('----------------------------\n');

    // Exit cleanly
    print('[DRIVER] Sending "/exit" to agy session...');
    driver.sendLine('/exit');
    await Future.delayed(const Duration(seconds: 2));

    // Save transcript
    final transcriptPath = '.temp/agy_automation_transcript.txt';
    final fullTranscript = StringBuffer()
      ..writeln('=== SCROLLED OFF LINES ($totalScrolled lines) ===')
      ..writeln(totalBackBuffer.join('\n'))
      ..writeln('\n=== FINAL VISIBLE SCREEN ===')
      ..writeln(driver.getScreenText());

    File(transcriptPath).writeAsStringSync(fullTranscript.toString());
    print('[DRIVER] Full transcript saved to $transcriptPath.');

    // Save structured JSON result
    final resultJsonPath = '.temp/agy_automation_result.json';
    File(resultJsonPath).writeAsStringSync(jsonEncode({
      'status': 'SUCCESS',
      'task1_prompt': task1,
      'task1_elapsed_seconds': sw1.elapsed.inSeconds,
      'task1_scrolled_lines': task1Scrolled,
      'task2_prompt': task2,
      'task2_elapsed_seconds': sw2.elapsed.inSeconds,
      'total_scrolled_lines': totalScrolled,
      'snapshots_count': driver.snapshots.length,
      'transcript_file': transcriptPath,
    }));
    print('[DRIVER] Results metadata saved to $resultJsonPath.');

    driver.dispose();
    proc.kill();
    print('\n[DRIVER] Live agy interaction test completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
