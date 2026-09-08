#!/usr/bin/env python3
"""
The manifest-driven installer engine.

Walks manifest.toml and applies each row. Install, dry-run, uninstall, verify
and status all derive from the same table, so they cannot drift apart, and
adding a config layer is a row in the manifest rather than new code here.

Backup semantics matter and are easy to get wrong. The engine writes an
`original/` backup exactly once, on the first install, and never overwrites it.
Uninstall restores from `original/`. The obvious alternative — restore from the
most recent backup — strands anyone who installs twice and uninstalls once in
the state that existed *after* their first install, which is not where they
started and not anywhere they asked to be.

Usage:
    engine.py install   --repo DIR [--profile full] [--dry-run]
    engine.py uninstall --repo DIR [--dry-run]
    engine.py verify    --repo DIR [--profile full]
    engine.py status    --repo DIR [--profile full]
"""
import argparse
import configparser
import filecmp
import json
import os
import shlex
import shutil
import subprocess
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jsonmerge import merge_owned  # noqa: E402
from manifest import load, select  # noqa: E402
from paths import expand_dest  # noqa: E402
from textblock import inject, strip  # noqa: E402

MARK_BEGIN = "/* >>> openagentisland >>> */"
MARK_END = "/* <<< openagentisland <<< */"
# Lua and ini files cannot carry C comments, so the fence is rewritten per
# comment syntax. The marker text is identical so it is still greppable.
COMMENT_STYLE = {
    ".lua": ("-- >>> openagentisland >>>", "-- <<< openagentisland <<<"),
    ".conf": ("# >>> openagentisland >>>", "# <<< openagentisland <<<"),
}

if sys.stdout.isatty():
    DIM, BOLD, RESET = "\033[2m", "\033[1m", "\033[0m"
    GREEN, YELLOW, RED, BLUE = "\033[32m", "\033[33m", "\033[31m", "\033[34m"
else:
    DIM = BOLD = RESET = GREEN = YELLOW = RED = BLUE = ""


def step(msg):
    print(f"\n{BLUE}==>{RESET} {BOLD}{msg}{RESET}")


def ok(msg):
    print(f"  {GREEN}✓{RESET} {msg}")


def info(msg):
    print(f"  {DIM}·{RESET} {msg}")


def warn(msg):
    # Flush stdout first: these two streams are read as one ordered log by a
    # human, and unflushed stdout makes warnings appear before the step they
    # belong to.
    sys.stdout.flush()
    print(f"  {YELLOW}!{RESET} {msg}", file=sys.stderr, flush=True)


