"""
Dotted-path access into nested dicts, plus destination expansion.

Pure functions, no filesystem access — keep it that way. These are used to
address individual keys inside a config document the rice only partly owns, so
they must never raise on a shape they did not expect: a manifest naming a key
path that does not exist in the user's file is a normal situation, not an error.
"""
import os


def _walk(obj, parts):
    """Return (value, found). Never raises on an unexpected shape."""
    for p in parts:
        if not isinstance(obj, dict) or p not in obj:
            return None, False
        obj = obj[p]
    return obj, True


def has_path(obj, path):
    return _walk(obj, path.split("."))[1]


def get_path(obj, path):
    return _walk(obj, path.split("."))[0]


def set_path(obj, path, value):
    """Create intermediate dicts as needed, replacing anything non-dict in the way."""
    parts = path.split(".")
    for p in parts[:-1]:
        if not isinstance(obj.get(p), dict):
            obj[p] = {}
        obj = obj[p]
    obj[parts[-1]] = value


def expand_dest(dest, home):
    """Only a LEADING ~ expands.

    A ~ anywhere else is a literal directory name, which is the behaviour a
    shell would give and the one a manifest author will expect.
    """
    if dest == "~":
        return home
    if dest.startswith("~/"):
        return os.path.join(home, dest[2:])
    return dest
