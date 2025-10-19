import argv
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile

type Instruction {
  Instruction(opcode: Opcode, operand: Operand)
}

type Opcode {
  Push
  Pop
  Add
  Sub
  Incr
  Decr
  Mul
  Div
  Jump
  JE
  JNE
  JGT
  JLT
  JGE
  JLE
  Get
  Set
  GetArg
  SetArg
  Noop
  Print
  PrintC
  PrintStack
  Call
  Ret
}

type Operand {
  None
  Immediate(Int)
}

type StackFrame {
  StackFrame(stack_offset: Int, return_ip: Int)
}

type Stack {
  Stack(values: List(Int), size: Int)
}

type CallStack =
  List(StackFrame)

pub fn main() -> Nil {
  case argv.load().arguments {
    [] -> {
      io.println(
        "Usage: gleam run -- examples/<file>.bytecode or ./vm examples/<file>.bytecode if you build it with gleescript",
      )
      Nil
    }

    [path, ..] -> run_file(path)
  }
}

fn run_file(path: String) -> Nil {
  case simplifile.read(path) {
    Ok(source) -> {
      let program = parse_program(source)
      interpret(program)
    }

    Error(error) ->
      panic as { "failed to read file: " <> file_error_to_string(error) }
  }
}

fn file_error_to_string(error: simplifile.FileError) -> String {
  case error {
    simplifile.Enoent -> "file does not exist"
    simplifile.Enotdir -> "path is not a file"
    simplifile.Eacces -> "insufficient permissions"
    simplifile.Eisdir -> "path is a directory"
    _ -> "unknown error"
  }
}

fn interpret(program: List(Instruction)) -> Nil {
  interpret_loop(program, 0, empty_stack(), [], list.length(program))
}

fn interpret_loop(
  program: List(Instruction),
  pointer: Int,
  stack: Stack,
  call_stack: CallStack,
  program_len: Int,
) -> Nil {
  case pointer >= program_len || pointer < 0 {
    True -> Nil
    False -> {
      let instruction = list_get(program, pointer)
      let #(next_pointer, next_stack, next_call_stack) =
        execute_instruction(instruction, pointer, stack, call_stack)
      interpret_loop(
        program,
        next_pointer,
        next_stack,
        next_call_stack,
        program_len,
      )
    }
  }
}

