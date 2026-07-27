#!/bin/bash
# Undoes install-local-sync.sh: stops the nightly job, removes the Desktop
# alias. Leaves the inbox folder and its photos alone.
set -euo pipefail
LABEL="${VIBES_LABEL:-com.$(whoami | tr -cd 'a-zA-Z0-9').vibes-daily}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
# Only ever the alias. If something of that name is a real folder it isn't ours,
# and `rm -f` on a directory exits 1 — which under `set -e` would abort the
# uninstall just before it told you it had worked.
ALIAS="$HOME/Desktop/vibes-inbox"
if [ -L "$ALIAS" ]; then rm -f "$ALIAS"; fi

echo "Nightly sync stopped and Desktop alias removed. Your images and the ~/vibes-inbox folder are untouched."
