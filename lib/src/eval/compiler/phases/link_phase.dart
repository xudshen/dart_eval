part of '../compiler.dart';

/// Result of the link phase — all intermediate data needed by subsequent phases.
class LinkResult {
  final Set<Library> reachableLibraries;
  final Map<Library, int> libraryIndexMap;
  final Map<int, Map<String, DeclarationOrPrefix>> visibleDeclarationsByIndex;
  final Map<int, Map<String, TypeRef>> visibleTypesByIndex;

  LinkResult({
    required this.reachableLibraries,
    required this.libraryIndexMap,
    required this.visibleDeclarationsByIndex,
    required this.visibleTypesByIndex,
  });
}

/// Phase 2: Build libraries from ASTs, merge bridge declarations, resolve
/// imports/exports, populate lookup tables, cache type refs, compute visible
/// types.
///
/// This phase takes parsed compilation units and:
/// 1. Groups them into [Library] objects
/// 2. Merges bridge declarations with source libraries sharing the same URI
/// 3. Indexes libraries and discovers entrypoints
/// 4. Discovers reachable libraries via import/export graph traversal
/// 5. Resolves imports/exports to determine visible declarations
/// 6. Populates lookup tables for top-level and instance declarations
/// 7. Caches type references and computes visible types per library
LinkResult _linkLibraries(
  List<DartCompilationUnit> units,
  CompilerContext ctx,
  Map<String, List<BridgeDeclaration>> bridgeDeclarations,
  List<String> entrypoints,
  Map<int, Map<String, DeclarationOrBridge>> topLevelDeclarationsMap,
  Map<int, Map<String, Map<String, Declaration>>> instanceDeclarationsMap,
  Map<int, Map<String, int>> topLevelGlobalIndices,
  void Function(int libraryIndex, DeclarationOrBridge declarationOrBridge)
      populateLookupTables,
  TypeRef? Function(int libraryIndex, DeclarationOrBridge declarationOrBridge)
      cacheTypeRef,
) {
  // Map unit sources into a Set of [Library]s using [_buildLibraries].
  final unitLibraries = {
    ..._buildLibraries(units),
  };

  // Establish a mapping relationship from URI to Library
  final unitLibraryUriMap = {
    for (final library in unitLibraries) library.uri: library
  };

  // Merge bridge libraries with unit libraries that share an identical URI
  final libraries = <Library>{};
  final mergedLibraryUris = <Uri>{};

  // Iterate over bridge libraries
  for (final bridgeLibrary in bridgeDeclarations.keys) {
    // Wrap bridge declarations in this library as [DeclarationOrBridge]s
    final bridgeLibDeclarations = [
      for (final bridgeDeclaration in bridgeDeclarations[bridgeLibrary]!)
        DeclarationOrBridge(-1, bridge: bridgeDeclaration)
    ];

    final uri = Uri.parse(bridgeLibrary);

    // See if there is already a unit library with an identical URI
    // If the two overlap, perform a merge operation
    final unitLibrary = unitLibraryUriMap[uri];
    if (unitLibrary != null) {
      /// Merge source code declarations from the unit library with the bridge
      libraries.add(unitLibrary.copyWith(
          declarations: [...unitLibrary.declarations, ...bridgeLibDeclarations]));

      /// Document this is a merged library
      mergedLibraryUris.add(uri);
    } else {
      // If there is no existing unit library with an identical URI, create
      // a new [Library] with the bridge declarations
      libraries.add(Library(Uri.parse(bridgeLibrary),
          imports: [],
          exports: [],
          declarations: [
            for (final bridgeDeclaration in bridgeDeclarations[bridgeLibrary]!)
              DeclarationOrBridge(-1, bridge: bridgeDeclaration)
          ]));
    }
  }

  // At this point bridge libraries and merged libraries are already in the
  // [libraries] Set. Add the rest of the unit libraries that were not merged.
  unitLibraryUriMap.forEach((uri, library) {
    if (!mergedLibraryUris.contains(uri)) {
      libraries.add(library);
    }
  });

  var i = 0;
  final libraryIndexMap = <Library, int>{};
  final inverseIndexMap = <int, Library>{};
  final computedEntrypoints = <Uri>{};

  for (final library in libraries) {
    if (libraryIndexMap[library] == null) {
      libraryIndexMap[library] = i++;
    }

    inverseIndexMap[libraryIndexMap[library]!] = library;

    var isEntrypoint = false;
    for (final entrypoint in entrypoints) {
      if (library.uri.toString().endsWith(entrypoint)) {
        computedEntrypoints.add(library.uri);
        isEntrypoint = true;
      }
    }

    if (!isEntrypoint) {
      /// Discover entrypoints
      for (final declaration in library.declarations) {
        if (declaration.isBridge) {
          computedEntrypoints.add(library.uri);
          continue;
        }
        final d = declaration.declaration!;
        if (d is FunctionDeclaration) {
          final overrideAnno = d.metadata.firstWhereOrNull(
              (element) => element.name.name == 'RuntimeOverride');
          if (overrideAnno != null) {
            computedEntrypoints.add(library.uri);
          }
        }
      }
    }
  }

  final reachableLibraries =
      _discoverReachableLibraries(libraries, computedEntrypoints).toSet();

  final discoveredIdentifiers = <Library, Map<String, Set<String>>>{};

  for (final lib in reachableLibraries) {
    final treeShaker = TreeShakeVisitor();
    discoveredIdentifiers[lib] = {};
    for (final decl in lib.declarations) {
      final d = decl.declaration;
      final names = DeclarationOrBridge.nameOf(decl);
      if (d != null) {
        d.visitChildren(treeShaker);
      }
      for (final name in names) {
        discoveredIdentifiers[lib]![name] = treeShaker.ctx.identifiers;
      }
      treeShaker.ctx.identifiers = {};
    }
  }

  // Resolve the export and import relationship of the libraries
  final visibleDeclarations = _resolveImportsAndExports(
      reachableLibraries, discoveredIdentifiers, computedEntrypoints,
      libraryIndexMap);

  // Populate lookup tables [topLevelDeclarationsMap],
  // [instanceDeclarationsMap], and [topLevelGlobalIndices], and generate
  // remaining library IDs
  for (final library in reachableLibraries) {
    final libraryIndex = libraryIndexMap[library]!;
    for (final declarationOrBridge in library.declarations) {
      populateLookupTables(libraryIndex, declarationOrBridge);
    }
  }

  // Pass a mapping of library URI to integer index into the context
  final libraryMapString = {
    for (final lib in reachableLibraries)
      lib.uri.toString(): libraryIndexMap[lib]!
  };
  ctx.libraryMap = libraryMapString;

  final visibleDeclarationsByIndex = {
    for (final lib in reachableLibraries)
      libraryIndexMap[lib]!: {...visibleDeclarations[lib]!}
  };

  final declarationTypes = <DeclarationOrBridge, TypeRef>{};

  for (final library in reachableLibraries) {
    final libraryIndex = libraryIndexMap[library]!;
    for (final declaration in library.declarations) {
      final type = cacheTypeRef(libraryIndex, declaration);
      if (type != null) {
        declarationTypes[declaration] = type;
      }
    }
  }

  final visibleTypesByIndex = <int, Map<String, TypeRef>>{};
  for (final library in reachableLibraries) {
    final libraryIndex = libraryIndexMap[library]!;
    final declarations = visibleDeclarations[library]!;

    for (final entry in declarations.entries) {
      final name = entry.key;
      final dop = entry.value;
      if (dop.children != null) {
        final res = <String, TypeRef>{};
        for (final childName in dop.children!.keys) {
          final child = dop.children![childName]!;
          final cached = declarationTypes[child];
          if (cached == null) continue;
          res['$name.$childName'] = cached;
          if (child.isBridge) {
            final bridge = child.bridge!;
            final type0 = BridgeTypeRef.type(ctx.typeRefIndexMap[cached]);
            if (bridge is BridgeClassDef) {
              child.bridge =
                  bridge.copyWith(type: bridge.type.copyWith(type: type0));
            } else if (bridge is BridgeEnumDef) {
              child.bridge = bridge.copyWith(type: type0);
            } else {
              assert(false);
            }
          }
        }
        visibleTypesByIndex[libraryIndex] ??= {};
        visibleTypesByIndex[libraryIndex]!.addAll(res);
        continue;
      }
      visibleTypesByIndex[libraryIndex] ??= {};
      final declarationOrBridge = dop.declaration!;
      final type = declarationTypes[declarationOrBridge];
      if (type == null) continue;
      if (declarationOrBridge.isBridge) {
        final bridge = declarationOrBridge.bridge!;
        final type0 = BridgeTypeRef.type(ctx.typeRefIndexMap[type]);
        if (bridge is BridgeClassDef) {
          declarationOrBridge.bridge =
              bridge.copyWith(type: bridge.type.copyWith(type: type0));
        } else if (bridge is BridgeEnumDef) {
          declarationOrBridge.bridge = bridge.copyWith(type: type0);
        } else {
          assert(false);
        }
      }
      visibleTypesByIndex[libraryIndex]![name] = type;
    }
  }

  return LinkResult(
    reachableLibraries: reachableLibraries,
    libraryIndexMap: libraryIndexMap,
    visibleDeclarationsByIndex: visibleDeclarationsByIndex,
    visibleTypesByIndex: visibleTypesByIndex,
  );
}

