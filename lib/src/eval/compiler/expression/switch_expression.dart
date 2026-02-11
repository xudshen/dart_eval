import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/invoke.dart';
import 'package:dart_eval/src/eval/compiler/helpers/pattern.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';

/// Compile a [SwitchExpression] to EVC bytecode.
///
/// Combines the result-variable pattern from [compileConditionalExpression]
/// with the recursive case-matching pattern from [compileSwitchStatement].
Variable compileSwitchExpression(
    CompilerContext ctx, SwitchExpression e, [TypeRef? boundType]) {
  ctx.setLocal('#switch_result', BuiltinValue().push(ctx));
  final vRef = IdentifierReference(null, '#switch_result');
  final types = <TypeRef>{if (boundType != null) boundType};

  final switchExpr = compileExpression(e.expression, ctx).boxIfNeeded(ctx);

  _compileSwitchExpressionCases(
      ctx, switchExpr, e.cases, 0, boundType, types, vRef);

  final val = vRef.getValue(ctx).updated(ctx);
  return val.copyWith(
      type: types.isNotEmpty
          ? TypeRef.commonBaseType(ctx, types).copyWith(boxed: val.boxed)
          : val.type);
}

void _compileSwitchExpressionCases(
    CompilerContext ctx,
    Variable switchExpr,
    List<SwitchExpressionCase> cases,
    int index,
    TypeRef? boundType,
    Set<TypeRef> types,
    IdentifierReference vRef) {
  if (index >= cases.length) return;

  final currentCase = cases[index];
  final isLast = index == cases.length - 1;

  macroBranch(
    ctx,
    boundType == null ? null : AlwaysReturnType(boundType, false),
    condition: (ctx) {
      final matches = patternMatchAndBind(
          ctx, currentCase.guardedPattern.pattern, switchExpr);
      final guard = currentCase.guardedPattern.whenClause;
      if (guard != null) {
        final guardExpr = compileExpression(guard.expression, ctx);
        return matches.invoke(ctx, '&&', [guardExpr]).result;
      }
      return matches;
    },
    thenBranch: (ctx, rt) {
      final v = compileExpression(currentCase.expression, ctx, boundType);
      types.add(v.type);
      vRef.setValue(ctx, v);
      return StatementInfo(-1);
    },
    elseBranch: isLast
        ? null
        : (ctx, rt) {
            _compileSwitchExpressionCases(
                ctx, switchExpr, cases, index + 1, boundType, types, vRef);
            return StatementInfo(-1);
          },
    resolveStateToThen: true,
    source: currentCase,
  );
}
