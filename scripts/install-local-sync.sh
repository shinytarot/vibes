#!/bin/bash
# One-time setup for the desktop-folder flow: a Desktop alias you drag photos
# into, synced to this repo every night by launchd. Run once, from a clone of
# your own repo (not the template itself).
#
# Override before running if you want non-defaults:
#   VIBES_INBOX=~/Pictures/vibes-inbox VIBES_HOUR=21 ./scripts/install-local-sync.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_DIR="$(pwd)"

INBOX="${VIBES_INBOX:-$HOME/vibes-inbox}"
HOUR="${VIBES_HOUR:-22}"
MINUTE="${VIBES_MINUTE:-0}"
LABEL="${VIBES_LABEL:-com.$(whoami | tr -cd 'a-zA-Z0-9').vibes-daily}"

# Every check that can refuse goes before anything that changes your files, so a
# refusal leaves you exactly where you started rather than halfway.
#
# -n on the symlink below, or an existing alias is followed and the new one lands
# *inside* the folder it points at — a self-referential symlink in your own
# inbox, and no error. Something real of that name is a different problem:
# swallowing it silently would be worse than stopping, since it may well have
# your photos in it.
ALIAS="$HOME/Desktop/vibes-inbox"
if [ -e "$ALIAS" ] && [ ! -L "$ALIAS" ]; then
  echo "There's already something called 'vibes-inbox' on your Desktop, and it"
  echo "isn't an alias. Rename or move it, then run this again — I won't touch it."
  exit 1
fi

mkdir -p "$INBOX"

# Anything already uploaded through the images/ folder (e.g. via github.com)
# moves into the inbox first, so switching flows doesn't drop it off the page.
find images -maxdepth 1 -type f ! -name '.*' -exec mv {} "$INBOX/" \;

ln -sfn "$INBOX" "$ALIAS"

# Self-contained venv so this doesn't depend on the system python having
# pillow/pillow-heif already — the GitHub Action's environment doesn't help here.
python3 -m venv .venv
"$REPO_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$REPO_DIR/.venv/bin/pip" install --quiet pillow pillow-heif

chmod +x scripts/local-sync.sh

PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$REPO_DIR/scripts/local-sync.sh</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>VIBES_INBOX</key><string>$INBOX</string>
	</dict>
	<key>StandardOutPath</key><string>$HOME/Library/Logs/vibes-daily.log</string>
	<key>StandardErrorPath</key><string>$HOME/Library/Logs/vibes-daily.log</string>
	<key>StartCalendarInterval</key>
	<array>
		<dict>
			<key>Hour</key><integer>$HOUR</integer>
			<key>Minute</key><integer>$MINUTE</integer>
		</dict>
	</array>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo
echo "Done. A 'vibes-inbox' alias is on your Desktop — drag photos in, remove them to take them down."
echo "They go live by $HOUR:$(printf '%02d' "$MINUTE") each night. Log: ~/Library/Logs/vibes-daily.log"
echo "To sync right now instead of waiting: ./scripts/local-sync.sh"
