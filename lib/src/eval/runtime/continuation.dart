/// A continuation represents a state of the VM that can be saved and resumed during an async suspension
class Continuation {
  const Continuation(
      {required this.programOffset,
      required this.frameOffset,
      required this.frame,
      required this.args,
      this.catchFrame = const []});

  final int programOffset;
  final int frameOffset;
  final List<Object?> frame;
  final List<Object?> args;

  /// Saved catch stack entries from the current frame at the point of suspension.
  /// Restored by bridgeCall when resuming so that PopCatch can find the catch
  /// offsets pushed by Try opcodes before the await.
  final List<int> catchFrame;
}
