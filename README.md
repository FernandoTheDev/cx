<p align="center">
  <img src="assets/logo.png" width="300" alt="cx_logo"/>
</p>

# The Cx Programming Language

**Cx** is a pragmatic systems programming language designed to write C code with modern ergonomics, zero-cost abstractions, and complete transparency.

Instead of compiling to opaque machine code or complex IR, Cx transpiles to clean, highly readable **C99**. You get the safety and expressiveness of modern languages, while retaining the universal portability, tooling, and performance of the C ecosystem.

## Core Philosophy

1. **Zero-Cost Abstractions:** Generics are resolved via monomorphization. No `void*`, no runtime type erasure, no hidden allocations.
2. **Explicit over Implicit:** `==` compares pointers (pure C semantics). `===` compares string content. You are always in control.
3. **Transparent Output:** The generated C code is meant to be read, debugged, and manually inspected if necessary.
4. **Seamless C Interop:** Use any C library natively. Cross-compile to any platform supported by a C compiler (e.g., `CC=x86_64-w64-mingw32-gcc cx main.cx`).

## Key Features

- **Generics & Monomorphization:** Write containers and algorithms once, instantiate for any type with zero runtime overhead.
- **Error Unions (`T!E`):** Typed success/error returns that force explicit handling, eliminating silent failures.
- **Struct Methods & Overloading:** Group behavior with data. The compiler automatically resolves `.` vs `->` and handles method overloading.
- **`defer` Statements:** Guaranteed, LIFO-ordered cleanup at every exit point of a function, preventing resource leaks.
- **Native Modules:** A simple `import` system. No manual `.h`/`.c` splits, no include guards, no duplicated prototypes.
- **Compile-time Reflection:** Inspect types at compile-time with built-ins like `__is(T, U)` and `__type(T)`.
- **Low-Level Control:** Full support for `volatile`, `restrict`, `_Atomic`, and inline assembly (`__raw`).

## A Quick Look

See how Cx eliminates boilerplate while generating standard, optimized C99:

```c
include <stdlib.h> // import std.lib; // from Cx Stdlib
include <stdio.h> // import std.io;   // from Cx Stdlib

enum MathError { DivByZero }

struct Calculator {
    // Error Union: forces the caller to handle the error
    int!MathError divide(int a, int b) {
        if b == 0 return MathError.DivByZero;
        return a / b;
    }
}

int main() {
    Calculator calc;
    defer printf("Cleanup done.\n"); // Guaranteed to run at the end

    int!MathError result = calc.divide(10, 2);
    
    if !result.valid {
        printf("Error: %d\n", result.error);
        return 1;
    }
    
    printf("Result: %d\n", result.ok);
    return 0;
}
```

## Tooling & Ecosystem

- **Fast Compilation:** Powered by the D programming language frontend, compiling to C in milliseconds.
- **Built-in Updater:** Keep the compiler up to date with a simple `cx update`.
- **Rich Standard Library:** Includes `std.array`, `std.stack`, `std.io`, and more, all built with Cx generics.

## Cx vs C: The Boilerplate Reduction

| Feature | Traditional C | Cx |
| :--- | :--- | :--- |
| **Generic Container** | Manual copy-paste or unsafe `void*` | `struct Box<T>` (Monomorphized) |
| **Error Handling** | Manual `struct` with `valid` flag + unions | `int!Error` (Compiler-generated) |
| **Resource Cleanup** | Repeated `free()` or `goto` cleanup blocks | `defer free(ptr);` (LIFO injection) |
| **String Equality** | `strcmp(a, b) == 0` | `a === b` |
| **Module Sharing** | `.h` + `.c` + Include guards + Prototypes | Single `.cx` file + `import module` |

## Status

Cx is in active, early-stage development. The compiler is stable for Linux environments and successfully passes a comprehensive test suite (70+ examples including VMs, HashMaps, and LLVM wrappers).

**Next Milestone:** Full self-hosting (rewriting the Cx compiler in Cx).

---
*For more detailed examples, explore the [`examples/`](examples) directory or read the [Installation Guide](INSTALL.md).*
