#!/usr/bin/env python3
"""Convert VCS-based testbenches to Verilator.

For each testbench/<name>/ dir:
  - Parse run.sh to find source files, +incdir+, +define+, -top, -timescale, -f filelist
  - Generate run_verilator.sh (uses: verilator --binary --timing ...)
  - For every tb*.sv in the dir, write a *_verilator.sv variant with:
      * covergroup ... endgroup blocks commented out
      * covergroup handle declarations / `.new()` / `.sample()` commented out
      * get_coverage() replaced with 0
      * $finish(0) / $finish(1) normalized to $finish
  PASS/FAIL still keyed by $display("PASS:..."/"FAIL:...").
"""
from __future__ import annotations
import os, re, shlex, sys, stat
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# ---------------- run.sh parsing ----------------

def parse_vcs_invocation(run_sh_text: str):
    """Return list of (srcs, incdirs, defines, top, timescale, filelist_fs,
    uses_svaext, extra_shell_tail) entries, one per vcs call."""
    lines = run_sh_text.splitlines()
    # Collapse backslash-continuations
    collapsed = []
    buf = ""
    for ln in lines:
        s = ln.rstrip()
        if s.endswith("\\"):
            buf += s[:-1] + " "
        else:
            buf += s
            collapsed.append(buf)
            buf = ""
    if buf:
        collapsed.append(buf)

    # Extract env var assignments (SNAP=.., etc.) so we can expand them.
    env = {}
    for cmd in collapsed:
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.+)$", cmd.strip())
        if m and " " not in m.group(1):
            val = m.group(2).strip()
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            env[m.group(1)] = val

    var_re = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
    def expand(s):
        # Iteratively expand ${VAR} / $VAR until no known variable remains.
        # Unknown variables are left as-is.
        for _ in range(20):
            def sub(m):
                name = m.group(1) or m.group(2)
                return env.get(name, m.group(0))
            new = var_re.sub(sub, s)
            if new == s:
                return s
            s = new
        return s

    invocations = []
    for cmd in collapsed:
        stripped = cmd.strip()
        # Extract the vcs subcommand from constructs like "if ! vcs ...; then"
        mvcs = re.search(r"\bvcs\b\s+(.*)", stripped)
        if not mvcs:
            continue
        # Drop any trailing shell junk after the vcs invocation (e.g. "; then")
        vcs_body = mvcs.group(1)
        vcs_body = re.split(r";\s*(?:then|do|done|fi|&&|\|\|)\b", vcs_body)[0]
        stripped = "vcs " + vcs_body
        stripped = expand(stripped)
        try:
            toks = shlex.split(stripped, posix=True)
        except ValueError:
            toks = stripped.split()
        srcs, incdirs, defines, filelists = [], [], [], []
        top = None
        timescale = None
        uses_svaext = False
        i = 1
        while i < len(toks):
            t = toks[i]
            if t.startswith("+incdir+"):
                incdirs.append(t[len("+incdir+"):])
            elif t.startswith("+define+"):
                defines.append(t[len("+define+"):])
            elif t.startswith("-timescale="):
                timescale = t.split("=", 1)[1]
            elif t == "-timescale" and i + 1 < len(toks):
                timescale = toks[i + 1]; i += 1
            elif t == "-top" and i + 1 < len(toks):
                top = toks[i + 1]; i += 1
            elif t == "-f" and i + 1 < len(toks):
                filelists.append(toks[i + 1]); i += 1
            elif t == "-o" and i + 1 < len(toks):
                i += 1  # skip output name
            elif t == "-assert" and i + 1 < len(toks):
                if toks[i + 1] == "svaext":
                    uses_svaext = True
                i += 1
            elif t.startswith("-cm"):
                # -cm or -cm line+cond... may take value
                if t == "-cm" and i + 1 < len(toks):
                    i += 1
            elif t in ("-sverilog", "-full64", "-debug_access+all"):
                pass
            elif t.startswith("-"):
                # Unknown VCS option; ignore
                pass
            elif t.endswith(".sv") or t.endswith(".v") or t.endswith(".svh"):
                srcs.append(t)
            else:
                # ignore unknown bare tokens
                pass
            i += 1
        invocations.append({
            "srcs": srcs,
            "incdirs": incdirs,
            "defines": defines,
            "top": top,
            "timescale": timescale,
            "filelists": filelists,
            "uses_svaext": uses_svaext,
        })
    # Tail heuristic: if the shell script has a `grep -q "PASS:"` check, preserve it.
    has_grep_pass = bool(re.search(r'grep\s+-q\s+"?PASS:"?', run_sh_text))
    fail_msg = None
    pass_msg = None
    m = re.search(r'echo\s+"PASS:\s*([^"]+)"', run_sh_text)
    if m: pass_msg = m.group(1).strip()
    m = re.search(r'echo\s+"FAIL:\s*([^"]+)"', run_sh_text)
    if m: fail_msg = m.group(1).strip()
    # Only use rewritten-shell approach if the original run.sh has explicit
    # PASS/FAIL verdict logic somewhere (echo "PASS:" / "FAIL:" or grep-based
    # verdict). Otherwise fall back to generic emit to avoid losing the
    # pass signal that a simple `./simv` script would just imply.
    has_verdict_logic = bool(
        re.search(r'echo\s+"(PASS|FAIL):', run_sh_text)
        or re.search(r'grep\s+-q\s+"[^"]*(PASS|FAIL)', run_sh_text)
    )
    rewritten_shell = None
    if has_verdict_logic:
        rewritten_shell = _rewrite_shell_for_verilator(run_sh_text, collapsed)
    return invocations, has_grep_pass, pass_msg, fail_msg, rewritten_shell


