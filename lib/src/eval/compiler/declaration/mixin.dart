import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/declaration/constructor.dart';
import 'package:dart_eval/src/eval/compiler/declaration/declaration.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';

/// Compile a [MixinDeclaration] similarly to a [ClassDeclaration].
///
/// Mixins are compiled as class-like structures: they have fields and methods
/// but no constructors. A default constructor is generated so that the `with`
/// clause can instantiate the mixin's part of the object layout.
void compileMixinDeclaration(CompilerContext ctx, MixinDeclaration d) {
  final $runtimeType =
      ctx.typeRefIndexMap[TypeRef.lookupDeclaration(ctx, ctx.library, d)];
  final mixinName = d.name.lexeme;
  ctx.instanceDeclarationPositions[ctx.library]![mixinName] = [
    {},
    {},
    {},
    $runtimeType
  ];
  ctx.instanceGetterIndices[ctx.library]![mixinName] = {};
  final fields = <FieldDeclaration>[];
  final methods = <MethodDeclaration>[];
  for (final m in d.members) {
    if (m is FieldDeclaration) {
      if (!m.isStatic) {
        fields.add(m);
      }
    } else {
      m as MethodDeclaration;
      methods.add(m);
    }
  }
  // Generate default constructor for mixin
  ctx.resetStack(position: 0);
  ctx.currentClass = d;
  compileDefaultConstructor(ctx, d, fields);
  var i = 0;
  for (final m in <ClassMember>[...fields, ...methods]) {
    ctx.resetStack(
        position: (m is MethodDeclaration && m.isStatic) ? 0 : 1);
    ctx.currentClass = d;
    compileDeclaration(m, ctx, parent: d, fieldIndex: i, fields: fields);
    if (m is FieldDeclaration) {
      i += m.fields.variables.length;
    }
  }
  ctx.currentClass = null;
  ctx.resetStack();
}
