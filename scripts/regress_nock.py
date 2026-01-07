#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
import tempfile


NOUN_WIDTH = 28
NIL = (1 << NOUN_WIDTH) - 1
HED_TAG_BIT = 1 << 57
TEL_TAG_BIT = 1 << 56
LARGE_ATOM_BIT = 1 << 60
WORD_MASK = (1 << 64) - 1
NOUN_MASK = (1 << NOUN_WIDTH) - 1


class Cell:
    __slots__ = ("head", "tail")

    def __init__(self, head, tail):
        self.head = head
        self.tail = tail

    def __repr__(self):
        return f"Cell({self.head!r}, {self.tail!r})"


def is_cell(noun):
    return isinstance(noun, Cell)


def pretty(noun, tail_pos=False):
    if is_cell(noun):
        content = f"{pretty(noun.head, False)} {pretty(noun.tail, True)}"
        return content if tail_pos else f"[{content}]"
    return str(noun)


def noun_equal(a, b, seen=None):
    if a is b:
        return True
    if is_cell(a) != is_cell(b):
        return False
    if not is_cell(a):
        return a == b
    if seen is None:
        seen = set()
    key = (id(a), id(b))
    if key in seen:
        return True
    seen.add(key)
    return noun_equal(a.head, b.head, seen) and noun_equal(a.tail, b.tail, seen)


def parse_mem_file(path):
    words = []
    with open(path, "r") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            parts = line.split()
            if not parts:
                continue
            try:
                value = int(parts[-1], 16)
            except ValueError:
                token = parts[-1].lower()
                if token and set(token) <= {"x", "z"}:
                    value = 0
                else:
                    continue
            words.append(value & WORD_MASK)
    return words


def decode_large_atom(mem, header_word):
    length = header_word & NOUN_MASK
    ptr = (header_word >> NOUN_WIDTH) & NOUN_MASK
    if length == 0:
        return 0
    value = 0
    shift = 0
    for _ in range(length):
        if ptr >= len(mem):
            raise IndexError(f"limb pointer {ptr} out of range")
        limb_word = mem[ptr]
        limb = (limb_word >> NOUN_WIDTH) & NOUN_MASK
        value |= limb << shift
        shift += NOUN_WIDTH
        ptr = limb_word & NOUN_MASK
    return value


def decode_addr(mem, addr, cache, visiting):
    if addr in cache:
        return cache[addr]
    if addr in visiting:
        return f"<cycle:{addr}>"
    if addr >= len(mem):
        return f"<oob:{addr}>"
    visiting.add(addr)
    word = mem[addr]
    if word & LARGE_ATOM_BIT:
        noun = decode_large_atom(mem, word)
        cache[addr] = noun
        visiting.remove(addr)
        return noun

    hed_tag = 1 if (word & HED_TAG_BIT) else 0
    tel_tag = 1 if (word & TEL_TAG_BIT) else 0
    hed_val = (word >> NOUN_WIDTH) & NOUN_MASK
    tel_val = word & NOUN_MASK

    if hed_tag == 1 and tel_tag == 1 and tel_val == NIL:
        noun = hed_val
        cache[addr] = noun
        visiting.remove(addr)
        return noun

    head = hed_val if hed_tag else decode_addr(mem, hed_val, cache, visiting)
    tail = tel_val if tel_tag else decode_addr(mem, tel_val, cache, visiting)
    noun = Cell(head, tail)
    cache[addr] = noun
    visiting.remove(addr)
    return noun


def decode_mem_root(path, root_addr=1):
    mem = parse_mem_file(path)
    cache = {}
    visiting = set()
    return decode_addr(mem, root_addr, cache, visiting)


def axis_slot(axis, subject):
    if not isinstance(axis, int):
        raise ValueError("axis must be an atom")
    if axis <= 0:
        raise ValueError("axis must be positive")
    if axis == 1:
        return subject
    path = []
    while axis > 1:
        path.append(axis & 1)
        axis //= 2
    cur = subject
    for direction in reversed(path):
        if not is_cell(cur):
            raise ValueError("axis over atom")
        cur = cur.tail if direction else cur.head
    return cur


def edit_axis(axis, value, subject):
    if not isinstance(axis, int):
        raise ValueError("axis must be an atom")
    if axis <= 0:
        raise ValueError("axis must be positive")
    if axis == 1:
        return value
    path = []
    while axis > 1:
        path.append(axis & 1)
        axis //= 2

    def walk(cur, idx):
        if idx < 0:
            return value
        if not is_cell(cur):
            raise ValueError("edit axis over atom")
        direction = path[idx]
        if direction:
            return Cell(cur.head, walk(cur.tail, idx - 1))
        return Cell(walk(cur.head, idx - 1), cur.tail)

    return walk(subject, len(path) - 1)


