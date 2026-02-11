part of '../compiler.dart';

/// Phase 4: Emit the final [Program] from the compiled context.
///
/// Resolves type chains, builds the global initializer table, and constructs
/// the [Program] object containing all bytecode, type information, declaration
/// positions, and runtime metadata.
Program _emitProgram(
  CompilerContext ctx,
  Map<Library, int> libraryIndexMap,
  Set<Library> reachableLibraries,
) {
  // Reassign bridge static function indices for bridge classes
  for (final library in reachableLibraries) {
    for (final dec in library.declarations) {
      if (dec.isBridge) {
        final bridge = dec.bridge;
        if (bridge is BridgeClassDef && bridge.bridge) {
          _reassignBridgeStaticFunctionIndicesForClass(ctx, bridge);
        }
      }
    }
  }

  for (final type in ctx.runtimeTypeList) {
    ctx.typeTypes.add(type.resolveTypeChain(ctx).getRuntimeIndices(ctx));
  }

  final globalInitializers = List<int>.filled(ctx.globalIndex, 0);

  for (final gi in ctx.runtimeGlobalInitializerMap.entries) {
    globalInitializers[gi.key] = gi.value;
  }

  final typeIds = <int, Map<String, int>>{};

  for (final t in ctx.typeRefIndexMap.entries) {
    final type = t.key;
    typeIds.putIfAbsent(type.file, () => {})[type.name] = t.value;
  }

  final libraryMapString = {
    for (final lib in reachableLibraries)
      lib.uri.toString(): libraryIndexMap[lib]!
  };

  return Program(
    ctx.topLevelDeclarationPositions,
    ctx.instanceDeclarationPositions,
    typeIds,
    ctx.typeTypes,
    ctx.offsetTracker.apply(ctx.out),
    libraryMapString,
    ctx.bridgeStaticFunctionIndices,
    ctx.constantPool.pool,
    ctx.runtimeTypes.pool,
    globalInitializers,
    ctx.enumValueIndices,
    ctx.runtimeOverrideMap,
  );
}

/// Helper for emit phase: reassign bridge static function indices for bridge
/// classes that are both bridge and wrap.
void _reassignBridgeStaticFunctionIndicesForClass(
    CompilerContext ctx, BridgeClassDef classDef) {
  final type = TypeRef.fromBridgeTypeRef(ctx, classDef.type.type);
  final lib = type.file;

  classDef.constructors.forEach((name, constructor) {
    final idc = ctx.bridgeStaticFunctionIndices[lib]!;
    final id = '${type.name}.$name';
    final prev = classDef.wrap ? idc[id]! : idc.remove(id)!;
    ctx.bridgeStaticFunctionIndices[lib]!['#${type.name}.$name'] = prev;
  });
}
