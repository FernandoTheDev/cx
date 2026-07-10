<p align="center">
  <img src="assets/logo.png" width="300" alt="cx_logo"/>
</p>

# The Cx Programming Language

The `Cx` programming language was created for a single reason: to write C code with more syntactic sugar and improvements. `Cx` offers a range of features, some of which are:

- Generics with monomorphization;
- Structs with methods;
- Functions, structs, enums, and unions can be declared and used anywhere in your code;
- Native module system;
- Native use of C libraries in `Cx`;
- Static methods on structs;
- Defers;
- Error Union/Result;
- Syntax changes in certain cases to keep greater readability;
- Single use of `.` to access fields, resolution is handled by the `cx` compiler;

Among other features.

`Cx` compiles directly to `C`, specifically to `C99` to maintain support and compatibility with older systems. The generated `C` code is completely readable and organized. What the compiler automatically does:

- Prototype generation for functions, unions, enums, and structs;
- Removal of syntactic sugar such as `defer`, inserting code at every exit point of the function;

## Cx vs C: side-by-side examples

### 1. Structs with methods (no more prefix repetition)

In C, every function "belonging" to a type needs a manual prefix and has to repeat the pointer as its first parameter:

```c
// C
#include <stdlib.h>

typedef struct Arena Arena;
struct Arena {
    char* data;
    unsigned int size;
    unsigned int cap;
};

Arena arena_new(unsigned int cap);
void* arena_alloc(Arena* self, unsigned int size);
void arena_delete(Arena* self);

Arena arena_new(unsigned int cap) {
    char* data = malloc(cap);
    Arena a = {data, 0, cap};
    return a;
}

void* arena_alloc(Arena* self, unsigned int size) {
    char* data = self->data + self->size;
    self->size += size;
    return (void*) data;
}

int main() {
    Arena arena = arena_new(64);
    void* ptr = arena_alloc(&arena, 4);
    arena_delete(&arena);
    return 0;
}
```

In Cx, `self` disappears from the signature (but stays explicit in the body), and the namespace comes for free:

```c
// Cx
include <stdlib.h>

struct Arena {
    char* data;
    u32 size;
    u32 cap;

    static Arena new(u32 cap) {
        char* data = malloc(cap);
        return (Arena) {data, 0, cap};
    }

    void* alloc(u32 size) {
        char* data = self.data + self.size;
        self.size += size;
        return (void*) data;
    }

    void delete() {
        free(self.data);
    }
}

int main() {
    Arena arena = Arena.new(64);
    void* ptr = arena.alloc(4);
    arena.delete();
    return 0;
}
```

`self.field` becomes `self->field` automatically in the generated C — `.` is always used in Cx, and the compiler decides on its own whether to emit `.` or `->`.

---

### 2. Defer: guaranteed cleanup at every exit point

In C, manual cleanup has to be repeated (or handled with `goto`) at every `return`:

```c
// C
int process(FILE* f) {
    if (!f) return 1;
    // ... work ...
    if (some_error) {
        fclose(f); // easy to forget this
        return 1;
    }
    fclose(f);
    return 0;
}
```

In Cx, `defer` guarantees execution at any `return` in the function, in reverse order of declaration (LIFO):

```c
// Cx
int process(FILE* f) {
    if !f { return 1; }
    defer fclose(f);
    // ... work ...
    if some_error {
        return 1; // fclose(f) is already injected here automatically
    }
    return 0;
}
```

The compiler injects the call before every `return` in the scope — no runtime cost, no stack, no function pointer. It's just repeated text in the generated C.

---

### 3. String comparison: no hidden ambiguity

In C, `==` on `char*` compares the pointer, not the content — a classic and silent mistake:

```c
// C
char* a = "Fernando";
char* b = get_name();
if (a == b) { ... }        // compares ADDRESS, almost always wrong
if (strcmp(a, b) == 0) {}  // correct form, but easy to forget
```

