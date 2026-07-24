# The CX Programming Language Specs

**Cx** is a pragmatic systems programming language that transpiles to clean, highly readable **C99**. It provides modern ergonomics, zero-cost abstractions, and complete transparency while retaining the universal portability of the C ecosystem.

---

## 1. Lexical Elements

### 1.1. Comments
```cx
// Single line comment
/* Multi-line 
   comment */
```

### 1.2. Keywords
```text
__is       __type     __typename alias      break      case
const      continue   default    defer      else       enum
fn         for        foreach    goto       if         import
include    inline     null       overload   register   restrict
return     static     struct     switch     true       false
union      volatile   while      _Atomic
```

### 1.3. Operators & Symbols
*   **Arithmetic:** `+`, `-`, `*`, `/`, `%`, `++`, `--`
*   **Assignment:** `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`
*   **Logical:** `&&`, `||`, `!`
*   **Bitwise:** `&`, `|`, `^`, `~`, `<<`, `>>`
*   **Comparison:** 
    *   `==` (Pointer/Value equality - pure C semantics)
    *   `===` (Deep equality: strings use `strcmp`, structs use `<type>_cmp`)
    *   `!=`, `<`, `>`, `<=`, `>=`
*   **Navigation & Null:** `?.` (Safe navigation), `??` (Null coalescing)
*   **Ranges & Slices:** `..` (Range), `...` (Ellipsis/Copy)
*   **Misc:** `=>` (Arrow/Expression body), `?` (Ternary), `@`, `#`

---

## 2. Types

### 2.1. Primitives & Built-ins
Cx provides a rich set of built-in types that map directly and transparently to standard C99 types.

**Standard Integers:**
*   `byte`, `char` → `char`
*   `ubyte` → `unsigned char`
*   `short`, `ushort` → `short`, `unsigned short`
*   `int`, `uint` → `int`, `unsigned int`
*   `long`, `c_long`, `ulong`, `c_ulong` → `long`, `unsigned long`
*   `size_t` → `size_t`

**Fixed-Width Integers** (require standard headers, mapped to `<stdint.h>` equivalents):
*   `i8` / `int8_t`, `u8` / `uint8_t`
*   `i16` / `int16_t`, `u16` / `uint16_t`
*   `i32` / `int32_t`, `u32` / `uint32_t`
*   `i64` / `int64_t`, `u64` / `uint64_t`

**Floating-Point:**
*   `float`, `f32` → `float`
*   `double`, `f64` → `double`

**Boolean & Void:**
*   `bool`, `i1` → `bool` (or `int` in pre-C23)
*   `void`, `i0` → `void`

**Special Built-ins:**
*   `cstr` → `char*` (Null-terminated C string)

**Type Qualifiers:**
*   `const`, `volatile`, `_Atomic`, `restrict` (Passed through directly to the generated C code).

### 2.2. Pointers & Arrays
```cx
int* ptr;             // Pointer
int[3] arr;           // Fixed-size array (stack allocated)
int[] arr = [10, 20];
```

### 2.3. Slices
Slices provide safe, bounds-aware views or copies over arrays.
```cx
int[5] arr = [10, 20, 30, 40, 50];
Slice<int> view = arr[1..3];       // View (start..end)
Slice<int> copy = arr[1...3];      // Copy (start...end, heap allocated)
```

### 2.4. Generics
Generics are resolved via **monomorphization** at compile-time (zero-cost, no `void*` erasure).
```cx
struct Box<T> {
    T value;
    bool hasValue;
}

struct HashMap<K, V> { ... }
```

### 2.5. Error Unions (`T!E`)
Typed success/error returns that force explicit handling, eliminating silent failures.
```cx
enum MathError { DivByZero }

int!MathError divide(int a, int b) {
    if b == 0 return MathError.DivByZero;
    return a / b;
}

// Usage:
int!MathError result = divide(10, 0);
if !result.valid {
    printf("Error: %s\n", result.error.id);
} else {
    printf("Result: %d\n", result.ok);
}
```

---

## 3. Variables & Modifiers

### 3.1. Declaration & Initialization
```cx
int x = 10;
int x, y = 10, 20;
char* name = "Cx";
```

### 3.2. Modifiers
```cx
const int MAX = 100;
volatile u32 hardware_reg;
_Atomic u32 counter;
u32* restrict ptr;
static int global_var; // TODO
```