// ---------------------------------------------------------------------------
// Helper functions used exclusively during the link phase
// ---------------------------------------------------------------------------

List<Library> _buildLibraries(Iterable<DartCompilationUnit> units) {
  /// Self-incrementing ID generator, each [DartCompilationUnit] has a unique
  /// integer ID that identifies it. These IDs are local to this function, since
  /// they are only used to build the [Library]s which will be later associated
  /// with their own IDs.
  var i = 0;

  /// ID to [DartCompilationUnit] mapping
  final compilationUnitMap = <int, DartCompilationUnit>{};

  /// URI to ID mapping
  final uriMap = <String, int>{};

  /// Library name to ID mapping
  final libraryIdMap = <String, int>{};

  for (final unit in units) {
    /// Establish a mapping relationship
    compilationUnitMap[i] = unit;
    uriMap[unit.uri.toString()] = i;
    if (unit.library != null && unit.library!.name2 != null) {
      /// Library instruction for source files that start with "library *****"
      libraryIdMap[unit.library!.name2!.name] = i;
    }
    i++;
  }

  /// CompilationUnit graph structure
  final cuGraph =
      CompilationUnitGraph(compilationUnitMap, uriMap, libraryIdMap);

  // Calculate strong link components using the Dijkstra path-based strong
  // component algorithm.
  // Accounting for `library` directives and `part` / `part of` relationships,
  // the algorithm will group source files into libraries.
  // Return type is List<List<int>> where each inner list is a list of source
  // file IDs that should be joined into a single library
  final libGroups = computeStrongComponents(cuGraph);

  final libraries = <Library>[];
  for (final group in libGroups) {
    final primaryId = group.length == 1
        ? group[0]
        : group.firstWhere((e) => compilationUnitMap[e]!.partOf == null);
    final primary = compilationUnitMap[primaryId]!;
    final library = Library(primary.uri,
        library: primary.library?.name2?.name,
        imports: primary.imports,
        exports: primary.exports,
        declarations: group.map((e) => compilationUnitMap[e]!).fold(
            [],
            (pv, element) => pv
              ..addAll(element.declarations
                  .map((d) => DeclarationOrBridge(-1, declaration: d)))));
    libraries.add(library);
  }

  return libraries;
}

