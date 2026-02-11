/// Records scope events during compilation and produces a human-readable
/// scope tree dump showing variable-to-slot mappings and closure boundaries.
///
/// Usage:
///   final recorder = ScopeRecorder();
///   compiler.compileWriteAndLoad(sources, scopeRecorder: recorder);
///   print(recorder.dump());
class ScopeRecorder {
  final _events = <_ScopeEvent>[];

  void onBeginAllocScope({
    required int depth,
    required int existingAllocLen,
    required bool isClosure,
  }) {
    _events.add(_ScopeEvent.begin(
      depth: depth,
      existingAllocLen: existingAllocLen,
      isClosure: isClosure,
    ));
  }

  void onEndAllocScope({required int depth}) {
    _events.add(_ScopeEvent.end(depth: depth));
  }

  void onSetLocal({
    required String name,
    required int scopeFrameOffset,
    required int frameIndex,
    required bool boxed,
    required String? typeName,
  }) {
    _events.add(_ScopeEvent.local(
      name: name,
      scopeFrameOffset: scopeFrameOffset,
      frameIndex: frameIndex,
      boxed: boxed,
      typeName: typeName,
    ));
  }

  /// Produce a human-readable scope tree dump.
  String dump() {
    final sb = StringBuffer();
    var indent = 0;

    for (final event in _events) {
      final pad = '  ' * indent;
      switch (event.kind) {
        case _EventKind.begin:
          final boundary = event.isClosure ? ' [closure boundary]' : '';
          sb.writeln('${pad}Scope (depth=${event.depth}, '
              'existingAlloc=${event.existingAllocLen}$boundary) {');
          indent++;
        case _EventKind.end:
          indent = (indent - 1).clamp(0, 100);
          sb.writeln('${'  ' * indent}}');
        case _EventKind.local:
          final boxStr = event.boxed ? ' (boxed)' : '';
          final typeStr = event.typeName != null ? ': ${event.typeName}' : '';
          sb.writeln('$pad${event.name} → slot ${event.scopeFrameOffset}$typeStr$boxStr');
      }
    }

    return sb.toString();
  }
}

enum _EventKind { begin, end, local }

class _ScopeEvent {
  final _EventKind kind;
  final int depth;
  final int existingAllocLen;
  final bool isClosure;
  final String name;
  final int scopeFrameOffset;
  final int frameIndex;
  final bool boxed;
  final String? typeName;

  _ScopeEvent._({
    required this.kind,
    this.depth = 0,
    this.existingAllocLen = 0,
    this.isClosure = false,
    this.name = '',
    this.scopeFrameOffset = 0,
    this.frameIndex = 0,
    this.boxed = false,
    this.typeName,
  });

  factory _ScopeEvent.begin({
    required int depth,
    required int existingAllocLen,
    required bool isClosure,
  }) =>
      _ScopeEvent._(
        kind: _EventKind.begin,
        depth: depth,
        existingAllocLen: existingAllocLen,
        isClosure: isClosure,
      );

  factory _ScopeEvent.end({required int depth}) =>
      _ScopeEvent._(kind: _EventKind.end, depth: depth);

  factory _ScopeEvent.local({
    required String name,
    required int scopeFrameOffset,
    required int frameIndex,
    required bool boxed,
    required String? typeName,
  }) =>
      _ScopeEvent._(
        kind: _EventKind.local,
        name: name,
        scopeFrameOffset: scopeFrameOffset,
        frameIndex: frameIndex,
        boxed: boxed,
        typeName: typeName,
      );
}
