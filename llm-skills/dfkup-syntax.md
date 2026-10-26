# DFkup Language Reference

DFkup is a fast, Nim-embedded scripting language. Syntax is heavily inspired by Nim.

## Literals & Types

```
42         # integer
3.14       # float
"hello"    # string (double-quoted, supports \n \r \t \" \\ \0 escapes)
'hello'    # string (single-quoted, no escapes)
`cmd`      # backtick string (no escapes)
true       # boolean
false      # boolean
nil        # null value
```

## Variables

```
var x = 42                 # mutable variable
let name = "world"         # immutable variable
const max = 100            # compile-time constant
var x: int = 10            # typed declaration
var a, b: string           # multiple variables, same type
```

## Functions

```
fn add(a, b): int =        # named function with return type
  result = a + b

fn greet(name: string) =   # typed parameters
  echo "Hello " & name

fn(x: int): int = x * x    # anonymous function
```

Return type is optional. Use `result` as the implicit return variable, or `return expr`.

## Control Flow

```
if condition:
  doThing()

if a > b:
  echo "a > b"
elif a == b:
  echo "equal"
else:
  echo "a < b"

while x > 0:
  x = x - 1

for x in items(data):
  echo x

break
continue
yield value
```

## Operators

| Category | Operators |
|----------|-----------|
| Arithmetic | `+` `-` `*` `/` `%` `^` |
| Comparison | `==` `!=` `<` `>` `<=` `>=` |
| Logical | `and` `&&` `or` `\|\|` |
| String | `&` (concat) |
| Assignment | `=` |

## Arrays

```
[1, 2, 3]                  # array literal
let a = [1, 2, 3]          # array[string], array[int], array[float], array[bool]
data[0]                    # index access
```

## Generic types

Arrays and custom types take element types in brackets. Nesting
associates to the right: `array[array[int]]` is an array of
`array[int]`.

```
var scores: array[int] = [85, 92, 78]
var matrix: array[array[int]] = [[1, 2], [3, 4]]
var names: array[string] = ["a", "b"]

fn first(a: array[int]): int =
  return a[0]

fn doubled(): array[int] =
  return [1, 2]
```

## Generic functions

Type parameters go in brackets after the name, with an optional
constraint after a colon. Constraints are checked at the call site;
missing inference is an error.

```
func hello[T: string](name: T): T =
  return name

func first[T: array[string]](xs: T): string =
  return xs[0]

func pair[T: string, X: int](a: T, b: X): X =
  return b
```

## Objects

```
{a: 1, b: "hello"}         # object literal (JSON-like)
obj.field                  # dot access
```

## Enums

An enum gives a fixed set of named values a name. A field is always reached
through its enum, so two enums can share a field name without colliding.

```
type Fruits = enum
  apple = "Apple"          # explicit value
  strawberry               # a bare field stands for itself

type BadFruits = enum
  apple

echo Fruits.apple          # Apple
echo Fruits.strawberry     # strawberry
echo BadFruits.apple       # apple
echo apple                 # error: undeclared identifier 'apple'
```

`==` and `!=` compare fields of the same enum. Each enum is its own type, so
comparing across two different enums is a compile-time `type mismatch`.

```
echo Fruits.apple == Fruits.apple        # true
echo Fruits.apple != Fruits.strawberry   # true
echo Fruits.apple == BadFruits.apple     # error: type mismatch
```

Enums work as parameter and variable types:

```
func label(f: Fruits): string =
  if f == Fruits.apple: return "apple-ish"
  return "other"

var picked: Fruits = Fruits.strawberry
echo label(picked)         # other
```

`$` renders an enum as its value, which is how one reaches a function that
takes a string:

```
echo $Fruits.apple                    # Apple
echo "picked: " & $picked             # picked: strawberry
```

Several declarations may share one `type` keyword, each on its own line:

```
type
  Veg = enum
    carrot = "Carrot"
    leek
  Color = enum
    red
    green = "Green"
```

