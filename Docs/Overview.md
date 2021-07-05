# Language overview

The *mvs-calculus* is a statically typed, expression-oriented language.
A program is a sequence of structure declarations, followed by a single expression.

```mvs
struct Pair {
  var fs: Int; var sn: Int
} in
let p = Pair(4, 2) in
p.fs
```

By default, a program prints the value computed by its expression, as long as it is an integer or a floating-point number.
For instance, the above program prints the value `4` when executed.

## Variables and constants

Variables are declared with the keyword `var`, followed by a name.
The declaration creates a binding that is assigned to some initial value, and that is visible within the scope of the declaration.
Constants are declared similarly, with the keyword `let`.

```mvs
let num: Int = 10 in
num + 1 // Prints "11"
```

The above program declares a constant `num` of type `Int`, which is assigned to the value `10` in the expression `num + 1`.

There are three built-in data types in the mvs-calculus: `Int` for signed integer values, `Float` for floating-point values, and a generic type `[T]` for arrays of type `T`.
Numeric values (i.e., `Int` and `Float`) support all common arithmetic operations and comparisons.
In addition, the language also features two kinds of user-defined types: functions and structures (see below).

Type annotations may be elided when the type of the variable can be inferred from the initial expression.

```mvs
let num = 10.0 in
num + 1.0 // Prints "11.0"
```

## Structures and arrays

A structure is a heterogeneous data aggregate, composed of zero or more fields.
Each field is typed explicitly and associated with a mutability qualifier (`let` or `var`) that denotes whether it is constant or mutable.
Fields can be of any type, but type definitions cannot be mutually recursive.
Hence, all values have a finite representation.

Instances of a structure are created using the structure's name, followed by a sequence of expressions denoting the values of each of its fields (in the order of definition).
The value of a field is accessed using a dot followed by the name of the field.

```mvs
struct Pair {
  var fs: Int; var sn: Int
} in
let p = Pair(4, 2) in
p.fs // Prints "4"
```

An array is a dynamically sized list of homogeneous elements.
Instances are expressed as bracketed lists of expressions, which are then accessed via a 0-based integer index.

```mvs
let nums: [Int] = [1, 2, 3] in
nums[0] // Prints "1"
```

## Assignments

Variables, fields, and array elements can be assigned to other values after their initialization.

```mvs
var num = 10 in
num = num + 1 in
num // Prints "11"
```

All types have value semantics.
Thus, all values form disjoint topological trees, rooted at variables or constants.
Further, the operational semantics of assignment is always to copy the right operand and never create aliases.

```mvs
struct Pair { ... } in
var p = Pair(4, 2) in
var q = p in
q.sn = 8 in
p.sn // Prints "4", not "8"
```

Immutability applies transitively.
All fields of a data aggregate assigned to a constant are also treated as immutable by the type system, regardless of their declaration.

```mvs
struct Pair {
  var fs: Int; var sn: Int
} in
let p = Pair(4, 2) in
p.sn = 8 in // <- type error
p
```

Likewise, all elements of an array are constant if the array itself is assigned to a constant.

```mvs
struct Pair { ... } in
let a = [Pair(4, 2)] in
a[0].sn = 8 in // <- type error
a
```

## Functions

There exist two kinds of functions: named and anonymous functions.
Named functions are declared with the keyword `fun`.
They are called using their name, followed by a sequence of expressions denoting the arguments.

```mvs
fun decr(n: Int) -> Int {
  n - 1
} in
decr(10) // Prints "9"
```

Named functions can refer to their own name recursively.
However, they are not forward-declared.
Thus, they can only refer to functions declared beforehand.

```mvs
fun decr(n: Int) -> Int { ... } in
fun fact(n: Int) -> Int {
  if n > 1
    ? n * fact(decr(n))
    ! 1
} in
fact(6) // Prints "720"
```

Anonymous functions are expressed as function literals.

```mvs
((n: Int) -> Int { n + 1 })(10) // Prints "11"
```

### Higher-order functions

All functions (named or otherwise) are first-class values that can be assigned to variables, stored in fields, or passed as arguments.
Infix operators (e.g., `+` in `10 + 1`) are first-class citizen values as well.

```mvs
let ops: [(Int, Int) -> Int] = [+, -] in
ops[0](10, 1) // Prints "11"
```

Variables that occur free in a function's body are captured from the function's declaration environment, creating a closure.

```mvs
fun add(a: Int) -> (Int) -> Int {
  (b: Int) -> Int { a + b }
} in
let incr = add(1) in
incr(10) // Prints "11"
```

> Note: a current limitation of the compiler prevents named functions from capturing local symbols.

Closures are independent and immutable, to preserve value semantics, meaning that captured values are copied, and cannot be mutated within the function.


### Inout parameters

To implement part-wise in-place mutation across function boundaries, values of parameters annotated inout can be mutated by the callee.
Operationally, an inout argument is copied when the function is called and copied back to its original location when the function returns.

```mvs
struct Pair { ... } in
struct U {} in
fun swap(x: inout Int, y: inout Int) -> U {
  let tmp = x in
  x = y in
  y = tmp in U()
} in
var p = Pair(4, 2) in
_ = swap(&p.fs, &p.sn)
in p.fs // Prints "2"
```

`inout` extends to multiple arguments, with one important restriction: overlapping mutations are prohibited to prevent any writeback from being discarded.

```mvs
struct U {} in
fun swap(x: inout Int, y: inout Int) -> U {
  let tmp = x in
  x = y in
  y = tmp in U()
} in
var num = 10 in
swap(&num, &num) // <- type error
```

### Synthesized equality operators

The compiler synthesizes an equality function for all types, including user-defined ones, provided as an operator `==`.
A negated version of this function is provided as an operator `!=`.

```mvs
struct Pair { ... } in
let a = [Pair(4, 2)] in
let b = [Pair(4, 2)] in
a == b // Prints 1
```

Two functions compare equal only if they are copies of the same binding.

```mvs
let f = () -> Int { 1 } in
let g = f in
f == g // Prints 1
```

### Built-in functions

The language exposes a built-in function `uptime` that returns a floating-point number denoting the number of nanoseconds since boot.
