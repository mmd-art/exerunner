r"""Swift string literals: finds single-line "..." literals (with escapes and \( ) interpolations that
may hold strings of their own), skipping comments, raw and multi-line literals."""
import re

CYR = re.compile(r"[А-Яа-яЁё]")

WRAPPED = re.compile(r"(?<![A-Za-z0-9_.])t\($")

def wrapped(src, start):
    """True when the literal at `start` is already the argument of t(...)"""
    return bool(WRAPPED.search(src[:start].rstrip()))

def skip_string(src, i, spans, depth):
    """src[i] is the opening quote; returns the index after the closing one and records the span
    (and those of literals nested inside interpolations)"""
    k = i + 1
    n = len(src)
    while k < n:
        ch = src[k]
        if ch == "\\":
            if k + 1 < n and src[k + 1] == "(":
                k = skip_interpolation(src, k + 2, spans, depth + 1)
                continue
            k += 2
            continue
        if ch == '"':
            spans.append((i, k + 1, depth))
            return k + 1
        if ch == "\n":
            raise ValueError(f"unterminated string at {i}")
        k += 1
    raise ValueError(f"unterminated string at {i}")

def skip_interpolation(src, k, spans, depth):
    level = 1
    while level:
        ch = src[k]
        if ch == '"':
            k = skip_string(src, k, spans, depth)
            continue
        if ch == "(":
            level += 1
        elif ch == ")":
            level -= 1
        k += 1
    return k

def literals(src):
    """(start, end, depth) of every single-line literal; depth 0 at top level"""
    spans = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            i = src.index("*/", i) + 2
        elif src.startswith('"""', i):
            i = src.index('"""', i + 3) + 3
        elif src.startswith('#"', i):
            i = src.index('"#', i + 2) + 2
        elif src[i] == '"':
            i = skip_string(src, i, spans, 0)
        else:
            i += 1
    return spans

def key_of(literal):
    """The lookup key of a literal: interpolations as %@, escapes resolved"""
    body = literal[1:-1]
    out, k = [], 0
    while k < len(body):
        ch = body[k]
        if ch == "\\":
            nxt = body[k + 1]
            if nxt == "(":
                level, k = 1, k + 2
                while level:
                    c = body[k]
                    if c == '"':
                        spans = []
                        k = skip_string(body, k, spans, 1)
                        continue
                    level += c == "("
                    level -= c == ")"
                    k += 1
                out.append("%@")
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(nxt, nxt))
            k += 2
            continue
        out.append(ch)
        k += 1
    return "".join(out)
