#!/usr/bin/env python3
import argparse
import struct
import sys
import time

try:
    import serial
except ImportError as exc:
    print("pyserial is required: pip install pyserial")
    raise


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


def is_cell(noun):
    return isinstance(noun, Cell)


def pretty(noun, tail_pos=False):
    if is_cell(noun):
        content = f"{pretty(noun.head, False)} {pretty(noun.tail, True)}"
        return content if tail_pos else f"[{content}]"
    return str(noun)


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


def decode_mem_root(mem, root_addr):
    cache = {}
    visiting = set()
    return decode_addr(mem, root_addr, cache, visiting)


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


def read_exact(port, count):
    data = bytearray()
    while len(data) < count:
        chunk = port.read(count - len(data))
        if not chunk:
            raise RuntimeError("serial timeout")
        data.extend(chunk)
    return bytes(data)


def send_write(port, addr, words):
    port.write(b"W")
    port.write(struct.pack("<H", addr))
    port.write(struct.pack("<H", len(words)))
    for word in words:
        port.write(struct.pack("<Q", word))
    ack = read_exact(port, 1)
    if ack != b"w":
        raise RuntimeError(f"unexpected write ack {ack!r}")


def send_read(port, addr, count):
    port.write(b"R")
    port.write(struct.pack("<H", addr))
    port.write(struct.pack("<H", count))
    ack = read_exact(port, 1)
    if ack != b"r":
        raise RuntimeError(f"unexpected read ack {ack!r}")
    data = read_exact(port, count * 8)
    words = []
    for idx in range(count):
        word = struct.unpack_from("<Q", data, idx * 8)[0]
        words.append(word & WORD_MASK)
    return words


def send_start(port, addr):
    port.write(b"S")
    port.write(struct.pack("<H", addr))
    ack = read_exact(port, 1)
    if ack != b"s":
        raise RuntimeError(f"unexpected start ack {ack!r}")


def send_reset(port):
    port.write(b"X")
    ack = read_exact(port, 1)
    if ack != b"x":
        raise RuntimeError(f"unexpected reset ack {ack!r}")


def send_status(port):
    port.write(b"P")
    ack = read_exact(port, 1)
    if ack != b"p":
        raise RuntimeError(f"unexpected status ack {ack!r}")
    payload = read_exact(port, 16)
    flags, error, edit_error, hint_tag = payload[0], payload[1], payload[2], payload[3]
    hint = struct.unpack_from("<I", payload, 4)[0]
    root_ptr = struct.unpack_from("<I", payload, 8)[0]
    free_ptr = struct.unpack_from("<I", payload, 12)[0]
    return {
        "busy": bool(flags & 0x1),
        "done": bool(flags & 0x2),
        "error": error,
        "edit_error": edit_error,
        "hint_tag": hint_tag & 0x1,
        "hint": hint,
        "root_ptr": root_ptr,
        "free_ptr": free_ptr,
    }


def main():
    parser = argparse.ArgumentParser(description="UART loader for NockPU on DE10-Lite.")
    parser.add_argument("--port", required=True, help="Serial port (e.g. /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--mem", help="Memory hex file to load")
    parser.add_argument("--start-addr", type=int, default=1)
    parser.add_argument("--reset", action="store_true", help="Pulse core reset after load")
    parser.add_argument("--run", action="store_true", help="Start evaluation after load")
    parser.add_argument("--poll", action="store_true", help="Poll until done")
    parser.add_argument("--mem-depth", type=int, default=1 << 11)
    parser.add_argument("--dump", help="Write full memory dump to hex file")
    parser.add_argument("--decode", action="store_true", help="Decode result noun from memory dump")
    args = parser.parse_args()

    with serial.Serial(args.port, args.baud, timeout=2) as port:
        if args.mem:
            words = parse_mem_file(args.mem)
            send_write(port, 0, words)
            if args.reset:
                send_reset(port)

        if args.run:
            send_start(port, args.start_addr)

        status = send_status(port)
        if args.poll:
            while not status["done"]:
                time.sleep(0.1)
                status = send_status(port)

        if args.dump or args.decode:
            words = send_read(port, 0, args.mem_depth)
            if args.dump:
                with open(args.dump, "w") as handle:
                    for word in words:
                        handle.write(f"{word:016x}\n")

            if args.decode:
                root_addr = status["root_ptr"] or 1
                noun = decode_mem_root(words, root_addr)
                print(pretty(noun, False))

        print("status", status)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
