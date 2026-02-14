// co19 Pilot Baseline (2026-02-14):
//   Pass: 7/10
//   Fail: 3/10
//     #4 FAIL: CompileError — implicit default constructor not found (new A())
//     #5 FAIL: CompilationUnitImpl cast to ClassDeclaration — top-level function reference
//     #8 FAIL: CompilationUnitImpl cast to ClassDeclaration — top-level function call
//
// Selected tests:
//   1. Additive_Expressions/allowed_characters_t01 — addition with whitespace
//   2. Additive_Expressions/syntax_t17 — assignment chaining with addition
//   3. Multiplicative_Expressions/syntax_t27 — assignment chaining with multiplication
//   4. Relational_Expressions/equivalent_t01 — operator overloading (<, >, <=, >=)
//   5. Equality/evaluation_t01 — evaluation order of ==
//   6. Logical_Boolean_Expressions/evaluation_form_and_t01 — && operator
//   7. Conditional/evaluation_t01 — ternary operator
//   8. Type_Test/definition_t02 — is dynamic
//   9. Unary_Expressions/variable_decrement_t01 — pre-decrement
//  10. Postfix_Expressions/variable_increment_t01 — post-increment

import 'package:dart_eval/dart_eval.dart';
import 'package:test/test.dart';

import '../_infrastructure/expect_plugin.dart';

Runtime _compile(String source) {
  final plugin = Co19ExpectPlugin();
  final compiler = Compiler();
  compiler.addPlugin(plugin);
  final runtime = compiler.compileWriteAndLoad({
    'co19_test': {
      'main.dart': source,
    }
  });
  plugin.configureForRuntime(runtime);
  return runtime;
}

void _run(Runtime runtime) {
  runtime.executeLib('package:co19_test/main.dart', 'main');
}

void main() {
  group('co19 Expressions pilot', () {
    // 1. Additive_Expressions/allowed_characters_t01
    test('addition with whitespace', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

main() {
  int i = 0;
  i = i + 1;
  i = i + 1;
  i = i + 1;
  Expect.equals(3, i);
}
''');
      _run(rt);
    });

    // 2. Additive_Expressions/syntax_t17
    test('assignment chaining with addition', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

main() {
  var foo, bar;
  bar = (foo = 1 + 2);
  Expect.equals(3, foo);
  Expect.equals(3, bar);
}
''');
      _run(rt);
    });

    // 3. Multiplicative_Expressions/syntax_t27
    test('assignment chaining with multiplication', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

main() {
  var foo, bar;
  bar = (foo = 1 * 2);
  Expect.equals(2, foo);
  Expect.equals(2, bar);
}
''');
      _run(rt);
    });

    // 4. Relational_Expressions/equivalent_t01
    test('operator overloading for relational expressions', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

var logStr = "";

class A {
  operator <(var v) {
    logStr = "\${logStr}<";
    return true;
  }
  operator >(var v) {
    logStr = "\${logStr}>";
    return true;
  }
  operator <=(var v) {
    logStr = "\${logStr}<=";
    return true;
  }
  operator >=(var v) {
    logStr = "\${logStr}>=";
    return true;
  }
}

main() {
  logStr = "";
  A a = new A();
  a < 1;
  a > 1;
  a <= 1;
  a >= 1;
  Expect.equals("<><=>=", logStr);
}
''');
      _run(rt);
    });

    // 5. Equality/evaluation_t01
    test('equality evaluation order', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

var log = '';

foo(p) => log = '\${log}\${p}';

main() {
  foo(1) == foo(2);
  Expect.equals('12', log);
}
''');
      _run(rt);
    });

    // 6. Logical_Boolean_Expressions/evaluation_form_and_t01
    test('logical AND operator', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

main() {
  Expect.isTrue(true && true);
  Expect.isFalse(true && false);
  Expect.isFalse(false && true);
  Expect.isFalse(false && false);
}
''');
      _run(rt);
    });

    // 7. Conditional/evaluation_t01
    test('conditional (ternary) operator', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

main() {
  Expect.equals(1, true ? 1 : 2);
  Expect.equals(2, false ? 1: 2);

  Expect.equals("yes", (2 > 1) ? "yes" : "no");
  Expect.equals("no", (2 <= -2) ? "yes" : "no");
  Expect.equals("yes", (identical(0, 0)) ? "yes" : "no");
}
''');
      _run(rt);
    });

    // 8. Type_Test/definition_t02
    test('is dynamic type test', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

class C {}

f(C y) {
  C x = y;
  Expect.isTrue(x is dynamic);
}

main() {
  f(new C());
}
''');
      _run(rt);
    });

    // 9. Unary_Expressions/variable_decrement_t01
    test('pre-decrement operator', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

main() {
  var v1 = 1;
  var v2 = 1;
  var r1 = --v1;
  var r2 = (v2 -= 1);
  Expect.equals(v1, v2);
  Expect.equals(r1, r2);
}
''');
      _run(rt);
    });

    // 10. Postfix_Expressions/variable_increment_t01
    test('post-increment operator', () {
      final rt = _compile('''
import 'package:co19_expect/expect.dart';

void test(var n) {
  var v = n;
  var r = v++;
  Expect.equals(r, n);
  Expect.equals(v, (n + 1));
}

main() {
  test(0);
  test(-1);
  test(1);
  test(1000000);
  test(-1000000);
}
''');
      _run(rt);
    });
  });
}
