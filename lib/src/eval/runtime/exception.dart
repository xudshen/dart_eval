import 'dart:math';

import 'package:dart_eval/src/eval/shared/stdlib/core/num.dart';

/// Format a dart_eval stack sample for printing.
String formatStackSample(List st, int size, [int? frameOffset]) {
  final sb = StringBuffer('[');
  var i = 0;
  if (frameOffset != null) {
    i = max(0, frameOffset - size ~/ 1.3);
  }
  final end = min(i + size, st.length);
  for (; i < end; i++) {
    final s = st[i];
    if (i == frameOffset) {
      sb.write('*');
    }
    sb.write('L$i: ');
    if (s is List) {
      sb.write(formatStackSample(s, 3));
    } else if (s is String) {
      sb.write('"$s"');
    } else if (s is $num) {
      sb.write('\$$s');
    } else if (s == null) {
      sb.write('null');
    } else if (s is int || s is double || s is bool) {
      sb.write('(raw) $s');
    } else {
      try {
        sb.write('$s');
      } catch (_) {
        sb.write('<${s.runtimeType}>');
      }
    }
    if (i < end - 1) {
      sb.write(', ');
    }
  }
  sb.write(']');
  return sb.toString();
}

class EvalUnknownPropertyException implements Exception {
  const EvalUnknownPropertyException(this.name);

  final String name;

  @override
  String toString() => 'EvalUnknownPropertyException ($name)';
}

class InvalidUnboxedValueException implements Exception {
  const InvalidUnboxedValueException(this.value);

  final Object value;

  @override
  String toString() => 'InvalidUnboxedValueException: $value';
}

class ProgramExit implements Exception {
  final int exitCode;

  ProgramExit(this.exitCode);
}

/// Thrown when the runtime exceeds its configured instruction limit.
///
/// This prevents infinite loops from exhausting memory or hanging the process.
/// Set via [Runtime.instructionLimit].
class InstructionLimitExceededException implements Exception {
  const InstructionLimitExceededException(this.count, this.limit);

  /// The instruction count when the limit was hit.
  final int count;

  /// The configured limit.
  final int limit;

  @override
  String toString() =>
      'InstructionLimitExceededException: executed $count instructions '
      '(limit: $limit)';
}