In Cx, `==` remains pure, honest C (pointer comparison). `===` is the explicit, opt-in way to compare content:

```c
// Cx
char* a = "Fernando";
char* b = get_name();
if a == b { ... }   // still compares the pointer, semantics of C unchanged
if a === b { ... }  // becomes strcmp(a, b) == 0 in the generated C (only between two char*)
```

No behavior changes "under the hood" without you asking for it.

---

### 4. Error Union: no manual tagged union

In C, representing a typed "success or error" requires writing the union by hand:

```c
// C
typedef enum { ERR_EQUALS } Error;
typedef struct {
    int valid;
    union { int ok; Error error; } val;
} IntError;

IntError sum(int x, int y) {
    IntError r;
    if (x == y) {
        r.valid = 0;
        r.val.error = ERR_EQUALS;
        return r;
    }
    r.valid = 1;
    r.val.ok = x + y;
    return r;
}
```

In Cx, `T!E` generates that struct automatically, and `return` decides on its own whether it's a success or an error:

```c
// Cx
enum Error { Equals }

int!Error sum(int x, int y) {
    if x == y {
        return Error.Equals; // becomes { .valid = false, .val.error = ... }
    }
    return x + y;             // becomes { .valid = true, .val.ok = ... }
}

int main() {
    int!Error r = sum(10, 9);
    if !r.valid {
        printf("error: %d\n", r.error);
        return 1;
    }
    printf("ok: %d\n", r.ok);
    return 0;
}
```

---

### 5. Generics: zero-overhead via monomorphization

In C, a type-safe generic container requires manually copying the struct and functions for each type, or giving up type safety with `void*`:

```c
// C - copied by hand for each type
typedef struct { int value; int hasValue; } Box_int;
Box_int Box_int_of(int val) { Box_int b; b.value = val; b.hasValue = 1; return b; }

typedef struct { float value; int hasValue; } Box_float;
Box_float Box_float_of(float val) { Box_float b; b.value = val; b.hasValue = 1; return b; }
// ... repeat for every type used
```

In Cx, you write it once, and the compiler generates each instantiation on demand, without `void*` and without heavy type analysis:

```c
// Cx
struct Box<T> {
    T value;
    bool hasValue;

    static Box<T> of(T val) {
        return (Box<T>) {val, true};
    }

    T unwrap() {
        return self.value;
    }
}

int main() {
    Box<int> a = Box<int>.of(67);      // generates Box_int
    Box<float> b = Box<float>.of(3.5F); // generates Box_float
    return 0;
}
```

---

### 6. Array vs struct declaration: `[]` and `{}` without ambiguity

In C, `{}` is used to initialize both arrays and structs — you only know which one by the type declared on the left:

```c
// C
struct Point p = {10, 20};
int nums[3] = {1, 2, 3};
```

In Cx, `{}` is reserved for structs and `[]` for arrays, keeping the reading more explicit:

```c
// Cx
struct Point p = {10, 20};
int[3] nums = [1, 2, 3]; // {1, 2, 3} is also supported
```

---

### 7. Native modules: no headers, no manual prototypes

In C, sharing code between files requires an `.h`/`.c` pair, include guards, and duplicated prototypes:

```c
// utils.h
#ifndef UTILS_H
#define UTILS_H
int sum(int a, int b);
#endif

// utils.c
#include "utils.h"
int sum(int a, int b) { return a + b; }

// main.c
#include "utils.h"
int main() { return sum(1, 2); }
```

In Cx, a single file per module, imported by logical name — no header, no manual prototype, no include guard:

```c
// utils.cx
int sum(int a, int b) { return a + b; }

// main.cx
import utils;
int main() { return sum(1, 2); }
```

The compiler resolves the dependency graph, detects and ignores cycles automatically, and generates the prototypes in the final C by itself.

## Status

Cx is in an early stage of development, which means many features are still to be added to the language, as well as bug fixes. The compiler build has only been tested on Linux.
