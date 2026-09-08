"""
Merge only the keys the rice declares it owns.

`~/.config/illogical-impulse/config.json` is 17 KB of rice settings mixed with
end-4 defaults and values that belong to the machine, not the rice: the
wallpaper path, the monitor layout, personal preferences. Copying our file over
someone else's destroys all of it.

So ownership is explicit and narrow. A manifest row using mode "merge-json"
must list the key paths it may write, and nothing outside that list is touched.
The manifest loader refuses a merge-json row with no keys for exactly this
reason — an empty list would silently mean "change nothing", which reads as a
working install while doing nothing at all.
"""
import copy

from paths import get_path, has_path, set_path


def merge_owned(base, overlay, keys):
    """Return a copy of `base` with only `keys` taken from `overlay`.

    A key absent from `overlay` is skipped rather than written as None: the
    overlay not mentioning something means "no opinion", not "unset it".
    """
    out = copy.deepcopy(base)
    for k in keys:
        if has_path(overlay, k):
            set_path(out, k, copy.deepcopy(get_path(overlay, k)))
    return out
