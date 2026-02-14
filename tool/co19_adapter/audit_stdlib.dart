// Scans dart_eval stdlib binding files and reports bound vs missing methods.
//
// Usage: fvm dart tool/co19_adapter/audit_stdlib.dart

import 'dart:io';

/// Scan a binding file for $getProperty switch cases.
List<String> extractGetPropertyCases(String content) {
  final cases = <String>[];
  final pattern = RegExp(r"case\s+'([^']+)':");
  // Find the $getProperty method region.
  final getPropertyIndex = content.indexOf(r'$getProperty');
  if (getPropertyIndex == -1) return cases;

  // Find the switch block after $getProperty.
  final switchIndex = content.indexOf('switch', getPropertyIndex);
  if (switchIndex == -1) return cases;

  // Find the closing of this switch (next method or end of class).
  // Simple heuristic: scan until we hit a line starting with a non-indented
  // method signature or class closing brace.
  final region = content.substring(switchIndex);
  final endIndex = region.indexOf(RegExp(r'\n  \$|^\}', multiLine: true));
  final switchBlock = endIndex == -1 ? region : region.substring(0, endIndex);

  for (final match in pattern.allMatches(switchBlock)) {
    cases.add(match.group(1)!);
  }
  return cases;
}

/// Scan for Dart instance method implementations (not in $getProperty).
/// Looks for `returnType methodName(` patterns.
List<String> extractDartMethods(String content) {
  final methods = <String>[];
  // Match lines like: void forEach(...), bool containsValue(...), etc.
  final pattern = RegExp(
      r'^\s+(?:[\w<>,\s\?]+)\s+([\w]+)\s*\(',
      multiLine: true);
  for (final match in pattern.allMatches(content)) {
    final name = match.group(1)!;
    // Skip internal/private methods and constructors.
    if (!name.startsWith('_') &&
        !name.startsWith('\$') &&
        name != 'wrap' &&
        name != 'call' &&
        name != 'configureForRuntime' &&
        name != 'configureForCompile') {
      methods.add(name);
    }
  }
  return methods.toSet().toList()..sort();
}

/// Audit result for a single binding file.
class BindingAudit {
  final String file;
  final List<String> boundMethods;
  final List<String> dartMethods;

  BindingAudit(this.file, this.boundMethods, this.dartMethods);

  List<String> get potentiallyMissing {
    final boundSet = boundMethods.toSet();
    return dartMethods.where((m) => !boundSet.contains(m)).toList();
  }
}

void main() {
  final stdlibDir = Directory('lib/src/eval/shared/stdlib');
  if (!stdlibDir.existsSync()) {
    print('Error: run from packages/dart_eval/');
    exit(1);
  }

  final files = stdlibDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  print('=== dart_eval stdlib Binding Audit ===\n');

  var totalBound = 0;
  var totalDartMethods = 0;
  final allAudits = <BindingAudit>[];

  for (final file in files) {
    final content = file.readAsStringSync();
    final bound = extractGetPropertyCases(content);
    if (bound.isEmpty) continue;

    final dart = extractDartMethods(content);
    final audit = BindingAudit(
        file.path.replaceFirst('lib/src/eval/shared/stdlib/', ''),
        bound,
        dart);
    allAudits.add(audit);

    totalBound += bound.length;
    totalDartMethods += dart.length;

    print('--- ${audit.file} ---');
    print('  Bound in \$getProperty: ${bound.length}');
    print('    ${bound.join(", ")}');
    if (audit.potentiallyMissing.isNotEmpty) {
      print('  Dart methods not in switch: ${audit.potentiallyMissing.length}');
      print('    ${audit.potentiallyMissing.join(", ")}');
    }
    print('');
  }

  print('=== SUMMARY ===');
  print('Files scanned: ${allAudits.length}');
  print('Total \$getProperty cases: $totalBound');
  print('Total Dart methods found: $totalDartMethods');
  print('');

  // Highlight Map specifically.
  final mapAudit = allAudits.where((a) => a.file.contains('map.dart'));
  if (mapAudit.isNotEmpty) {
    final map = mapAudit.first;
    print('=== MAP DETAIL ===');
    print('Bound: ${map.boundMethods.join(", ")}');
    print('Missing from switch: ${map.potentiallyMissing.join(", ")}');
  }
}