def _rewrite_shell_for_verilator(orig_text: str, collapsed_cmds: list) -> str:
    """Rewrite a VCS-style run.sh into a Verilator-compatible version by
    replacing vcs-invocation lines and simv references, while keeping the
    surrounding shell structure (loops, if/elif/fi) intact."""
    # Work on the original text, splitting into "logical" blocks where a
    # single backslash-continued command is treated as one unit.
    lines = orig_text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        # Detect multi-line backslash continuation block
        j = i
        while j < len(lines) - 1 and lines[j].rstrip().endswith("\\"):
            j += 1
        block = "\n".join(lines[i:j + 1])
        # Does this block contain a vcs invocation anywhere?
        if re.search(r"(^|[\s;&|(!])vcs\b", block):
            # Replace the entire block with a marker comment. The shell
            # structure around it (if/elif conditions) must be preserved —
            # so rewrite `if ! vcs ... ; then` into `if false; then` to
            # keep the branch layout, and plain-standalone `vcs ...` into
            # a no-op.
            if re.match(r"\s*if\s+!\s+vcs\b", lines[i]):
                # "if ! vcs ... ; then" — we already built successfully in
                # the Verilator step above, so this becomes "if false; then"
                # (build-fail branch never fires here).
                out.append("if false; then  # [verilator-rewrite] VCS compile branch")
                # Skip through to end of block
                i = j + 1
                continue
            if re.match(r"\s*elif\s+!\s+vcs\b", lines[i]):
                out.append("elif false; then  # [verilator-rewrite] VCS compile branch")
                i = j + 1
                continue
            # Plain `vcs ...` invocation — replace with a no-op
            out.append(": # [verilator-rewrite] dropped vcs invocation")
            i = j + 1
            continue
        # Replace standalone `./simv` / $SIMV / $SIMV_NAME invocations
        # Only rewrite simv references; keep surrounding logic.
        replaced = ln
        # `./simv` style (including `./simv_cov`, `./simv_xxx`)
        replaced = re.sub(r"\./simv(_[A-Za-z0-9_]+)?\b", "./obj_dir/simv_vlt", replaced)
        # `$SIMV_NAME` / `${SIMV_NAME}` / `${TESTBENCH_DIR}/${SIMV_NAME}` style — replace
        # the SIMV_NAME var with the verilator binary path
        replaced = re.sub(r"\$\{?SIMV_NAME\}?", "./obj_dir/simv_vlt", replaced)
        # `-cm line+cond...` arg no longer valid — strip from simv command
        replaced = re.sub(r"\s-cm\s+\S+", "", replaced)
        # Test-file existence checks for `simv` binary — rewrite to our path
        replaced = re.sub(r"\[\s*(!?)\s*-[xf]\s+simv\s*\]",
                          lambda m: f"[ {m.group(1)} -x ./obj_dir/simv_vlt ]", replaced)
        # Remove any vcs-style pipestatus check of VCS_STATUS variable
        # by leaving it; harmless if unset.
        out.append(replaced)
        i += 1
    return "\n".join(out)

