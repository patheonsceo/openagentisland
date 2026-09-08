"""
Fenced blocks in files this project shares with another.

Some files the rice writes into are not ours: matugen's GTK templates, Zen's
userChrome.css. We cannot own the whole file, so we own a marked region of it.
The markers exist so the block can be found again exactly — to remove it on
uninstall, and so a second install replaces rather than duplicates it.

Ported from the Python heredocs that were embedded in install.sh. Behaviour is
deliberately unchanged; the point of moving it here is that it is now tested.
"""


def inject(text, body, begin, end):
    """Insert or replace the fenced block. Idempotent at the byte level.

    Both paths append `block` to a right-stripped head and nothing else. The
    original bash added a newline *and* the block on the insert path, while the
    replace path added only the block — so the first and second runs produced
    files that differed by one blank line. Harmless to look at, but it made
    "running twice changes nothing" untrue, which is the claim --status has to
    rely on to report honestly.
    """
    block = f"\n{begin}\n{body.rstrip()}\n{end}\n"
    if begin in text and end in text:
        head, rest = text.split(begin, 1)
        _, tail = rest.split(end, 1)
        return head.rstrip("\n") + block + tail.lstrip("\n")
    return text.rstrip("\n") + block


def strip(text, begin, end):
    """Remove the fenced block, leaving everything around it untouched.

    A half-present fence (one marker, not both) is left alone rather than
    guessed at — the file has been edited by hand and we should not improvise.
    """
    if begin not in text or end not in text:
        return text
    head, rest = text.split(begin, 1)
    _, tail = rest.split(end, 1)
    return head.rstrip("\n") + "\n" + tail.lstrip("\n")