fn execute_instruction(
  instruction: Instruction,
  pointer: Int,
  stack: Stack,
  call_stack: CallStack,
) -> #(Int, Stack, CallStack) {
  case instruction {
    Instruction(opcode: Noop, operand: _) ->
      #(pointer + 1, stack, call_stack)

    Instruction(opcode: Push, operand: Immediate(value)) ->
      #(pointer + 1, stack_push(stack, value), call_stack)

    Instruction(opcode: Pop, operand: None) -> {
      let #(_, next_stack) = stack_pop(stack)
      #(pointer + 1, next_stack, call_stack)
    }

    Instruction(opcode: Add, operand: None) -> {
      let #(a, stack1) = stack_pop(stack)
      let #(b, stack2) = stack_pop(stack1)
      #(pointer + 1, stack_push(stack2, a + b), call_stack)
    }

    Instruction(opcode: Sub, operand: None) -> {
      let #(a, stack1) = stack_pop(stack)
      let #(b, stack2) = stack_pop(stack1)
      #(pointer + 1, stack_push(stack2, b - a), call_stack)
    }

    Instruction(opcode: Mul, operand: None) -> {
      let #(a, stack1) = stack_pop(stack)
      let #(b, stack2) = stack_pop(stack1)
      #(pointer + 1, stack_push(stack2, a * b), call_stack)
    }

    Instruction(opcode: Div, operand: None) -> {
      let #(a, stack1) = stack_pop(stack)
      let #(b, stack2) = stack_pop(stack1)
      #(pointer + 1, stack_push(stack2, b / a), call_stack)
    }

    Instruction(opcode: Incr, operand: None) -> #(
      pointer + 1,
      stack_update_top(stack, fn(value) { value + 1 }),
      call_stack,
    )

    Instruction(opcode: Decr, operand: None) -> #(
      pointer + 1,
      stack_update_top(stack, fn(value) { value - 1 }),
      call_stack,
    )

    Instruction(opcode: Jump, operand: Immediate(target)) ->
      #(target, stack, call_stack)

    Instruction(opcode: JE, operand: Immediate(target)) ->
      conditional_jump(pointer, stack, call_stack, target, fn(value) {
        value == 0
      })

    Instruction(opcode: JNE, operand: Immediate(target)) ->
      conditional_jump(pointer, stack, call_stack, target, fn(value) {
        value != 0
      })

    Instruction(opcode: JGT, operand: Immediate(target)) ->
      conditional_jump(pointer, stack, call_stack, target, fn(value) {
        value > 0
      })

    Instruction(opcode: JLT, operand: Immediate(target)) ->
      conditional_jump(pointer, stack, call_stack, target, fn(value) {
        value < 0
      })

    Instruction(opcode: JGE, operand: Immediate(target)) ->
      conditional_jump(pointer, stack, call_stack, target, fn(value) {
        value >= 0
      })

    Instruction(opcode: JLE, operand: Immediate(target)) ->
      conditional_jump(pointer, stack, call_stack, target, fn(value) {
        value <= 0
      })

    Instruction(opcode: Get, operand: Immediate(index)) -> {
      let offset = current_stack_offset(call_stack)
      let value = stack_get_absolute(stack, index + offset)
      #(pointer + 1, stack_push(stack, value), call_stack)
    }

    Instruction(opcode: Set, operand: Immediate(index)) -> {
      let offset = current_stack_offset(call_stack)
      let value = stack_peek(stack)
      #(
        pointer + 1,
        stack_replace_absolute(stack, index + offset, value),
        call_stack,
      )
    }

    Instruction(opcode: GetArg, operand: Immediate(index)) -> {
      let frame = current_frame(call_stack)
      // Arguments are indexed from the base of the current frame
      // frame.stack_offset points to the position AFTER all arguments
      // So argument 0 is at (stack_offset - num_args), argument 1 at (stack_offset - num_args + 1), etc.
      // But we don't know num_args, so we work backwards from stack_offset
      // GetArg 0 is the LAST argument pushed (closest to stack_offset)
      // GetArg 1 is the second-to-last, etc.
      let arg_index = frame.stack_offset - index - 1
      let value = stack_get_absolute(stack, arg_index)
      #(pointer + 1, stack_push(stack, value), call_stack)
    }

    Instruction(opcode: SetArg, operand: Immediate(index)) -> {
      let frame = current_frame(call_stack)
      let arg_index = frame.stack_offset - index - 1
      let value = stack_peek(stack)
      #(
        pointer + 1,
        stack_replace_absolute(stack, arg_index, value),
        call_stack,
      )
    }

    Instruction(opcode: Print, operand: None) -> {
      io.print(int.to_string(stack_peek(stack)))
      #(pointer + 1, stack, call_stack)
    }

    Instruction(opcode: PrintC, operand: None) -> {
      io.print(codepoint_to_string(stack_peek(stack)))
      #(pointer + 1, stack, call_stack)
    }

    Instruction(opcode: PrintStack, operand: None) -> {
      io.println(stack_to_string(stack))
      #(pointer + 1, stack, call_stack)
    }

    Instruction(opcode: Call, operand: Immediate(target)) -> {
      let frame =
        StackFrame(stack_offset: stack_len(stack), return_ip: pointer + 1)
      #(target, stack, [frame, ..call_stack])
    }

    Instruction(opcode: Ret, operand: None) -> {
      let #(frame, rest) = call_stack_pop(call_stack)
      #(frame.return_ip, stack, rest)
    }

    _ -> panic as "invalid instruction encoding"
  }
}

fn conditional_jump(
  pointer: Int,
  stack: Stack,
  call_stack: CallStack,
  target: Int,
  predicate: fn(Int) -> Bool,
) -> #(Int, Stack, CallStack) {
  let value = stack_peek(stack)
  case predicate(value) {
    True -> {
      let #(_, next_stack) = stack_pop(stack)
      #(target, next_stack, call_stack)
    }
    False -> #(pointer + 1, stack, call_stack)
  }
}

fn parse_program(source: String) -> List(Instruction) {
  let lines =
    source
    |> string.split(on: "\n")
    |> list.map(process_line)
    |> list.filter(fn(tokens) {
      case tokens {
        [] -> False
        _ -> True
      }
    })

  let labels = build_labels(lines)
  let procedures = find_procedures(lines)

  lines
  |> list.map(fn(tokens) { parse_instruction(tokens, labels, procedures) })
}

fn instruction(opcode: Opcode) -> Instruction {
  Instruction(opcode: opcode, operand: None)
}

