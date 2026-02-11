// ignore_for_file: body_might_complete_normally_nullable

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/ops/all_ops.dart';

class PrescanVisitor extends RecursiveAstVisitor<PrescanContext?> {
  final PrescanContext ctx = PrescanContext();
  late final TypeRef dynamicType;

  @override
  PrescanContext? visitFunctionDeclaration(FunctionDeclaration node) {
    ctx.beginAllocScope();
    super.visitFunctionDeclaration(node);
    ctx.endAllocScope();
  }

  @override
  PrescanContext? visitMethodDeclaration(MethodDeclaration node) {
    ctx.beginAllocScope();
    super.visitMethodDeclaration(node);
    ctx.endAllocScope();
  }

  @override
  PrescanContext? visitVariableDeclaration(VariableDeclaration node) {
    node.initializer?.accept(this);
    ctx.setLocal(node.name.lexeme, Variable.alloc(ctx, dynamicType));
  }

  @override
  PrescanContext? visitBlock(Block node) {
    ctx.beginAllocScope();
    node.visitChildren(this);
    ctx.endAllocScope();
  }

  @override
  PrescanContext? visitIfStatement(IfStatement node) {
    ctx.beginAllocScope();
    node.expression.accept(this);
    final initialState = ctx.saveState();
    ctx.beginAllocScope();
    node.thenStatement.accept(this);
    ctx.endAllocScope();
    ctx.resolveBranchStateDiscontinuity(initialState);
    if (node.elseStatement != null) {
      ctx.beginAllocScope();
      node.elseStatement!.accept(this);
      ctx.endAllocScope();
      ctx.resolveBranchStateDiscontinuity(initialState);
    }
    ctx.endAllocScope();
  }

  @override
  PrescanContext? visitForStatement(ForStatement node) {
    final parts = node.forLoopParts;
    final loopVarNames = <String>[];

    // Visit iterable expression before outer scope (mirrors compiler)
    if (parts is ForEachParts) {
      parts.iterable.accept(this);
    }

    // Mirror macroLoop's outer scope
    ctx.beginAllocScope();
    final outerScopeIndex = ctx.locals.length - 1;

    if (parts is ForPartsWithDeclarations) {
      for (final v in parts.variables.variables) {
        v.accept(this); // triggers visitVariableDeclaration
        loopVarNames.add(v.name.lexeme);
      }
    } else if (parts is ForEachPartsWithDeclaration) {
      ctx.setLocal(
          parts.loopVariable.name.lexeme, Variable.alloc(ctx, dynamicType));
      loopVarNames.add(parts.loopVariable.name.lexeme);
    } else if (parts is ForPartsWithExpression) {
      parts.initialization?.accept(this);
    }

    // Mirror macroLoop's condition scope
    ctx.beginAllocScope();

    if (parts is ForParts) {
      parts.condition?.accept(this);
      for (final u in parts.updaters) {
        u.accept(this);
      }
    }

    // Visit body (Block will open its own scope via visitBlock)
    node.body.accept(this);

    // End condition scope
    ctx.endAllocScope();

    // Detect loop variables captured by closures
    if (loopVarNames.isNotEmpty) {
      for (final v in ctx.localsReferencedFromClosure) {
        if (v.frameIndex == outerScopeIndex &&
            loopVarNames.contains(v.name)) {
          ctx.loopVarScopesNeedingIteration.add(outerScopeIndex);
          ctx.closedFrames.remove(outerScopeIndex);
          break;
        }
      }
    }

    // End outer scope
    ctx.endAllocScope();

    return null;
  }

  @override
  PrescanContext? visitFunctionExpression(FunctionExpression node) {
    if (node.parent is Statement || node.parent is Expression) {
      ctx.inClosure = true;
      node.visitChildren(this);
      ctx.inClosure = false;
    }
    return null;
  }

  @override
  PrescanContext? visitSimpleIdentifier(SimpleIdentifier node) {
    if (ctx.inClosure) {
      final l = ctx.lookupLocal(node.name);
      if (l != null && l.frameIndex != ctx.locals.length - 1) {
        ctx.localsReferencedFromClosure.add(l);
        ctx.closedFrames.add(l.frameIndex!);
      }
    }
    node.visitChildren(this);
  }
}

class PrescanContext with ScopeContext {
  PrescanContext();

  var inClosure = false;
  List<Variable> localsReferencedFromClosure = [];
  Set<int> closedFrames = {};
  Set<int> loopVarScopesNeedingIteration = {};

  @override
  int pushOp(EvcOp op, int length) {
    return 0;
  }
}
