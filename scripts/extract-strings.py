#!/usr/bin/env python3
"""Extracts every interface string from L("en", "it") calls in Sources/ as templates.

Interpolations become numbered placeholders ({0}, {1}, ...), exactly like `LText` builds them at runtime, so the
translation tables in Sources/NexoLLM/Localization/ can be checked against the code.

    scripts/extract-strings.py   -> JSON list of {"en": ..., "it": ..., "file": ...} on stdout
    (scripts/gen-strings.py uses it to build and check the Spanish, French, German and Portuguese tables.)
"""
import json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "Sources", "NexoLLM")


def parse_literal(s, i):
    """Parses a Swift string literal starting at s[i] == '"'. Returns (template, end_index)."""
    assert s[i] == '"'
    i += 1
    out, n = [], 0
    while i < len(s):
        c = s[i]
        if c == '"':
            return "".join(out), i + 1
        if c == "\\":
            nx = s[i + 1]
            if nx == "(":
                # Interpolation: skip to the matching parenthesis (strings inside are skipped whole).
                depth, j = 1, i + 2
                while depth:
                    if s[j] == '"':
                        _, j = parse_literal(s, j)
                        continue
                    if s[j] == "(":
                        depth += 1
                    elif s[j] == ")":
                        depth -= 1
                    j += 1
                out.append("{%d}" % n)
                n += 1
                i = j
                continue
            if nx == "u":
                m = re.match(r"\\u\{([0-9a-fA-F]+)\}", s[i:])
                out.append(chr(int(m.group(1), 16)))
                i += len(m.group(0))
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}[nx])
            i += 2
            continue
        out.append(c)
        i += 1
    raise ValueError("unterminated literal")


def skip_ws(s, i):
    while i < len(s) and s[i] in " \t\r\n":
        i += 1
    return i


def extract():
    pairs, seen = [], set()
    for dirpath, _, files in os.walk(SRC):
        for f in sorted(files):
            if not f.endswith(".swift") or dirpath.endswith("Localization"):
                continue
            s = open(os.path.join(dirpath, f), encoding="utf-8").read()
            for m in re.finditer(r"(?<![A-Za-z0-9_.])L\(", s):
                i = skip_ws(s, m.end())
                if i >= len(s) or s[i] != '"':
                    continue
                try:
                    en, i = parse_literal(s, i)
                    i = skip_ws(s, i)
                    if s[i] != ",":
                        continue
                    i = skip_ws(s, i + 1)
                    if s[i] != '"':
                        continue
                    it, _ = parse_literal(s, i)
                except Exception:
                    continue
                if en not in seen:
                    seen.add(en)
                    pairs.append({"en": en, "it": it, "file": f})
    return pairs


if __name__ == "__main__":
    json.dump(extract(), sys.stdout, ensure_ascii=False, indent=1)