def die(msg):
    sys.stdout.flush()
    print(f"\n{RED}error:{RESET} {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def markers_for(path):
    return COMMENT_STYLE.get(os.path.splitext(path)[1], (MARK_BEGIN, MARK_END))


class Engine:
    def __init__(self, repo, home, dry_run=False):
        self.repo = os.path.abspath(repo)
        self.home = home
        self.dry_run = dry_run
        data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local/share")
        self.backup_root = os.path.join(data_home, "openagentisland-backups")
        self.original = os.path.join(self.backup_root, "original")
        self.manifest_path = os.path.join(self.repo, "manifest.toml")

    # ── primitives ────────────────────────────────────────────────────
    # Every mutation goes through one of these, which is what makes
    # --dry-run honest by construction rather than by remembering to check
    # a flag at each call site.

    def _mkdirs(self, path):
        if self.dry_run:
            return
        os.makedirs(path, exist_ok=True)

    def _write(self, path, text):
        if self.dry_run:
            info(f"would write {self.short(path)}")
            return
        self._mkdirs(os.path.dirname(path))
        with open(path, "w") as fh:
            fh.write(text)

    def _shell(self, cmd):
        """Run a manifest `post` command.

        Split rather than handed to a shell, so a destination path can never be
        reinterpreted as shell syntax. A post that genuinely needs a pipeline
        should be a script in install/ and named here by path.
        """
        argv = shlex.split(cmd)
        # A post naming a script in this repo is resolved against the repo, so
        # it works regardless of the directory the installer was invoked from.
        # A bare command like `fc-cache` is left alone to resolve via PATH.
        candidate = os.path.join(self.repo, argv[0])
        if os.path.isfile(candidate):
            argv[0] = candidate
        if self.dry_run:
            info(f"would run: {' '.join(argv)}")
            return
        subprocess.run(argv, check=False)

    def short(self, path):
        return path.replace(self.home, "~", 1) if path.startswith(self.home) else path

    # ── backup ────────────────────────────────────────────────────────

    def backup(self, dest):
        """Snapshot dest into original/ the first time we ever touch it."""
        if not os.path.lexists(dest):
            # Record that it did not exist, so uninstall knows to remove rather
            # than restore. Without this, anything we create is left behind.
            self._record_absent(dest)
            return
        rel = os.path.relpath(dest, "/")
        target = os.path.join(self.original, "root", rel)
        if os.path.lexists(target):
            return  # already have the true original; never overwrite it
        if self.dry_run:
            info(f"would back up {self.short(dest)}")
            return
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.islink(dest):
            os.symlink(os.readlink(dest), target)
        elif os.path.isdir(dest):
            shutil.copytree(dest, target, symlinks=True)
        else:
            shutil.copy2(dest, target)
        self._append_manifest(dest, "existed")

    def _record_absent(self, dest):
        self._append_manifest(dest, "absent")

    def _append_manifest(self, dest, state):
        if self.dry_run:
            return
        os.makedirs(self.original, exist_ok=True)
        path = os.path.join(self.original, "manifest.tsv")
        # First write wins: the earliest observation is the true original.
        if os.path.exists(path):
            with open(path) as fh:
                if any(line.split("\t")[0] == dest for line in fh):
                    return
        with open(path, "a") as fh:
            fh.write(f"{dest}\t{state}\n")

    def _read_backup_manifest(self):
        path = os.path.join(self.original, "manifest.tsv")
        if not os.path.exists(path):
            return []
        rows = []
        with open(path) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line:
                    dest, state = line.split("\t")
                    rows.append((dest, state))
        return rows

    # ── modes ─────────────────────────────────────────────────────────

    def do_symlink(self, art, src, dest):
        if os.path.islink(dest) and os.path.realpath(dest) == os.path.realpath(src):
            ok(f"{art.id}: already linked")
            return
        self.backup(dest)
        if self.dry_run:
            info(f"would link {self.short(dest)} -> {src}")
            return
        if os.path.lexists(dest):
            if os.path.isdir(dest) and not os.path.islink(dest):
                shutil.rmtree(dest)
            else:
                os.remove(dest)
        self._mkdirs(os.path.dirname(dest))
        os.symlink(src, dest)
        ok(f"{art.id}: linked {self.short(dest)}")

    def do_copy(self, art, src, dest):
        self.backup(dest)
        if self.dry_run:
            info(f"would copy {art.src} -> {self.short(dest)}")
            return
        self._mkdirs(os.path.dirname(dest))
        if os.path.isdir(src):
            shutil.copytree(src, dest, symlinks=True, dirs_exist_ok=True)
        else:
            shutil.copy2(src, dest)
        ok(f"{art.id}: copied to {self.short(dest)}")

    def do_extract(self, art, src, dest):
        self.backup(dest)
        if self.dry_run:
            info(f"would extract {art.src} -> {self.short(dest)}")
            return
        self._mkdirs(dest)
        # zstd is not one of tarfile's built-in compressions, so decompression
        # is piped from the binary and the tar stream is read in-process. No
        # shell is involved, so a path can never be reinterpreted as syntax.
        with subprocess.Popen(["zstd", "-dc", src], stdout=subprocess.PIPE) as proc:
            with tarfile.open(fileobj=proc.stdout, mode="r|") as tf:
                tf.extractall(dest, filter="data")
            if proc.wait() != 0:
                die(f"{art.id}: zstd failed to decompress {art.src}")
        ok(f"{art.id}: extracted to {self.short(dest)}")

    def do_inject(self, art, src, dest):
        begin, end = markers_for(dest)
        body = open(src).read()
        self.backup(dest)
        existing = open(dest).read() if os.path.exists(dest) else ""
        merged = inject(existing, body, begin, end)
        if merged == existing:
            ok(f"{art.id}: block already current")
            return
        self._write(dest, merged)
        ok(f"{art.id}: injected into {self.short(dest)}")

    def do_setting(self, art, src, dest):
        parser = configparser.ConfigParser()
        parser.optionxform = str  # keys are case-sensitive here
        parser.read(src)
        if dest.startswith("gsettings:"):
            return self._do_gsettings(art, parser)
        self.backup(dest)
        target = configparser.ConfigParser()
        target.optionxform = str
        if os.path.exists(dest):
            target.read(dest)
        for section in parser.sections():
            if not target.has_section(section):
                target.add_section(section)
            for key, value in parser.items(section):
                target.set(section, key, value)
        if self.dry_run:
            info(f"would set {len(parser.sections())} section(s) in {self.short(dest)}")
            return
        self._mkdirs(os.path.dirname(dest))
        with open(dest, "w") as fh:
            target.write(fh, space_around_delimiters=False)
        ok(f"{art.id}: settings written to {self.short(dest)}")

    def _do_gsettings(self, art, parser):
        if not shutil.which("gsettings"):
            warn(f"{art.id}: gsettings not found, skipping")
            return
        for schema in parser.sections():
            for key, value in parser.items(schema):
                prev = subprocess.run(["gsettings", "get", schema, key],
                                      capture_output=True, text=True)
                if prev.returncode == 0:
                    self._save_gsetting(schema, key, prev.stdout.strip())
                if self.dry_run:
                    info(f"would gsettings set {schema} {key} {value}")
                    continue
                subprocess.run(["gsettings", "set", schema, key, value], check=False)
        if not self.dry_run:
            ok(f"{art.id}: gsettings applied")

    def _save_gsetting(self, schema, key, value):
        if self.dry_run:
            return
        os.makedirs(self.original, exist_ok=True)
        path = os.path.join(self.original, "gsettings.tsv")
        ident = f"{schema}\t{key}"
        if os.path.exists(path):
            with open(path) as fh:
                if any(line.startswith(ident + "\t") for line in fh):
                    return
        with open(path, "a") as fh:
            fh.write(f"{schema}\t{key}\t{value}\n")

    def do_merge_json(self, art, src, dest):
        self.backup(dest)
        overlay = json.load(open(src))
        base = {}
        if os.path.exists(dest):
            try:
                base = json.load(open(dest))
            except json.JSONDecodeError:
                # Refuse rather than overwrite. A malformed config is someone's
                # broken file, not an invitation to replace it.
                die(f"{art.id}: {self.short(dest)} is not valid JSON — "
                    f"fix or move it aside, then rerun")
        merged = merge_owned(base, overlay, art.keys)
        if merged == base:
            ok(f"{art.id}: config already current")
            return
        self._write(dest, json.dumps(merged, indent=2) + "\n")
        ok(f"{art.id}: merged {len(art.keys)} owned key(s) into {self.short(dest)}")

    HANDLERS = {
        "symlink": do_symlink,
        "copy": do_copy,
        "extract": do_extract,
        "inject": do_inject,
        "setting": do_setting,
        "merge-json": do_merge_json,
    }

    # ── commands ──────────────────────────────────────────────────────

    def artifacts(self, profile):
        return select(load(self.manifest_path), profile)

    def install(self, profile):
        step(f"Installing profile '{profile}'")
        for art in self.artifacts(profile):
            src = os.path.join(self.repo, art.src)
            dest = expand_dest(art.dest, self.home)
            if not dest.startswith("gsettings:") and not os.path.exists(src):
                warn(f"{art.id}: source missing ({art.src}) — skipping")
                continue
            self.HANDLERS[art.mode](self, art, src, dest)
            if art.post:
                self._shell(art.post)
        step("Done")
        if not self.dry_run:
            info(f"backup: {self.short(self.original)}")

    def verify(self, profile):
        step(f"Verifying profile '{profile}'")
        bad = []
        for art in self.artifacts(profile):
            dest = expand_dest(art.dest, self.home)
            if dest.startswith("gsettings:"):
                continue
            if os.path.lexists(dest):
                ok(f"{art.id}: {self.short(dest)}")
            else:
                print(f"  {RED}✗{RESET} {art.id}: missing {self.short(dest)}")
                bad.append(art.id)
        if bad:
            die(f"{len(bad)} artifact(s) did not land: {', '.join(bad)}")
        ok("every artifact landed")

    def status(self, profile):
        """Report how the live system differs from the repo. Never changes anything."""
        step(f"Status for profile '{profile}'")
        for art in self.artifacts(profile):
            src = os.path.join(self.repo, art.src)
            dest = expand_dest(art.dest, self.home)
            print(f"  {self._status_of(art, src, dest):<12} {art.id}")

    def _status_of(self, art, src, dest):
        if dest.startswith("gsettings:"):
            return "n/a"
        if not os.path.lexists(dest):
            return "missing"
        if art.mode == "symlink":
            if not os.path.islink(dest):
                return "not-a-link"
            return "ok" if os.path.realpath(dest) == os.path.realpath(src) else "wrong-target"
        if art.mode == "inject":
            begin, _ = markers_for(dest)
            return "ok" if begin in open(dest).read() else "not-injected"
        if art.mode == "copy" and os.path.isdir(src):
            cmp = filecmp.dircmp(src, dest)
            return "ok" if not (cmp.left_only or cmp.diff_files) else "differs"
        if art.mode == "copy":
            return "ok" if filecmp.cmp(src, dest, shallow=False) else "differs"
        return "present"

    def uninstall(self):
        step("Uninstall")
        rows = self._read_backup_manifest()
        if not rows:
            die(f"no backup found under {self.short(self.original)}")

        # Strip injected fences first. Those files may legitimately have changed
        # since install — matugen rewrites them — so surgically removing our
        # block is safer than stamping the whole file back.
        for art in load(self.manifest_path):
            if art.mode != "inject":
                continue
            dest = expand_dest(art.dest, self.home)
            if not os.path.exists(dest):
                continue
            begin, end = markers_for(dest)
            text = open(dest).read()
            cleaned = strip(text, begin, end)
            if cleaned != text:
                self._write(dest, cleaned)
                ok(f"stripped our block from {self.short(dest)}")

        injected = {expand_dest(a.dest, self.home)
                    for a in load(self.manifest_path) if a.mode == "inject"}

        for dest, state in rows:
            if dest in injected:
                continue  # already handled surgically above
            if state == "absent":
                if os.path.lexists(dest):
                    if self.dry_run:
                        info(f"would remove {self.short(dest)}")
                    elif os.path.isdir(dest) and not os.path.islink(dest):
                        shutil.rmtree(dest)
                    else:
                        os.remove(dest)
                    ok(f"removed {self.short(dest)}")
                continue
            rel = os.path.relpath(dest, "/")
            src = os.path.join(self.original, "root", rel)
            if not os.path.lexists(src):
                continue
            if self.dry_run:
                info(f"would restore {self.short(dest)}")
                continue
            if os.path.lexists(dest):
                if os.path.isdir(dest) and not os.path.islink(dest):
                    shutil.rmtree(dest)
                else:
                    os.remove(dest)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if os.path.islink(src):
                os.symlink(os.readlink(src), dest)
            elif os.path.isdir(src):
                shutil.copytree(src, dest, symlinks=True)
            else:
                shutil.copy2(src, dest)
            ok(f"restored {self.short(dest)}")

        self._restore_gsettings()
        step("Done")

    def _restore_gsettings(self):
        path = os.path.join(self.original, "gsettings.tsv")
        if not os.path.exists(path) or not shutil.which("gsettings"):
            return
        for line in open(path):
            schema, key, value = line.rstrip("\n").split("\t", 2)
            if self.dry_run:
                info(f"would gsettings reset {schema} {key} -> {value}")
                continue
            subprocess.run(["gsettings", "set", schema, key, value.strip("'")],
                           check=False)
        ok("gsettings restored")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["install", "uninstall", "verify", "status"])
    ap.add_argument("--repo", required=True)
    ap.add_argument("--profile", default="full")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    home = os.environ.get("HOME") or die("HOME is not set")
    engine = Engine(args.repo, home, args.dry_run)
    if args.dry_run:
        warn("DRY RUN — nothing will be modified")

    if args.command == "install":
        engine.install(args.profile)
    elif args.command == "uninstall":
        engine.uninstall()
    elif args.command == "verify":
        engine.verify(args.profile)
    else:
        engine.status(args.profile)


if __name__ == "__main__":
    main()
