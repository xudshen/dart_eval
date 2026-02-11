/// Represents a call-level frame in the dart_eval VM.
///
/// Each CallFrame corresponds to one function invocation (from Call, execute(),
/// bridgeCall(), or PushFinally). It groups the return address and catch
/// offsets that were previously stored in separate `callStack` and `catchStack`
/// lists.
///
/// Note: This does NOT include scope-level data (locals, scopeName,
/// savedFrameOffset), because Call and PushScope are separate instructions
/// and scope-level entries can outnumber call-level entries (due to Try
/// pushing extra frameOffsetStack entries). The scope-level stacks (stack,
/// scopeNameStack, frameOffsetStack) remain as separate lists on Runtime.
class CallFrame {
  CallFrame(this.returnAddress, [List<int>? catchOffsets])
      : catchOffsets = catchOffsets ?? [];

  /// The program offset to return to after this call completes.
  /// -1 means this is a root frame (execute/bridgeCall entry point).
  final int returnAddress;

  /// Catch offsets registered by Try opcodes within this call frame.
  /// Positive values are catch block offsets; negative values are finally
  /// block offsets (encoded as -programOffset).
  final List<int> catchOffsets;

  @override
  String toString() => 'CallFrame(ret=$returnAddress, catches=$catchOffsets)';
}
