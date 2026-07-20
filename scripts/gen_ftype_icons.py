#!/usr/bin/env python3
"""Generate a nvim-web-devicons override from DEV-TOOLS-DES-0004 §2-32.

Parses the icon-rules AsciiDoc and emits lua/utils/ftype_icons.lua with
`by_extension` and `by_filename` glyph maps. Re-run when the spec changes:

    python3 scripts/gen_ftype_icons.py

Scope: exact-filename tables (§7-12, parts of §24-32) and extension tables
(§13-32). Directory rules (§4-6), special/generic objects (§2-3), and
content/MIME detection (§40-41) are out of scope for a static devicons map.
"""
import re
import sys
import pathlib

ADOC = pathlib.Path("DEV-TOOLS-DES-0004-icon-rules.adoc")
OUT = pathlib.Path("lua/utils/ftype_icons.lua")

# Only the type-icon rule groups carry filename/extension -> glyph mappings.
INCLUDE_SECTIONS = set(range(7, 33))  # §7 .. §32


def glyph_of(cell: str):
    for ch in cell:
        if ord(ch) >= 0xE000:
            return ch
    return None


def classify(tok: str, default_mode: str):
    tok = tok.strip()
    if not tok:
        return None
    if tok.startswith("*."):
        return ("ext", tok[2:].lower())
    if tok.startswith("."):
        if default_mode == "file":
            return ("file", tok)              # dotfile is a filename (§46)
        return ("ext", tok[1:].lower())       # simple or compound extension
    if "*" in tok:
        return None                           # glob filename pattern; skip
    if tok.endswith(".*"):
        return ("file", tok[:-2])             # README.* -> README
    if default_mode == "ext":
        return ("ext", tok.lower())
    return ("file", tok)                       # exact filename (case kept)


def iter_tables(text):
    """Yield (section_num, header_cols, data_rows) for each table."""
    section = None
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^===?\s+(\d+)\.", lines[i])
        if m:
            section = int(m.group(1))
        if lines[i].strip() == "|===":
            rows = []
            i += 1
            while i < len(lines) and lines[i].strip() != "|===":
                if lines[i].lstrip().startswith("|"):
                    rows.append(lines[i])
                i += 1
            if rows:
                header = [c.strip() for c in rows[0].split("|")[1:]]
                yield section, header, rows[1:]
        i += 1


FOLDER_LABELS = {
    "Directory": "closed",
    "Open directory": "open",
    "Empty directory": "empty",
}


def main():
    text = ADOC.read_text(encoding="utf-8")
    by_ext, by_file, by_dir, folder = {}, {}, {}, {}
    stats = {"ext": 0, "file": 0, "dir": 0, "skipped_rows": 0}

    for section, header, rows in iter_tables(text):
        col1 = header[0] if header else ""

        # §2 generic folder glyphs (closed / open / empty).
        if section == 2:
            for row in rows:
                cols = row.split("|")[1:]
                if len(cols) < 2:
                    continue
                label = cols[0].strip()
                g = glyph_of(cols[1])
                if g and label in FOLDER_LABELS:
                    folder[FOLDER_LABELS[label]] = g
            continue

        # §4-6 directory-name glyphs.
        if section in (4, 5, 6):
            for row in rows:
                cols = row.split("|")[1:]
                if len(cols) < 2:
                    continue
                g = glyph_of(cols[1])
                if not g:
                    continue
                toks = re.findall(r"`([^`]+)`", cols[0])
                if not toks:
                    plain = cols[0].strip()
                    if plain:
                        toks = [plain]
                for tok in toks:
                    by_dir.setdefault(tok.lower(), g)
                    stats["dir"] += 1
            continue

        if section not in INCLUDE_SECTIONS:
            continue
        if "Directory" in col1:
            continue
        if "Extension" in col1 and "ilename" not in col1 and "ames" not in col1:
            mode = "ext"
        elif "Filename" in col1 and "xtension" not in col1:
            mode = "file"
        else:
            mode = "mixed"  # per-token decision

        for row in rows:
            cols = row.split("|")[1:]
            if len(cols) < 2:
                continue
            g = glyph_of(cols[1])
            if not g:
                stats["skipped_rows"] += 1
                continue
            for tok in re.findall(r"`([^`]+)`", cols[0]):
                res = classify(tok, mode)
                if not res:
                    continue
                kind, key = res
                if kind == "ext":
                    by_ext.setdefault(key, g)
                    stats["ext"] += 1
                else:
                    by_file.setdefault(key, g)
                    stats["file"] += 1

    def emit(tbl):
        out = []
        for k in sorted(tbl):
            out.append(f'\t\t["{k}"] = "{tbl[k]}",')
        return "\n".join(out)

    def emit_flat(tbl):
        return "\n".join(f'\t\t{k} = "{tbl[k]}",' for k in sorted(tbl))

    lua = (
        "-- GENERATED by scripts/gen_ftype_icons.py from DEV-TOOLS-DES-0004.\n"
        "-- Do not edit by hand; re-run the generator to refresh.\n"
        "--\n"
        "-- Primary file-type glyphs (§7-32) plus generic folder glyphs (§2)\n"
        "-- and directory-name glyphs (§4-6). Applied to nvim-web-devicons\n"
        "-- (lua/plugins/devicons.lua), neo-tree folders/directories, and\n"
        "-- mini.icons; colors are left to the theme (§89).\n"
        "return {\n"
        "\tby_extension = {\n" + emit(by_ext) + "\n\t},\n"
        "\tby_filename = {\n" + emit(by_file) + "\n\t},\n"
        "\tby_directory = {\n" + emit(by_dir) + "\n\t},\n"
        "\tfolder = {\n" + emit_flat(folder) + "\n\t},\n"
        "}\n"
    )
    OUT.write_text(lua, encoding="utf-8")
    print(f"wrote {OUT}: {len(by_ext)} extensions, {len(by_file)} filenames, "
          f"{len(by_dir)} directories, {len(folder)} folder glyphs "
          f"({stats['skipped_rows']} rows had no glyph)")


if __name__ == "__main__":
    main()
