#!/usr/bin/env python3
"""Check that every mapping this config defines is named in README.md.

Exit status: 0 all documented, 1 some undocumented, 2 the audit could not run.

    python3 scripts/audit_keymaps.py
    python3 scripts/audit_keymaps.py --inventory inv.json   # reuse a dump

The mappings come from scripts/keymaps.py, which records them during a real
boot (see scripts/keymap_inventory.lua). This script used to find them two
other ways, and both under-reported:

  * A regex over `vim.keymap.set("mode", "lhs", ...)` calls. It cannot see a
    mapping defined through an alias or a helper -- `local map = vim.keymap.set`
    in config/yocto.lua, `local function map(keys, ...)` in config/lsp.lua --
    and this config defines 45 mappings that way. They were silently exempt
    from this check.
  * `plugin.keys` read from lazy's plugin table, which returns only the last
    spec fragment's list.

Before that it used a regex over `keys = {` blocks, which stopped at the first
nested entry and reported "all documented" while missing several keys. That is
the failure this script exists to prevent, which is why it still refuses to
report success unless the canaries below are found.

Only mappings this config *authors* are audited -- its own `vim.keymap.set`
calls and its lazy `keys` specs. Mappings created inside a plugin (mini.surround
binding `sa` from its own options) are in docs/keymaps.md but are not something
README.md is expected to list key by key.
"""

import argparse
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# If any of these is missing from the authored set, extraction is broken and a
# clean report would be a lie. One from a lazy `keys` spec, one from a spec
# entry that is not its block's first, one from a plain vim.keymap.set, and one
# defined through a local alias (the class the old regex could not see).
CANARIES = ("<leader>xq", "<leader>xl", "<leader>ff", "<leader>qq", "<leader>yb")


def die(message):
    """Fail in a way that cannot be mistaken for a clean audit."""
    sys.stderr.write("audit: " + message + "\n")
    raise SystemExit(2)


def load_keymaps_module():
    sys.dont_write_bytecode = True
    path = os.path.join(HERE, "keymaps.py")
    spec = importlib.util.spec_from_file_location("keymaps_inventory_driver", path)
    if spec is None or spec.loader is None:
        die("cannot load %s" % path)
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as exc:  # noqa: BLE001 - any failure here is fatal anyway
        die("cannot load %s: %s" % (path, exc))
    return module


def authored_mappings(args):
    """lhs -> set of owners, for every mapping this config defines itself."""
    km = load_keymaps_module()
    if args.inventory:
        try:
            with open(args.inventory, encoding="utf-8") as fh:
                payload = json.load(fh)
        except (OSError, ValueError) as exc:
            die("cannot read %s: %s" % (args.inventory, exc))
    else:
        payload = km.collect(args.nvim, args.timeout, args.wait_ms)

    maps = km.build(payload)
    km.check_canaries(maps)

    found = {}
    for mapping in maps:
        if mapping.owner_kind in ("config", "spec"):
            found.setdefault(mapping.lhs or mapping.key, set()).add(mapping.owner)
    return found


def documented_keys(readme):
    """Every key the README names, with its grouped shorthands expanded."""
    raw = open(readme, encoding="utf-8").read()
    spans = set(m.group(1).strip() for m in re.finditer(r"`([^`]+)`", raw))
    spans |= set(m.group(1).strip() for m in re.finditer(r"<code>(.+?)</code>", raw))
    doc = set()
    for span in spans:
        span = span.replace("&lt;", "<").replace("&gt;", ">").replace("&#124;", "|")
        doc.add(span.lower())
        # <M-S-Left/Right/Up/Down> and <leader>w<Left/Right/Up/Down>
        m = re.match(r"^(.*?)<([A-Za-z0-9]+(?:-[A-Za-z0-9]+)*)((?:/[A-Za-z0-9]+)+)>$", span)
        if m:
            prefix, first, rest = m.groups()
            head = re.match(r"^((?:[A-Za-z0-9]+-)*)", first).group(1)
            for opt in [first] + [head + x for x in rest.strip("/").split("/")]:
                doc.add(("%s<%s>" % (prefix, opt)).lower())
        for part in re.split(r"\s+/\s+", span):  # "`a` / `b`" inside one span
            doc.add(part.strip().lower())
    return doc


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--nvim", default="nvim", help="Neovim binary to dump with")
    ap.add_argument("--timeout", type=int, default=300, help="seconds to allow it")
    ap.add_argument("--wait-ms", type=int, default=9000,
                    help="ms to let the config settle before dumping")
    ap.add_argument("--inventory", metavar="PATH", default=None,
                    help="read a saved inventory instead of booting Neovim")
    args = ap.parse_args()

    defined = authored_mappings(args)

    absent = [c for c in CANARIES if c not in defined]
    if absent:
        die("expected mappings not found: %s\n"
            "       Either extraction broke (most likely) or these keys were renamed.\n"
            "       If they were renamed, update CANARIES at the top of this script.\n"
            "       Refusing to report a result either way." % ", ".join(absent))

    doc = documented_keys(os.path.join(ROOT, "README.md"))
    missing = sorted(k for k in defined if k.lower() not in doc)
    print("mappings defined: %d   documented: %d   undocumented: %d"
          % (len(defined), len(defined) - len(missing), len(missing)))
    for key in missing:
        print("  %-18s %s" % (key, ", ".join(sorted(defined[key]))))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
