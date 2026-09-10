#!/usr/bin/env python3
"""Check that every mapping this config defines is named in README.md.

Exit status: 0 all documented, 1 some undocumented, 2 the audit could not run.

Mappings come from two places, and both are read the reliable way rather than
by pattern-matching Lua:

  * lazy.nvim `keys = { ... }` specs are dumped from the *live* plugin table by
    a headless Neovim, so lazy's own parser decides what a key spec is. Reading
    them out of the source text looks easy and is not: an earlier version of
    this check used a regex over `keys = {` blocks, stopped at the first nested
    entry, and quietly reported "all documented" while missing several keys.
    That is the failure this script exists to prevent, so it refuses to report
    success unless the canaries below are found.
  * `vim.keymap.set("mode", "lhs", ...)` calls, which are regular enough in
    this tree to match directly.

Neovim is run against a *copy* of the repo, never the repo itself: lazy writes
lazy-lock.json into stdpath('config') and would rewrite the committed file.
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

# If any of these is missing from the extracted set, extraction is broken and
# a clean report would be a lie. One from a lazy `keys` spec, one from a
# vim.keymap.set call, one from a spec entry that is not the block's first.
CANARIES = ("<leader>xq", "<leader>xl", "<leader>ff", "<leader>qq")

LUA_DUMP = r"""
local ok, config = pcall(require, "lazy.core.config")
if not ok then
  io.stderr:write("<<KEYS>>\n<<END>>\n")
  vim.cmd("qa!")
  return
end
local out = {}
for name, plugin in pairs(config.plugins) do
  for _, key in ipairs(plugin.keys or {}) do
    local lhs = type(key) == "string" and key or key[1]
    if lhs then
      out[#out + 1] = lhs .. "\t" .. name
    end
  end
end
table.sort(out)
io.stderr:write("<<KEYS>>\n" .. table.concat(out, "\n") .. "\n<<END>>\n")
vim.cmd("qa!")
"""

def die(message):
    """Fail in a way that cannot be mistaken for a clean audit."""
    sys.stderr.write("audit: " + message + "\n")
    raise SystemExit(2)


SETCALL = re.compile(r'vim\.keymap\.set\(\s*(?:\{[^}]*\}|"[^"]*")\s*,\s*"((?:[^"\\]|\\.)*)"')


def lazy_keys(root, nvim, timeout):
    """lhs -> plugin name, straight from lazy's parsed plugin table."""
    tmp = tempfile.mkdtemp(prefix="audit-keymaps-")
    try:
        cfg = os.path.join(tmp, "cfg")
        os.makedirs(cfg)
        shutil.copytree(root, os.path.join(cfg, "nvim"), ignore=shutil.ignore_patterns(".git"))
        dump = os.path.join(tmp, "dump.lua")
        with open(dump, "w", encoding="utf-8") as fh:
            fh.write(LUA_DUMP)
        env = dict(os.environ, XDG_CONFIG_HOME=cfg)
        try:
            proc = subprocess.run(
                [nvim, "--headless", "-c", "luafile " + dump],
                env=env, capture_output=True, text=True, timeout=timeout,
            )
        except FileNotFoundError:
            die("%s not found; cannot read the lazy key specs" % nvim)
        except subprocess.TimeoutExpired:
            die("%s timed out after %ss (first run installs plugins; retry)" % (nvim, timeout))
        body = re.search(r"<<KEYS>>\n(.*?)\n?<<END>>", proc.stderr, re.S)
        if not body:
            sys.stderr.write(proc.stderr[-2000:] + "\n")
            die("no key dump in Neovim's output (see above)")
        found = {}
        for line in body.group(1).splitlines():
            lhs, _, who = line.partition("\t")
            if lhs:
                found.setdefault(lhs, set()).add(who)
        return found
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--nvim", default="nvim", help="Neovim binary to dump specs with")
    ap.add_argument("--timeout", type=int, default=300, help="seconds to allow it")
    args = ap.parse_args()

    defined = lazy_keys(root, args.nvim, args.timeout)
    for path in sorted(glob.glob(os.path.join(root, "lua/**/*.lua"), recursive=True)
                       + [os.path.join(root, "init.lua")]):
        rel = os.path.relpath(path, root)
        for m in SETCALL.finditer(open(path, encoding="utf-8").read()):
            defined.setdefault(m.group(1), set()).add(rel)

    absent = [c for c in CANARIES if c not in defined]
    if absent:
        die("expected mappings not found: %s\n"
            "       Either extraction broke (most likely) or these keys were renamed.\n"
            "       If they were renamed, update CANARIES at the top of this script.\n"
            "       Refusing to report a result either way." % ", ".join(absent))

    doc = documented_keys(os.path.join(root, "README.md"))
    missing = sorted(k for k in defined if k.lower() not in doc)
    print("mappings defined: %d   documented: %d   undocumented: %d"
          % (len(defined), len(defined) - len(missing), len(missing)))
    for key in missing:
        print("  %-18s %s" % (key, ", ".join(sorted(defined[key]))))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