def args_from(noun, count):
  args = []
  cur = noun
  for _ in range(count - 1):
    if not is_cell(cur):
      raise ValueError("not enough arguments")
    args.append(cur.head)
    cur = cur.tail
  args.append(cur)
  return args


def nock_eval(subject, formula):
    while is_cell(formula) and formula.tail == NIL and is_cell(formula.head):
        formula = formula.head
    if not is_cell(formula):
        return formula
    op = formula.head
    args = formula.tail

    if is_cell(op):
        return Cell(nock_eval(subject, op), nock_eval(subject, args))
    if not isinstance(op, int):
        raise ValueError("opcode must be an atom")

    if op == 0:
        (axis,) = args_from(args, 1)
        return axis_slot(axis, subject)
    if op == 1:
        (value,) = args_from(args, 1)
        return value
    if op == 2:
        b, c = args_from(args, 2)
        return nock_eval(nock_eval(subject, b), nock_eval(subject, c))
    if op == 3:
        (b,) = args_from(args, 1)
        return 0 if is_cell(nock_eval(subject, b)) else 1
    if op == 4:
        (b,) = args_from(args, 1)
        value = nock_eval(subject, b)
        if not isinstance(value, int):
            raise ValueError("increment on cell")
        return value + 1
    if op == 5:
        b, c = args_from(args, 2)
        return 0 if noun_equal(nock_eval(subject, b), nock_eval(subject, c)) else 1
    if op == 6:
        b, c, d = args_from(args, 3)
        cond = nock_eval(subject, b)
        if is_cell(cond):
            raise ValueError("if condition is cell")
        return nock_eval(subject, c if cond == 0 else d)
    if op == 7:
        b, c = args_from(args, 2)
        return nock_eval(nock_eval(subject, b), c)
    if op == 8:
        b, c = args_from(args, 2)
        return nock_eval(Cell(nock_eval(subject, b), subject), c)
    if op == 9:
        b, c = args_from(args, 2)
        core = nock_eval(subject, c)
        arm = axis_slot(b, core)
        return nock_eval(core, arm)
    if op == 10:
        bc, d = args_from(args, 2)
        b, c = args_from(bc, 2)
        value = nock_eval(subject, c)
        sub = nock_eval(subject, d)
        return edit_axis(b, value, sub)
    if op == 11:
        if is_cell(args) and is_cell(args.head):
            b, c = args_from(args.head, 2)
            d = args.tail
            _ = nock_eval(subject, c)
            return nock_eval(subject, d)
        b, c = args_from(args, 2)
        if is_cell(b):
            raise ValueError("malformed hint")
        return nock_eval(subject, c)

    raise ValueError(f"unsupported opcode {op}")


DEFAULT_TESTS = [
    "memory/slot_tb.hex",
    "memory/constant_tb.hex",
    "memory/evaluate.hex",
    "memory/evaluate2.hex",
    "memory/evaluate3.hex",
    "memory/evaluate4.hex",
    "memory/inc_slot.hex",
    "memory/increment.hex",
    "memory/atom_incr.hex",
    "memory/nested_increment.hex",
    "memory/add_equal.hex",
    "memory/autocons.hex",
    "memory/autocons2.hex",
    "memory/cell_tb.hex",
    "memory/cell_auto.hex",
    "memory/if.hex",
    "memory/if_ans2.hex",
    "memory/opcode_5/yes_atom.hex",
    "memory/opcode_5/yes_cell.hex",
    "memory/opcode_5/yes_deep_cell.hex",
    "memory/opcode_5/nested_yes.hex",
    "memory/opcode_5/no_atom.hex",
    "memory/opcode_5/no_atom_cell.hex",
    "memory/opcode_5/no_deep_cell.hex",
    "memory/opcode7.hex",
    "memory/opcode8.hex",
    "memory/opcode8_nested.hex",
    "memory/opcode8_2.hex",
    "memory/opcode9.hex",
    "memory/opcode9_2.hex",
    "memory/opcode9_incr.hex",
    "memory/opcode9_9201.hex",
    "memory/opcode10.hex",
    "memory/opcode11_static.hex",
    "memory/opcode11_dynamic.hex",
    "memory/large_axis_slot.hex",
    "memory/large_atom_incr.hex",
    "memory/large_atom_equal.hex",
    "memory/large_axis_replace.hex",
    "memory/add.hex",
    "memory/decrement.hex",
    "memory/cap.hex",
    "memory/inc_3.hex",
    "memory/ackerman_1_2.hex",
]
SMOKE_ONLY = {
    "memory/add.hex",
    "memory/decrement.hex",
    "memory/cap.hex",
}
HINT_EXPECTATIONS = {
    "memory/opcode11_static.hex": (267062763, 1),
    "memory/opcode11_dynamic.hex": (420, 1),
}


