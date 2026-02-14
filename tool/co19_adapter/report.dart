// Parses `dart test --reporter json` output and generates a formatted
// conformance report.
//
// Usage:
//   fvm dart test test/co19/ --reporter json > /tmp/co19.json
//   fvm dart tool/co19_adapter/report.dart /tmp/co19.json

import 'dart:convert';
import 'dart:io';

class TestResult {
  final String name;
  final bool passed;
  final String? error;

  TestResult(this.name, this.passed, [this.error]);
}

class GroupReport {
  final String name;
  int pass = 0;
  int fail = 0;
  final errors = <String, int>{};

  GroupReport(this.name);

  int get total => pass + fail;
  double get passRate => total == 0 ? 0 : pass / total * 100;
}

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: fvm dart tool/co19_adapter/report.dart <json-file>');
    print('');
    print('Generate JSON with:');
    print('  fvm dart test test/co19/ --reporter json > /tmp/co19.json');
    exit(1);
  }

  final file = File(args[0]);
  if (!file.existsSync()) {
    print('Error: file not found: ${args[0]}');
    exit(1);
  }

  final lines = file.readAsLinesSync();

  // Parse JSON reporter events.
  final tests = <int, String>{}; // testID → name
  final errors = <int, String>{}; // testID → classified error
  final results = <TestResult>[];

  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    late final Map<String, dynamic> event;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) continue;
      event = decoded;
    } on FormatException {
      continue; // skip non-JSON lines (e.g. stderr from test runner)
    }
    final type = event['type'] as String?;

    if (type == 'testStart') {
      final test = event['test'] as Map<String, dynamic>;
      final id = test['id'] as int;
      final name = test['name'] as String;
      tests[id] = name;
    } else if (type == 'error') {
      final id = event['testID'] as int;
      final error = event['error'] as String? ?? '';
      errors[id] = _classifyError(error);
    } else if (type == 'testDone') {
      final id = event['testID'] as int;
      final result = event['result'] as String;
      final name = tests[id] ?? 'unknown';

      // Skip loading/setup tests.
      if (name.startsWith('loading ')) continue;

      final passed = result == 'success';
      results.add(TestResult(name, passed, passed ? null : errors[id]));
    }
  }

  // Group by top-level category.
  final groups = <String, GroupReport>{};
  var totalPass = 0;
  var totalFail = 0;

  for (final r in results) {
    final parts = r.name.split(' > ');
    final group =
        parts.length > 1 ? parts.sublist(0, 2).join(' > ') : parts[0];

    groups.putIfAbsent(group, () => GroupReport(group));
    if (r.passed) {
      groups[group]!.pass++;
      totalPass++;
    } else {
      groups[group]!.fail++;
      totalFail++;
      if (r.error != null) {
        groups[group]!.errors[r.error!] =
            (groups[group]!.errors[r.error!] ?? 0) + 1;
      }
    }
  }

  final total = totalPass + totalFail;

  // Print report.
  print('');
  print('═══════════════════════════════════════════════════');
  print('  dart_eval co19 Conformance Report');
  print('═══════════════════════════════════════════════════');
  print('');
  print('  Overall: $totalPass / $total '
      '(${(totalPass / total * 100).toStringAsFixed(1)}%)');
  print('  ${_progressBar(totalPass, total, 40)}');
  print('');

  // Per-group breakdown.
  final sortedGroups = groups.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  for (final g in sortedGroups) {
    final bar = _progressBar(g.pass, g.total, 20);
    final pct = g.passRate.toStringAsFixed(0);
    print('  $bar ${g.pass.toString().padLeft(3)}/${g.total.toString().padLeft(3)}'
        ' (${'$pct%'.padLeft(4)})  ${g.name}');
  }

  // Error classification summary.
  print('');
  print('── Error Categories ──────────────────────────────');
  final allErrors = <String, int>{};
  for (final g in sortedGroups) {
    for (final e in g.errors.entries) {
      allErrors[e.key] = (allErrors[e.key] ?? 0) + e.value;
    }
  }
  final sortedErrors = allErrors.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedErrors) {
    print('  ${e.value.toString().padLeft(4)}  ${e.key}');
  }
  print('');
}

String _progressBar(int done, int total, int width) {
  if (total == 0) return '[${' ' * width}]';
  final filled = (done / total * width).round();
  final empty = width - filled;
  return '[${'█' * filled}${'░' * empty}]';
}

String _classifyError(String error) {
  if (error.contains('Cannot find static method')) {
    return 'CompileError: implicit constructor';
  }
  if (error.contains('CompilationUnitImpl')) {
    return 'CompileError: top-level function reference';
  }
  if (error.contains('CompileError')) {
    // Extract the specific CompileError message.
    final match = RegExp(r'CompileError: (.+?)(?:\n|$)').firstMatch(error);
    return 'CompileError: ${match?.group(1) ?? 'unknown'}';
  }
  if (error.contains('is not a subtype of type')) {
    return 'RuntimeError: type cast failure';
  }
  if (error.contains('Tried to invoke a nonexistent external function')) {
    return 'RuntimeError: missing bridge function';
  }
  if (error.contains('UnimplementedError')) {
    return 'UnimplementedError';
  }
  if (error.contains('RangeError') || error.contains('Stack underflow')) {
    return 'RuntimeError: stack/range error';
  }
  if (error.contains('Co19ExpectException')) {
    return 'AssertionError: Expect assertion failed';
  }
  // Truncate long error messages.
  final firstLine = error.split('\n').first;
  if (firstLine.length > 60) {
    return '${firstLine.substring(0, 57)}...';
  }
  return firstLine;
}
