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
  test('Gemini sends special tag to trigger driver action', () async {
    print('================================================================');
    print('  Test: Gemini Sending Special OSC Tag to Trigger Driver Action');
    print('================================================================\n');

    final terminal = Terminal(maxLines: 10000);
    terminal.resize(80, 24);

    final agyPath = _findAgy();
    final ptyBridgePath = _getPtyBridge();
    print('[DRIVER] Spawning agy ($agyPath) via $ptyBridgePath in 80x24 PTY...');

    final proc = await Process.start(
      'python3',
      [
        ptyBridgePath,
        '80',
        '24',
        agyPath,
        '--model',
        'gemini-3.8-flash-medium',
        '--dangerously-skip-permissions',
      ],
      environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );

    final driver = TerminalDriver(
      terminal,
      quietPeriod: const Duration(milliseconds: 1500),
    );
    terminal.onOutput = (text) {
      proc.stdin.write(text);
      proc.stdin.flush();
    };

    final stdoutSub = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    final stderrSub = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    final triggeredActions = <String>[];

    driver.onTag.listen((tag) {
      print('  -> [EVENT: TAG] code=${tag.code}, args=${tag.args}');
    });

    driver.onBell.listen((_) {
      print('  -> [EVENT: BELL] Terminal bell received.');
    });

    print('[DRIVER] Waiting for agy startup & prompt...');
    await driver.waitForPattern(
      RegExp(r'\? for shortcuts|>'),
      timeout: const Duration(seconds: 30),
    );
    await driver.waitForQuiet(
      silence: const Duration(seconds: 2),
      timeout: const Duration(seconds: 10),
    );
    print('[DRIVER] agy is ready.\n');

    // Prompt Gemini to output the special tag at the start of its own line
    const initialPrompt =
        'Explain what a page table is in 2 concise sentences. '
        'Immediately after, on a new line starting with ">>", output: '
        '>>[TAG:TRIGGER_ACTION:request_snapshot_and_ack]';
    print('[DRIVER] Prompting Gemini: "$initialPrompt"');
    driver.sendLine(initialPrompt);

    print('[DRIVER] Waiting for Gemini to emit >>[TAG:TRIGGER_ACTION:request_snapshot_and_ack]...');
    await driver.waitForPattern(
      RegExp(
        r'^\s*>>\[TAG:TRIGGER_ACTION:request_snapshot_and_ack\]',
        multiLine: true,
      ),
      timeout: const Duration(seconds: 45),
    );
    print('[DRIVER] Special tag received from Gemini! Triggering automated action...\n');
    triggeredActions.add('request_snapshot_and_ack');

    // Trigger action: Capture snapshot and send follow-up task
    driver.captureSnapshot(label: 'gemini-trigger-request_snapshot_and_ack');
    print('  [ACTION EXECUTION] Captured snapshot on demand: "${driver.snapshots.last.label}"');
    print('  [ACTION EXECUTION] Sending follow-up instruction to Gemini...\n');

    const followUpPrompt =
        'Driver received the tag and captured the snapshot! '
        'Now compute 123 * 456, and then on a new line starting with ">>", output: '
        '>>[TAG:TRIGGER_ACTION:all_steps_done]';
    driver.sendLine(followUpPrompt);

    print('[DRIVER] Waiting for Gemini to emit >>[TAG:TRIGGER_ACTION:all_steps_done]...');
    await driver.waitForPattern(
      RegExp(
        r'^\s*>>\[TAG:TRIGGER_ACTION:all_steps_done\]',
        multiLine: true,
      ),
      timeout: const Duration(seconds: 45),
    );
    print('[DRIVER] Second tag received! Triggering all_steps_done action...\n');
    triggeredActions.add('all_steps_done');

    print('[DRIVER] Waiting for output stream to settle...');
    await driver.waitForQuiet(
      silence: const Duration(milliseconds: 1500),
      timeout: const Duration(seconds: 30),
    );

    print('\n================ VERIFICATION RESULTS ================');
    print('Triggered actions count: ${triggeredActions.length}');
    print('Triggered actions: $triggeredActions');
    print('Snapshots captured: ${driver.snapshots.length}');
    print('Lines scrolled off screen: ${driver.capturedBackBuffer.length}');
    print('Screen contains calculation result: ${driver.getScreenText().contains("56,088") || driver.getScreenText().contains("56088")}');
    print('======================================================\n');

    expect(triggeredActions, contains('request_snapshot_and_ack'));
    expect(triggeredActions, contains('all_steps_done'));
    expect(driver.snapshots.any((s) => s.label?.contains('request_snapshot_and_ack') == true), isTrue);
    expect(driver.getScreenText().contains('56,088') || driver.getScreenText().contains('56088'), isTrue);

    print('[DRIVER] Sending "/exit" to agy...');
    driver.sendLine('/exit');
    await Future.delayed(const Duration(seconds: 2));

    await stdoutSub.cancel();
    await stderrSub.cancel();
    driver.dispose();
    proc.kill();
    print('\n[DRIVER] Test completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
