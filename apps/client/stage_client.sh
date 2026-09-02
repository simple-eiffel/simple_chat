#!/bin/bash
# =============================================================================
# stage_client.sh - build simple_chat's runnable client folder
# =============================================================================
#
#   usage:  apps/client/stage_client.sh [destination]
#   e.g.:   apps/client/stage_client.sh dist/simple_chat_client
#
#   Default destination: dist/simple_chat_client (a RUNNABLE FOLDER, never a
#   zip: the fleet's rule is that a distributable is a folder you can cd into
#   from a DOS prompt and run).
#
# WHAT TRAVELS WITH THE CLIENT, AND WHY EACH ONE HAS TO:
#
#   SimpleChat.exe                  the finalized simple_chat_client target.
#                                   Every target of this system finalizes to
#                                   simple_chat.exe, so it is RENAMED here -
#                                   otherwise the client, the server and the
#                                   test runner are three files with one name
#                                   and a taskkill by image name is a loaded
#                                   gun.
#
#   cairo.dll                       simple_cairo links cairo.LIB, an IMPORT
#                                   library: the DLL must be found at PROCESS
#                                   START or the exe does not launch at all.
#                                   There is no runtime check to degrade
#                                   through and the failure looks exactly like
#                                   a crash.
#
#   assets/noto-emoji/png/128/      the Noto artwork simple_shaping resolves
#                                   emoji against. SW_SHAPING.make looks for it
#                                   beside the RUNNING EXECUTABLE, never in the
#                                   working directory: a shortcut, a service,
#                                   an Explorer double-click and a debugger all
#                                   have different working directories and none
#                                   of them is a contract. Missing artwork is
#                                   NOT a crash - simple_shaping degrades to a
#                                   note and a box - but the robot will not be
#                                   a robot.
#
#   LICENSE-ASSETS.md               the artwork's licence. It ships WITH the
#                                   artwork; that is the condition of
#                                   redistributing it.
#
#   client.toml                     a template. The client reads
#                                   %APPDATA%\simple_chat\client.toml by
#                                   default; this copy is what a member edits
#                                   and puts there. It carries NO password and
#                                   NO token: the session is a DPAPI blob the
#                                   client writes itself.
#
# usp10, gdi32, dwrite, winhttp and shell32 are Windows' own. Nothing else
# needs an installer.
#
# Every finalize wipes F_code, so run this after each build.
# =============================================================================

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
DEST="${1:-$PROJECT/dist/simple_chat_client}"
ROOT="${SIMPLE_EIFFEL:-/d/prod}"

BUILT="$PROJECT/EIFGENs/simple_chat_client/F_code/simple_chat.exe"
CAIRO="$ROOT/simple_cairo/cairo.dll"
SHAPING="$ROOT/simple_shaping"

if [ ! -f "$BUILT" ]; then
    echo "ERROR: $BUILT not found." >&2
    echo "       Build it first:" >&2
    echo "         /d/prod/ec.sh test -config simple_chat.ecf -target simple_chat_client" >&2
    exit 1
fi
if [ ! -f "$CAIRO" ]; then
    echo "ERROR: $CAIRO not found (is SIMPLE_EIFFEL set?)" >&2
    exit 1
fi

mkdir -p "$DEST"

cp "$BUILT" "$DEST/SimpleChat.exe"
echo "staged: SimpleChat.exe ($(du -h "$DEST/SimpleChat.exe" | cut -f1))"

cp "$CAIRO" "$DEST/"
echo "staged: cairo.dll"

if [ -f "$SHAPING/LICENSE-ASSETS.md" ]; then
    cp "$SHAPING/LICENSE-ASSETS.md" "$DEST/"
    echo "staged: LICENSE-ASSETS.md"
else
    echo "WARNING: $SHAPING/LICENSE-ASSETS.md not found - the emoji artwork must not" >&2
    echo "         be redistributed without it" >&2
fi

SRC_ASSETS="$SHAPING/assets/noto-emoji/png/128"
if [ -d "$SRC_ASSETS" ]; then
    mkdir -p "$DEST/assets/noto-emoji/png/128"
    cp -r "$SRC_ASSETS/." "$DEST/assets/noto-emoji/png/128/"
    echo "staged: assets/noto-emoji/png/128 ($(ls "$DEST/assets/noto-emoji/png/128" | wc -l) files)"
else
    echo "WARNING: $SRC_ASSETS not found - emoji will degrade to a note and a box" >&2
fi

cat > "$DEST/client.toml" <<'TOML'
# simple_chat client configuration.
#
# The client reads %APPDATA%\simple_chat\client.toml. Copy this file there and
# edit it, or leave it alone and type the address into the login window once -
# the client writes the file itself when it closes.
#
# NOTHING SECRET LIVES HERE. There is no password field and there never will
# be. If you tick "remember me", the client stores the SESSION as a DPAPI blob
# sealed to your Windows account - unreadable by another user, on another PC,
# or by anything that does not know this application's entropy.

# The servers to try, in order: the primary first, then any standby host.
# https anywhere; plain http only to this machine's own loopback.
server_urls = ["https://rixchat.duckdns.org"]

# Look for a server running on THIS PC before going out to the network.
# The host's own GUI wants this; a friend's GUI does no harm leaving it on -
# the probe is one request with a two-second timeout.
prefers_local = true
local_port = 8080

# Where the window comes up, and how big.
window_x = 100
window_y = 100
window_width = 900
window_height = 700
TOML
echo "staged: client.toml (template)"

echo ""
echo "runnable folder ready: $DEST"
echo "  run it from a command prompt:  cd \"$DEST\" && SimpleChat.exe"