fn instruction_with_immediate(opcode: Opcode, value: Int) -> Instruction {
  Instruction(opcode: opcode, operand: Immediate(value))
}

fn process_line(line: String) -> List(String) {
  line
  |> strip_comment
  |> string.trim()
  |> split_whitespace
}

fn strip_comment(line: String) -> String {
  case string.split_once(line, on: "#") {
    Ok(#(before, _)) -> before
    Error(_) -> line
  }
}

fn split_whitespace(text: String) -> List(String) {
  text
  |> string.replace(each: "\t", with: " ")
  |> string.replace(each: "\r", with: " ")
  |> string.replace(each: "\u{000B}", with: " ")
  |> string.replace(each: "\u{000C}", with: " ")
  |> string.split(on: " ")
  |> list.filter(fn(token) { token != "" })
}

fn build_labels(lines: List(List(String))) -> dict.Dict(String, Int) {
  build_labels_loop(lines, 0, dict.new())
}

fn build_labels_loop(
  lines: List(List(String)),
  index: Int,
  labels: dict.Dict(String, Int),
) -> dict.Dict(String, Int) {
  case index >= list.length(lines) {
    True -> labels
    False -> {
      let tokens = list_get(lines, index)
      let next_labels = case tokens {
        ["label", name] -> dict.insert(labels, name, index)
        _ -> labels
      }

      build_labels_loop(lines, index + 1, next_labels)
    }
  }
}

fn find_procedures(lines: List(List(String))) -> dict.Dict(String, #(Int, Int)) {
  find_procedures_loop(lines, 0, dict.new())
}

fn find_procedures_loop(
  lines: List(List(String)),
  index: Int,
  procedures: dict.Dict(String, #(Int, Int)),
) -> dict.Dict(String, #(Int, Int)) {
  let line_count = list.length(lines)

  case index >= line_count {
    True -> procedures
    False -> {
      let tokens = list_get(lines, index)
      case tokens {
        ["Proc", name] -> {
          let end_index = find_procedure_end(lines, index + 1)
          let updated = dict.insert(procedures, name, #(index, end_index + 1))
          find_procedures_loop(lines, index + 1, updated)
        }

        _ -> find_procedures_loop(lines, index + 1, procedures)
      }
    }
  }
}

fn find_procedure_end(lines: List(List(String)), index: Int) -> Int {
  let tokens = list_get(lines, index)
  case tokens {
    ["End"] -> index
    _ -> find_procedure_end(lines, index + 1)
  }
}

fn parse_instruction(
  tokens: List(String),
  labels: dict.Dict(String, Int),
  procedures: dict.Dict(String, #(Int, Int)),
) -> Instruction {
  case tokens {
    ["Push", value] -> instruction_with_immediate(Push, parse_int(value))
    ["Pop"] -> instruction(Pop)
    ["Add"] -> instruction(Add)
    ["Sub"] -> instruction(Sub)
    ["Mul"] -> instruction(Mul)
    ["Div"] -> instruction(Div)
    ["Incr"] -> instruction(Incr)
    ["Decr"] -> instruction(Decr)
    ["Jump", label] -> instruction_with_immediate(Jump, lookup_label(labels, label))
    ["JE", label] -> instruction_with_immediate(JE, lookup_label(labels, label))
    ["JNE", label] -> instruction_with_immediate(JNE, lookup_label(labels, label))
    ["JGT", label] -> instruction_with_immediate(JGT, lookup_label(labels, label))
    ["JLT", label] -> instruction_with_immediate(JLT, lookup_label(labels, label))
    ["JGE", label] -> instruction_with_immediate(JGE, lookup_label(labels, label))
    ["JLE", label] -> instruction_with_immediate(JLE, lookup_label(labels, label))
    ["Get", index] -> instruction_with_immediate(Get, parse_non_negative(index))
    ["Set", index] -> instruction_with_immediate(Set, parse_non_negative(index))
    ["GetArg", index] -> instruction_with_immediate(GetArg, parse_non_negative(index))
    ["SetArg", index] -> instruction_with_immediate(SetArg, parse_non_negative(index))
    ["Print"] -> instruction(Print)
    ["PrintC"] -> instruction(PrintC)
    ["PrintStack"] -> instruction(PrintStack)
    ["Proc", name] -> {
      let #(_, skip_to) = lookup_procedure(procedures, name)
      instruction_with_immediate(Jump, skip_to)
    }
    ["Call", name] -> {
      let #(start, _) = lookup_procedure(procedures, name)
      instruction_with_immediate(Call, start + 1)
    }
    ["Ret"] -> instruction(Ret)
    ["label", _] -> instruction(Noop)
    ["End"] -> instruction(Noop)
    _ -> panic as { "invalid instruction: " <> string.join(tokens, with: " ") }
  }
}

fn lookup_label(labels: dict.Dict(String, Int), label: String) -> Int {
  case dict.get(labels, label) {
    Ok(value) -> value
    Error(_) -> panic as { "unknown label " <> label }
  }
}

fn lookup_procedure(
  procedures: dict.Dict(String, #(Int, Int)),
  name: String,
) -> #(Int, Int) {
  case dict.get(procedures, name) {
    Ok(value) -> value
    Error(_) -> panic as { "unknown procedure " <> name }
  }
}

fn parse_int(text: String) -> Int {
  case int.parse(text) {
    Ok(value) -> value
    Error(_) -> panic as { "invalid integer: " <> text }
  }
}

fn parse_non_negative(text: String) -> Int {
  let value = parse_int(text)
  case value < 0 {
    True -> panic as { "expected non negative integer, got " <> text }
    False -> value
  }
}

fn empty_stack() -> Stack {
  Stack(values: [], size: 0)
}

fn stack_len(stack: Stack) -> Int {
  stack.size
}

fn stack_push(stack: Stack, value: Int) -> Stack {
  Stack(values: [value, ..stack.values], size: stack.size + 1)
}

fn stack_pop(stack: Stack) -> #(Int, Stack) {
  case stack.values {
    [] -> panic as "attempted to pop from an empty stack"
    [value, ..rest] -> #(value, Stack(values: rest, size: stack.size - 1))
  }
}

fn stack_peek(stack: Stack) -> Int {
  case stack.values {
    [] -> panic as "attempted to peek an empty stack"
    [value, ..] -> value
  }
}

fn stack_update_top(stack: Stack, updater: fn(Int) -> Int) -> Stack {
  let #(top, rest) = stack_pop(stack)
  stack_push(rest, updater(top))
}

fn stack_get_absolute(stack: Stack, index: Int) -> Int {
  case index < 0 || index >= stack.size {
    True -> panic as "stack index out of bounds"
    False -> {
      let index_from_top = stack.size - 1 - index
      list_get(stack.values, index_from_top)
    }
  }
}

fn stack_replace_absolute(stack: Stack, index: Int, value: Int) -> Stack {
  case index < 0 || index >= stack.size {
    True -> panic as "stack index out of bounds"
    False -> {
      let index_from_top = stack.size - 1 - index
      let values = list_set(stack.values, index_from_top, value)
      Stack(values: values, size: stack.size)
    }
  }
}

fn stack_to_string(stack: Stack) -> String {
  let values = stack.values |> list.reverse |> list.map(int.to_string)
  "[" <> string.join(values, with: ", ") <> "]"
}

fn list_get(list_: List(a), index: Int) -> a {
  case list_ {
    [] -> panic as "list index out of bounds"
    [value, ..rest] ->
      case index == 0 {
        True -> value
        False -> list_get(rest, index - 1)
      }
  }
}

fn list_set(list_: List(a), index: Int, value: a) -> List(a) {
  case list_ {
    [] -> panic as "list index out of bounds"
    [head, ..tail] ->
      case index == 0 {
        True -> [value, ..tail]
        False -> [head, ..list_set(tail, index - 1, value)]
      }
  }
}

fn current_stack_offset(call_stack: CallStack) -> Int {
  case call_stack {
    [] -> 0
    [frame, ..] -> frame.stack_offset
  }
}

fn current_frame(call_stack: CallStack) -> StackFrame {
  case call_stack {
    [] -> panic as "attempted to access arguments outside of a procedure"
    [frame, ..] -> frame
  }
}

fn call_stack_pop(call_stack: CallStack) -> #(StackFrame, CallStack) {
  case call_stack {
    [] -> panic as "attempted to return without a call stack frame"
    [frame, ..rest] -> #(frame, rest)
  }
}

fn codepoint_to_string(codepoint: Int) -> String {
  case string.utf_codepoint(codepoint) {
    Ok(cp) -> string.from_utf_codepoints([cp])
    Error(_) -> panic as "invalid codepoint"
  }
}
