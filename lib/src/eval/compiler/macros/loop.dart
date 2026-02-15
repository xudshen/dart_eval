import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/macros/macro.dart';
import 'package:dart_eval/src/eval/compiler/model/label.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

StatementInfo macroLoop(
  CompilerContext ctx,
  AlwaysReturnType? expectedReturnType, {
  required MacroStatementClosure body,
  MacroClosure? initialization,
  MacroVariableClosure? condition,
  MacroClosure? update,
  MacroClosure? after,
  bool alwaysLoopOnce = false,
  bool updateBeforeBody = false,
  List<String> loopVariableNames = const [],
  bool bodyContainsClosure = false,
}) {
  ctx.beginAllocScope();
  final outerScopeIndex = ctx.locals.length - 1;

  if (initialization != null) {
    initialization(ctx);
  }

  /// Make a save-state of the box/unbox status of all locals
  final save = ctx.saveState();

  // Determine if per-iteration scope is needed.
  // Activated when the loop declares variables AND the body contains closures
  // that could capture them. The bodyContainsClosure flag is a lightweight AST
  // check; the prescan path is a more precise (but currently disabled) fallback.
  final needsPerIterationScope = loopVariableNames.isNotEmpty &&
      (bodyContainsClosure ||
          (ctx.preScan?.loopVarScopesNeedingIteration
                  .contains(outerScopeIndex) ??
              false));

  // Save original slot offsets of loop variables in the outer scope
  final origSlotOffsets = <int>[];
  if (needsPerIterationScope) {
    for (final name in loopVariableNames) {
      final v = ctx.lookupLocal(name)!;
      origSlotOffsets.add(v.scopeFrameOffset);
    }
  }

  JumpIfFalse? rewriteCond;
  int? rewritePos;
  Variable? conditionResult;
  ContextSaveState? conditionSaveState;
  var loopStart = ctx.out.length;

  ctx.beginAllocScope();

  if (!alwaysLoopOnce && condition != null) {
    conditionResult = condition(ctx).unboxIfNeeded(ctx);
    conditionSaveState = ctx.saveState();
    rewriteCond = JumpIfFalse.make(conditionResult.scopeFrameOffset, -1);
    rewritePos = ctx.pushOp(rewriteCond, JumpIfFalse.LEN);
  }

  var pops = ctx.peekAllocPops();

  if (update != null && updateBeforeBody) {
    update(ctx);
  }

  // --- Per-iteration scope setup ---
  final savedSFO = ctx.scopeFrameOffset;
  // Pre-reserved scratch slots for _emitCopyBack, allocated during setup so
  // body locals are placed at higher offsets and won't be overwritten.
  List<Variable>? copyBackIndexVars;
  Variable? copyBackTempVar;
  if (needsPerIterationScope) {
    final numVars = loopVariableNames.length;

    // Push loop var values as args for the new frame
    for (final name in loopVariableNames) {
      final v = ctx.lookupLocal(name)!;
      v.pushArg(ctx);
    }

    // PushScope: create new runtime frame with loop var copies
    final ps = PushScope.make(ctx.sourceFile, -1, '#iter');
    ctx.pushOp(ps, PushScope.len(ps));

    // PushCaptureScope: store parent frame reference at slot numVars
    ctx.pushOp(PushCaptureScope.make(), PushCaptureScope.length);

    // Track the per-iteration scope in the compiler
    ctx.beginAllocScope(
        existingAllocLen: numVars + 1, closure: true);

    // Register loop var copies at slots 0..N-1
    for (var j = 0; j < numVars; j++) {
      final origVar = ctx.locals[outerScopeIndex][loopVariableNames[j]]!;
      ctx.setLocal(
          loopVariableNames[j],
          origVar.copyWith(
            scopeFrameOffset: j,
            frameIndex: ctx.locals.length - 1,
          ));
    }

    // Register #prev (parent frame reference) at slot N
    ctx.setLocal(
        '#prev', Variable(numVars, CoreTypes.list.ref(ctx), isFinal: true));

    // Align compiler scopeFrameOffset with runtime frameOffset.
    // PushScope resets the runtime frame, so we must sync the compiler's
    // accumulated offset to match (numVars args + 1 for #prev).
    ctx.scopeFrameOffset = numVars + 1;

    // Pre-reserve scratch slots for _emitCopyBack:
    // - One index constant per loop variable (holds the parent-frame slot index)
    // - One temp slot (used for unboxing in the boxed case)
    // These are allocated NOW so body locals start at higher offsets, preventing
    // _emitCopyBack from overwriting closure-captured body-local slots.
    copyBackIndexVars = <Variable>[];
    for (var j = 0; j < numVars; j++) {
      copyBackIndexVars.add(
          BuiltinValue(intval: origSlotOffsets[j]).push(ctx));
    }
    copyBackTempVar = BuiltinValue().push(ctx);
  }

  // Record allocNest depth at label creation so the break cleanup can pop
  // any intermediate alloc scopes introduced by body constructs (if blocks,
  // nested blocks, etc.) that don't have their own label cleanup.
  final labelAllocDepth = ctx.allocNest.length;

  late final CompilerLabel label;

  int breakCleanup(CompilerContext ctx) {
    // Pop intermediate alloc scopes added by body constructs.  The break
    // compiler cleans up intermediate *labels* but not intermediate *scopes*
    // — e.g., an `if` block's outer alloc scope has no label and would
    // otherwise remain on allocNest, misaligning the expected structure.
    while (ctx.allocNest.length > labelAllocDepth) {
      ctx.endAllocScopeQuiet();
    }

    // Break cleanup: per-iteration scope teardown
    if (needsPerIterationScope) {
      _emitCopyBack(ctx, loopVariableNames, copyBackIndexVars!,
          copyBackTempVar!);
      ctx.pushOp(PopScope.make(), PopScope.LEN);
      ctx.endAllocScopeQuiet(popValues: false);
    }

    ctx.endAllocScopeQuiet();

    /// Box/unbox variables that were declared outside the loop and changed in
    /// the loop body to match the save state
    ctx.resolveBranchStateDiscontinuity(save);

    if (conditionSaveState != null) {
      ctx.restoreBoxingState(conditionSaveState);
      ctx.resolveBranchStateDiscontinuity(save);
    }

    ctx.endAllocScopeQuiet();
    final result = ctx.pushOp(JumpConstant.make(-1), JumpConstant.LEN);
    return result;
  }

  int continueCleanup(CompilerContext ctx) {
    // Pop intermediate alloc scopes (same as break cleanup)
    while (ctx.allocNest.length > labelAllocDepth) {
      ctx.endAllocScopeQuiet();
    }

    // Per-iteration scope teardown
    if (needsPerIterationScope) {
      _emitCopyBack(ctx, loopVariableNames, copyBackIndexVars!,
          copyBackTempVar!);
      ctx.pushOp(PopScope.make(), PopScope.LEN);
      ctx.endAllocScopeQuiet(popValues: false);
    }

    // Pop inner loop scope (condition + body allocations)
    ctx.endAllocScopeQuiet();

    // Resolve boxing state for outer variables changed during body
    ctx.resolveBranchStateDiscontinuity(save);

    // For C-style for: re-emit the update code (e.g., i++)
    if (update != null && !updateBeforeBody) {
      update(ctx);
    }

    // For do-while: re-emit the condition check
    if (alwaysLoopOnce && condition != null) {
      final condResult = condition(ctx).unboxIfNeeded(ctx);
      final jif = JumpIfFalse.make(condResult.scopeFrameOffset, -1);
      final jifPos = ctx.pushOp(jif, JumpIfFalse.LEN);
      // Condition true → loop back
      ctx.pushOp(JumpConstant.make(loopStart), JumpConstant.LEN);
      // Condition false → exit loop (rewrite JumpIfFalse to here)
      ctx.rewriteOp(jifPos,
          JumpIfFalse.make(condResult.scopeFrameOffset, ctx.out.length), 0);
      // Exit: pop outer loop scope and jump past loop via break resolution
      ctx.endAllocScopeQuiet();
      final exitJump = ctx.pushOp(JumpConstant.make(-1), JumpConstant.LEN);
      ctx.labelReferences.putIfAbsent(label, () => <int>{}).add(exitJump);
      return exitJump;
    }

    // Jump to loop start (condition re-check for while/for/for-each)
    return ctx.pushOp(JumpConstant.make(loopStart), JumpConstant.LEN);
  }

  label = CompilerLabel(LabelType.loop, loopStart, breakCleanup,
      continueCleanup: continueCleanup);

  ctx.labels.add(label);
  final statementResult = body(ctx, expectedReturnType);
  ctx.labels.removeLast();

  if (!(statementResult.willAlwaysThrow || statementResult.willAlwaysReturn)) {
    // --- Per-iteration scope teardown (normal flow) ---
    if (needsPerIterationScope) {
      _emitCopyBack(ctx, loopVariableNames, copyBackIndexVars!,
          copyBackTempVar!);
      ctx.pushOp(PopScope.make(), PopScope.LEN);
      ctx.endAllocScope(popValues: false);
      ctx.scopeFrameOffset = savedSFO;
    }

    if (update != null && !updateBeforeBody) {
      update(ctx);
    }

    /// For do-while type loops, execute the condition check after the body
    if (alwaysLoopOnce && condition != null) {
      conditionResult = condition(ctx).unboxIfNeeded(ctx);
      rewriteCond = JumpIfFalse.make(conditionResult.scopeFrameOffset, -1);
      rewritePos = ctx.pushOp(rewriteCond, JumpIfFalse.LEN);
    }

    ctx.endAllocScope();

    /// Box/unbox variables that were declared outside the loop and changed in
    /// the loop body to match the save state
    ctx.resolveBranchStateDiscontinuity(save);

    ctx.pushOp(JumpConstant.make(loopStart), JumpConstant.LEN);
  } else {
    if (needsPerIterationScope) {
      // Body always throws/returns; still clean up compiler state
      ctx.endAllocScope(popValues: false);
      ctx.scopeFrameOffset = savedSFO;
    }
    pops = 0;
  }

  if (rewritePos != null) {
    ctx.rewriteOp(rewritePos,
        JumpIfFalse.make(conditionResult!.scopeFrameOffset, ctx.out.length), 0);
  }

  if (conditionSaveState != null) {
    ctx.restoreBoxingState(conditionSaveState);
    ctx.resolveBranchStateDiscontinuity(save);
  }

  if (after != null) {
    after(ctx);
  }

  ctx.endAllocScope(popAdjust: pops);
  ctx.resolveLabel(label);

  return statementResult;
}