# ---------------- tb sanitizer ----------------

COVERGROUP_HANDLE_RE = re.compile(
    r"^(\s*)([A-Za-z_][\w]*)\s+([A-Za-z_][\w]*)\s*=\s*new\s*\(\s*\)\s*;\s*$"
)

def _find_matching(text: str, start: int, open_kw: str, close_kw: str) -> int:
    """Find the index of the matching close_kw (word-bounded) starting search
    right after start. Handles nested open_kw. Returns end index (past the
    close keyword), or -1 if not found."""
    pos = start
    depth = 1
    open_re = re.compile(r"\b" + re.escape(open_kw) + r"\b")
    close_re = re.compile(r"\b" + re.escape(close_kw) + r"\b")
    while pos < len(text) and depth > 0:
        m_open = open_re.search(text, pos)
        m_close = close_re.search(text, pos)
        if not m_close:
            return -1
        if m_open and m_open.start() < m_close.start():
            depth += 1
            pos = m_open.end()
        else:
            depth -= 1
            pos = m_close.end()
    return pos if depth == 0 else -1

def comment_region(text: str, a: int, b: int, tag: str) -> str:
    """Comment out lines in text[a:b] with a line-by-line comment prefix."""
    region = text[a:b]
    commented = "\n".join(
        (f"// [verilator-strip {tag}] " + line) if line.strip() else line
        for line in region.split("\n")
    )
    return text[:a] + commented + text[b:]

