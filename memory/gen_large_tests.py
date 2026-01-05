#!/usr/bin/env python3
import os


class Cell:
    def __init__(self, head, tail):
        self.head = head
        self.tail = tail


def listify(items):
    if len(items) == 1:
        return items[0]
    return Cell(items[0], listify(items[1:]))


def left_chain(depth, leaf, right):
    if depth == 0:
        return leaf
    return Cell(left_chain(depth - 1, leaf, right), right)


memory = [0]
bitmask = (1 << 28) - 1
NIL = bitmask
EXECUTE_BIT = 1 << 63
HED_TAG_BIT = 1 << 57
TEL_TAG_BIT = 1 << 56
LARGE_ATOM_BIT = 1 << 60


def emit_large_atom(value):
    limbs = []
    while value > 0:
        limbs.append(value & bitmask)
        value >>= 28
    if not limbs:
        limbs = [0]

    header_addr = len(memory)
    memory.append(0)

    limb_addrs = []
    for _ in limbs:
        limb_addrs.append(len(memory))
        memory.append(0)

    for i, limb in enumerate(limbs):
        is_last = i == (len(limbs) - 1)
        tel_tag = TEL_TAG_BIT if is_last else 0
        tel_val = NIL if is_last else limb_addrs[i + 1]
        memory[limb_addrs[i]] = (
            HED_TAG_BIT
            | tel_tag
            | ((limb & bitmask) << 28)
            | (tel_val & bitmask)
        )

    memory[header_addr] = (
        LARGE_ATOM_BIT
        | TEL_TAG_BIT
        | ((limb_addrs[0] & bitmask) << 28)
        | (len(limbs) & bitmask)
    )
    return header_addr


def emit_noun(noun):
    if isinstance(noun, Cell):
        return 0, emit_cell(noun)
    if isinstance(noun, int):
        if noun <= bitmask:
            return 1, noun & bitmask
        return 0, emit_large_atom(noun)
    raise TypeError("unsupported noun type")


def emit_cell(noun):
    cell_loc = len(memory)
    if len(memory) == 1:
        memory.append(EXECUTE_BIT)
    else:
        memory.append(0)

    hed_tag, hed_val = emit_noun(noun.head)
    tel_tag, tel_val = emit_noun(noun.tail)
    memory[cell_loc] |= (
        (hed_tag << 57)
        | (tel_tag << 56)
        | ((hed_val & bitmask) << 28)
        | (tel_val & bitmask)
    )
    return cell_loc


def write_mem(path, noun):
    global memory
    memory = [0]
    emit_noun(noun)
    memory[0] = len(memory)
    with open(path, "w") as handle:
        for mem in memory:
            handle.write(f"{mem:016x}\n")


def main():
    out_dir = os.path.dirname(__file__)
    big_axis = 1 << 28
    big_atom = (1 << 28) + ((1 << 28) - 1)

    subject_deep = left_chain(28, 42, 0)
    slot_formula = listify([0, big_axis])
    slot_noun = listify([subject_deep, slot_formula])
    write_mem(os.path.join(out_dir, "large_axis_slot.hex"), slot_noun)

    incr_formula = listify([4, listify([1, big_atom])])
    incr_noun = listify([0, incr_formula])
    write_mem(os.path.join(out_dir, "large_atom_incr.hex"), incr_noun)

    eq_formula = listify([5, listify([1, big_atom]), listify([1, big_atom])])
    eq_noun = listify([0, eq_formula])
    write_mem(os.path.join(out_dir, "large_atom_equal.hex"), eq_noun)

    new_val = 99
    replace_formula = listify([
        10,
        listify([big_axis, listify([1, new_val])]),
        listify([0, 1]),
    ])
    replace_noun = listify([subject_deep, replace_formula])
    write_mem(os.path.join(out_dir, "large_axis_replace.hex"), replace_noun)


if __name__ == "__main__":
    main()
