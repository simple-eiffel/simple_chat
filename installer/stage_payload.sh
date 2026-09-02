#!/bin/bash
# =============================================================================
# stage_payload.sh - assemble installer/src/, everything SimpleChat.iss packs
# =============================================================================
#
#   usage:  installer/stage_payload.sh
#
# Run it from anywhere; it finds the project itself. It expects both release
# targets to have been built already:
#
#     /d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_server
#     /d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_client
#
# `release' builds BOTH binaries per target: simple_chat_lean.exe (contracts
# compiled out - the shipping build) and simple_chat_dbc.exe (every
# precondition, postcondition and invariant left in - the diagnostic build).
# The installer ships the LEAN pair. The _dbc pair stays in F_code for
# defect-chasing and is deliberately not packaged.
#
# WHAT IS STAGED, AND WHY EACH ONE HAS TO BE
#
#   client/SimpleChat.exe          the client target, RENAMED. Every Eiffel
#                                  target in this project finalizes to
#                                  simple_chat.exe, so the client, the server
#                                  and the test runner would otherwise be three
#                                  files with one name - and a taskkill by
#                                  image name would be a loaded gun.
#   client/cairo.dll               simple_cairo links cairo.LIB, an IMPORT
#                                  library: the DLL must resolve at PROCESS
#                                  START or the client does not launch at all.
#                                  There is no runtime check to degrade through.
#   client/assets/.../128/         the Noto artwork simple_shaping resolves
#                                  emoji against. SW_SHAPING.make looks beside
#                                  the RUNNING EXECUTABLE, never in the working
#                                  directory. Missing artwork is not a crash -
#                                  the robot is just a box.
#   client/LICENSE-ASSETS.md       the artwork's licence. Shipping it WITH the
#                                  artwork is the condition of redistributing it.
#   server/SimpleChatServer.exe    the server target, renamed for the same reason.
#   caddy/caddy.exe                the pinned front door (see THIRD-PARTY.md).
#                                  NOT downloaded here - see the note below.
#
# The caddy payload is deliberately NOT fetched by this script: pinning means
# pinning, and a build step that silently pulls "whatever is latest" is how a
# pin rots. installer/THIRD-PARTY.md carries the tag, the URL and the SHA-512,
# and the two commands to re-fetch and re-verify it by hand.
# =============================================================================

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
SRC="$HERE/src"
ROOT="${SIMPLE_EIFFEL:-/d/prod}"

SHAPING="$ROOT/simple_shaping"
CAIRO="$ROOT/simple_cairo/cairo.dll"

SERVER_BUILT="$PROJECT/EIFGENs/simple_chat_server/F_code/simple_chat_lean.exe"
CLIENT_BUILT="$PROJECT/EIFGENs/simple_chat_client/F_code/simple_chat_lean.exe"

fail () { echo "ERROR: $*" >&2; exit 1; }

[ -f "$SERVER_BUILT" ] || fail "$SERVER_BUILT not found.
       Build it first:
         /d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_server"
[ -f "$CLIENT_BUILT" ] || fail "$CLIENT_BUILT not found.
       Build it first:
         /d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_client"
[ -f "$CAIRO" ] || fail "$CAIRO not found (is SIMPLE_EIFFEL set?)"
[ -f "$SRC/caddy/caddy.exe" ] || fail "$SRC/caddy/caddy.exe not found.
       Fetch the pinned release by hand - the tag, URL and SHA-512 are in
       installer/THIRD-PARTY.md - and unzip caddy.exe and LICENSE into
       installer/src/caddy/."

echo "staging into $SRC"

# --- clean everything except the hand-fetched caddy payload -----------------
rm -rf "$SRC/client" "$SRC/server" "$SRC/common"
mkdir -p "$SRC/client" "$SRC/server" "$SRC/common"