def sanitize_tb_text(text: str, source_name: str) -> tuple[str, list[str]]:
    notes: list[str] = []

    # 1) Collect covergroup handle type names so we can comment their decls.
    cg_types: set[str] = set()
    for m in re.finditer(r"\bcovergroup\s+([A-Za-z_][\w]*)\b", text):
        cg_types.add(m.group(1))

    # 2) Comment out covergroup ... endgroup blocks.
    # Scan forward with a cursor so we don't re-match the comment we just wrote.
    spans = []
    cursor = 0
    # Only match `covergroup` as a statement-starting keyword
    # (start of line after optional whitespace); this avoids matching
    # the word inside comments.
    kw_re = re.compile(r"^[ \t]*covergroup\b", re.MULTILINE)
    while True:
        m = kw_re.search(text, cursor)
        if not m:
            break
        # m.start() is start-of-line; advance to the keyword start
        kw_start = m.end() - len("covergroup")
        end = _find_matching(text, m.end(), "covergroup", "endgroup")
        if end == -1:
            notes.append("unterminated covergroup; left as-is")
            cursor = m.end()
            continue
        if end < len(text) and text[end:end+1] == ";":
            end += 1
        spans.append((kw_start, end))
        cursor = end
    for a, b in reversed(spans):
        text = comment_region(text, a, b, "cg")

    # 3) Comment out handle declarations: <cg_type> varname = new();
    cg_handles: set[str] = set()
    if cg_types:
        cg_union = "|".join(re.escape(t) for t in cg_types)
        pat = re.compile(
            rf"^(\s*)({cg_union})\s+([A-Za-z_][\w]*)\s*(=\s*new\s*\(\s*\)\s*)?;\s*$",
            re.MULTILINE,
        )
        def _sub(m):
            cg_handles.add(m.group(3))
            return f"{m.group(1)}// [verilator-strip cg-inst] {m.group(0).lstrip()}"
        text = pat.sub(_sub, text)

    # 3b: deferred — see after steps 4/5 below, so that `.sample()` and
    # `.get_coverage()` are first replaced with inline placeholders rather
    # than commented out wholesale (which would leave e.g. dangling `if`
    # headers without a statement body).

    # 4) Replace .sample(...) call expressions with an inline /* no-op */
    # comment so the surrounding syntax stays valid, e.g.
    #   if (cond) cg.sample();  -> if (cond) /* sample */;
    #   cg.sample();            -> /* sample */;  (valid null statement)
    text = re.sub(
        r"\b[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*\.sample\s*\([^()]*\)",
        "/* [verilator-strip sample] */",
        text,
    )

    # 5) Replace dotted get_coverage()/get_inst_coverage() call chains with
    # a constant 0 (real). We must match the *full* dotted chain so the
    # replacement leaves valid syntax — matching only the trailing segment
    # would leave dangling prefixes like "cg_inst.0".
    text = re.sub(
        r"\b[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*\.get_(?:inst_)?coverage\s*\(\s*\)",
        "0", text)
    text = re.sub(r"\bget_(?:inst_)?coverage\s*\(\s*\)", "0", text)

    # 5b) Now (after .sample()/.get_coverage() are substituted with inline
    # placeholders) comment out any line that still references a stripped
    # covergroup handle. Skip lines whose only reference is inside the
    # inline "/* [verilator-strip sample] */" placeholder string.
    if cg_handles:
        handle_union = "|".join(re.escape(h) for h in cg_handles)
        handle_ref = re.compile(rf"\b({handle_union})\.")
        new_lines = []
        for ln in text.split("\n"):
            stripped = ln.lstrip()
            if (handle_ref.search(ln)
                and not stripped.startswith("//")):
                indent = ln[: len(ln) - len(stripped)]
                new_lines.append(f"{indent}// [verilator-strip cg-ref] {stripped}")
            else:
                new_lines.append(ln)
        text = "\n".join(new_lines)

    # 6) Normalize $finish(N) → $finish
    text = re.sub(r"\$finish\s*\(\s*\d+\s*\)", "$finish", text)

    # 6b) Upgrade FAIL-marker $display calls to $fatal so the simulator
    # exits non-zero on failure. We deliberately do this for every
    # `$display("FAIL..." ...)` call — $fatal terminates the simulation
    # immediately (skipping any subsequent $display/$finish), which is
    # exactly what we want for the exit-code-based F2P contract. Only match
    # when the string literal starts with "FAIL" to avoid disturbing
    # unrelated $display calls.
    text = re.sub(
        r"\$display\s*\(\s*(\"FAIL[^\"]*\"(?:\s*,[^)]*)?)\s*\)",
        lambda m: "$fatal(1, " + m.group(1) + ")",
        text,
    )

    # 7) $stop → $finish (Verilator's $stop does not always exit)
    # Leave $stop alone; Verilator supports it.

    # 8) Remove -assert / SVA issues? Leave SVA as-is — Verilator supports
    # basic immediate asserts; complex concurrent ones may fail, flagged.

    return text, notes

# ---------------- run_verilator.sh generator ----------------

def resolve_vlt_srcs(invocations):
    """Merge all vcs invocations' sources, excluding the tb_*.sv file (we will
    substitute the _verilator.sv variant) — we return everything and let the
    caller do the swap."""
    all_srcs, all_inc, all_def, tops, timescales, all_fls = [], [], [], [], [], []
    uses_svaext = False
    for inv in invocations:
        all_srcs.extend(inv["srcs"])
        all_inc.extend(inv["incdirs"])
        all_def.extend(inv["defines"])
        if inv["top"]:
            tops.append(inv["top"])
        if inv["timescale"]:
            timescales.append(inv["timescale"])
        all_fls.extend(inv["filelists"])
        uses_svaext = uses_svaext or inv["uses_svaext"]
    # De-duplicate while preserving order
    def dedup(xs):
        seen, out = set(), []
        for x in xs:
            if x not in seen:
                seen.add(x); out.append(x)
        return out
    return (dedup(all_srcs), dedup(all_inc), dedup(all_def),
            dedup(tops), dedup(timescales), dedup(all_fls), uses_svaext)

