import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/model/label.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';

StatementInfo compileContinueStatement(
    ContinueStatement s, CompilerContext ctx) {
  if (s.label != null) {
    throw CompileError('Continue labels are not currently supported', s);
  }

  final currentState = ctx.saveState();

  final index =
      ctx.labels.lastIndexWhere((label) => label.type == LabelType.loop);

  if (index == -1) {
    throw CompileError(
        'Cannot use \'continue\' outside of a loop context', s);
  }

  for (var i = ctx.labels.length - 1; i > index; i--) {
    ctx.labels[i].cleanup(ctx);
  }

  final label = ctx.labels[index];
  if (label.continueCleanup != null) {
    label.continueCleanup!(ctx);
  } else {
    throw CompileError('Loop label missing continue handler', s);
  }

  ctx.restoreState(currentState);
  return StatementInfo(-1);
}
