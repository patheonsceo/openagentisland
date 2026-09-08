#!/usr/bin/env python3
"""
Generate docs/what-it-installs.md from manifest.toml.

Documentation that lists what an installer touches goes stale the moment a row
is added and nobody remembers the docs. Generating the page from the same table
the installer reads makes that impossible: regenerate and the page is current,
and CI can assert there is no diff.

Run: python3 install/gen_docs.py
Deterministic — running it twice produces no diff.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from manifest import load  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "what-it-installs.md")

MODE_BLURB = {
    "symlink": "Linked, not copied — the destination points back into the repo.",
    "copy": "Copied in. Your existing file is backed up first.",
    "inject": "A marked block is added to a file this rice shares with another "
              "project. Everything around it is left alone.",
    "setting": "Individual keys are written. Other keys in the file are untouched.",
    "extract": "Unpacked from an archive.",
    "merge-json": "Only the listed keys are written into your existing JSON. "
                  "Everything else in the file survives.",
}


def main():
    artifacts = load(os.path.join(REPO, "manifest.toml"))

    lines = [
        "# What it installs",
        "",
        "_Every file the installer touches, generated from the manifest it reads._",
        "",
        "> [!NOTE]",
        "> This page is generated from `manifest.toml` by `install/gen_docs.py`.",
        "> It is the same table the installer reads, so it cannot fall out of date.",
        "",
        "Run `./install.sh --status` to see how your machine currently differs from",
        "any of this, and `./install.sh --dry-run` to watch a full install without",
        "changing anything.",
        "",
        "## Every destination",
        "",
        "| What | Where it goes | How | Profile |",
        "| --- | --- | --- | --- |",
    ]

    for a in artifacts:
        dest = "gsettings (dconf)" if a.dest.startswith("gsettings:") else f"`{a.dest}`"
        lines.append(f"| `{a.id}` | {dest} | {a.mode} | {', '.join(a.profile)} |")

    lines += ["", "## What each method means", ""]
    for mode in sorted({a.mode for a in artifacts}):
        lines += [f"**`{mode}`** — {MODE_BLURB[mode]}", ""]

    owned = [a for a in artifacts if a.mode == "merge-json"]
    if owned:
        lines += [
            "## Settings this rice claims",
            "",
            "Your shell config is mostly yours. These are the only paths the",
            "installer will write; anything else in the file — your wallpaper, your",
            "monitor layout, your preferences — is left exactly as it was.",
            "",
        ]
        for a in owned:
            lines += [f"In `{a.dest}`:", ""]
            lines += [f"- `{k}`" for k in a.keys]
            lines.append("")

    lines += [
        "## Undoing it",
        "",
        "```bash",
        "./install.sh --uninstall",
        "```",
        "",
        "The first install snapshots every destination before changing it, and that",
        "snapshot is never overwritten by later runs. So installing twice and",
        "uninstalling once still returns you to how things were before the first",
        "install, rather than to the state in between.",
        "",
    ]

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        fh.write("\n".join(lines))

    print(f"wrote {os.path.relpath(OUT, REPO)} ({len(artifacts)} artifacts)")


if __name__ == "__main__":
    main()