/// Analyze the import and export relationships of the library, and return a
/// mapping of library to its visible declarations.
/// The visible declarations of a library are the declarations of the library
/// itself, as well as the declarations of the libraries it imports, including
/// declarations exported by another imported library. A graph is used to
/// resolve long export chains.
Map<Library, Map<String, DeclarationOrPrefix>> _resolveImportsAndExports(
    Iterable<Library> libraries,
    Map<Library, Map<String, Set<String>>> usedIdentifiers,
    Set<Uri> entrypoints,
    Map<Library, int> libraryIds) {
  /// URI-Library mapping
  final uriMap = {for (final l in libraries) l.uri: l};

  /// A directed graph based on library exports, allowing the resolution of
  /// export chains.
  /// See test/lib_composition_test.dart "Export chains" for an example of how
  /// this is used.
  final exportGraph = DirectedGraph<Uri>({
    // Pass in a Map representing edges in the graph.
    // Each edge represents a library, with the key being the library's URI
    // and the value being a set of its exports.
    for (final l in libraries)
      l.uri: {
        for (final export in l.exports) l.uri.resolve(export.uri.stringValue!)
      }
  });

  final crawler = CachedFastCrawler(exportGraph.edges);

  final result = <Library, Map<String, DeclarationOrPrefix>>{};
  final usedDeclarationsForLibrary = <int, Set<String>>{};

  final worklist = <Library>[];
  final importMap = <Library, List<_Import>>{};
  final importedDeclarationsMap =
      <Library, Map<Library, Iterable<Pair<String, DeclarationOrBridge>>>>{};

  // Traversing libraries
  for (final l in libraries) {
    // All visible declarations under this Library
    final visibleDeclarationsLib = <String, DeclarationOrPrefix>{
      for (final d in DeclarationOrBridge.expand(l.declarations))
        // Key: the expanded name of the declaration (see [_expandDeclarations])
        // Value: DeclarationOrPrefix (declaration content, and store the ID
        // of the containing library)
        d.first: DeclarationOrPrefix(
            declaration: d.second..sourceLib = libraryIds[l]!),
    };

    final dartCoreUri = Uri.parse('dart:core');
    final isDartCore = l.uri == dartCoreUri;

    final isEntrypoint = entrypoints.contains(l.uri);
    final ids = isEntrypoint
        ? usedIdentifiers[l]?.values.expand((e) => e).toSet()
        : null;

    final imports = [
      ...l.imports
          .map((e) => _Import.resolve(e, l.uri, e.prefix?.name, e.combinators))
          .whereNot((import) =>
              import.uri.toString().startsWith('package:eval_annotation')),
      if (!isDartCore) _Import(dartCoreUri, null)
    ];

    importMap[l] = imports;
    importedDeclarationsMap[l] = {
      l: DeclarationOrBridge.expand(l.declarations)
    };

    /// Iterate over the library's imports including the implicit import of
    /// dart:core.
    for (final import in imports) {
      /// Use the export graph to find all declarations that become visible
      /// through this import.
      /// directed_graph returns a tree structure with import.uri as the root
      /// and exported libraries as leaves.
      final tree = crawler.tree(import.uri);

      /// Flatten and deduplicate the tree to get a list of all libraries that
      /// are visible through this import.
      final importedLibs = [...tree.map((e) => e.last), import.uri]
          .map((e) =>
              uriMap[e] ??
              (throw CompileError(
                  "Cannot find import '$e' (while parsing '${l.uri}')")))
          .toSet();

      /// Get all the [ExportDirective]s of the imported library tree. While
      /// we've already found all of the libraries that are visible through
      /// this import, we still need access to the raw [ExportDirective]s to
      /// identify which declarations are visible (since some exports may use
      /// `show` or `hide`).
      final exportsPerUri = <Uri, List<ExportDirective>>{};
      for (final lib in importedLibs) {
        for (final export in lib.exports) {
          final uri = lib.uri.resolve(export.uri.stringValue!);
          final uriList = exportsPerUri[uri];
          if (uriList != null) {
            uriList.add(export);
          } else {
            exportsPerUri[uri] = [export];
          }
        }
      }

      final visibleDeclarations = <Pair<String, DeclarationOrBridge>>{};

      for (final lib in importedLibs) {
        final libId = libraryIds[lib]!;
        final expandedDeclarations =
            DeclarationOrBridge.expand(lib.declarations);
        final importedDeclarations = expandedDeclarations
            .where((element) =>
                _combinatorListAccepts(import.combinators, element.first, true))
            .toList();
        importedDeclarationsMap[l]![lib] = importedDeclarations;

        final result = <Pair<String, DeclarationOrBridge>>{};

        for (final declaration in importedDeclarations) {
          if (lib.uri == import.uri) {
            result.add(declaration..second.sourceLib = libId);
          }
          final exports = exportsPerUri[lib.uri] ?? <ExportDirective>[];
          for (final export in exports) {
            final combinators = export.combinators;
            if (_combinatorListAccepts(combinators, declaration.first, false)) {
              result.add(declaration..second.sourceLib = libId);
            }
          }
          if (isEntrypoint && ids!.contains(declaration.first)) {
            usedDeclarationsForLibrary[libId] ??= {'main'};
            usedDeclarationsForLibrary[libId]!.add(declaration.first);
            if (!worklist.contains(lib)) {
              worklist.add(lib);
            }
          }
        }

        visibleDeclarations.addAll(result);
      }

      final mappedVisibleDeclarations = {
        if (import.prefix != null)
          import.prefix!: DeclarationOrPrefix(children: {
            for (final d in visibleDeclarations) d.first: d.second
          })
        else
          for (final d in visibleDeclarations)
            d.first: DeclarationOrPrefix(declaration: d.second)
      };

      visibleDeclarationsLib.addAll(mappedVisibleDeclarations);
    }

    result[l] = visibleDeclarationsLib;
  }

  final processedImports = <String>{};

  /// Run tree-shaking
  while (worklist.isNotEmpty) {
    final library = worklist.removeLast();
    Map<int, Set<String>> applyUsedDeclarations = {};
    for (final dec
        in (usedDeclarationsForLibrary[libraryIds[library]] ?? {})) {
      final ids = usedIdentifiers[library]?[dec];
      if (ids == null) continue;
      final importsWithImplicitSelf = [
        ...importMap[library]!,
        _Import(library.uri, null)
      ];

      final usedSelf = <String>{};
      final selfList = result[library]?.entries.toList() ?? [];
      while (selfList.isNotEmpty) {
        final declaration = selfList.removeLast();
        if (usedSelf.contains(declaration.key) ||
            !ids.contains(declaration.key)) {
          continue;
        }
        final s = usedIdentifiers[library]![declaration.key];
        for (final id in s ?? {}) {
          ids.add(id);
          final selfDec = result[library]?[id];
          if (usedSelf.contains(id) || selfDec == null) continue;
          selfList.add(MapEntry(id, selfDec));
        }
        usedSelf.add(declaration.key);
      }

      for (final import in importsWithImplicitSelf) {
        final iid = '${library.uri}:${import.uri}';
        if (processedImports.contains(iid)) {
          continue;
        }
        processedImports.add(iid);
        final lib = uriMap[import.uri]!;
        final decs = result[library]?.entries.toList();
        if (decs == null) continue;
        for (final declaration in decs) {
          if (ids.contains(declaration.key)) {
            final applyLib =
                declaration.value.declaration?.sourceLib ?? libraryIds[lib]!;
            applyUsedDeclarations[applyLib] ??= {'main'};
            applyUsedDeclarations[applyLib]!.add(declaration.key);
            if (!worklist.contains(lib)) {
              worklist.add(lib);
            }
          }
        }
      }
    }
    for (final libId in applyUsedDeclarations.keys) {
      usedDeclarationsForLibrary[libId] ??= {};
      usedDeclarationsForLibrary[libId]!
          .addAll(applyUsedDeclarations[libId]!);
    }
  }

  for (final l in libraries) {
    if (entrypoints.contains(l.uri)) {
      continue;
    }
    l.declarations = l.declarations
        .where((declaration) =>
            declaration.isBridge ||
            DeclarationOrBridge.nameOf(declaration).any((name) =>
                {...?usedDeclarationsForLibrary[libraryIds[l]]}.contains(name)))
        .toList();
  }

  return result;
}