/// Emit bytecode to copy loop variable values from the per-iteration frame
/// back to the parent frame via #prev and ListSetIndexed.
///
/// Uses [copyBackIndexVars] and [copyBackTempVar] that were pre-reserved
/// during per-iteration scope setup. This avoids allocating new slots here,
/// which would overlap with body-local variable slots that closures may still
/// reference (since closures capture the per-iteration frame's `List<Object?>`).
///
/// If a loop variable became boxed during the body (e.g., from `==` which
/// calls BoxInt in-place), we unbox to the pre-reserved temp slot before
/// writing to the parent. This preserves the boxed value at the original
/// per-iteration slot so closures that captured the frame still see the
/// expected boxed value.
void _emitCopyBack(CompilerContext ctx, List<String> loopVariableNames,
    List<Variable> copyBackIndexVars, Variable copyBackTempVar) {
  for (var j = 0; j < loopVariableNames.length; j++) {
    final localVar = ctx.lookupLocal(loopVariableNames[j])!;
    final prevVar = ctx.lookupLocal('#prev')!;

    int valueSlot = localVar.scopeFrameOffset;

    if (localVar.boxed) {
      // The loop variable was boxed in-place (e.g., by `==`).  Copy to the
      // pre-reserved temporary and unbox it so the parent frame receives the
      // raw value it expects — without modifying per_iter[slot] in-place.
      ctx.pushOp(
          CopyValue.make(
              copyBackTempVar.scopeFrameOffset, localVar.scopeFrameOffset),
          CopyValue.LEN);
      ctx.pushOp(Unbox.make(copyBackTempVar.scopeFrameOffset), Unbox.LEN);
      valueSlot = copyBackTempVar.scopeFrameOffset;
    }

    ctx.pushOp(
        ListSetIndexed.make(prevVar.scopeFrameOffset,
            copyBackIndexVars[j].scopeFrameOffset, valueSlot),
        ListSetIndexed.LEN);
  }
}