Names follow the same rule as the rest of dfkup: the first letter is
significant and the rest is case-insensitive. `Fruits.strawBERRY` resolves;
`Fruits.Apple` and `fruits.apple` do not.

## Iterators

```
iterator range*(min: int, max: int): int  # built-in range iterator

for i in range(0, 10):
  echo i

for item in items(data):   # items() for arrays, json arrays
  echo item
```

## Coroutines and Async

An `async func` is a stackful coroutine. `yield` suspends it, `resume` advances
it, and `status` reports `csCreated` / `csSuspended` / `csCompleted`.

There are three ways to drive one. Use `await` for the result, `dispatch` when
you want the coroutine itself, and `createCoro` only when you need one that has
not started yet.

```
async func counter(): int =
  yield 1
  yield 2
  return 3

# await: drive to completion, evaluate to the return value
echo await counter()      # 3

# dispatch: start it and hand back the coroutine. Arguments bind here and the
# first `yield` is spent by the dispatch, so `resume` continues from 2.
let c = dispatch(counter)
while status(c) != "csCompleted":
  echo resume(c)          # 2, then 3

# createCoro: build it unstarted, and drive it from the very first value
let d = createCoro(counter)
while status(d) != "csCompleted":
  echo resume(d)          # 1, 2, then 3
```

`await` drives a coroutine to completion and evaluates to its return value.
Every value the awaited coroutine yields is forwarded as a yield of the
awaiting coroutine, so streamed values pass straight through.

```
async func inner(): string =
  yield "Hel"
  return "lo"

async func outer(): string =
  return await inner()      # yields "Hel", evaluates to "lo"

echo await inner()          # "lo"; the "Hel" yield has no resumer at toplevel
```

Arguments belong to the call: `await f(x)` creates the coroutine and binds `x`
on its first resume, and `dispatch(f, x)` binds `x` up front. A later `resume`
on a dispatched coroutine takes no arguments.

`await` binds as tightly as a postfix operator: it takes a primary plus any
`.` / `[` chain and stops before every binary operator. So the concat applies
to the awaited result, not the other way round.

```
async func inner(): string =
  yield "Hel"
  return "lo"

fn go(): string =
  return await inner() & "!"        # (await inner()) & "!"  =>  "lo!"
  # return await inner() & "x" & "y" also works; it is left-associative
```

`then` is looser than `await`, so it attaches to the whole `await`. The operand
itself has to be a coroutine call or a coroutine value, so parens are not a way
to group a compound operand: `await (a & b)` awaits a non-coroutine.

An `async func` cannot be called directly. Naming one bare is a compile error
that names both sanctioned forms:

```
async func compute(): int =
  return 42

fn bad(): int =
  return compute()
# error: 'compute' is an async function, so it cannot be called directly:
#        use 'await compute(...)' for its result,
#        or 'dispatch(compute, ...)' for the coroutine
```

`then` chains a continuation onto the result. `await f() then p(args...)`
calls `p(awaitedResult, args...)`, and the whole expression is itself a
coroutine.

```
fn decorate(body: string): string =
  return "[" & body & "]"

async func outer(): string =
  return await plain() then decorate()
```

Coroutines nest: a coroutine may resume another coroutine, and the outer one is
correctly restored when the inner one finishes.

## Comments

```
// line comment
/* block comment */
```

## Built-in Functions: System

