import 'package:eval_annotation/eval_annotation.dart';

@Bind()
class TestSdk {
  final String greeting;
  TestSdk({required this.greeting});

  /// extern: bindgen should only generate compile-time declaration,
  /// not runtime binding
  @Bind(extern: true)
  static TestSdk get current => throw StateError('unavailable');

  /// Normal member: bindgen should generate both declaration and runtime binding
  static String hello() => 'hello';
}