# --- client -----------------------------------------------------------------
cp "$CLIENT_BUILT" "$SRC/client/SimpleChat.exe"
echo "  client/SimpleChat.exe        $(du -h "$SRC/client/SimpleChat.exe" | cut -f1)"

cp "$CAIRO" "$SRC/client/cairo.dll"
echo "  client/cairo.dll             $(du -h "$SRC/client/cairo.dll" | cut -f1)"

if [ -f "$SHAPING/LICENSE-ASSETS.md" ]; then
    cp "$SHAPING/LICENSE-ASSETS.md" "$SRC/client/"
    echo "  client/LICENSE-ASSETS.md"
else
    fail "$SHAPING/LICENSE-ASSETS.md not found - the emoji artwork must not be
       redistributed without it"
fi

SRC_ASSETS="$SHAPING/assets/noto-emoji/png/128"
[ -d "$SRC_ASSETS" ] || fail "$SRC_ASSETS not found - emoji would degrade to a box"
mkdir -p "$SRC/client/assets/noto-emoji/png/128"
cp -r "$SRC_ASSETS/." "$SRC/client/assets/noto-emoji/png/128/"
echo "  client/assets/...png/128     $(ls "$SRC/client/assets/noto-emoji/png/128" | wc -l) files, $(du -sh "$SRC/client/assets/noto-emoji/png/128" | cut -f1)"

cp "$HERE/templates/client.toml.in" "$SRC/client/"
echo "  client/client.toml.in"

# --- server -----------------------------------------------------------------
cp "$SERVER_BUILT" "$SRC/server/SimpleChatServer.exe"
echo "  server/SimpleChatServer.exe  $(du -h "$SRC/server/SimpleChatServer.exe" | cut -f1)"

for f in run_server.cmd start_server.cmd start_server_hidden.vbs stop_server.cmd \
         create_admin.cmd create_user.cmd view_log.cmd backup_room.cmd \
         restore_backup.cmd HOSTING-GUIDE.html server.toml.in ; do
    cp "$HERE/templates/$f" "$SRC/server/"
    echo "  server/$f"
done

# Windows launchers must have CRLF: a .cmd with LF endings mangles the last
# token of every line, and a stray CR is how "goto :eof" becomes "goto :eof\r".
for f in "$SRC/server"/*.cmd "$SRC/server"/*.vbs ; do
    sed -i 's/$/\r/; s/\r\r$/\r/' "$f"
done
echo "  (server launchers normalized to CRLF)"

# --- common -----------------------------------------------------------------
cp "$HERE/templates/README.txt" "$SRC/common/"
cp "$HERE/THIRD-PARTY.md" "$SRC/common/"
echo "  common/README.txt"
echo "  common/THIRD-PARTY.md"

cat > "$SRC/common/LICENSE-SIMPLECHAT.txt" <<'LICENSE'
MIT License

Copyright (c) 2026 Larry Rix

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
LICENSE
sed -i 's/$/\r/' "$SRC/common/LICENSE-SIMPLECHAT.txt"
echo "  common/LICENSE-SIMPLECHAT.txt"

# --- caddy (hand-fetched; just verify and name the licence) -----------------
if [ -f "$SRC/caddy/LICENSE" ] && [ ! -f "$SRC/caddy/LICENSE-CADDY" ]; then
    cp "$SRC/caddy/LICENSE" "$SRC/caddy/LICENSE-CADDY"
fi
[ -f "$SRC/caddy/LICENSE-CADDY" ] || fail "installer/src/caddy/LICENSE-CADDY missing
       (Caddy is Apache-2.0; its LICENSE ships with the release zip)"
echo "  caddy/caddy.exe              $(du -h "$SRC/caddy/caddy.exe" | cut -f1)"
echo "  caddy/LICENSE-CADDY"

echo ""
echo "payload staged. Now compile:"
echo "  \"/c/Program Files (x86)/Inno Setup 6/ISCC.exe\" installer/SimpleChat.iss"