| Function | Signature | Description |
|----------|-----------|-------------|
| `echo` | `echo(x: string/int/float/bool/json/nil)` | Print value |
| `len` | `len(data: string/json/array): int` | Length |
| `high` | `high(data: json/array): int` | Last index |
| `inc` | `inc(x: int): int` | Increment |
| `fileExists` | `fileExists(path: string): bool` | Check file |
| `dirExists` | `dirExists(path: string): bool` | Check dir |
| `readFile` | `readFile(path: string): string` | Read file |
| `writeFile` | `writeFile(path, content: string)` | Write file |
| `copyFile` | `copyFile(src, dest: string)` | Copy file |
| `moveFile` | `moveFile(src, dest: string)` | Move file |
| `removeFile` | `removeFile(path: string)` | Delete file |
| `createDir` | `createDir(path: string)` | Create dir |
| `removeDir` | `removeDir(path: string)` | Remove dir |
| `listDir` | `listDir(path: string): json` | List dir |
| `getCurrentDir` | `getCurrentDir(): string` | CWD |
| `setCurrentDir` | `setCurrentDir(path: string)` | Change dir |
| `joinPath` | `joinPath(a, b: string): string` | Join paths |
| `parentDir` | `parentDir(path: string): string` | Parent dir |
| `expandFilename` | `expandFilename(path: string): string` | Expand path |
| `absolutePath` | `absolutePath(path: string): string` | Absolute path |
| `getEnv` | `getEnv(key: string): string` | Env var |
| `existsEnv` | `existsEnv(key: string): bool` | Check env var |
| `getAppDir` | `getAppDir(): string` | App directory |
| `getAppFilename` | `getAppFilename(): string` | App path |
| `sleep` | `sleep(ms: int)` | Sleep ms |
| `getCurrentProcessId` | `getCurrentProcessId(): int` | PID |
| `getFileSize` | `getFileSize(path: string): int` | File size |

## Built-in Functions: Coroutines

| Function | Signature | Description |
|----------|-----------|-------------|
| `createCoro` | `createCoro(f): coroutine` | Wrap an `async func` without starting it |
| `dispatch` | `dispatch(f, args...): coroutine` | Start it and return the coroutine |
| `resume` | `resume(c: coroutine, args?): any` | Advance, yields or returns |
| `status` | `status(c: coroutine): string` | `csCreated`/`csSuspended`/`csCompleted` |

## Keywords: async

| Keyword | Usage | Description |
|---------|-------|-------------|
| `async func` | `async func f(): T =` | Declare a coroutine |
| `yield` | `yield v` | Suspend with a value |
| `await` | `await f(args)` / `await coroValue` | Drive to completion |
| `then` | `await f() then p(args)` | Sequential continuation |

## Standard library

`system` is available automatically. Every other module loads on first
import — scripts that import nothing pay nothing:

```
import "std/json"
import "std/strings"
```

Available modules: `json`, `yaml`, `strings`, `sequtils`, `http`,
`cli`, `config`, `regex`, `browser`, `toml`, `uuid`, `dotenv`, `csv`,
`bson`, `colors`, `qr`, `nanoid`, `llm`, `httpclient`, `xml`, `feed`,
`ical`, `css`, `svg`, `markdown`, `strongpwd`, `twofa`, `fswatch`,
`algos`, `bench`, `date`, `locale`, `vcard`, `plist`, `fuzzy`, `diff`,
`html`, `path`. `system`, `json`, `strings`, `sequtils` and `regex`
are linked into the binary; the rest load from shards.

## Built-in Functions: JSON

`import "std/json"` first.

| Function | Signature | Description |
|----------|-----------|-------------|
| `parseJson` | `parseJson(s: string): json` | Parse JSON string |
| `dumpJson` | `dumpJson(v: json): string` | Serialize to JSON |
| `toJson` | `toJson(v: any): json` | Convert value to JSON |
| `pretty` | `pretty(v: json): string` | Pretty-print JSON |
| `keys` | `keys(obj: json): json` | Object keys array |
| `values` | `values(obj: json): json` | Object values array |
| `join` | `join(arr: json, sep: string): string` | Join array |
| `get` | `get(obj, key: string, default: json/string): json` | Safe access |

## Built-in Functions: Strings

`import "std/strings"` first.

