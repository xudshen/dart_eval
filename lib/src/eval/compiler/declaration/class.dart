import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/declaration/constructor.dart';
import 'package:dart_eval/src/eval/compiler/declaration/declaration.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';

void compileClassDeclaration(CompilerContext ctx, ClassDeclaration d,
    {bool statics = false}) {
  // Load class-level type parameters (e.g. T in class Foo<T>) so they
  // resolve to dynamic during member compilation
  TypeRef.loadTemporaryTypes(ctx, d.typeParameters?.typeParameters);

  final $runtimeType =
      ctx.typeRefIndexMap[TypeRef.lookupDeclaration(ctx, ctx.library, d)];
  final clsName = d.name.lexeme;
  ctx.instanceDeclarationPositions[ctx.library]![clsName] = [
    {},
    {},
    {},
    $runtimeType
  ];
  ctx.instanceGetterIndices[ctx.library]![clsName] = {};
  final constructors = <ConstructorDeclaration>[];
  final fields = <FieldDeclaration>[];
  final methods = <MethodDeclaration>[];
  for (final m in d.members) {
    if (m is ConstructorDeclaration) {
      constructors.add(m);
    } else if (m is FieldDeclaration) {
      if (!m.isStatic) {
        fields.add(m);
      }
    } else {
      m as MethodDeclaration;
      methods.add(m);
    }
  }
  var i = 0;
  if (constructors.isEmpty) {
    ctx.resetStack(position: 0);
    ctx.currentClass = d;
    compileDefaultConstructor(ctx, d, fields);
  }
  for (final m in <ClassMember>[...fields, ...methods, ...constructors]) {
    ctx.resetStack(
        position: m is ConstructorDeclaration ||
                (m is MethodDeclaration && m.isStatic)
            ? 0
            : 1);
    ctx.currentClass = d;
    compileDeclaration(m, ctx, parent: d, fieldIndex: i, fields: fields);
    if (m is FieldDeclaration) {
      i += m.fields.variables.length;
    }
  }
  // Merge mixin methods into this class's instance declaration positions
  if (d.withClause != null) {
    final classPositions =
        ctx.instanceDeclarationPositions[ctx.library]![clsName]!;
    final classGetterIndices =
        ctx.instanceGetterIndices[ctx.library]![clsName]!;
    for (final mixinType in d.withClause!.mixinTypes) {
      final mixinName = mixinType.name2.lexeme;
      final mixinPositions =
          ctx.instanceDeclarationPositions[ctx.library]?[mixinName];
      if (mixinPositions == null) continue;
      // Merge getters (index 0), setters (index 1), methods (index 2)
      for (var idx = 0; idx < 3; idx++) {
        final mixinMap = mixinPositions[idx] as Map;
        final classMap = classPositions[idx] as Map;
        for (final entry in mixinMap.entries) {
          classMap.putIfAbsent(entry.key, () => entry.value);
        }
      }
      // Merge getter indices
      final mixinGetterIndices =
          ctx.instanceGetterIndices[ctx.library]?[mixinName];
      if (mixinGetterIndices != null) {
        for (final entry in mixinGetterIndices.entries) {
          classGetterIndices.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
  }
  ctx.currentClass = null;
  ctx.temporaryTypes[ctx.library]?.clear();
  ctx.resetStack();
}
