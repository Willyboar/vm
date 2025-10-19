# vm

A tiny stack-based virtual machine for experimenting with bytecode programs written in a compact, assembly-like syntax.

## Running Programs
- Interpret a bytecode file directly:
  ```sh
  gleam run -- examples/hello_world.bytecode
  ```
- Produce a standalone executable with Gleescript and run it:
  ```sh
  gleam run -m gleescript
  ./vm examples/hello_world.bytecode
  ```

## Bytecode Format
- One instruction per line; tokens are separated by whitespace.
- Line comments start with `#` and extend to the end of the line.
- `label <name>` declares a jump target.
- `Proc <name>` … `End` wraps a callable procedure that is invoked with `Call <name>` and returns with `Ret`.

### Instruction Set
| Mnemonic    | Operand           | Description |
|-------------|-------------------|-------------|
| `Push n`    | integer           | Push `n` onto the stack. |
| `Pop`       | –                 | Discard the top value. |
| `Add`       | –                 | Pop two values, push their sum. |
| `Sub`       | –                 | Pop two values, push right minus left. |
| `Mul`       | –                 | Pop two values, push their product. |
| `Div`       | –                 | Pop two values, push integer division result. |
| `Incr`      | –                 | Increment the top value in place. |
| `Decr`      | –                 | Decrement the top value in place. |
| `Jump lbl`  | label             | Jump unconditionally to `lbl`. |
| `JE lbl`    | label             | Jump to `lbl` if the top value is zero. |
| `JNE lbl`   | label             | Jump to `lbl` if the top value is non-zero. |
| `JGT lbl`   | label             | Jump to `lbl` if the top value is greater than zero. |
| `JLT lbl`   | label             | Jump to `lbl` if the top value is less than zero. |
| `JGE lbl`   | label             | Jump to `lbl` if the top value is ≥ 0. |
| `JLE lbl`   | label             | Jump to `lbl` if the top value is ≤ 0. |
| `Get i`     | stack index       | Push the value at absolute stack index `i`. |
| `Set i`     | stack index       | Replace the value at absolute stack index `i` with the top value. |
| `GetArg i`  | stack index       | Push the `i`th argument of the current procedure (0 is the last argument pushed). |
| `SetArg i`  | stack index       | Overwrite the `i`th argument of the current procedure with the top value. |
| `Print`     | –                 | Write the top value as a decimal integer. |
| `PrintC`    | –                 | Write the top value as a Unicode codepoint. |
| `PrintStack`| –                 | Print the entire stack (top to bottom). |
| `Call name` | procedure name    | Jump to procedure `name`, preserving a return frame. |
| `Ret`       | –                 | Return to the previous call frame. |
| `Noop`      | –                 | Does nothing (produced by `label`/`End`). |

## Sample Programs
- `examples/hello_world.bytecode` – prints “Hello World!”.
- `examples/sum.bytecode` – accumulates the sum of the first 100 integers.
- `examples/procedure.bytecode` – demonstrates procedures and argument passing.
- `examples/factorial.bytecode` – computes `5!` iteratively.
- More examples are available in `examples/` covering recursion and branching patterns.

## Development
The interpreter itself lives in `src/vm.gleam`. Tests can be executed with:
```sh
gleam test
```