| Function | Signature | Description |
|----------|-----------|-------------|
| `contains` | `contains(s, sub: string): bool` | Substring check |
| `startsWith` | `startsWith(s, prefix: string): bool` | Prefix check |
| `endsWith` | `endsWith(s, suffix: string): bool` | Suffix check |
| `find` | `find(s, sub: string, start: int = 0): int` | Substring index, -1 when absent |
| `count` | `count(s, sub: string): int` | Occurrence count |
| `toLower` | `toLower(s: string): string` | Lowercase |
| `toUpper` | `toUpper(s: string): string` | Uppercase |
| `capitalize` | `capitalize(s: string): string` | Capitalize first letter |
| `strip` | `strip(s: string): string` | Trim whitespace |
| `isEmptyOrWhitespace` | `isEmptyOrWhitespace(s: string): bool` | Blank check |
| `repeat` | `repeat(s: string, n: int): string` | Repeat n times |
| `replace` | `replace(s, from, to: string): string` | Replace all |
| `split` | `split(s, sep: string): json` | Split into JSON array |
| `join` | `join(parts: json, sep: string): string` | Join JSON array |
| `parseInt` | `parseInt(s: string): int` | Parse integer |
| `parseFloat` | `parseFloat(s: string): float` | Parse float |
| `parseBool` | `parseBool(s: string): bool` | Parse boolean |

## Built-in Functions: Sequtils

`import "std/sequtils"` first. These operate on `array` values.

| Function | Signature | Description |
|----------|-----------|-------------|
| `isEmpty` | `isEmpty(data: array): bool` | Empty check |
| `contains` | `contains(data: array, val: int): bool` | Membership |
| `count` | `count(data: array, val: int): int` | Occurrence count |
| `indexOf` | `indexOf(data: array, val: int): int` | First index, -1 when absent |
| `first` | `first(data: array): int` | First element |
| `last` | `last(data: array): int` | Last element |
| `min` | `min(data: array): int` | Smallest element |
| `max` | `max(data: array): int` | Largest element |
| `distinct` | `distinct(data: array): array` | Deduplicate |
| `concat` | `concat(a, b: array): array` | Concatenate |
| `reverse` | `reverse(data: array): array` | Reversed copy |
| `flatten` | `flatten(data: array): array` | Flatten one level |
| `sort` | `sort(data: array): array` | Sorted copy |
| `add` | `add(s: array, item: any)` | Append in place |

## Built-in Functions: Regex

`import "std/regex"` first. `match` needs a full match, `find`
locates the first occurrence, `findAll` returns every occurrence as a
JSON array. Each result is
`{matched: bool, start: int, stop: int, groups: json, groupCount: int}`.

| Function | Signature | Description |
|----------|-----------|-------------|
| `match` | `match(input, pattern: string): json` | Full-match test |
| `find` | `find(input, pattern: string): json` | First occurrence |
| `findAll` | `findAll(input, pattern: string): json` | Every occurrence |

## CLI Usage

```
dfkup run <script.dfkup>           # Run a script
dfkup run --nojit <script.dfkup>   # Run without JIT
dfkup ast <script.dfkup>           # Print AST
dfkup ast --dumptree <script.dfkup> # Print AST tree
```

JIT is **enabled by default**. Pass `--nojit` to disable it.

## Examples

```
# Fibonacci
fn fib(n: int): int =
  if n < 2:
    result = n
  else:
    result = fib(n - 1) + fib(n - 2)

echo fib(30)

# Nested loops
fn nested(n: int): int =
  var total = 0
  var i = 0
  while i < n:
    var j = 0
    while j < n:
      total = total + 1
      j = j + 1
    i = i + 1
  result = total

echo nested(60)

# String concat
fn concat(n: int): string =
  var s = ""
  var i = 0
  while i < n:
    s = s & "x"
    i = i + 1
  result = s

echo len(concat(10000))

# JSON
import "std/json"

let d = parseJson("""{"a": 1, "b": "hello"}""")
echo dumpJson(d)
echo get(d, "missing", "N/A")
for k in items(keys(d)):
  echo k

# Strings, arrays, regex
import "std/strings"
import "std/sequtils"
import "std/regex"

echo toUpper("hello")
echo join(split("a,b,c", ","), " | ")

var scores = [85, 92, 78]
echo sort(scores)
echo contains(scores, 92)

let m = find("hello42world", "([a-z]+)(\\d+)")
echo m["groups"]

# File operations
if fileExists("data.txt"):
  let content = readFile("data.txt")
  echo content
```
