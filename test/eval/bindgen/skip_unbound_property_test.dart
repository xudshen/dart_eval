import 'dart:io';

import 'package:dart_eval/src/eval/bindgen/bindgen.dart';
import 'package:dart_eval/src/eval/bindgen/type.dart';
import 'package:dart_eval/src/eval/cli/utils.dart';
import 'package:test/test.dart';

/// Verifies that propertyGetters() skips members whose return type
/// cannot be wrapped (wrapVar returns the skip sentinel).
void main() {
  late Bindgen bindgen;

  setUpAll(() {
    bindgen = Bindgen();
    final projectRoot = findProjectRoot(Directory.current);
    final packageConfig = getPackageConfig(projectRoot);
    for (final package in packageConfig.packages) {
      bindgen.inject(package: package);
    }
  });

  test('generated wrapper code does not contain runtime.wrapAlways', () async {
    final output = await bindgen.parseFromConfig(
      libraryUri: 'dart:math',
      className: 'Random',
      overrideLibrary: 'dart:math',
    );

    expect(output, isNotNull);
    expect(output, isNot(contains('runtime.wrapAlways')),
        reason: 'Generated code should use explicit wrappers, not wrapAlways');
    expect(output, isNot(contains('wrapAlways')),
        reason: 'No form of wrapAlways should appear in generated code');
  });

  test('generated code does not contain skip sentinel', () async {
    final output = await bindgen.parseFromConfig(
      libraryUri: 'dart:math',
      className: 'Random',
      overrideLibrary: 'dart:math',
    );

    expect(output, isNotNull);
    expect(output, isNot(contains(wrapVarSkipSentinel)),
        reason: 'Skip sentinel must not leak into generated code');
  });

  test('bridge mode: no wrapAlways or sentinel in generated code', () async {
    final bridgeBindgen = Bindgen();
    final projectRoot = findProjectRoot(Directory.current);
    final packageConfig = getPackageConfig(projectRoot);
    for (final package in packageConfig.packages) {
      bridgeBindgen.inject(package: package);
    }

    final output = await bridgeBindgen.parseFromConfig(
      libraryUri: 'dart:math',
      className: 'Random',
      overrideLibrary: 'dart:math',
      isBridge: true,
    );

    expect(output, isNotNull);
    expect(output, isNot(contains('wrapAlways')),
        reason: 'Bridge mode should not use wrapAlways');
    expect(output, isNot(contains(wrapVarSkipSentinel)),
        reason: 'Skip sentinel must not leak into bridge mode generated code');
  });

  test('class with unbound property types omits those properties', () async {
    // Utf8Codec has encoder/decoder getters returning Utf8Encoder/Utf8Decoder
    // which extend Converter (a generic type). These may be unbound depending
    // on dart_eval stdlib coverage.
    final codecBindgen = Bindgen();
    final projectRoot = findProjectRoot(Directory.current);
    final packageConfig = getPackageConfig(projectRoot);
    for (final package in packageConfig.packages) {
      codecBindgen.inject(package: package);
    }

    final output = await codecBindgen.parseFromConfig(
      libraryUri: 'dart:convert',
      className: 'Utf8Codec',
      overrideLibrary: 'dart:convert',
    );

    // Whether output is null (fully skipped) or has content,
    // the sentinel must never leak through
    if (output != null) {
      expect(output, isNot(contains(wrapVarSkipSentinel)),
          reason: 'Skip sentinel must not leak into generated code');
      expect(output, isNot(contains('wrapAlways')),
          reason: 'wrapAlways must not appear in generated code');
    }
  });
}
