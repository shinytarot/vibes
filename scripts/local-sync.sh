#!/bin/bash
# Nightly sync: rebuilds images/ from a local inbox folder, converts, commits, pushes.
# Installed by install-local-sync.sh (launchd calls this). Safe to run by hand anytime.
set -euo pipefail
cd "$(dirname "$0")/.."

INBOX="${VIBES_INBOX:-$HOME/vibes-inbox}"
BRANCH="$(git symbolic-ref --short HEAD)"

# This script's own note-to-self, written at the bottom. It lives in the inbox so
# it's seen, which means it must be excluded from the copy below — otherwise it
# gets published, rejected for not being an image, and named in its own next
# edition, forever.
NOTICE_NAME="⚠️ THESE DIDN'T GO UP.txt"
NOTICE="$INBOX/$NOTICE_NAME"

echo "--- $(date '+%Y-%m-%d %H:%M') ---"
mkdir -p "$INBOX"

# The README says this is safe to run by hand, and it is — but not at the same
# moment launchd is running it. Two copies racing over the same images/ end with
# one dying on a half-deleted directory, and that night's sync just doesn't
# happen. mkdir is the atomic test-and-set every filesystem gives you for free.
LOCK=".vibes-lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "another sync is already running — leaving this one to it"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

git fetch origin "$BRANCH"

# The Action rewrites history whenever an image is uploaded through github.com,
# so there's no merge to do here — lining up with the remote means a hard reset.
# That would also wipe any edit to index.html, which is where your own words at
# the top of the page live: you'd write a paragraph, see it all evening, and find
# it gone in the morning with nothing to say why. So anything changed outside the
# two paths this script owns is carried across the reset and put back after it.
#
# What counts as "yours" is measured against the last state this machine and the
# remote agreed on — recorded at the end of each successful run, because it cannot
# be inferred. `git merge-base` is the obvious way to find it and it does not work
# here: the Action force-pushes a rewritten commit, so the local machine's last
# commit is never an ancestor of origin and the merge base lands one commit too
# early. That makes the run's own previous edit look like unpushed local work, and
# it gets carried across the reset and written over whatever you typed in the
# browser since — the exact thing this carry exists to prevent, silently.
#
# Two sources of "yours": edits not yet committed, and commits not yet pushed.
CARRY="$(mktemp -d)"
trap 'rm -rf "$CARRY"; rmdir "$LOCK" 2>/dev/null || true' EXIT
MARKER=".vibes-last-sync"
if [ -s "$MARKER" ] && git cat-file -e "$(cat "$MARKER")^{commit}" 2>/dev/null; then
  BASE="$(cat "$MARKER")"
else
  # Losing the marker silently re-arms the bug it was added to kill, and it's a
  # dotfile that a re-clone or a tidy-up removes without ceremony. Say so.
  echo "no usable $MARKER — falling back to merge-base for this run, which can"
  echo "mis-read a github.com edit as a local one. It'll be correct again next run."
  BASE="$(git merge-base "origin/$BRANCH" HEAD)"
fi
{
  git diff --name-only HEAD -- . \
    ':(exclude)images' ':(exclude)image_widths_heights.json'
  git diff --name-only "$BASE" HEAD -- . \
    ':(exclude)images' ':(exclude)image_widths_heights.json'
} | sort -u \
  | while IFS= read -r f; do
      [ -f "$f" ] || continue
      mkdir -p "$CARRY/$(dirname "$f")"
      cp "$f" "$CARRY/$f"
    done

git reset --hard "origin/$BRANCH"

# Record agreement HERE, not only after the push. This line is the moment local
# and origin are identical, and it must be written even if the run aborts a step
# later — the empty-inbox guard, a laptop that slept before the push, a crash.
# Writing it only on the success path left HEAD advanced and the marker stale, so
# the next run read its own last state as unpushed work and deleted whatever had
# been typed in the browser since. That is the bug the marker exists to prevent,
# reintroduced through the back door.
git rev-parse HEAD > "$MARKER"

