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


if __name__ == "__main__":
    test_paths()
    test_expand()
    print()
    if FAILED:
        print(f"FAILED ({len(FAILED)}): {', '.join(FAILED)}")
        sys.exit(1)
    print("all passed")
