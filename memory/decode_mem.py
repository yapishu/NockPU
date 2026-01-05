#!/usr/bin/env python3
import sys


NOUN_WIDTH = 28
NIL = (1 << NOUN_WIDTH) - 1
HED_TAG_BIT = 1 << 57
TEL_TAG_BIT = 1 << 56
LARGE_ATOM_BIT = 1 << 60
WORD_MASK = (1 << 64) - 1
NOUN_MASK = (1 << NOUN_WIDTH) - 1


class Cell:
    def __init__(self, head, tail):
        self.head = head
        self.tail = tail


def pretty(noun, tail_pos=False):
    if isinstance(noun, Cell):
        content = f"{pretty(noun.head, False)} {pretty(noun.tail, True)}"
        return content if tail_pos else f"[{content}]"
    return str(noun)


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


def main():
    if len(sys.argv) < 2:
        print("Usage: decode_mem.py <mem_file> [root_addr]")
        return 1
    path = sys.argv[1]
    root_addr = int(sys.argv[2], 0) if len(sys.argv) > 2 else 1
    mem = parse_mem_file(path)
    cache = {}
    visiting = set()
    noun = decode_addr(mem, root_addr, cache, visiting)
    print(pretty(noun, False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