def compile_sim(vvp_path):
    cmd = ["iverilog", "-DNO_VCD", "-o", vvp_path, "-c", "command_file"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise RuntimeError("iverilog failed")


def parse_error(output, label):
    for line in output.splitlines():
        if line.startswith(label):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    return int(parts[1], 16)
                except ValueError:
                    return None
    return None


def parse_cycles(output):
    for line in output.splitlines():
        if line.startswith("cycles"):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    return int(parts[1])
                except ValueError:
                    return None
    return None


def parse_int(output, label):
    for line in output.splitlines():
        if line.startswith(label):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    return int(parts[1])
                except ValueError:
                    return None
    return None


def run_case(vvp_path, mem_path, dump_path, max_cycles, print_cycles, force_gc, force_free):
    cmd = ["vvp", vvp_path, f"+mem={mem_path}", f"+dump={dump_path}"]
    if max_cycles:
        cmd.append(f"+max_cycles={max_cycles}")
    if print_cycles:
        cmd.append("+print_cycles")
    if force_gc:
        cmd.append("+force_gc")
    if force_free is not None:
        cmd.append(f"+force_free={force_free}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr or "vvp failed")
    error = parse_error(result.stdout, "error")
    edit_error = parse_error(result.stdout, "edit_error")
    cycles = parse_cycles(result.stdout)
    root_ptr = parse_int(result.stdout, "root_ptr")
    gc_seen = parse_int(result.stdout, "gc_seen")
    hint = parse_int(result.stdout, "hint")
    hint_tag = parse_int(result.stdout, "hint_tag")
    timed_out = "timeout: traversal_finished not asserted after" in result.stdout
    return error, edit_error, timed_out, cycles, root_ptr, gc_seen, hint, hint_tag, result.stdout


def main():
    parser = argparse.ArgumentParser(description="Run NockPU regression tests.")
    parser.add_argument("--tests", nargs="*", default=DEFAULT_TESTS)
    parser.add_argument("--max-cycles", type=int, default=0)
    parser.add_argument("--print-cycles", action="store_true")
    parser.add_argument("--force-gc", action="store_true")
    parser.add_argument("--require-gc", action="store_true")
    parser.add_argument("--force-free", type=int)
    args = parser.parse_args()

    sys.setrecursionlimit(10000)

    with tempfile.TemporaryDirectory() as tmpdir:
        vvp_path = os.path.join(tmpdir, "npu_regress.vvp")
        compile_sim(vvp_path)
        failures = 0
        for mem_path in args.tests:
            dump_path = os.path.join(tmpdir, "mem_dump.hex")
            if not os.path.exists(mem_path):
                print(f"missing {mem_path}")
                failures += 1
                continue
            try:
                error, edit_error, timed_out, cycles, root_ptr, gc_seen, hint, hint_tag, _ = run_case(
                    vvp_path,
                    mem_path,
                    dump_path,
                    args.max_cycles,
                    args.print_cycles,
                    args.force_gc,
                    args.force_free,
                )
            except Exception as exc:
                print(f"{mem_path}: sim failed ({exc})")
                failures += 1
                continue
            if timed_out:
                print(f"{mem_path}: timeout")
                failures += 1
                continue
            if error not in (None, 0) or edit_error not in (None, 0):
                print(f"{mem_path}: error {error} edit_error {edit_error}")
                failures += 1
                continue
            if args.require_gc and not gc_seen:
                print(f"{mem_path}: no gc observed")
                failures += 1
                continue
            if mem_path in HINT_EXPECTATIONS:
                expected_hint, expected_hint_tag = HINT_EXPECTATIONS[mem_path]
                if hint is None or hint_tag is None:
                    print(f"{mem_path}: missing hint output")
                    failures += 1
                    continue
                if hint != expected_hint or hint_tag != expected_hint_tag:
                    print(f"{mem_path}: hint mismatch (hint {hint} tag {hint_tag})")
                    failures += 1
                    continue

            cycle_note = ""
            if args.print_cycles and cycles is not None:
                cycle_note = f", cycles {cycles}"
            if mem_path in SMOKE_ONLY:
                print(f"{mem_path}: ok (smoke{cycle_note})")
                continue

            try:
                root = decode_mem_root(mem_path, 1)
                if not is_cell(root):
                    raise ValueError("root is not [subject formula]")
                subject = root.head
                formula = root.tail
                expected = nock_eval(subject, formula)
                root_addr = root_ptr if root_ptr is not None else 1
                got = decode_mem_root(dump_path, root_addr)
            except Exception as exc:
                print(f"{mem_path}: decode/eval failed ({exc})")
                failures += 1
                continue

            if not noun_equal(expected, got):
                print(f"{mem_path}: mismatch")
                print(f"expected {pretty(expected)}")
                print(f"got      {pretty(got)}")
                if root_ptr is not None:
                    print(f"root_ptr {root_ptr}")
                failures += 1
            else:
                if cycle_note:
                    print(f"{mem_path}: ok ({cycle_note[2:]})")
                else:
                    print(f"{mem_path}: ok")

        if failures:
            print(f"{failures} failures")
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
