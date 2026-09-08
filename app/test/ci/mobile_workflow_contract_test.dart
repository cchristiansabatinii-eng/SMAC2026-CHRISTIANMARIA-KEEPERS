import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> workflow;
  late String workflowText;

  setUpAll(() {
    workflow = File('../.github/workflows/ci.yml').readAsLinesSync();
    workflowText = workflow.join('\n');
  });

  test('Android emulator runner commands are independently executable', () {
    final actionLine = workflow.indexWhere(
      (line) => line.contains('ReactiveCircus/android-emulator-runner@'),
    );
    expect(actionLine, isNonNegative);
    final actionStep = _stepNamed(
      workflow,
      'Run Android storage and family invitation integrations',
    ).join('\n');
    expect(actionStep, contains('working-directory: app'));

    final scriptLine = workflow.indexWhere(
      (line) => line.trim() == 'script: |',
      actionLine,
    );
    expect(scriptLine, isNonNegative);

    final scriptIndent = workflow[scriptLine].indexOf('script:');
    final commands = <String>[];
    for (var index = scriptLine + 1; index < workflow.length; index += 1) {
      final line = workflow[index];
      if (line.trim().isEmpty) continue;
      final indent = line.length - line.trimLeft().length;
      if (indent <= scriptIndent) break;
      commands.add(line.trim());
    }

    expect(commands, isNotEmpty);
    expect(commands, isNot(contains('cd app')));
    expect(
      commands.where((command) => command.endsWith(r'\')),
      isEmpty,
      reason:
          'android-emulator-runner executes each script line in a separate '
          'shell, so shell continuations become literal command arguments.',
    );
  });

  test('iOS smoke starts from an exact clean simulator', () {
    expect(
      workflowText,
      contains(
        r"awk -F '[()]' '/^[[:space:]]*iPhone 17 Pro[[:space:]]*\(/ {print $2; exit}'",
      ),
    );
    expect(
      workflowText,
      contains(r'xcrun simctl shutdown "$device_id" || true'),
    );
    expect(workflowText, contains(r'xcrun simctl erase "$device_id"'));
    expect(
      RegExp(
        r'^\s*xcrun simctl boot "\$device_id"\s*$',
        multiLine: true,
      ).hasMatch(workflowText),
      isTrue,
      reason: 'A real boot failure must not be masked before the device test.',
    );
  });

  test('iOS smoke is bounded, verbose, and leaves failure diagnostics', () {
    final smokeStep = _stepNamed(
      workflow,
      'Run the real iOS storage and persistence smoke',
    ).join('\n');
    expect(smokeStep, contains('timeout-minutes: 15'));
    expect(smokeStep, contains('flutter test --verbose --no-dds --no-pub'));

    final diagnosticStep = _stepNamed(
      workflow,
      'Collect iOS Runner diagnostics',
    ).join('\n');
    expect(diagnosticStep, contains('if: failure() || cancelled()'));
    expect(diagnosticStep, contains(r'process == "Runner"'));
    expect(diagnosticStep, contains('tail -n 1000'));
  });
}

List<String> _stepNamed(List<String> workflow, String name) {
  final start = workflow.indexWhere((line) => line.trim() == '- name: $name');
  expect(start, isNonNegative, reason: 'Missing workflow step "$name".');
  final stepIndent = workflow[start].length - workflow[start].trimLeft().length;
  final block = <String>[workflow[start]];
  for (var index = start + 1; index < workflow.length; index += 1) {
    final line = workflow[index];
    final indent = line.length - line.trimLeft().length;
    if (line.trimLeft().startsWith('- name:') && indent == stepIndent) break;
    if (line.trim().isNotEmpty && indent < stepIndent) break;
    block.add(line);
  }
  return block;
}