bool _combinatorListAccepts(
    Iterable<Combinator> combinators, String name, bool rejectInvalid) {
  if (name.startsWith('_')) return false;
  if (combinators.isEmpty) {
    return true;
  }
  for (final combinator in combinators) {
    if (combinator is ShowCombinator) {
      final shown = {for (final n in combinator.shownNames) n.name};
      if (shown.contains(name)) {
        return true;
      }
      if (rejectInvalid) return false;
    } else if (combinator is HideCombinator) {
      final hidden = {for (final n in combinator.hiddenNames) n.name};
      if (!hidden.contains(name)) {
        return true;
      }
      if (rejectInvalid) return false;
    } else {
      throw CompileError(
          'Unsupported import combinator ${combinator.runtimeType}');
    }
  }
  return false;
}

/// Given the list of entrypoint libraries, recursively find all library IDs
/// that are reachable through imports and exports using a graph.
Iterable<Library> _discoverReachableLibraries(
    Iterable<Library> libraries, Iterable<Uri> entrypoints) sync* {
  final uriMap = {for (final l in libraries) l.uri: l};
  final libraryGraph = DirectedGraph<Uri>({
    for (final l in libraries)
      l.uri: {
        for (final import in l.imports) l.uri.resolve(import.uri.stringValue!),
        for (final export in l.exports) l.uri.resolve(export.uri.stringValue!)
      }
  });

  yield uriMap[Uri.parse('dart:core')]!;
  yield uriMap[Uri.parse('dart:async')]!;
  yield uriMap[Uri.parse('dart:io')]!;

  for (final entrypoint in entrypoints) {
    yield uriMap[entrypoint]!;
    final tree = FastCrawler(libraryGraph.edges).tree(entrypoint);
    yield* tree
        .map((branch) => branch.last)
        .whereNot((e) => e.toString().startsWith('package:eval_annotation'))
        .where((e) => uriMap.containsKey(e))
        .map((e) => uriMap[e]!);
  }
}

class _Import {
  final Uri uri;
  final String? prefix;
  final List<Combinator> combinators;

  _Import(this.uri, this.prefix, [this.combinators = const []]);

  factory _Import.resolve(ImportDirective import, Uri base, String? prefix,
      [List<Combinator> combinators = const []]) {
    final uri = Uri.parse(import.uri.stringValue!);
    return _Import(
        base.resolveUri(uri), import.prefix?.name, import.combinators);
  }
}