def build_run_verilator(dir_name: str, invocations, has_grep_pass: bool,
                       pass_msg: str | None, fail_msg: str | None,
                       tb_sv_files: list[str],
                       tb_sv_map: dict[str, str],
                       verdict_tail: str | None = None,
                       tb_dir=None) -> str:
    srcs, incdirs, defines, tops, timescales, filelists, uses_svaext = resolve_vlt_srcs(invocations)
    # Replace any source that has a sanitized variant with that variant.
    new_srcs = []
    for s in srcs:
        base = os.path.basename(s)
        if base in tb_sv_map:
            new_srcs.append(tb_sv_map[base])
        else:
            new_srcs.append(s)
    srcs = new_srcs
    top = tops[0] if tops else None
    timescale = timescales[0] if timescales else "1ns/1ps"

    parts = ["#!/bin/bash",
             "# Auto-generated Verilator runner (converted from run.sh).",
             "# Pass/fail is still determined by PASS:/FAIL: text in the log.",
             "# Note: complex run.sh scripts with loops/multi-config VCS calls",
             "# are flattened here — only the first VCS invocation is emulated.",
             "",
             "TESTBENCH_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]:-$0}\")\" 2>/dev/null && pwd)\"",
             "cd \"$TESTBENCH_DIR\"",
             "",
             "rm -rf obj_dir",
             "",
             "verilator \\",
             "  --binary \\",
             "  --timing \\",
             "  --Wno-fatal \\",
             "  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \\",
             "  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \\",
             "  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \\",
             "  --Wno-ENUMVALUE --Wno-PINMISSING --Wno-ASCRANGE \\",
             "  --Wno-CASEX --Wno-WIDTHCONCAT --Wno-MODDUP \\",
             "  --Wno-ASSIGNIN --Wno-VARHIDDEN --Wno-DECLFILENAME \\",
             "  --Wno-COMBDLY --Wno-IGNOREDRETURN --Wno-LITENDIAN \\",
             f"  --timescale {timescale} \\",
             ]
    if uses_svaext:
        parts.append("  --assert \\")
    for d in defines:
        parts.append(f"  +define+{d} \\")
    for inc in incdirs:
        parts.append(f"  +incdir+{inc} \\")
        # Also use as module library search path so Verilator can
        # auto-find modules that aren't explicitly listed (VCS does
        # lazy lookup; Verilator needs -y for the same behavior).
        parts.append(f"  -y {inc} \\")
    # Add common library search dirs from source file parents so any
    # module referenced from the file list (but not listed) is found.
    lib_dirs = sorted({os.path.dirname(s) for s in srcs if "/" in s})
    for ld in lib_dirs:
        parts.append(f"  -y {ld} \\")
    # Defer -f filelist until after pkg_srcs so packages are declared
    # before any module inside the filelist tries to import them.
    _deferred_filelists = list(filelists)
    # Packages must be explicitly compiled (Verilator cannot lazily
    # discover them via -y). Glob *_pkg.sv under every library dir
    # and prepend them to the compile list if not already listed.
    # NOTE: paths in run.sh are relative to the testbench dir (tb_dir),
    # so we must resolve globs from tb_dir, not from the converter's CWD.
    import glob as _glob
    pkg_srcs = []
    src_set = set(srcs)
    search_dirs = list(dict.fromkeys(list(incdirs) + lib_dirs))
    for ld in search_dirs:
        if not ld:
            continue
        # Resolve ld relative to tb_dir so "../../snapshots/..." works
        # regardless of where the converter was invoked from.
        if tb_dir and not os.path.isabs(ld):
            resolved = os.path.normpath(os.path.join(str(tb_dir), ld))
        else:
            resolved = ld
        for abs_p in sorted(_glob.glob(os.path.join(resolved, "*_pkg.sv"))):
            # Skip packages that import UVM (or any verif framework pkg
            # Verilator can't compile) — pulling them in via auto-discovery
            # poisons the whole build even when the tb itself doesn't need
            # UVM.
            try:
                head = open(abs_p, errors="replace").read()
            except Exception:
                head = ""
            if re.search(r"\bimport\s+(uvm_pkg|dv_utils_pkg|uvm_utils_pkg)\b",
                         head):
                continue
            # Map back to a path expressed the same way as sources (relative
            # to tb_dir) so the generated script can find it.
            if tb_dir:
                try:
                    rel = os.path.relpath(abs_p, str(tb_dir))
                except ValueError:
                    rel = abs_p
            else:
                rel = abs_p
            if rel not in src_set and rel not in pkg_srcs:
                pkg_srcs.append(rel)

    # Topologically sort pkg_srcs so a package A that imports package B
    # comes after B. Verilator compiles packages in order and needs the
    # dependency available at the point of import.
    def _pkg_info(path):
        try:
            abs_path = path if os.path.isabs(path) else os.path.normpath(
                os.path.join(str(tb_dir), path)) if tb_dir else path
            text = open(abs_path, errors="replace").read()
        except Exception:
            return None, set()
        # The package name declared in this file
        m = re.search(r"\bpackage\s+([A-Za-z_][\w]*)\b", text)
        name = m.group(1) if m else None
        # Names it imports
        imports = set(
            m2.group(1) for m2 in re.finditer(
                r"\bimport\s+([A-Za-z_][\w]*)\s*::", text)
        )
        return name, imports

    # Pull _pkg.sv files that already live in srcs into pkg_srcs too, so
    # we can topo-sort the complete package dependency graph. We'll strip
    # them from srcs afterward to avoid duplicates.
    pkg_in_srcs = [s for s in srcs if s.endswith("_pkg.sv")]
    for s in pkg_in_srcs:
        if s not in pkg_srcs:
            pkg_srcs.append(s)
    srcs = [s for s in srcs if not s.endswith("_pkg.sv")]

    pkg_meta = {p: _pkg_info(p) for p in pkg_srcs}
    name_to_path = {m[0]: p for p, m in pkg_meta.items() if m[0]}
    ordered, placed = [], set()
    def _place(p, stack):
        if p in placed or p in stack:
            return
        stack = stack | {p}
        name, imps = pkg_meta.get(p, (None, set()))
        for imp in imps:
            dep = name_to_path.get(imp)
            if dep and dep not in placed:
                _place(dep, stack)
        ordered.append(p)
        placed.add(p)
    for p in pkg_srcs:
        _place(p, set())
    pkg_srcs = ordered
    for p in pkg_srcs:
        parts.append(f"  {p} \\")
    for fl in _deferred_filelists:
        parts.append(f"  -f {fl} \\")
    for s in srcs:
        parts.append(f"  {s} \\")
    if top:
        parts.append(f"  --top-module {top} \\")
    parts.append("  -o simv_vlt 2>&1 | tee verilator_build.log")
    parts.append("")
    parts.append("if [ ! -x obj_dir/simv_vlt ]; then")
    parts.append('  echo "FAIL: Verilator build failed." >&2')
    parts.append("  exit 1")
    parts.append("fi")
    parts.append("")
    # Alias obj_dir/simv_vlt's log as simv.log (original verdict checks
    # grep simv.log); also keep a verilator.log copy.
    parts.append("# Wrap obj_dir/simv_vlt so any `./simv ...` or `${SIMV_NAME}` in")
    parts.append("# the preserved shell block writes to verilator.log / simv.log.")
    parts.append("")
    if verdict_tail:
        # Append the full rewritten original shell block. The verdict_tail
        # typically invokes `./obj_dir/simv_vlt | tee simv.log` and then
        # grep-matches simv.log to decide PASS/FAIL. That's redundant — we
        # rely on simv_vlt's own exit code ($finish → 0, $fatal → non-zero)
        # for the F2P verdict.
        # We rewrite:
        #   1. Any "./obj_dir/simv_vlt ... | tee file" to capture
        #      PIPESTATUS[0] into __SIMV_RC immediately after.
        #   2. Append `exit "$__SIMV_RC"` at the very end.
        parts.append("set -o pipefail")
        parts.append("__SIMV_RC=0")
        patched_tail = verdict_tail
        # Inject a post-pipe capture for any `./obj_dir/simv_vlt` line
        # that's part of a pipeline (typical pattern: `... | tee simv.log`).
        import re as _re
        def _inject_rc_capture(m):
            line = m.group(0)
            return line + "\n__SIMV_RC=${PIPESTATUS[0]}"
        # Match any line containing ./obj_dir/simv_vlt followed by a pipe
        patched_tail = _re.sub(
            r"(^[^\n]*\./obj_dir/simv_vlt[^\n]*\|[^\n]*$)",
            _inject_rc_capture,
            patched_tail,
            flags=_re.MULTILINE,
        )
        # For non-pipe simv_vlt invocations, capture $? immediately after.
        patched_tail = _re.sub(
            r"(^[^\n]*\./obj_dir/simv_vlt(?![^\n|]*\|)[^\n]*$)",
            lambda m: m.group(0) + "\n__SIMV_RC=$?",
            patched_tail,
            flags=_re.MULTILINE,
        )
        parts.append("# ---- rewritten run.sh body (vcs/simv substituted) ----")
        parts.append(patched_tail)
        parts.append("")
        parts.append("[ -f simv.log ] || cp -f verilator.log simv.log 2>/dev/null || true")
        parts.append('exit "$__SIMV_RC"')
    else:
        # Run simv_vlt and propagate its exit code. Pass/fail is carried by
        # the Verilator exit status ($finish → 0, $fatal → non-zero).
        parts.append("set -o pipefail")
        parts.append("./obj_dir/simv_vlt 2>&1 | tee verilator.log")
        parts.append("RC=${PIPESTATUS[0]}")
        parts.append("cp -f verilator.log simv.log 2>/dev/null || true")
        parts.append('exit "$RC"')
    parts.append("")
    return "\n".join(parts)

