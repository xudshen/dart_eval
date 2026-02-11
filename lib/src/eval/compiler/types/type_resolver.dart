part of '../type.dart';

/// Extension on [TypeRef] providing type chain resolution methods.
///
/// These methods traverse the type hierarchy to build ordered chains
/// of supertypes, used for common base type computation and type
/// assignability checks.
extension TypeRefResolver on TypeRef {
  List<List<TypeRef>> getTypeChain(CompilerContext ctx) {
    final l1extends = extendsType;
    final l2extends =
        extendsType?.resolveTypeChain(ctx).getTypeChain(ctx) ?? [];
    final chain = <List<TypeRef>>[
      if (l1extends != null && l2extends.isEmpty) [l1extends],
      ...l2extends
    ];

    for (final imp in implementsType.reversed) {
      if (chain.isEmpty) {
        chain.add([]);
      }
      chain[0].add(imp);
      final tc = imp.resolveTypeChain(ctx).getTypeChain(ctx);
      for (var i = 0; i < tc.length; i++) {
        if (chain.length < i + 2) {
          chain.add([]);
        }
        chain[i + 1].addAll(tc[i]);
      }
    }

    for (final w in withType.reversed) {
      if (chain.isEmpty) {
        chain.add([]);
      }
      chain[0].add(w);
      final tc = w.resolveTypeChain(ctx).getTypeChain(ctx);
      for (var i = 0; i < tc.length; i++) {
        if (chain.length < i + 1) {
          chain.add([]);
        }
        chain[i + 1].addAll(tc[i]);
      }
    }

    return [
      [this],
      ...chain
    ];
  }
}
