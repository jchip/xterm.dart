import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

void main() {
  runApp(const TerminalAutomationDemoApp());
}

class TerminalAutomationDemoApp extends StatelessWidget {
  const TerminalAutomationDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xterm.dart Automation & Driver Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF181A1F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF61AFEF),
          secondary: Color(0xFF98C379),
          surface: Color(0xFF21252B),
        ),
      ),
      home: const AutomationDemoPage(),
    );
  }
}

class AutomationDemoPage extends StatefulWidget {
  const AutomationDemoPage({super.key});

  @override
  State<AutomationDemoPage> createState() => _AutomationDemoPageState();
}

class _AutomationDemoPageState extends State<AutomationDemoPage>
    with SingleTickerProviderStateMixin {
  late final Terminal terminal;
  late TerminalDriver driver;
  late final TabController tabController;

  String statusText = 'Ready';
  bool isRunningScenario = false;
  final List<String> executionLogs = [];
  Pty? _activePty;
  Process? _activeProcess;
  Timer? _triggerTimer;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 4, vsync: this);

    terminal = Terminal(maxLines: 2000);
    terminal.onOutput = _handleDriverSend;
    driver = TerminalDriver(
      terminal,
      quietPeriod: const Duration(milliseconds: 300),
    );

    _hookDriverEvents();
    terminal.addListener(() => setState(() {}));

    _triggerTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      _checkTriggers,
    );

    // Welcome banner
    terminal.write(
      '\x1b[1;36m=== xterm.dart Terminal Automation Driver Demo ===\x1b[0m\r\n'
      'Ready to execute automation scripts with quiet detection,\r\n'
      'alt-buffer scrollback capture, OSC tags, and bell tracking.\r\n\r\n'
      '\x1b[90mSelect a scenario on the right panel to begin.\x1b[0m\r\n\r\n'
      '\$ ',
    );
  }

  void _hookDriverEvents() {
    driver.onQuiet.listen((_) => _refreshState('Quiet (Settled)'));
    driver.onBell.listen((count) => _refreshState('Bell ring #$count'));
    driver.onTag.listen((tag) => _refreshState('Tag received: ${tag.code}'));
  }

  void _checkTriggers(Timer timer) {
    final trigger = File('.temp/run_agy.trigger');
    if (trigger.existsSync()) {
      try {
        trigger.deleteSync();
      } catch (_) {}
      if (!isRunningScenario) {
        _runScenario5LiveAgy();
      }
    }
  }

  void _handleDriverSend(String text) {
    // Simulated shell response engine
    _addLog('Driver -> Terminal Input: ${text.replaceAll('\r', '\\r')}');

    // Echo input back like a terminal
    terminal.write(text);

    final cleanText = text.replaceAll('\r', '').trim();
    if (cleanText.isEmpty) return;

    Timer(const Duration(milliseconds: 60), () {
      if (cleanText.startsWith('echo ')) {
        final arg = cleanText.substring(5);
        terminal.write('\r\n$arg\r\n\$ ');
      }
    });
  }

  void _addLog(String msg) {
    print('[DEMO] $msg');
    setState(() {
      final now = DateTime.now().toIso8601String().substring(11, 19);
      executionLogs.add('[$now] $msg');
      if (executionLogs.length > 200) executionLogs.removeAt(0);
    });
  }

  void _refreshState(String status) {
    setState(() {
      statusText = status;
    });
  }

  @override
  void dispose() {
    _triggerTimer?.cancel();
    _activePty?.kill();
    _activeProcess?.kill();
    driver.dispose();
    tabController.dispose();
    super.dispose();
  }

  // --- Scenarios ---

  Future<void> _runScenario1CliQuiet() async {
    if (isRunningScenario) return;
    setState(() => isRunningScenario = true);
    _addLog('Scenario 1 started: CLI automation with quiet detection');

    try {
      terminal.write('npm test\r\n');
      _addLog('Emitted command "npm test". Waiting for quiet period...');

      await Future.delayed(const Duration(milliseconds: 150));
      terminal.write('Running suite 1/3: core-tests...\r\n');

      await Future.delayed(const Duration(milliseconds: 200));
      terminal.write('Running suite 2/3: buffer-tests...\r\n');

      await Future.delayed(const Duration(milliseconds: 200));
      terminal.write('Running suite 3/3: integration-tests...\r\n');

      await Future.delayed(const Duration(milliseconds: 200));
      terminal.write('All 3 suites passed! (32 tests)\r\n\$ ');

      // Driver waits until quiet
      await driver.waitForQuiet(silence: const Duration(milliseconds: 300));
      _addLog('Quiet period confirmed! Program has settled.');

      // Automated follow-up command
      _addLog('Sending next command "git status"...');
      driver.sendLine('git status');
      await Future.delayed(const Duration(milliseconds: 100));
      terminal.write('On branch master\r\nnothing to commit, working tree clean\r\n\$ ');

      await driver.waitForQuiet();
      _addLog('Scenario 1 completed successfully.');
    } finally {
      setState(() => isRunningScenario = false);
    }
  }

  Future<void> _runScenario2AltBufferCapture() async {
    if (isRunningScenario) return;
    setState(() => isRunningScenario = true);
    _addLog('Scenario 2 started: Alt-buffer pager with back-buffer capture');

    try {
      terminal.write('less long_changelog.txt\r\n');
      await Future.delayed(const Duration(milliseconds: 200));

      // Switch to alternative screen buffer (CSI ? 1049 h)
      terminal.write('\x1b[?1049h\x1b[H\x1b[2J');
      _addLog('Switched to Alternative Screen Buffer (TUI mode)');

      // Draw initial TUI viewport (5 lines)
      for (var i = 1; i <= 5; i++) {
        terminal.write('Changelog entry #$i: initialized feature v$i\r\n');
      }

      await Future.delayed(const Duration(milliseconds: 300));
      _addLog('Paging down through 10 more lines in alt buffer...');

      // Scroll lines off the top
      for (var i = 6; i <= 15; i++) {
        await Future.delayed(const Duration(milliseconds: 80));
        terminal.write('Changelog entry #$i: patch release note fix $i\r\n');
      }

      await driver.waitForQuiet(silence: const Duration(milliseconds: 200));
      _addLog(
        'Alt buffer scrolled! Captured ${driver.altScrolledLines.length} '
        'evicted lines into persistent back-buffer.',
      );

      // Exit pager and switch back to main buffer (CSI ? 1049 l)
      await Future.delayed(const Duration(milliseconds: 500));
      terminal.write('\x1b[?1049l');
      terminal.write('Exited pager.\r\n\$ ');

      _addLog(
        'Switched back to Main Buffer. Scrolled lines remain preserved in Back-Buffer tab!',
      );
    } finally {
      setState(() => isRunningScenario = false);
    }
  }

  Future<void> _runScenario3TagsAndBells() async {
    if (isRunningScenario) return;
    setState(() => isRunningScenario = true);
    _addLog('Scenario 3 started: Semantic OSC tags and bell signaling');

    try {
      // 1. Semantic Prompt Start (OSC 133;A)
      terminal.write('\x1b]133;A\x07');
      terminal.write('\$ ');
      _addLog('Emitted OSC 133;A (Prompt start)');

      await Future.delayed(const Duration(milliseconds: 150));

      // 2. Command entered (OSC 133;B)
      terminal.write('\x1b]133;B\x07');
      terminal.write('deploy --production\r\n');
      _addLog('Emitted OSC 133;B (Command executed)');

      await Future.delayed(const Duration(milliseconds: 200));

      // 3. Custom Application Tag (OSC 777)
      terminal.write('\x1b]777;build;status=in_progress;step=compile\x07');
      terminal.write('Building assets...\r\n');
      _addLog('Emitted OSC 777 custom tag (compile)');

      await Future.delayed(const Duration(milliseconds: 300));

      // 4. Bell event to alert user
      terminal.write('\x07'); // BEL
      terminal.write('\x1b[1;33m[ALERT] Critical step reached! Bell triggered.\x1b[0m\r\n');
      _addLog('Triggered terminal bell (\\a)');

      await Future.delayed(const Duration(milliseconds: 200));

      // 5. Command complete tag (OSC 133;D;0)
      terminal.write('\x1b]133;D;0\x07');
      terminal.write('Deployment completed with exit code 0.\r\n\$ ');
      _addLog('Emitted OSC 133;D;0 (Command completed successfully)');

      await driver.waitForQuiet();
      _addLog('Scenario 3 completed. Check OSC Tags tab!');
    } finally {
      setState(() => isRunningScenario = false);
    }
  }

  Future<void> _runScenario4InPlaceTui() async {
    if (isRunningScenario) return;
    setState(() => isRunningScenario = true);
    _addLog('Scenario 4 started: In-place TUI dashboard & frame snapshots');

    try {
      // Enter alt screen
      terminal.write('\x1b[?1049h\x1b[H\x1b[2J');
      _addLog('Entered alt screen for dashboard');

      for (var tick = 1; tick <= 3; tick++) {
        final cpu = 25 + tick * 18;
        final mem = 40 + tick * 8;
        terminal.write('\x1b[H'); // Move to top-left
        terminal.write('\x1b[1;35m--- TUI SYSTEM DASHBOARD (Frame $tick/3) ---\x1b[0m\r\n');
        terminal.write('CPU Usage : [$cpu%] ${'#' * (cpu ~/ 5)}\r\n');
        terminal.write('Memory    : [$mem%] ${'#' * (mem ~/ 5)}\r\n');
        terminal.write('Status    : Active telemetry stream\r\n');
        driver.captureSnapshot(label: 'TUI-Dashboard-Frame-$tick');
        await Future.delayed(const Duration(milliseconds: 400));
      }

      await Future.delayed(const Duration(milliseconds: 200));
      terminal.write('\x1b[?1049l');
      terminal.write('Closed dashboard.\r\n\$ ');
      _addLog('Scenario 4 completed. Check Snapshots tab for captured frames!');
    } finally {
      setState(() => isRunningScenario = false);
    }
  }

  void _restoreSimulatedDriver() {
    driver.dispose();
    terminal.onOutput = _handleDriverSend;
    driver = TerminalDriver(
      terminal,
      quietPeriod: const Duration(milliseconds: 300),
    );
    _hookDriverEvents();
  }

  Future<void> _runScenario5LiveAgy() async {
    if (isRunningScenario) return;
    setState(() => isRunningScenario = true);
    _addLog('Scenario 5 started: Spawning agy with Gemini 3.8 Flash (Medium)...');

    StreamSubscription? ptySub;
    StreamSubscription? stderrSub;
    try {
      terminal.write(
        '\r\n\x1b[1;34m=== Starting Live agy Session (Gemini 3.8 Flash Medium) ===\x1b[0m\r\n',
      );

      _activePty?.kill();
      _activeProcess?.kill();

      final agyPath = _findAgyPath();
      final ptyBridgePath = _resolvePtyBridgePath();

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
      _activeProcess = proc;

      ptySub = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);

      stderrSub = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);

      driver.dispose();
      driver = TerminalDriver(
        terminal,
        quietPeriod: const Duration(milliseconds: 1500),
      );
      _hookDriverEvents();

      terminal.onOutput = (data) {
        proc.stdin.write(data);
        proc.stdin.flush();
      };

      _addLog('Waiting for agy startup & prompt settlement...');
      await driver.waitForPattern(
        RegExp(r'\? for shortcuts|>'),
        timeout: const Duration(seconds: 35),
      );
      await driver.waitForQuiet(
        silence: const Duration(milliseconds: 1500),
        timeout: const Duration(seconds: 10),
      );
      _addLog('agy ready! Prompt detected on screen.');

      // Task 1: Generate 15 lines explaining virtual memory and TLB
      const task1 =
          'Explain how virtual memory, page tables, and TLBs work in operating systems. Output exactly 15 concise numbered points.';
      _addLog('Sending Task 1: "$task1"');
      driver.sendLine(task1);

      _addLog('Monitoring agy generation stream. Waiting for response & quiet...');
      await driver.waitForResponse(
        silence: const Duration(milliseconds: 1500),
        timeout: const Duration(seconds: 120),
      );
      _addLog('agy Task 1 finished! Quiet period detected.');

      final task1Scrolled = driver.capturedBackBuffer.length;
      final task1Screen = driver
          .getScreenLines(trimTrailing: true)
          .where((l) => l.isNotEmpty)
          .toList();
      _addLog('Task 1 results:');
      _addLog('  - Lines scrolled off screen into back-buffer: $task1Scrolled');
      _addLog('  - Visible lines currently on screen: ${task1Screen.length}');
      driver.captureSnapshot(label: 'agy-task1-finished');

      // Task 2: Follow-up interaction
      const task2 =
          'From that explanation, summarize the top 3 key takeaways in 3 short bullet points.';
      _addLog('Sending follow-up Task 2: "$task2"');
      driver.sendLine(task2);

      _addLog('Waiting for agy follow-up response...');
      await driver.waitForResponse(
        silence: const Duration(milliseconds: 1500),
        timeout: const Duration(seconds: 60),
      );
      _addLog('agy Task 2 finished! Quiet period detected.');
      driver.captureSnapshot(label: 'agy-task2-finished');

      final totalScrolled = driver.capturedBackBuffer.length;
      final allScrolledText = driver.capturedBackBuffer.join('\n');
      final allScreenText = driver.getScreenText();

      // Write results to disk for automated inspection
      final tempDir = Directory('.temp').existsSync() ? Directory('.temp') : Directory.systemTemp;
      final resultFile = File('${tempDir.path}/agy_automation_result.json');
      resultFile.writeAsStringSync(jsonEncode({
        'status': 'SUCCESS',
        'task1_prompt': task1,
        'task1_scrolled_count': task1Scrolled,
        'task2_prompt': task2,
        'total_scrolled_lines': totalScrolled,
        'snapshots_count': driver.snapshots.length,
        'screen_text_sample': allScreenText.substring(0, min(allScreenText.length, 500)),
      }));

      final transcriptFile = File('${tempDir.path}/agy_captured_output.txt');
      transcriptFile.writeAsStringSync(
        '=== CAPTURED SCROLLED-OFF LINES (${driver.capturedBackBuffer.length} lines) ===\n'
        '$allScrolledText\n\n'
        '=== VISIBLE SCREEN TEXT ===\n'
        '$allScreenText\n',
      );

      _addLog('Sending "/exit" to agy...');
      driver.sendLine('/exit');
      await Future.delayed(const Duration(seconds: 2));

      _addLog('Scenario 5 SUCCESS! Captured $totalScrolled scrolled-off lines in back-buffer.');
    } catch (e, st) {
      _addLog('Scenario 5 failed: $e');
      final tempDir = Directory('.temp').existsSync() ? Directory('.temp') : Directory.systemTemp;
      final errFile = File('${tempDir.path}/agy_automation_result.json');
      errFile.writeAsStringSync(jsonEncode({
        'status': 'ERROR',
        'error': e.toString(),
        'screen': driver.getScreenText(),
        'back_buffer_count': driver.capturedBackBuffer.length,
        'stackTrace': st.toString(),
      }));
    } finally {
      await ptySub?.cancel();
      await stderrSub?.cancel();
      _activePty?.kill();
      _activePty = null;
      _activeProcess?.kill();
      _activeProcess = null;
      _restoreSimulatedDriver();
      setState(() => isRunningScenario = false);
    }
  }

  Future<void> _runScenario6GeminiTagTrigger() async {
    if (isRunningScenario) return;
    setState(() => isRunningScenario = true);
    _addLog('Scenario 6 started: Gemini Tag-Triggered Automation');

    StreamSubscription? ptySub;
    StreamSubscription? stderrSub;
    try {
      terminal.write(
        '\r\n\x1b[1;35m=== Starting Gemini Tag-Triggered Automation ===\x1b[0m\r\n',
      );

      _activePty?.kill();
      _activeProcess?.kill();

      final agyPath = _findAgyPath();
      final ptyBridgePath = _resolvePtyBridgePath();

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
      _activeProcess = proc;

      ptySub = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);

      stderrSub = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);

      driver.dispose();
      driver = TerminalDriver(
        terminal,
        quietPeriod: const Duration(milliseconds: 1500),
      );
      _hookDriverEvents();

      terminal.onOutput = (data) {
        proc.stdin.write(data);
        proc.stdin.flush();
      };

      _addLog('Waiting for agy startup & prompt...');
      await driver.waitForPattern(
        RegExp(r'\? for shortcuts|>'),
        timeout: const Duration(seconds: 30),
      );
      await driver.waitForQuiet(silence: const Duration(milliseconds: 1500));
      _addLog('agy ready! Prompt detected.');

      const prompt1 =
          'Explain how virtual memory works in 2 sentences. '
          'Immediately after, on a new line starting with ">>", output: '
          '>>[TAG:TRIGGER_ACTION:request_snapshot_and_ack]';

      _addLog('Sending prompt 1 to Gemini...');
      driver.sendLine(prompt1);

      _addLog('Waiting for Gemini to emit special tag >>[TAG:TRIGGER_ACTION:request_snapshot_and_ack]...');
      await driver.waitForPattern(
        RegExp(
          r'^\s*>>\[TAG:TRIGGER_ACTION:request_snapshot_and_ack\]',
          multiLine: true,
        ),
        timeout: const Duration(seconds: 60),
      );

      _addLog('>>> TAG DETECTED! Driver automatically executing triggered action:');
      final snap = driver.captureSnapshot(label: 'gemini-tag-triggered');
      _addLog('  - Screen snapshot captured: "${snap.label}"');
      _addLog('  - Sending automated response to Gemini...');

      const prompt2 =
          'Driver detected your tag and captured a screen snapshot! '
          'Now calculate 123 * 456, then on a new line starting with ">>", output: '
          '>>[TAG:TRIGGER_ACTION:all_steps_done]';
      driver.sendLine(prompt2);

      _addLog('Waiting for Gemini to emit >>[TAG:TRIGGER_ACTION:all_steps_done]...');
      await driver.waitForPattern(
        RegExp(
          r'^\s*>>\[TAG:TRIGGER_ACTION:all_steps_done\]',
          multiLine: true,
        ),
        timeout: const Duration(seconds: 60),
      );

      _addLog('>>> SECOND TAG DETECTED! Gemini completed all steps.');
      await driver.waitForQuiet(silence: const Duration(milliseconds: 1500));

      _addLog('Sending "/exit" to agy...');
      driver.sendLine('/exit');
      await Future.delayed(const Duration(seconds: 2));

      _addLog('Scenario 6 SUCCESS! Gemini tag-triggered workflow executed.');
    } catch (e) {
      _addLog('Scenario 6 failed: $e');
    } finally {
      await ptySub?.cancel();
      await stderrSub?.cancel();
      _activeProcess?.kill();
      _activeProcess = null;
      _restoreSimulatedDriver();
      setState(() => isRunningScenario = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAlt = terminal.isUsingAltBuffer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('xterm.dart Automation & Driver Inspector'),
        backgroundColor: const Color(0xFF21252B),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isAlt
                  ? const Color(0xFFE5C07B).withValues(alpha: 0.2)
                  : const Color(0xFF61AFEF).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isAlt ? const Color(0xFFE5C07B) : const Color(0xFF61AFEF),
              ),
            ),
            child: Text(
              isAlt ? 'Buffer: ALTERNATIVE (TUI)' : 'Buffer: MAIN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isAlt ? const Color(0xFFE5C07B) : const Color(0xFF61AFEF),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: driver.bellCount > 0
                  ? const Color(0xFFE06C75).withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: driver.bellCount > 0
                    ? const Color(0xFFE06C75)
                    : Colors.grey,
              ),
            ),
            child: Text(
              'Bells: ${driver.bellCount}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: driver.bellCount > 0
                    ? const Color(0xFFE06C75)
                    : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Left: Live Terminal View
          Expanded(
            flex: 6,
            child: Container(
              color: const Color(0xFF1E2227),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: const Color(0xFF282C34),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TERMINAL DISPLAY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          'Size: ${terminal.viewWidth}x${terminal.viewHeight} | Status: $statusText',
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TerminalView(
                      terminal,
                      autofocus: true,
                      textStyle: const TerminalStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Divider
          const VerticalDivider(width: 1, color: Color(0xFF3E4451)),

          // Right: Automation Scenarios & Inspector Panel
          Expanded(
            flex: 5,
            child: Material(
              color: const Color(0xFF21252B),
              child: Column(
                children: [
                  // Scenarios Control Bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFF3E4451))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'AUTOMATION SCENARIOS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: isRunningScenario ? null : _runScenario1CliQuiet,
                              icon: const Icon(Icons.timer_outlined, size: 16),
                              label: const Text('1. CLI & Quiet'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF61AFEF),
                                foregroundColor: Colors.black,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isRunningScenario ? null : _runScenario2AltBufferCapture,
                              icon: const Icon(Icons.history_outlined, size: 16),
                              label: const Text('2. Alt-Buffer Capture'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF98C379),
                                foregroundColor: Colors.black,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isRunningScenario ? null : _runScenario3TagsAndBells,
                              icon: const Icon(Icons.notifications_active_outlined, size: 16),
                              label: const Text('3. Tags & Bell'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE5C07B),
                                foregroundColor: Colors.black,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isRunningScenario ? null : _runScenario4InPlaceTui,
                              icon: const Icon(Icons.camera_alt_outlined, size: 16),
                              label: const Text('4. TUI Snapshots'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC678DD),
                                foregroundColor: Colors.white,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isRunningScenario ? null : _runScenario5LiveAgy,
                              icon: const Icon(Icons.smart_toy_outlined, size: 16),
                              label: const Text('5. Live agy (Gemini 3.8 Flash)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF98C379),
                                foregroundColor: Colors.black,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isRunningScenario ? null : _runScenario6GeminiTagTrigger,
                              icon: const Icon(Icons.bolt, size: 16),
                              label: const Text('6. Gemini Tag Trigger'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE5C07B),
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Tab Selector
                  TabBar(
                    controller: tabController,
                    indicatorColor: const Color(0xFF61AFEF),
                    tabs: [
                      Tab(text: 'Back-Buffer (${driver.capturedBackBuffer.length})'),
                      Tab(text: 'OSC Tags (${driver.tagEvents.length})'),
                      Tab(text: 'Snapshots (${driver.snapshots.length})'),
                      Tab(text: 'Logs (${executionLogs.length})'),
                    ],
                  ),

                  // Tab Contents
                  Expanded(
                    child: TabBarView(
                      controller: tabController,
                      children: [
                        // Tab 1: Captured Back-Buffer
                        _buildBackBufferTab(),

                        // Tab 2: OSC Tags
                        _buildTagsTab(),

                        // Tab 3: Frame Snapshots
                        _buildSnapshotsTab(),

                        // Tab 4: Execution Logs
                        _buildLogsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackBufferTab() {
    final buffer = driver.capturedBackBuffer;
    if (buffer.isEmpty) {
      return const Center(
        child: Text(
          'No scrolled-off lines captured yet.\nRun Scenario 2 to test alt-buffer scrolling!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: buffer.length,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
          decoration: BoxDecoration(
            color: index.isEven
                ? Colors.black.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Text(
            '${(index + 1).toString().padLeft(3)} | ${buffer[index]}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFFABB2BF),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagsTab() {
    final tags = driver.tagEvents;
    if (tags.isEmpty) {
      return const Center(
        child: Text(
          'No OSC tags captured yet.\nRun Scenario 3 to emit semantic tags!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: tags.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF3E4451)),
      itemBuilder: (context, index) {
        final tag = tags[index];
        final timeStr = tag.timestamp.toIso8601String().substring(11, 19);
        return Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            title: Text(
              'OSC ${tag.code}: ${tag.tag}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF61AFEF),
                fontSize: 13,
              ),
            ),
            subtitle: Text(
              'Payload: ${tag.payload.isEmpty ? "(none)" : tag.payload}\nTime: $timeStr | Args: ${tag.args}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSnapshotsTab() {
    final snapshots = driver.snapshots;
    if (snapshots.isEmpty) {
      return const Center(
        child: Text(
          'No screen snapshots captured yet.\nRun Scenario 4 to test in-place TUI snapshots!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: snapshots.length,
      itemBuilder: (context, index) {
        final snap = snapshots[index];
        final timeStr = snap.timestamp.toIso8601String().substring(11, 19);
        return Material(
          color: Colors.transparent,
          child: ExpansionTile(
            dense: true,
            title: Text(
              'Snapshot #${index + 1}: ${snap.label ?? "unlabeled"}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Time: $timeStr | AltBuffer: ${snap.isAltBuffer} | Cursor: (${snap.cursor.x}, ${snap.cursor.y})',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                color: Colors.black.withValues(alpha: 0.4),
                child: SelectableText(
                  snap.text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF98C379),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: executionLogs.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            executionLogs[index],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        );
      },
    );
  }

  String _findAgyPath() {
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

  String _resolvePtyBridgePath() {
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
}
