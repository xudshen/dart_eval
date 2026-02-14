part of '../compiler.dart';

/// Phase 3: Compile all declarations into bytecode.
///
/// First compiles statics (top-level variables, static class/enum fields) so
/// their types can be inferred, then compiles all remaining declarations
/// (functions, classes, enums, etc.).
///
/// The [ctx] is mutated in place — bytecode is emitted into its output buffer.
void _compileDeclarations(
  CompilerContext ctx,
  Map<int, Map<String, DeclarationOrBridge>> topLevelDeclarationsMap,
  Map<int, Map<String, Map<String, Declaration>>> instanceDeclarationsMap,
  Map<int, Map<String, DeclarationOrPrefix>> visibleDeclarationsByIndex, [
  List<_ExtensionEntry> extensionDeclarations = const [],
]) {
  try {
    /// Compile statics first so we can infer their type
    topLevelDeclarationsMap.forEach((key, value) {
      final visibleInLibrary = visibleDeclarationsByIndex[key];
      if (visibleInLibrary == null) {
        return;
      }
      value.forEach((name, tlDeclaration) {
        if (tlDeclaration.isBridge || !visibleInLibrary.containsKey(name)) {
          return;
        }
        final declaration = tlDeclaration.declaration!;
        ctx.library = key;
        if (declaration is VariableDeclaration &&
            declaration.parent!.parent is TopLevelVariableDeclaration) {
          compileDeclaration(declaration, ctx);
          ctx.resetStack();
        } else if (declaration is ClassDeclaration) {
          ctx.currentClass = declaration;
          for (final d in declaration.members
              .whereType<FieldDeclaration>()
              .where((e) => e.isStatic)) {
            compileFieldDeclaration(-1, d, ctx, declaration);
            ctx.resetStack();
          }
          ctx.currentClass = null;
        } else if (declaration is EnumDeclaration) {
          ctx.currentClass = declaration;
          for (final d in declaration.members
              .whereType<FieldDeclaration>()
              .where((e) => e.isStatic)) {
            compileFieldDeclaration(-1, d, ctx, declaration);
            ctx.resetStack();
          }
          ctx.currentClass = null;
        } else if (declaration is MixinDeclaration) {
          ctx.currentClass = declaration;
          for (final d in declaration.members
              .whereType<FieldDeclaration>()
              .where((e) => e.isStatic)) {
            compileFieldDeclaration(-1, d, ctx, declaration);
            ctx.resetStack();
          }
          ctx.currentClass = null;
        }
      });
    });

    /// Compile the rest of the declarations
    topLevelDeclarationsMap.forEach((key, value) {
      ctx.topLevelDeclarationPositions[key] = {};
      ctx.instanceDeclarationPositions[key] = {};
      ctx.instanceGetterIndices[key] = {};
      final visibleInLibrary = visibleDeclarationsByIndex[key];
      if (visibleInLibrary == null) {
        return;
      }
      value.forEach((name, tlDeclaration) {
        if (tlDeclaration.isBridge || !visibleInLibrary.containsKey(name)) {
          return;
        }
        final declaration = tlDeclaration.declaration!;
        if (declaration is ConstructorDeclaration ||
            declaration is MethodDeclaration ||
            declaration is VariableDeclaration ||
            (declaration is TypeAlias && declaration is! ClassTypeAlias)) {
          return;
        }
        ctx.library = key;
        compileDeclaration(declaration, ctx);
        ctx.resetStack();
      });
    });

    // Compile extension methods after all class/mixin declarations so that
    // instanceDeclarationPositions[lib][className] already exists.
    for (final ext in extensionDeclarations) {
      final onType = ext.declaration.onClause?.extendedType;
      if (onType is! NamedType) continue;
      final typeName = onType.name2.lexeme;

      // Resolve the on-type's class declaration via visibleTypes so that
      // cross-library extensions work correctly.
      final typeRef = ctx.visibleTypes[ext.libraryIndex]?[typeName];
      final classLib = typeRef?.file ?? ext.libraryIndex;
      final classDob = topLevelDeclarationsMap[classLib]?[typeName];
      if (classDob == null || classDob.isBridge) continue;
      final parent = classDob.declaration;
      if (parent is! NamedCompilationUnitMember) continue;

      ctx.library = classLib;
      ctx.currentClass = parent;
      for (final member in ext.declaration.members) {
        if (member is MethodDeclaration && !member.isStatic) {
          ctx.resetStack(position: 1);
          compileDeclaration(member, ctx, parent: parent);
        }
      }
      ctx.currentClass = null;
      ctx.resetStack();
    }
  } on CompileError catch (e, stk) {
    Error.throwWithStackTrace(e.copyWithContext(ctx), stk);
  }
}