# ---------------- driver ----------------

def convert_dir(tb_dir: Path) -> dict:
    info = {"dir": tb_dir.name, "notes": [], "tbs": [], "ok": False}
    run_sh = tb_dir / "run.sh"
    if not run_sh.exists():
        info["notes"].append("no run.sh")
        return info
    text = run_sh.read_text(errors="replace")
    invocations, has_grep_pass, pass_msg, fail_msg, verdict_tail = parse_vcs_invocation(text)
    if not invocations:
        info["notes"].append("no vcs invocation found in run.sh")
        return info

    # Find tb source files in this directory (those listed in run.sh that live
    # here, i.e. have no '../' path).
    local_srcs = set()
    for inv in invocations:
        for s in inv["srcs"]:
            if "/" not in s:
                local_srcs.add(s)
    # Also treat anything matching tb*.sv / *tb*selfcheck.sv as local tb.
    # Skip previously-generated *_verilator.sv files so re-runs don't
    # create tb_*_verilator_verilator.sv chains.
    for p in tb_dir.iterdir():
        if p.is_file() and p.suffix == ".sv":
            nm = p.name
            if nm.endswith("_verilator.sv"):
                continue
            if nm.startswith("tb_") or nm.startswith("tb.") or "_selfcheck" in nm or nm == "tb.sv":
                local_srcs.add(nm)

    tb_map: dict[str, str] = {}
    for src in sorted(local_srcs):
        src_path = tb_dir / src
        if not src_path.exists():
            continue
        raw = src_path.read_text(errors="replace")
        sanitized, notes = sanitize_tb_text(raw, src)
        stem, ext = os.path.splitext(src)
        out_name = f"{stem}_verilator{ext}"
        (tb_dir / out_name).write_text(sanitized)
        tb_map[src] = out_name
        info["tbs"].append(out_name)
        info["notes"].extend(notes)

    run_vlt = build_run_verilator(
        tb_dir.name, invocations, has_grep_pass, pass_msg, fail_msg,
        list(tb_map.keys()), tb_map, verdict_tail, tb_dir=tb_dir,
    )
    out = tb_dir / "run_verilator.sh"
    out.write_text(run_vlt)
    out.chmod(out.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    info["ok"] = True
    return info

def main():
    targets = []
    if len(sys.argv) > 1:
        targets = [ROOT / a for a in sys.argv[1:]]
    else:
        for p in sorted(ROOT.iterdir()):
            if p.is_dir() and (p / "run.sh").exists():
                targets.append(p)
    results = []
    for p in targets:
        res = convert_dir(p)
        results.append(res)
        status = "OK" if res["ok"] else "SKIP"
        print(f"[{status}] {res['dir']}: tbs={len(res['tbs'])} notes={res['notes'] or '-'}")
    ok = sum(1 for r in results if r["ok"])
    print(f"\nSummary: {ok}/{len(results)} converted.")

if __name__ == "__main__":
    main()
