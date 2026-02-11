part of '../compiler.dart';

/// Phase 1: Parse source code into AST compilation units.
///
/// Converts [DartSource]s into [DartCompilationUnit] ASTs, caching previously
/// parsed sources to avoid redundant work. Cleans up stale cache entries for
/// sources no longer present in the input.
List<DartCompilationUnit> _parseSources(
  Iterable<DartSource> sources,
  List<DartSource> additionalSources,
  Map<DartSource, DartCompilationUnit> cachedParsedSources,
  DiagnosticMode diagnosticMode,
) {
  final cleanupList = cachedParsedSources.keys.toSet();

  final units = sources.followedBy(additionalSources).map((source) {
    cleanupList.remove(source);
    final cached = cachedParsedSources[source];
    if (cached != null) {
      return cached;
    }

    // Load the source code from the filesystem or a String and parse it
    // (internally using the Dart analyzer) into an AST
    final parsed = cachedParsedSources[source] = source.load(diagnosticMode);
    return parsed;
  }).toList();

  for (final source in cleanupList) {
    cachedParsedSources.remove(source);
  }

  return units;
}