# Which files got carried, recorded outside $CARRY so the commit below can include
# them. Without this they'd be restored and never committed — living on your Mac,
# dirtying the repo forever, never reaching the page. index.html is the one that
# matters, but scripts/vibes.py is fair game too: the README invites you to change
# the compression settings in it.
CARRIED="$(mktemp)"
trap 'rm -rf "$CARRY" "$CARRIED"; rmdir "$LOCK" 2>/dev/null || true' EXIT

find "$CARRY" -type f -print0 | while IFS= read -r -d '' kept; do
  f="${kept#"$CARRY"/}"
  # Identical to what the reset produced, so there is nothing to carry. Skipping
  # keeps "kept your changes to index.html" honest — it appeared on runs where
  # nothing had been touched, which teaches you to ignore the one line that
  # actually matters when it does appear.
  if cmp -s "$kept" "$f"; then continue; fi
  # If it moved on github.com too, yours is the one that survives — but say so,
  # because otherwise a paragraph written in the browser this morning quietly
  # disappears tonight. Nothing is destroyed; the other version stays in history.
  #
  # Compared against $BASE, not HEAD: the reset just made the worktree identical
  # to HEAD by definition, so a HEAD comparison can never be true and this would
  # be dead code that the README nonetheless promises.
  if ! git diff --quiet "$BASE" HEAD -- "$f" && ! cmp -s "$kept" "$f"; then
    echo "NOTE: $f changed here AND on github.com. Keeping your local copy;"
    echo "      the other version is still in this repo's history."
  fi
  cp "$kept" "$f"
  printf '%s\n' "$f" >> "$CARRIED"
  echo "kept your changes to $f"
done

# Deleting images/ on github.com is the documented way to clear the page — which
# means the very next run finds no such directory. Without this, `find images`
# fails, pipefail kills the script, and the sync is dead every night from then on
# until somebody types mkdir. Recreating it costs nothing and un-bricks that path.
mkdir -p images

# The inbox IS the page, so an empty one reads as "take everything down" — and it
# is far likelier that the folder got moved, renamed, or cleared to save space.
# `mkdir -p` above would have silently recreated it, so this is the only thing
# standing between a stray drag and the whole page coming down.
COUNT="$(find "$INBOX" -type f ! -path '*/.*' ! -name "$NOTICE_NAME" | wc -l | tr -d ' ')"
LIVE="$(find images -maxdepth 1 -type f -name '*.webp' | wc -l | tr -d ' ')"
if [ "$COUNT" -eq 0 ] && [ "$LIVE" -gt 0 ]; then
  # "It's empty" is a lie if the folder is visibly full — which happens when the
  # inbox itself sits under a hidden directory, since the walk skips those.
  # Same exclusions as COUNT, minus the hidden-path one — otherwise this script's
  # own notice file counts as "visible content" and anyone who has ever dropped a
  # video in the folder gets told their inbox is hidden when it's simply empty.
  if [ "$(find "$INBOX" -type f ! -name '.*' ! -name "$NOTICE_NAME" | wc -l | tr -d ' ')" -gt 0 ]; then
    echo "Everything in $INBOX sits under a hidden folder (a name starting with a"
    echo "dot), which this skips. Move the inbox somewhere without one in its path."
  else
    echo "$INBOX is empty — refusing to take all $LIVE images off your page."
    echo "Put them back, or delete images/ on github.com if you really mean it."
  fi
  exit 1
fi

