#!/usr/bin/env python3
"""Inventory every key mapping this config defines: document them, find conflicts.

    scripts/keymaps.py                      # conflict report
    scripts/keymaps.py --doc                # write docs/keymaps{,-by-plugin}.md
    scripts/keymaps.py --json x.json        # save the raw inventory
    scripts/keymaps.py --inventory x.json   # reuse one, without booting
    scripts/keymaps.py --self-test          # prove conflict detection works

Exit status: 0 nothing wrong, 1 conflicts found, 2 the tool could not run (or
could not trust itself).

The inventory comes from a real boot with scripts/keymap_inventory.lua loaded
via --cmd, so every mapping is seen *as it is created*: mappings made inside
plugins (mini.surround's `sa`, mini.move's arrows) are included, which no
static scan of this repo can manage, and two places claiming one key are still
two records rather than one survivor.

Neovim runs against a *copy* of the repo, never the repo itself: lazy.nvim
writes lazy-lock.json into stdpath('config') and would rewrite the committed
file (see scripts/nvim-sandbox.sh for the same dance).

Why the canaries below exist: attributing a mapping to the wrong stack frame is
a silent failure. Every mapping ends up owned by one bogus owner, every key has
exactly one owner, and the report cheerfully says "no conflicts" forever. That
bug happened during development and was invisible until conflicts were planted
on purpose, so this script refuses to report anything unless it can still see
one mapping of each attribution class -- and --self-test plants real conflicts
end to end.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# One known mapping per attribution class. If any of these stops being found,
# extraction is broken (or the mapping was renamed) and a clean report is a lie.
CANARIES = {
    "config": ("n", "<Space>qq"),  # vim.keymap.set in lua/config/keymaps.lua
    "spec": ("n", "<Space>ff"),  # a lazy.nvim `keys` spec (telescope)
    "plugin": ("n", "sa"),  # created inside mini.surround
}

# Mappings where a shorter key is deliberately a prefix of a longer one, so
# pressing the short one waits for 'timeoutlen'. These are the idioms this
# config has chosen on purpose; anything else is worth a second look.
PREFIX_ALLOW = {
    ("n", "gc"),  # mini.comments operator vs gcc (comment line)
    ("x", "gc"),
    ("o", "gc"),
    ("n", "sa"),  # mini.surround operators vs their suffixed forms
    ("n", "sd"),
    ("n", "sf"),
    ("n", "sF"),
    ("n", "sh"),
    ("n", "sr"),
    ("n", "sn"),
    ("x", "sa"),
    ("n", "g"),
    ("n", "z"),
    ("n", "<Space>"),  # the leader itself, mapped to <Nop> in config/globals.lua
    ("x", "<Space>"),
    ("s", "<Space>"),
}

MODE_EXPAND = {
    "": ("n", "i", "v", "x", "s", "o", "t", "c"),
    " ": ("n", "i", "v", "x", "s", "o", "t", "c"),
    "v": ("x", "s"),
    "!": ("i", "c"),
}

MODE_LABEL = {
    "n": "normal",
    "i": "insert",
    "v": "visual + select",
    "x": "visual",
    "s": "select",
    "o": "operator-pending",
    "t": "terminal",
    "c": "command-line",
}

TOKEN = re.compile(r"<[^<>]+>|.", re.S)

# Plumbing, not keys a human presses: plugins define <Plug>(...) targets to be
# referenced by other mappings. Counting them as mappings or as conflicts is
# noise either way.
INTERNAL = re.compile(r"^<(Plug|SNR|ScriptCmd)")


def die(message):
    """Fail in a way that cannot be mistaken for a clean report."""
    sys.stderr.write("keymaps: " + message + "\n")
    raise SystemExit(2)


def tokens(key):
    """Split a canonical key into keystrokes: '<Space>ff' -> ['<Space>','f','f']."""
    return TOKEN.findall(key)


def concrete_modes(mode):
    return MODE_EXPAND.get(mode, (mode,))


# --- collecting -----------------------------------------------------------


def collect(nvim, timeout, wait_ms, plant=None, keep=None):
    """Boot a copy of the repo with the dumper loaded and return its JSON."""
    tmp = tempfile.mkdtemp(prefix="keymaps-")
    try:
        cfg = os.path.join(tmp, "cfg")
        config_dir = os.path.join(cfg, "nvim")
        os.makedirs(cfg)
        shutil.copytree(ROOT, config_dir, ignore=shutil.ignore_patterns(".git"))

        if plant:
            # Append to the copy, so the planted conflicts travel the same path
            # as real ones: parsed by Lua, created by vim.keymap.set, attributed
            # by the stack walk.
            target = os.path.join(config_dir, "lua", "config", "keymaps.lua")
            with open(target, "a", encoding="utf-8") as fh:
                fh.write("\n-- planted by scripts/keymaps.py --self-test\n")
                fh.write("\n".join(plant) + "\n")

        out = os.path.join(tmp, "inventory.json")
        env = dict(
            os.environ,
            XDG_CONFIG_HOME=cfg,
            KEYMAP_OUT=out,
            KEYMAP_WAIT_MS=str(wait_ms),
        )
        shim = os.path.join(config_dir, "scripts", "keymap_inventory.lua")
        try:
            proc = subprocess.run(
                [nvim, "--headless", "--cmd", "luafile " + shim],
                env=env, capture_output=True, text=True, timeout=timeout,
            )
        except FileNotFoundError:
            die("%s not found; cannot read the mappings" % nvim)
        except subprocess.TimeoutExpired:
            die("%s timed out after %ss (a first run may install plugins; retry)"
                % (nvim, timeout))

        if not os.path.exists(out):
            sys.stderr.write((proc.stderr or "")[-2000:] + "\n")
            die("the dumper wrote no inventory (Neovim output above)")
        with open(out, encoding="utf-8") as fh:
            payload = json.load(fh)
        if keep:
            shutil.copyfile(out, keep)
        return payload
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --- the inventory --------------------------------------------------------


class Mapping:
    __slots__ = ("mode", "key", "lhs", "desc", "owner", "owner_kind", "buffer", "rhs")

    def __init__(self, mode, key, lhs, desc, owner, owner_kind, buffer, rhs):
        self.mode = mode
        self.key = key
        self.lhs = lhs
        self.desc = desc
        self.owner = owner
        self.owner_kind = owner_kind
        self.buffer = buffer
        self.rhs = rhs


def internal(key):
    return bool(INTERNAL.match(key or ""))


def build(payload):
    """Resolve every logged set call to an owner."""
    # lazy.nvim creates both the lazy-load trigger and the post-load mapping
    # from its own handler, so without this index every lazy key is owned by
    # "lazy.nvim" -- and a global map colliding with a plugin's lazy key, the
    # most likely conflict of all, is invisible.
    spec_owner = {}
    for spec in payload.get("lazy_keys", []):
        for mode in concrete_modes(spec.get("mode") or "n"):
            spec_owner[(mode, spec.get("key"))] = spec.get("plugin")

    maps = []
    for entry in payload.get("log", []):
        if internal(entry.get("key")):
            continue
        kind = entry.get("src_kind")
        if kind == "lazy-handler":
            plugin = None
            for mode in concrete_modes(entry["mode"]):
                plugin = spec_owner.get((mode, entry["key"]))
                if plugin:
                    break
            owner = "spec:" + plugin if plugin else "lazy.nvim"
            owner_kind = "spec" if plugin else "lazy"
        elif kind == "config":
            owner = "config:%s:%s" % (entry["src_id"], entry.get("src_line", 0))
            owner_kind = "config"
        elif kind == "plugin":
            owner = "plugin:" + entry["src_id"]
            owner_kind = "plugin"
        else:
            owner = "%s:%s" % (kind, entry["src_id"])
            owner_kind = kind or "unknown"
        maps.append(Mapping(
            mode=entry["mode"], key=entry["key"], lhs=entry.get("lhs"),
            desc=entry.get("desc"), owner=owner, owner_kind=owner_kind,
            buffer=entry.get("buffer"), rhs=entry.get("rhs"),
        ))
    return maps


def check_canaries(maps):
    """Refuse to report anything if attribution has quietly broken."""
    missing = []
    for kind, (mode, key) in sorted(CANARIES.items()):
        if not any(m.owner_kind == kind and m.mode == mode and m.key == key for m in maps):
            missing.append("%s (expected %s %s)" % (kind, mode, key))
    if missing:
        die("attribution canaries not found: %s\n"
            "       Either the stack-walk attribution broke (most likely -- every\n"
            "       mapping then gets one bogus owner and no conflict can ever be\n"
            "       reported), or these mappings moved. If they moved, update\n"
            "       CANARIES at the top of this script.\n"
            "       Refusing to report a result either way." % "; ".join(missing))


# --- conflicts ------------------------------------------------------------


class Finding:
    def __init__(self, tier, kind, mode, key, detail):
        self.tier = tier
        self.kind = kind
        self.mode = mode
        self.key = key
        self.detail = detail

    def line(self):
        return "  %-5s %-6s %-24s %s" % (self.tier, self.mode, self.key, self.detail)


def analyse(payload, maps):
    findings = []
    globals_ = [m for m in maps if not m.buffer]

    # 1. Two owners for one key, in a mode where both apply: whichever runs
    #    last silently wins, and which that is depends on load order.
    claims = {}
    for m in globals_:
        for mode in concrete_modes(m.mode):
            claims.setdefault((mode, m.key), {}).setdefault(m.owner, m)
    for (mode, key), owners in sorted(claims.items()):
        if len(owners) > 1:
            findings.append(Finding(
                "ERROR", "duplicate", mode, key,
                "claimed by " + "  ||  ".join(sorted(owners)),
            ))

    # 2. A shorter mapping that is a prefix of a longer one: pressing it waits
    #    for 'timeoutlen'. Often deliberate (gc/gcc), hence PREFIX_ALLOW.
    by_mode = {}
    for (mode, key) in claims:
        by_mode.setdefault(mode, set()).add(key)
    for mode, keys in sorted(by_mode.items()):
        toks = {k: tokens(k) for k in keys}
        for short in sorted(keys):
            if (mode, short) in PREFIX_ALLOW or len(toks[short]) == 0:
                continue
            mine = set(claims[(mode, short)])
            longer = [k for k in keys
                      if k != short and toks[k][:len(toks[short])] == toks[short]
                      and not (set(claims[(mode, k)]) & mine)]
            if longer:
                findings.append(Finding(
                    "warn", "prefix", mode, short,
                    "waits for timeoutlen; prefix of " + ", ".join(sorted(longer)[:4])
                    + (" (+%d more)" % (len(longer) - 4) if len(longer) > 4 else "")
                    + "  [" + ", ".join(sorted(mine)) + "]",
                ))

    # 3. Overriding a Neovim default is normal and intentional here, but worth
    #    listing: it is how `K`, `gd` and friends change meaning.
    defaults = {(d["mode"], d["key"]) for d in payload.get("defaults", [])}
    for (mode, key), owners in sorted(claims.items()):
        if (mode, key) in defaults:
            config_owners = sorted(o for o in owners if o.startswith("config:"))
            if config_owners:
                findings.append(Finding(
                    "info", "override-default", mode, key,
                    "replaces a Neovim default: " + ", ".join(config_owners),
                ))

    # 4. A buffer-local mapping over a global one: the deliberate way bitbake
    #    takes `gf` and the quickfix takes `<`/`>`.
    global_keys = set(claims)
    for m in maps:
        if not m.buffer:
            continue
        for mode in concrete_modes(m.mode):
            if (mode, m.key) in global_keys:
                findings.append(Finding(
                    "info", "buffer-shadow", mode, m.key,
                    "buffer-local (%s) shadows the global mapping" % m.owner,
                ))
                break

    buf_claims = {}
    for m in maps:
        if m.buffer:
            for mode in concrete_modes(m.mode):
                buf_claims.setdefault((mode, m.key), set()).add(m.owner)
    for (mode, key), owners in sorted(buf_claims.items()):
        if len(owners) > 1:
            findings.append(Finding(
                "info", "buffer-duplicate", mode, key,
                "two buffer-local owners: " + "  ||  ".join(sorted(owners)),
            ))

    # 6. Coverage. A mapping present after boot that was never seen being
    #    created came from somewhere these wrappers cannot watch -- a vimscript
    #    `:map`, or a runtime plugin such as matchit. That is a statement about
    #    this tool's reach, not a problem with the config, so it is info.
    accounted = set(claims) | {(mode, m.key) for m in maps if m.buffer
                               for mode in concrete_modes(m.mode)}
    accounted |= {(mode, d["key"]) for d in payload.get("defaults", [])
                  for mode in concrete_modes(d["mode"])}
    for entry in payload.get("final", []):
        key = entry.get("key", "?")
        if internal(key):
            continue
        if not any((mode, key) in accounted for mode in concrete_modes(entry.get("mode", "?"))):
            findings.append(Finding(
                "info", "unattributed", entry.get("mode", "?"), key,
                "present after boot but never seen being set (vimscript `:map`?)",
            ))
    for note in payload.get("notes", []):
        findings.append(Finding("warn", "dump", "-", "-", note))
    for name in payload.get("probes_failed", []):
        findings.append(Finding("warn", "probe", "-", name,
                                "could not open a buffer of this filetype"))

    # The same fact can be recorded once per probed buffer (which-key maps the
    # leader buffer-locally wherever it pops up). Report it once.
    unique, seen_findings = [], set()
    for finding in findings:
        token = (finding.tier, finding.kind, finding.mode, finding.key, finding.detail)
        if token not in seen_findings:
            seen_findings.add(token)
            unique.append(finding)
    return unique


# --- the document ---------------------------------------------------------


def group_of(mapping):
    """Bucket a mapping for the generated document."""
    if mapping.buffer:
        return "buffer"
    toks = tokens(mapping.key)
    if toks and toks[0] == "<Space>":
        if len(toks) == 1:
            return "other:the leader key"
        return "leader:" + toks[1]
    return "other:" + MODE_LABEL.get(mapping.mode, mapping.mode)


def code_span(text):
    """Wrap a key in a code span that survives backticks and table pipes."""
    text = (text or "").replace("|", "&#124;")
    if "`" in text:
        return "<code>%s</code>" % text.replace("&", "&amp;").replace(
            "<", "&lt;").replace(">", "&gt;")
    return "`%s`" % text


def md_escape(text):
    return (text or "").replace("|", "&#124;").replace("<", "&lt;").replace(">", "&gt;")


def render_doc(payload, maps, findings):
    by_key = {}
    for m in maps:
        by_key.setdefault((m.buffer is not None, m.mode, m.key), []).append(m)

    lines = []
    lines.append("# Key mappings")
    lines.append("")
    lines.append("<!-- Generated by scripts/keymaps.py --doc. Do not edit by hand. -->")
    lines.append("")
    lines.append("Every mapping this config creates, recorded during a real headless boot")
    lines.append("(`scripts/keymap_inventory.lua`) rather than read out of the source, so")
    lines.append("mappings made inside plugins are included too. Group *names* are not")
    lines.append("repeated here -- README.md is where the groups are described and why.")
    lines.append("")
    lines.append("Sorted by key. For the same mappings grouped by what they belong to, see")
    lines.append("[keymaps-by-plugin.md](keymaps-by-plugin.md).")
    lines.append("")
    lines.append("Run `scripts/keymaps.py` to check for conflicts, `--doc` to regenerate")
    lines.append("both files.")
    lines.append("")

    n_global = len({k for k in by_key if not k[0]})
    n_buffer = len({k for k in by_key if k[0]})
    no_desc = sum(1 for ms in by_key.values() if not any(m.desc for m in ms))
    lines.append("| | |")
    lines.append("|---|---|")
    lines.append("| Mappings (global, distinct key + mode) | %d |" % n_global)
    lines.append("| Mappings (buffer-local, distinct key + mode) | %d |" % n_buffer)
    lines.append("| Without a description | %d |" % no_desc)
    lines.append("| Neovim version | %s |" % md_escape(payload.get("nvim", "?")))
    lines.append("")

    def table(entries):
        rows = ["| Key | Mode | Description | Defined in |", "|---|---|---|---|"]
        for (is_buf, mode, key) in sorted(entries, key=lambda e: (e[2].lower(), e[1])):
            ms = by_key[(is_buf, mode, key)]
            desc = next((m.desc for m in ms if m.desc), "")
            written = next((m.lhs for m in ms if m.lhs), key)
            owners = sorted({m.owner for m in ms})
            rows.append("| %s | %s | %s | %s |" % (
                code_span(written), MODE_LABEL.get(mode, mode),
                md_escape(desc), ", ".join("`%s`" % o for o in owners),
            ))
        return rows

    buckets = {}
    for keyid in by_key:
        bucket = group_of(by_key[keyid][0])
        buckets.setdefault(bucket, []).append(keyid)

    leader = sorted(b for b in buckets if b.startswith("leader:"))
    other = sorted(b for b in buckets if b.startswith("other:"))

    if leader:
        lines.append("## Leader mappings")
        lines.append("")
        for bucket in leader:
            lines.append("### `<leader>%s`" % bucket.split(":", 1)[1])
            lines.append("")
            lines.extend(table(buckets[bucket]))
            lines.append("")

    if other:
        lines.append("## Non-leader mappings")
        lines.append("")
        for bucket in other:
            lines.append("### %s" % bucket.split(":", 1)[1])
            lines.append("")
            lines.extend(table(buckets[bucket]))
            lines.append("")

    if "buffer" in buckets:
        lines.append("## Buffer-local mappings")
        lines.append("")
        lines.append("Created when a buffer qualifies -- an LSP client attaching, a filetype,")
        lines.append("a quickfix window -- so they exist only there.")
        lines.append("")
        lines.extend(table(buckets["buffer"]))
        lines.append("")

    undocumented = sorted(
        (next((m.lhs for m in ms if m.lhs), key), MODE_LABEL.get(mode, mode))
        for (is_buf, mode, key), ms in by_key.items() if not any(m.desc for m in ms)
    )
    if undocumented:
        lines.append("## Mappings with no description")
        lines.append("")
        lines.append("These show as a blank entry in which-key and in the tables above.")
        lines.append("")
        for written, mode in undocumented:
            lines.append("- %s (%s)" % (code_span(written), mode))
        lines.append("")

    lines.append("## Coverage")
    lines.append("")
    probed = payload.get("buffers_probed", [])
    if probed:
        lines.append("Buffer contexts probed: " + ", ".join(
            "`%s`%s" % (p.get("ft") or p.get("requested"),
                        " (" + ", ".join(p["clients"]) + ")" if p.get("clients") else "")
            for p in probed) + ".")
        lines.append("")
    unloaded = payload.get("unloaded_plugins", [])
    if unloaded:
        lines.append("Plugins that could not be loaded in a headless boot, whose mappings are")
        lines.append("therefore absent: " + ", ".join("`%s`" % p for p in unloaded) + ".")
        lines.append("")
    lines.append("Buffer-local LSP mappings exist only where a server attaches, so this file")
    lines.append("reflects the environment it was generated in (NixOS-provided servers vs the")
    lines.append("dev container's mason ones). It is generated, but deliberately not")
    lines.append("staleness-checked for that reason.")
    lines.append("")
    lines.append("Not covered: mappings that exist only inside a plugin's own window")
    lines.append("(Telescope pickers, Neo-tree, Diffview panels) unless that window was")
    lines.append("probed above, and anything a plugin maps lazily on an event this boot")
    lines.append("never triggered.")
    lines.append("")
    problems = [f for f in findings if f.tier != "info"]
    lines.append("At generation time: %d conflict(s), %d warning(s)." % (
        sum(1 for f in findings if f.tier == "ERROR"),
        sum(1 for f in problems if f.tier == "warn"),
    ))
    lines.append("")
    return "\n".join(lines)


# --- the per-plugin document ---------------------------------------------

REPO_LITERAL = re.compile(r'"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"')


def spec_file_plugins(known):
    """lua/plugins/<x>.lua -> the plugin names that file declares.

    Read from the repo strings in the file, kept honest by intersecting with
    the plugin names lazy actually resolved. A file naming exactly one known
    plugin is attributed to it, so the mappings smart-splits.nvim sets from its
    own `config` function land in its section rather than in a file section.

    Where a file declares several plugins -- usually because its dependencies
    live in the same spec -- no attempt is made to guess which spec block a
    given line sits in. Knowing that needs real Lua parsing, and guessing it
    would put mappings under the wrong plugin, so those files stay as their own
    section with the plugins they configure named.
    """
    index = {}
    plugins_dir = os.path.join(ROOT, "lua", "plugins")
    if not os.path.isdir(plugins_dir):
        return index
    for name in sorted(os.listdir(plugins_dir)):
        if not name.endswith(".lua"):
            continue
        path = os.path.join(plugins_dir, name)
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        found = []
        for repo in REPO_LITERAL.findall(text):
            plugin = repo.split("/")[-1]
            if plugin in known and plugin not in found:
                found.append(plugin)
        index["lua/plugins/" + name] = found
    return index


def plugin_group(mapping, file_index):
    """(sort bucket, section title, note) for the per-plugin document."""
    if mapping.owner_kind in ("spec", "plugin"):
        return ("plugin", mapping.owner.split(":", 1)[1], None)
    if mapping.owner_kind == "config":
        source = mapping.owner.split(":", 1)[1].rsplit(":", 1)[0]
        declared = file_index.get(source)
        if declared is not None:
            if len(declared) == 1:
                return ("plugin", declared[0], None)
            return ("multi", source,
                    "configures " + ", ".join("`%s`" % d for d in declared)
                    if declared else "declares no plugin this tool could resolve")
        return ("config", source, None)
    if mapping.owner_kind == "runtime":
        return ("runtime", "Neovim runtime: " + mapping.owner.split(":", 1)[1], None)
    return ("other", mapping.owner, None)


def render_by_plugin(payload, maps):
    known = {p["name"] for p in payload.get("plugins", [])}
    known |= {p.get("dir") for p in payload.get("plugins", []) if p.get("dir")}
    file_index = spec_file_plugins(known)

    sections = {}
    notes = {}
    for mapping in maps:
        bucket, title, note = plugin_group(mapping, file_index)
        sections.setdefault((bucket, title), {}).setdefault(
            (mapping.buffer is not None, mapping.mode, mapping.key), []).append(mapping)
        if note:
            notes[(bucket, title)] = note

    lines = []
    lines.append("# Key mappings by plugin")
    lines.append("")
    lines.append("<!-- Generated by scripts/keymaps.py --doc. Do not edit by hand. -->")
    lines.append("")
    lines.append("The same mappings as [keymaps.md](keymaps.md), grouped by what they belong")
    lines.append("to instead of by key. Each plugin's section holds both the keys declared in")
    lines.append("its lazy.nvim `keys` spec and the ones it creates itself when it loads, so")
    lines.append("`mini.surround` lists `sa` even though nothing in this repo writes that key.")
    lines.append("")
    lines.append("Attribution is recorded during a real boot, from the file and line that")
    lines.append("created each mapping -- see [keymaps.md](keymaps.md) for how.")
    lines.append("")

    def table(entries):
        rows = ["| Key | Mode | Description | Defined in |", "|---|---|---|---|"]
        for (is_buf, mode, key) in sorted(entries, key=lambda e: (e[2].lower(), e[1])):
            ms = entries[(is_buf, mode, key)]
            desc = next((m.desc for m in ms if m.desc), "")
            written = next((m.lhs for m in ms if m.lhs), key)
            owners = sorted({m.owner for m in ms})
            rows.append("| %s | %s%s | %s | %s |" % (
                code_span(written), MODE_LABEL.get(mode, mode),
                ", buffer-local" if is_buf else "",
                md_escape(desc), ", ".join("`%s`" % o for o in owners),
            ))
        return rows

    def emit(bucket, heading, blurb=None):
        titles = sorted((t for (b, t) in sections if b == bucket), key=str.lower)
        if not titles:
            return
        lines.append("## " + heading)
        lines.append("")
        if blurb:
            lines.append(blurb)
            lines.append("")
        for title in titles:
            entries = sections[(bucket, title)]
            lines.append("### `%s`" % title)
            lines.append("")
            note = notes.get((bucket, title))
            if note:
                lines.append(note[0].upper() + note[1:] + ". Which spec block a given")
                lines.append("line belongs to is not something this tool infers.")
                lines.append("")
            lines.extend(table(entries))
            lines.append("")

    emit("plugin", "Plugins")
    emit("config", "Set by this config",
         "Set from a file that is not a plugin spec, so not tied to one plugin.")
    emit("multi", "Spec files configuring several plugins")
    emit("runtime", "Neovim itself",
         "Shipped with Neovim, not by this config -- listed so nothing is unaccounted for.")
    emit("other", "Unclassified")

    mapped = {t for (b, t) in sections if b == "plugin"}
    # A plugin configured by a spec file that configures several plugins cannot
    # be claimed to define no mappings: a mapping in that file may well be
    # its own, and which spec block a line sits in is not inferred here.
    ambiguous = set()
    for (bucket, title) in sections:
        if bucket == "multi":
            ambiguous.update(file_index.get(title) or [])
    silent = sorted((p["name"] for p in payload.get("plugins", [])
                     if p["name"] not in mapped and p.get("dir") not in mapped
                     and p["name"] not in ambiguous and p.get("dir") not in ambiguous),
                    key=str.lower)
    if silent:
        lines.append("## Plugins that define no mappings")
        lines.append("")
        lines.append("Listed so the plugin set is accounted for. Plugins configured by one of")
        lines.append("the multi-plugin spec files above are left out: a mapping in such a file")
        lines.append("may belong to any of them, and this tool does not guess which.")
        lines.append("")
        lines.append(", ".join("`%s`" % p for p in silent) + ".")
        lines.append("")
    return "\n".join(lines)


# --- self-test ------------------------------------------------------------

PLANT = [
    'vim.keymap.set("n", "<leader>ff", "<cmd>echo 1<cr>", { desc = "planted: vs lazy spec" })',
    'vim.keymap.set("n", "sa", "<cmd>echo 2<cr>", { desc = "planted: vs plugin-created" })',
    'vim.keymap.set("n", "<leader>bn", "<cmd>echo 3<cr>", { desc = "planted: vs config" })',
    'vim.keymap.set("n", "<leader>q", "<cmd>echo 4<cr>", { desc = "planted: prefix of <leader>qq" })',
]

EXPECT = [
    ("duplicate", "n", "<Space>ff", "spec:telescope.nvim"),
    ("duplicate", "n", "sa", "plugin:mini.surround"),
    ("duplicate", "n", "<Space>bn", "config:lua/config/keymaps.lua"),
    ("prefix", "n", "<Space>q", None),
]


def self_test(nvim, timeout, wait_ms):
    """Plant conflicts and insist they are all found.

    A conflict detector that has never caught one is indistinguishable from a
    detector that cannot. This plants one of every class -- against a lazy key
    spec, against a mapping created inside a plugin, against another config
    mapping, and a prefix collision -- and fails if any goes unreported.
    """
    print("self-test: booting a copy with %d planted conflicts..." % len(PLANT))
    payload = collect(nvim, timeout, wait_ms, plant=PLANT)
    maps = build(payload)
    check_canaries(maps)
    findings = analyse(payload, maps)

    ok = True
    for kind, mode, key, needle in EXPECT:
        hits = [f for f in findings
                if f.kind == kind and f.mode == mode and f.key == key
                and (needle is None or needle in f.detail)]
        status = "found" if hits else "MISSED"
        if not hits:
            ok = False
        print("  %-9s %-6s %-14s %s%s" % (
            kind, mode, key, status,
            "" if not hits else "  <- " + hits[0].detail[:70]))
    if not ok:
        die("self-test failed: planted conflicts went unreported, so a clean\n"
            "       report from this tool means nothing. Fix detection first.")
    print("self-test: all %d planted conflicts detected" % len(EXPECT))
    return 0


# --- cli ------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--nvim", default="nvim", help="Neovim binary to boot with")
    ap.add_argument("--timeout", type=int, default=300, help="seconds to allow it")
    ap.add_argument("--wait-ms", type=int, default=9000,
                    help="ms to let the config settle before dumping")
    ap.add_argument("--doc", nargs="?", const=os.path.join(ROOT, "docs", "keymaps.md"),
                    default=None, metavar="PATH", help="write the mapping document")
    ap.add_argument("--json", metavar="PATH", default=None, help="save the raw inventory")
    ap.add_argument("--inventory", metavar="PATH", default=None,
                    help="read a saved inventory instead of booting Neovim")
    ap.add_argument("--self-test", action="store_true",
                    help="plant conflicts and verify they are detected")
    ap.add_argument("--quiet", action="store_true", help="only report problems")
    args = ap.parse_args()

    if args.self_test:
        return self_test(args.nvim, args.timeout, args.wait_ms)

    if args.inventory:
        try:
            with open(args.inventory, encoding="utf-8") as fh:
                payload = json.load(fh)
        except (OSError, ValueError) as exc:
            die("cannot read %s: %s" % (args.inventory, exc))
    else:
        payload = collect(args.nvim, args.timeout, args.wait_ms, keep=args.json)
    maps = build(payload)
    check_canaries(maps)
    findings = analyse(payload, maps)

    if args.doc:
        os.makedirs(os.path.dirname(args.doc), exist_ok=True)
        stem, ext = os.path.splitext(args.doc)
        for path, text in (
            (args.doc, render_doc(payload, maps, findings)),
            (stem + "-by-plugin" + ext, render_by_plugin(payload, maps)),
        ):
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            print("wrote %s" % os.path.relpath(path, ROOT))

    globals_ = {(mode, m.key) for m in maps if not m.buffer
                for mode in concrete_modes(m.mode)}
    buffer_local = {(m.mode, m.key, m.owner) for m in maps if m.buffer}
    errors = [f for f in findings if f.tier == "ERROR"]
    warns = [f for f in findings if f.tier == "warn"]
    infos = [f for f in findings if f.tier == "info"]

    if not args.quiet:
        print("mappings: %d global, %d buffer-local   conflicts: %d   warnings: %d"
              % (len(globals_), len(buffer_local), len(errors), len(warns)))
    for finding in errors + warns + ([] if args.quiet else infos):
        print(finding.line())
    return 1 if errors else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
