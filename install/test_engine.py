#!/usr/bin/env python3
"""
Unit tests for the installer engine's pure logic.

Everything tested here is filesystem-free on purpose: these are the parts where
a mistake silently corrupts someone's configuration rather than failing loudly,
so they are worth testing exhaustively and cheaply.

Run: python3 install/test_engine.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

FAILED = []


def check(name, cond):
    if cond:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}")
        FAILED.append(name)


# ── paths ─────────────────────────────────────────────────────────────
from paths import expand_dest, get_path, has_path, set_path  # noqa: E402


def test_paths():
    print("paths")
    d = {"a": {"b": {"c": 1}}, "top": 2}
    check("get nested", get_path(d, "a.b.c") == 1)
    check("get top", get_path(d, "top") == 2)
    check("has nested", has_path(d, "a.b.c") is True)
    check("has missing leaf", has_path(d, "a.b.zzz") is False)
    check("has missing branch", has_path(d, "nope.deep") is False)
    check("get missing returns None", get_path(d, "nope.deep") is None)

    e = {}
    set_path(e, "x.y.z", 9)
    check("set creates branches", e == {"x": {"y": {"z": 9}}})

    f = {"x": {"keep": 1}}
    set_path(f, "x.new", 2)
    check("set keeps siblings", f == {"x": {"keep": 1, "new": 2}})

    # A scalar sitting where a branch is expected must read as absent, not raise.
    g = {"x": 5}
    check("has through scalar is False", has_path(g, "x.y") is False)
    check("get through scalar is None", get_path(g, "x.y") is None)

    # set must overwrite a scalar standing in the way rather than crashing.
    h = {"x": 5}
    set_path(h, "x.y", 1)
    check("set replaces a blocking scalar", h == {"x": {"y": 1}})


def test_expand():
    print("expand_dest")
    check("tilde", expand_dest("~/.config/foo", "/home/u") == "/home/u/.config/foo")
    check("bare tilde", expand_dest("~", "/home/u") == "/home/u")
    check("absolute untouched", expand_dest("/etc/x", "/home/u") == "/etc/x")
    check("no mid-string expansion", expand_dest("/a/~/b", "/home/u") == "/a/~/b")
    check("relative untouched", expand_dest("rel/path", "/home/u") == "rel/path")


# ── jsonmerge ─────────────────────────────────────────────────────────
from jsonmerge import merge_owned  # noqa: E402


def test_merge():
    print("merge_owned")
    base = {
        "background": {"wallpaperPath": "/home/them/pic.jpg", "mode": "fill"},
        "dock": {"enable": False},
        "personal": {"name": "them"},
    }
    overlay = {
        "background": {"wallpaperPath": "/repo/wall.jpg", "mode": "fit"},
        "dock": {"enable": True},
        "personal": {"name": "me"},
    }

    out = merge_owned(base, overlay, ["dock.enable"])
    check("owned key written", out["dock"]["enable"] is True)
    check("unowned sibling kept", out["background"]["wallpaperPath"] == "/home/them/pic.jpg")
    check("unowned branch kept", out["personal"]["name"] == "them")
    check("base not mutated", base["dock"]["enable"] is False)

    out2 = merge_owned(base, overlay, ["background.mode", "dock.enable"])
    check("two owned keys", out2["background"]["mode"] == "fit" and out2["dock"]["enable"] is True)
    check("wallpaper still theirs", out2["background"]["wallpaperPath"] == "/home/them/pic.jpg")

    # A key the overlay does not define must leave base alone, not write None.
    out3 = merge_owned(base, overlay, ["dock.missingKey"])
    check("absent overlay key is a no-op", "missingKey" not in out3["dock"])

    # A key absent from base must be created.
    out4 = merge_owned({}, {"a": {"b": 1}}, ["a.b"])
    check("creates missing branch", out4 == {"a": {"b": 1}})

    # Nested values must be deep-copied, never aliased to the overlay.
    ov = {"x": {"list": [1, 2]}}
    out5 = merge_owned({}, ov, ["x.list"])
    out5["x"]["list"].append(3)
    check("deep copied", ov["x"]["list"] == [1, 2])

    # Owning a whole branch copies the branch, not a reference to it.
    out6 = merge_owned({"d": {"keep": 1}}, {"d": {"a": 1, "b": 2}}, ["d"])
    check("owning a branch replaces it wholesale", out6["d"] == {"a": 1, "b": 2})

    check("empty key list is a no-op", merge_owned(base, overlay, []) == base)


# ── textblock ─────────────────────────────────────────────────────────
from textblock import inject, strip  # noqa: E402

B, E = "/* >>> oai >>> */", "/* <<< oai <<< */"


def test_textblock():
    print("textblock")
    out = inject("body {}", "a{}", B, E)
    check("appends when absent", out.count(B) == 1 and "a{}" in out)
    check("keeps original content", "body {}" in out)

    twice = inject(out, "a{}", B, E)
    check("idempotent", twice.count(B) == 1)
    check("idempotent output is stable", twice == out)

    replaced = inject(out, "b{}", B, E)
    check("replaces body", "b{}" in replaced and "a{}" not in replaced)
    check("still exactly one block", replaced.count(B) == 1)

    tail = inject("head\n", "x{}", B, E) + "trailer\n"
    stripped = strip(tail, B, E)
    check("strip removes markers", B not in stripped and E not in stripped)
    check("strip removes body", "x{}" not in stripped)
    check("strip keeps head", "head" in stripped)
    check("strip keeps trailer", "trailer" in stripped)

    check("strip on clean text is a no-op", strip("nothing here", B, E) == "nothing here")
    check("strip with only a begin marker is a no-op",
          strip("a\n" + B + "\nb", B, E) == "a\n" + B + "\nb")
    check("empty input works", inject("", "z{}", B, E).count(B) == 1)

    # Content around an existing block must survive replacement untouched.
    doc = "before\n" + B + "\nold\n" + E + "\nafter\n"
    check("replacement preserves surroundings",
          "before" in inject(doc, "new", B, E) and "after" in inject(doc, "new", B, E))


# ── manifest ──────────────────────────────────────────────────────────
import tempfile  # noqa: E402

from manifest import MODES, ManifestError, load, select  # noqa: E402


def _write(tmp, text):
    p = os.path.join(tmp, "m.toml")
    with open(p, "w") as fh:
        fh.write(text)
    return p


def _rejects(tmp, text, needle, label):
    try:
        load(_write(tmp, text))
        check(label, False)
    except ManifestError as exc:
        check(label, needle in str(exc))


def test_manifest():
    print("manifest")
    with tempfile.TemporaryDirectory() as tmp:
        good = _write(
            tmp,
            """