# images/ becomes exactly what's in the inbox right now — additions and
# removals both fall out of this for free. vibes.py re-encodes everything,
# but the encode is deterministic, so unchanged inputs produce byte-identical
# output and nothing gets committed.
#
# Walked recursively, because dragging a whole album out of Photos is the most
# obvious thing to do with a folder like this, and a non-recursive walk would
# have ignored every photo in it in silence. The page is flat, so a subfolder's
# name is folded into the filename rather than lost.
#
# `! -path '*/.*'` skips anything under a hidden folder, and it is not tidiness:
# vibes.py ignores dot-names, so a photo arriving as `.picasaoriginals/x.jpg`
# would be copied in, never re-encoded, never stripped of its GPS, and committed
# to a public repo as the untouched original. Deleting the whole of images/ each
# run rather than just the .webp files is the other half of that — a stray file
# from an older version would otherwise sit there permanently.
find images -maxdepth 1 -type f -delete
# Sorted, so the collision counter below hands out the same prefix every night.
# Unsorted, `find` returns whatever order the filesystem feels like, and the two
# colliding photos could swap which one is "1-" between runs — a commit and a
# reshuffled page every night, for no reason anyone could see.
find "$INBOX" -type f ! -path '*/.*' ! -name "$NOTICE_NAME" -print0 \
  | LC_ALL=C sort -z \
  | while IFS= read -r -d '' f; do
      # Basename only. Folding the folder name in reads better in a directory
      # listing and puts it in a public URL — "ediya-wedding-nov-2025-img_0042"
      # tells the internet where you were and who with, from a folder you named
      # for your own eyes. Newlines are flattened because they'd break every
      # line-based tool downstream, and same-named photos from different folders
      # get a counter rather than quietly overwriting each other.
      base="$(printf '%s' "${f##*/}" | tr '\n' '-')"
      dest="images/$base"
      n=1
      while [ -e "$dest" ]; do
        dest="images/${n}-$base"
        n=$((n + 1))
      done
      cp "$f" "$dest"
    done

./.venv/bin/python3 scripts/vibes.py

# The count check above is the cheap one and catches the common case — the folder
# got moved or renamed. This is the one that can't be fooled: an inbox holding
# nothing but files that turn out to be unpublishable (one stray video) passes
# the count and would still strip the page bare. Judge on what actually survived
# encoding, and put everything back if the answer is nothing.
if [ "$(find images -maxdepth 1 -name '*.webp' | wc -l | tr -d ' ')" -eq 0 ] \
   && [ "$LIVE" -gt 0 ]; then
  git checkout -- images image_widths_heights.json
  echo "nothing in $INBOX could be published, so all $LIVE images would have come"
  echo "down. Left the page as it was. See the note in the folder for which files."
fi

# index.html is in here too, not just the images: it's the file you edit to change
# the words at the top, and carrying an edit across the reset above without ever
# committing it would leave it living on your Mac and never reaching the page.
PATHS=(images image_widths_heights.json index.html)
if [ -s "$CARRIED" ]; then
  while IFS= read -r f; do PATHS+=("$f"); done < "$CARRIED"
fi
if [[ -n "$(git status --porcelain -- "${PATHS[@]}")" ]]; then
  git add -A -- "${PATHS[@]}"
  git commit -m "vibes sync $(date '+%Y-%m-%d %H:%M')" --quiet
  git push origin "$BRANCH"
  echo "pushed"
else
  echo "no changes"
fi

# Local and the remote now agree, so record where. Only reached if the push above
# succeeded — `set -e` aborts before this otherwise, leaving the previous marker
# in place, which is the correct answer for a run that didn't land.
git rev-parse HEAD > "$MARKER"

# A rejected file is silent otherwise: it just never shows up on the page, night
# after night, and the log that says why is a file nobody opens. So the notice
# goes into the inbox itself — the one folder you actually look at. It's rewritten
# every run and deleted when there's nothing left to say.
if [[ -s .vibes-rejected ]]; then
  echo "rejected (not published — unreadable or not an image): $(paste -sd, .vibes-rejected)"
  {
    echo "These files are in this folder but are not on your page:"
    echo
    sed 's/^/  · /' .vibes-rejected
    echo   # .vibes-rejected has no trailing newline, so this closes the last line
    echo
    echo "Either they aren't images (a video off a camera roll, a PDF), or the file"
    echo "is damaged and can't be opened. Re-save them as JPEGs and drop them back in,"
    echo "or drag them out of this folder — nothing else needs doing."
    echo
    echo "Last checked $(date '+%-d %B %Y, %H:%M'). This file rewrites itself, so"
    echo "there's no point editing it; it disappears once the folder is clean."
  } > "$NOTICE"
else
  rm -f "$NOTICE"
fi