---

## 4. Control Flow

### 4.1. Conditionals
Parentheses are optional for single statements.
```cx
if x == y return Error.Equals;

if (a > b) {
    // ...
} else if (a == b) {
    // ...
} else {
    // ...
}
```

### 4.2. Loops
```cx
// While
while i < 10 { i++; }

// For
for (int i = 0; i < 10; i++) { ... }
for (;;) { break; } // Infinite loop

// Foreach (Iterators)
foreach k, n; arr {
    printf("Index: %d, Value: %d\n", k, n);
}
foreach &n; arr { // Reference iteration
    n = n * 2;
}
```

### 4.3. Switch
```cx
switch x {
    case Foo.Bar:
        printf("Bar\n");
        break;
    default:
        printf("Other\n");
        break;
}
```

### 4.4. Goto & Labels
```cx
goto end;
start:
    return 67;
end:
    return 0;
```

### 4.5. Defer
Guaranteed, LIFO-ordered cleanup at every exit point of a scope.
```cx
int main() {
    defer printf("Runs last\n");
    defer printf("Runs first\n");
    return 0;
}
```

---

## 5. Functions

### 5.1. Signatures & Expression Bodies
```cx
int sum(int x, int y) {
    return x + y;
}

// Expression body
int sum(int x, int y) => x + y;
```

### 5.2. Overloading
Use the `overload` keyword. The compiler mangles the name based on argument types.
```cx
void print(int i) overload => printf("%d\n", i);
void print(float f) overload => printf("%f\n", f);
void print(char* s) overload => printf("%s\n", s);
```

### 5.3. Struct Methods & `self`
Methods are defined inside structs. The `self` keyword refers to the instance.
```cx
struct Calculator {
    int value;
    
    // Instance method
    void add(int x) {
        self.value = self.value + x;
    }
    
    // Static method
    static Calculator new() => .{0};
}
```

---

## 6. User-Defined Types

### 6.1. Structs
```cx
struct Point {
    float x;
    float y;
}

// Initialization
Point p = .{10.0, 20.0};
Point p2 = .{ x = 10.0, y = 20.0 };
Point p3 = Point.new(); // or: .new(); // If static constructor exists
```

### 6.2. Enums
Enums automatically generate an `_ids` array for string representation.
```cx
enum Color { Red, Green, Blue }

Color c = Color.Red;
if c == Color.Green { ... }
printf("%s\n", c.id); // Prints "Red" (compiles to Color_ids[c])
```

### 6.3. Unions
```cx
union Value {
    int i;
    float f;
    char* s;
}

// unions inside structs
struct Foo {
    union bar {
        int i;
        float f;
    }
}
```

### 6.4. Aliases
```cx
alias Fun = int(int, int);
alias Result = int!Error;
```

---

## 7. Modules & C Interop

### 7.1. Imports & Includes
```cx
// Cx Standard Library / Modules
import std.io;
import std.array;

// Raw C Headers
include <stdio.h>
include <stdlib.h>
```

### 7.2. Raw C / Inline Assembly
Escape hatch to inject raw C code or inline assembly directly into the transpiled output.
```cx
__raw {
    #include <immintrin.h>
}

u32 fast_add(u32 a, u32 b) {
    u32 result;
    __raw {
        __asm__ __volatile__(
            "addl %%ebx, %%eax"
            : "=a" (result)
            : "a" (a), "b" (b)
        );
    }
    return result;
}
```

---

## 8. Compile-Time Reflection

Inspect types at compile-time. These evaluate to constants during transpilation.

```cx
// Check if two types are exactly the same
if __is(T, int) { ... }

// Get the string representation of a type
printf("%s\n", __type(Foo<T>)); 

// Get the string representation of an expression's type
printf("%s\n", __typename(my_var));
```

---

## 9. Semantic Rules & "Cx vs C"

1. **Explicit over Implicit:** `==` compares pointers/values (pure C semantics). `===` compares string content (`strcmp`) or struct deep equality.
2. **Zero-Cost Abstractions:** Generics and Error Unions are resolved at compile-time into standard C structs and functions. No hidden allocations.
3. **Transparent Output:** The generated C code is meant to be read, debugged, and manually inspected.
4. **Memory Management:** Cx relies on explicit allocation (`malloc`/`free`) but provides `defer` to guarantee cleanup, preventing resource leaks without a garbage collector.