import 'dart:io';

/// Result of filtering a single co19 test file.
class FilterResult {
  final String path;
  final FilterStatus status;
  final String? reason;

  FilterResult(this.path, this.status, [this.reason]);

  @override
  String toString() => '$status: $path${reason != null ? ' ($reason)' : ''}';
}

enum FilterStatus {
  /// Test is included for adaptation.
  included,

  /// Test is permanently excluded (uses unsupported features).
  excluded,

  /// Test is temporarily skipped (may be supported later).
  skipped,

  /// Not a test file (lib.dart, helper, etc.).
  notTest,
}

/// Report summarizing a directory scan.
class FilterReport {
  final String directory;
  final List<FilterResult> results;

  FilterReport(this.directory, this.results);

  int get total => results.length;
  int get included =>
      results.where((r) => r.status == FilterStatus.included).length;
  int get excluded =>
      results.where((r) => r.status == FilterStatus.excluded).length;
  int get skipped =>
      results.where((r) => r.status == FilterStatus.skipped).length;
  int get notTest =>
      results.where((r) => r.status == FilterStatus.notTest).length;

  /// Aggregate exclude/skip reasons with counts.
  Map<String, int> get reasonCounts {
    final counts = <String, int>{};
    for (final r in results) {
      if (r.reason != null) {
        counts[r.reason!] = (counts[r.reason!] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  String toString() {
    final buf = StringBuffer();
    buf.writeln('FilterReport: $directory');
    buf.writeln(
        '  Total: $total | Included: $included | Excluded: $excluded | Skipped: $skipped | NotTest: $notTest');
    if (reasonCounts.isNotEmpty) {
      buf.writeln('  Reasons:');
      final sorted = reasonCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        buf.writeln('    ${e.key}: ${e.value}');
      }
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// File name matching
// ---------------------------------------------------------------------------

/// Matches co19 test file names: t01.dart, t02.dart, etc.
/// Also matches files like allowed_characters_t01.dart, evaluation_t01.dart.
final _testFilePattern = RegExp(r't\d{2}\.dart$');

/// Returns true if [fileName] is a co19 test file.
bool isCo19TestFile(String fileName) {
  return _testFilePattern.hasMatch(fileName);
}

// ---------------------------------------------------------------------------
// Exclusion rules (permanent — features dart_eval will not support)
// ---------------------------------------------------------------------------

/// Patterns that permanently exclude a test file.
final _permanentExcludePatterns = <String, RegExp>{
  'dart:isolate': RegExp(r"""import\s+['"]dart:isolate['"]"""),
  'dart:ffi': RegExp(r"""import\s+['"]dart:ffi['"]"""),
  'dart:mirrors': RegExp(r"""import\s+['"]dart:mirrors['"]"""),
  'dart:developer': RegExp(r"""import\s+['"]dart:developer['"]"""),
  'dart:html': RegExp(r"""import\s+['"]dart:html['"]"""),
  'dart:js': RegExp(r"""import\s+['"]dart:js['"]"""),
  'sync*': RegExp(r'\bsync\s*\*'),
  'async*': RegExp(r'\basync\s*\*'),
  'yield': RegExp(r'\byield\b'),
  'await for': RegExp(r'\bawait\s+for\b'),
  'compile-error': RegExp(r'@compile-error|@static-type-error|// \[analyzer\]'),
  'final class': RegExp(r'\bfinal\s+class\b'),
  'base class': RegExp(r'\bbase\s+class\b'),
  'interface class': RegExp(r'\binterface\s+class\b'),
};

/// Patterns that temporarily skip a test file (may be supported later).
final _temporarySkipPatterns = <String, RegExp>{
  'deferred import': RegExp(r'\bdeferred\s+(as|import)\b|import\b.*\bdeferred\b'),
  'conditional import':
      RegExp(r"""import\s+['"].*['"].*if\s*\("""),
  'sealed class': RegExp(r'\bsealed\s+class\b'),
  'extension type': RegExp(r'\bextension\s+type\b'),
};

/// Classify a single test file.
FilterResult filterFile(String path, String content) {
  final fileName = path.split('/').last;

  // Not a test file?
  if (!isCo19TestFile(fileName)) {
    return FilterResult(path, FilterStatus.notTest, 'not a test file');
  }

  // Check permanent exclusions.
  for (final entry in _permanentExcludePatterns.entries) {
    if (entry.value.hasMatch(content)) {
      return FilterResult(path, FilterStatus.excluded, entry.key);
    }
  }

  // Check temporary skips.
  for (final entry in _temporarySkipPatterns.entries) {
    if (entry.value.hasMatch(content)) {
      return FilterResult(path, FilterStatus.skipped, entry.key);
    }
  }

  return FilterResult(path, FilterStatus.included);
}

/// Recursively scan [directory] and classify all .dart files.
FilterReport scanDirectory(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    throw ArgumentError('Directory does not exist: $directory');
  }

  final results = <FilterResult>[];

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = entity.readAsStringSync();
      final relativePath =
          entity.path.substring(directory.length).replaceAll('\\', '/');
      results.add(filterFile(relativePath, content));
    }
  }

  // Sort by path for stable output.
  results.sort((a, b) => a.path.compareTo(b.path));

  return FilterReport(directory, results);
}

/// CLI entry point for standalone testing.
void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run tool/co19_adapter/filter.dart <co19-subdir>');
    print('  Example: dart run tool/co19_adapter/filter.dart '
        '../../../third_party/co19/Language/Expressions');
    exit(1);
  }

  final report = scanDirectory(args[0]);
  print(report);

  // Print included files.
  final included =
      report.results.where((r) => r.status == FilterStatus.included);
  print('\nIncluded files (${included.length}):');
  for (final r in included) {
    print('  ${r.path}');
  }
}