[[artifact]]
id = "shell"
src = "quickshell"
dest = "~/.config/quickshell/openagentisland"
mode = "symlink"
profile = ["island", "full"]

[[artifact]]
id = "fonts"
src = "assets/fonts"
dest = "~/.local/share/fonts"
mode = "copy"
post = "fc-cache -f"
""",
        )
        arts = load(good)
        check("loads both rows", len(arts) == 2)
        check("id preserved", arts[0].id == "shell")
        check("profile default is full", arts[1].profile == ["full"])
        check("post captured", arts[1].post == "fc-cache -f")
        check("distro defaults empty", arts[0].distro == [])
        check("keys default empty", arts[0].keys == [])

        check("select island", [a.id for a in select(arts, "island")] == ["shell"])
        check("select full", [a.id for a in select(arts, "full")] == ["shell", "fonts"])
        check("select unknown profile is empty", select(arts, "nope") == [])

        _rejects(tmp,
                 '[[artifact]]\nid="x"\nsrc="a"\ndest="~/a"\nmode="copy"\n'
                 '[[artifact]]\nid="x"\nsrc="b"\ndest="~/b"\nmode="copy"\n',
                 "duplicate", "duplicate id rejected")

        _rejects(tmp, '[[artifact]]\nid="x"\nsrc="a"\ndest="~/a"\nmode="teleport"\n',
                 "teleport", "unknown mode rejected")

        _rejects(tmp, '[[artifact]]\nid="x"\nmode="copy"\n',
                 "src", "missing field rejected")

        _rejects(tmp, '[[artifact]]\nid="c"\nsrc="a"\ndest="~/a"\nmode="merge-json"\n',
                 "keys", "merge-json without keys rejected")

        _rejects(tmp, '[[artifact]]\nid="c"\nsrc="a"\ndest="~/a"\nmode="merge-json"\nkeys=[]\n',
                 "keys", "merge-json with empty keys rejected")

        _rejects(tmp, '[[artifact]]\nid="x"\nsrc="a"\ndest="~/a"\nmode="copy"\nwat="?"\n',
                 "wat", "unknown field rejected")

        check("empty manifest loads to nothing", load(_write(tmp, "")) == [])

    check("modes are the documented six",
          MODES == {"symlink", "copy", "inject", "setting", "extract", "merge-json"})


if __name__ == "__main__":
    test_paths()
    test_expand()
    test_merge()
    test_textblock()
    test_manifest()
    print()
    if FAILED:
        print(f"FAILED ({len(FAILED)}): {', '.join(FAILED)}")
        sys.exit(1)
    print("all passed")
