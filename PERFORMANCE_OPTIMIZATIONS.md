# Performance Optimizations for dart_eval

This document describes the performance optimizations implemented in dart_eval.

## Top 3 Performance Issues Identified

### Issue 1: Collection Boxing with Spread Operators
**Location**: `lib/src/eval/runtime/ops/primitives.dart` (lines 280-351)

**Problem**: The `BoxList`, `BoxMap`, and `BoxSet` operations used spread operators (`...`) to create typed collections:
```dart
runtime.frame[reg] = $List.wrap(<$Value>[...(runtime.frame[reg] as List)]);
```

**Impact**: Every collection boxing operation created a full copy using spread syntax, which involves:
- Creating a new typed list literal
- Iterating through all elements
- Copying each element

**Solution**:
1. Check if the source collection is already properly typed
2. Use `List.of()`, `Map.of()`, `Set.of()` constructors which can be more efficient
3. Avoid unnecessary copies when the collection is already the correct type

```dart
if (source is List<$Value>) {
  frame[reg] = $List.wrap(source);
} else {
  frame[reg] = $List.wrap(List<$Value>.of(source as List<dynamic>));
}
```

### Issue 2: Fixed 255-Element Stack Frame Allocation
**Location**: `lib/src/eval/runtime/ops/flow.dart` (line 45)

**Problem**: Every function call allocated a fixed-size frame of 255 elements:
```dart
final frame = List<Object?>.filled(255, null);
```

**Impact**:
- Memory waste for simple functions that only use a few variables
- Unnecessary memory allocation overhead on every function call

**Solution**:
1. Calculate initial capacity based on argument count plus a small buffer
2. Use growable lists that can expand if needed
3. Unroll small argument copies for common cases (0-3 args)
4. Use `const []` for empty args to avoid allocating new empty lists

```dart
final initialCapacity = argsLen + 32;
final frame = List<Object?>.filled(
  initialCapacity > 255 ? 255 : initialCapacity,
  null,
  growable: true
);
```

### Issue 3: Method/Property Lookup Without Caching
**Location**: `lib/src/eval/runtime/ops/objects.dart` (lines 19-36, 252-289)

**Problem**: Every method invocation and property access walked the superclass chain:
```dart
while (true) {
  if (object is $InstanceImpl) {
    final offset = methods[method0];
    if (offset == null) {
      object = object.evalSuperclass;
      continue;
    }
    // ...
  }
}
```

**Impact**:
- Repeated type checks on every lookup
- Multiple property accesses on runtime object
- No caching of resolved methods

**Solution**:
1. Add fast paths for primitive type equality checks
2. Cache local variables to avoid repeated property access
3. Restructure property lookup to try getters first (more common case)
4. Cache `runtime._prOffset` before modification

```dart
// Fast path for primitives
if (v1 is! $Value) {
  runtime.returnValue = v1 == v2;
  return;
}

// Cache prOffset before modifying
final returnOffset = runtime._prOffset;
runtime.callStack.add(returnOffset);
```

## Additional Optimizations

### Local Variable Caching
Throughout the codebase, repeated access to `runtime.frame`, `runtime.stack`, and other properties has been replaced with local variable caching:

```dart
// Before
runtime.frame[runtime.frameOffset++] = value;
runtime.frame[_reg] = value;

// After
final frame = runtime.frame;
frame[runtime.frameOffset++] = value;
frame[_reg] = value;
```

### Constant Empty Collections
Instead of creating new empty lists with `[]`, use `const []`:

```dart
// Before
runtime.args = [];

// After
runtime.args = const [];
```

### Function Pointer Creation Optimization
**Location**: `lib/src/eval/runtime/ops/flow.dart` (PushFunctionPtr)

- Cache constant pool lookups
- Use `List.generate` with `growable: false` for fixed-size type lists
- Avoid repeated array indexing

## Benchmarks

The following benchmarks were created to measure performance:

1. **Deep function call stack** - Tests frame allocation with recursive functions
2. **Collection boxing operations** - Tests List/Map/Set boxing performance
3. **Method calls with inheritance chain** - Tests method lookup in deep inheritance
4. **Property access patterns** - Tests property getter performance
5. **Arithmetic operations** - Baseline for simple operations
6. **Large list operations** - Tests list manipulation at scale

See `test/performance_benchmark_test.dart` for the benchmark implementations.

## Expected Improvements

| Optimization | Expected Impact |
|--------------|-----------------|
| Collection boxing | 10-30% faster for collection-heavy code |
| Frame allocation | 5-15% memory reduction, faster function calls |
| Method lookup caching | 5-20% faster for OOP-heavy code |
| Local variable caching | 2-5% general improvement |

## Future Optimization Opportunities

1. **Method Resolution Cache**: Add a per-class cache for resolved method offsets
2. **Opcode Fusion**: Combine common operation sequences into single opcodes
3. **Type Specialization**: Create specialized opcodes for common type combinations
4. **Frame Pool**: Reuse frame objects instead of allocating new ones
5. **Inline Caching**: Cache method dispatch results at call sites
