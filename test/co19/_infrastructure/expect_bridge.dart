import 'package:dart_eval/dart_eval_bridge.dart';

/// Bridge class for co19's `Expect` assertion utility.
///
/// All methods are static — this bridge does not wrap a real Dart object.
/// It registers into `package:co19_expect/expect.dart` so that eval code
/// can `import 'package:co19_expect/expect.dart';` and call
/// `Expect.equals(...)`, `Expect.isTrue(...)`, etc.
class $Expect {
  static const _library = 'package:co19_expect/expect.dart';

  static const $type = BridgeTypeRef(
      BridgeTypeSpec('package:co19_expect/expect.dart', 'Expect'));

  static const $declaration = BridgeClassDef(
    BridgeClassType($type, isAbstract: false),
    constructors: {},
    fields: {},
    methods: {
      'equals': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('expected',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
      'notEquals': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('unexpected',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
      'isTrue': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
      'isFalse': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
      'isNull': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
      'isNotNull': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
      'throws': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('f',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.function)), false),
            ],
          ),
          isStatic: true),
      'fail': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('reason',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)), false),
            ],
          ),
          isStatic: true),
      'listEquals': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('expected',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
      'mapEquals': BridgeMethodDef(
          BridgeFunctionDef(
            returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
            params: [
              BridgeParameter('expected',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
              BridgeParameter('actual',
                  BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false),
            ],
          ),
          isStatic: true),
    },
    getters: {},
    setters: {},
    bridge: false,
    wrap: true,
  );

  static void configureForRuntime(Runtime runtime) {
    runtime.registerBridgeFunc(
        _library, 'Expect.equals', const _$equals().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.notEquals', const _$notEquals().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.isTrue', const _$isTrue().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.isFalse', const _$isFalse().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.isNull', const _$isNull().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.isNotNull', const _$isNotNull().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.throws', const _$throws().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.fail', const _$fail().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.listEquals', const _$listEquals().call);
    runtime.registerBridgeFunc(
        _library, 'Expect.mapEquals', const _$mapEquals().call);
  }
}

/// Exception thrown by Expect assertion failures, mirroring co19's
/// `ExpectException`.
class Co19ExpectException implements Exception {
  final String message;
  Co19ExpectException(this.message);

  @override
  String toString() => 'Co19ExpectException: $message';
}

// ---------------------------------------------------------------------------
// Static method implementations
// ---------------------------------------------------------------------------

class _$equals implements EvalCallable {
  const _$equals();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final expected = args[0]?.$reified;
    final actual = args[1]?.$reified;
    if (expected != actual) {
      throw Co19ExpectException(
          'Expect.equals(expected: <$expected>, actual: <$actual>) fails.');
    }
    return null;
  }
}

class _$notEquals implements EvalCallable {
  const _$notEquals();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final unexpected = args[0]?.$reified;
    final actual = args[1]?.$reified;
    if (unexpected == actual) {
      throw Co19ExpectException(
          'Expect.notEquals(unexpected: <$unexpected>, actual: <$actual>) fails.');
    }
    return null;
  }
}

class _$isTrue implements EvalCallable {
  const _$isTrue();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final actual = args[0]?.$reified;
    if (!identical(actual, true)) {
      throw Co19ExpectException('Expect.isTrue($actual) fails.');
    }
    return null;
  }
}

class _$isFalse implements EvalCallable {
  const _$isFalse();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final actual = args[0]?.$reified;
    if (!identical(actual, false)) {
      throw Co19ExpectException('Expect.isFalse($actual) fails.');
    }
    return null;
  }
}

class _$isNull implements EvalCallable {
  const _$isNull();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final actual = args[0]?.$reified;
    if (actual != null) {
      throw Co19ExpectException(
          'Expect.isNull(actual: <$actual>) fails.');
    }
    return null;
  }
}

class _$isNotNull implements EvalCallable {
  const _$isNotNull();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final actual = args[0]?.$reified;
    if (actual == null) {
      throw Co19ExpectException('Expect.isNotNull(actual: null) fails.');
    }
    return null;
  }
}

class _$throws implements EvalCallable {
  const _$throws();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final f = args[0] as EvalCallable;
    try {
      f.call(runtime, null, []);
    } catch (_) {
      // Expected an exception — success.
      return null;
    }
    throw Co19ExpectException('Expect.throws() fails: no exception thrown.');
  }
}

class _$fail implements EvalCallable {
  const _$fail();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final reason = args[0]?.$reified as String;
    throw Co19ExpectException('Expect.fail($reason)');
  }
}

class _$listEquals implements EvalCallable {
  const _$listEquals();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final expected = args[0]?.$reified;
    final actual = args[1]?.$reified;
    if (expected is! List) {
      throw Co19ExpectException('expected is not a List: $expected');
    }
    if (actual is! List) {
      throw Co19ExpectException('actual is not a List: $actual');
    }
    if (expected.length != actual.length) {
      throw Co19ExpectException(
          'Expect.listEquals: lengths differ '
          '(expected: ${expected.length}, actual: ${actual.length})');
    }
    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != actual[i]) {
        throw Co19ExpectException(
            'Expect.listEquals: mismatch at index $i '
            '(expected: ${expected[i]}, actual: ${actual[i]})');
      }
    }
    return null;
  }
}

class _$mapEquals implements EvalCallable {
  const _$mapEquals();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final expected = args[0]?.$reified;
    final actual = args[1]?.$reified;
    if (expected is! Map) {
      throw Co19ExpectException('expected is not a Map: $expected');
    }
    if (actual is! Map) {
      throw Co19ExpectException('actual is not a Map: $actual');
    }
    if (expected.length != actual.length) {
      throw Co19ExpectException(
          'Expect.mapEquals: lengths differ '
          '(expected: ${expected.length}, actual: ${actual.length})');
    }
    for (final key in expected.keys) {
      if (!actual.containsKey(key)) {
        throw Co19ExpectException(
            'Expect.mapEquals: missing key $key in actual');
      }
      if (expected[key] != actual[key]) {
        throw Co19ExpectException(
            'Expect.mapEquals: mismatch at key $key '
            '(expected: ${expected[key]}, actual: ${actual[key]})');
      }
    }
    return null;
  }
}
