"""
The artifact table: loading, validation, and profile selection.

A bad manifest must fail at load time, loudly, before anything has been written.
The alternative is discovering the mistake halfway through mutating someone's
home directory, with half the rice installed and no clean way back.
"""
import tomllib
from dataclasses import dataclass, field, fields

MODES = {"symlink", "copy", "inject", "setting", "extract", "merge-json"}
REQUIRED = ("id", "src", "dest", "mode")


class ManifestError(Exception):
    pass


@dataclass
class Artifact:
    id: str
    src: str
    dest: str
    mode: str
    # Which install profiles include this row. "island" is the notch alone;
    # "full" is the whole desktop.
    profile: list = field(default_factory=lambda: ["full"])
    # Shell command to run once this row has landed, e.g. fc-cache -f.
    post: str = ""
    # merge-json only: the key paths this rice owns and may write.
    keys: list = field(default_factory=list)
    # Reserved. Empty means every distro. The Ubuntu port adds values here
    # rather than introducing a new concept in the engine.
    distro: list = field(default_factory=list)


_FIELD_NAMES = {f.name for f in fields(Artifact)}


def load(path):
    with open(path, "rb") as fh:
        doc = tomllib.load(fh)

    rows, seen = [], set()
    for i, row in enumerate(doc.get("artifact", [])):
        where = row.get("id", f"row {i}")

        for f in REQUIRED:
            if f not in row:
                raise ManifestError(f"{where}: missing required field '{f}'")

        unknown = set(row) - _FIELD_NAMES
        if unknown:
            raise ManifestError(
                f"{where}: unknown field(s) {sorted(unknown)} — a typo here would "
                f"otherwise be silently ignored"
            )

        if row["mode"] not in MODES:
            raise ManifestError(
                f"{where}: unknown mode '{row['mode']}' (expected one of {sorted(MODES)})"
            )

        # An empty key list would mean "change nothing", which reads as a working
        # install while doing nothing at all. Refuse it rather than allow it.
        if row["mode"] == "merge-json" and not row.get("keys"):
            raise ManifestError(
                f"{where}: mode 'merge-json' requires a non-empty 'keys' — it may only "
                f"write key paths the rice declares it owns"
            )

        if row["id"] in seen:
            raise ManifestError(f"duplicate artifact id '{row['id']}'")
        seen.add(row["id"])

        rows.append(Artifact(**row))
    return rows


def select(artifacts, profile):
    return [a for a in artifacts if profile in a.profile]
