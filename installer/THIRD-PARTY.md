# Third-party components shipped in the SimpleChat installer

Everything here is redistributed under a licence that permits it, and every
binary is pinned to an exact release. Nothing in the build pipeline fetches
"whatever is latest": `stage_payload.sh` refuses to run if the pinned Caddy
payload is not already in place, because a pin that a script silently refreshes
is not a pin.

---

## Caddy — the front door

| | |
|---|---|
| Version | **v2.11.4** |
| Platform | windows / amd64 |
| Source | <https://github.com/caddyserver/caddy/releases/tag/v2.11.4> |
| Asset | `caddy_2.11.4_windows_amd64.zip` |
| URL | <https://github.com/caddyserver/caddy/releases/download/v2.11.4/caddy_2.11.4_windows_amd64.zip> |
| SHA-512 (zip) | `cd5ccfd86a4b40732cf715890d0dca5bf3f63adefec5a7914de85adf240c60ce7e5d2791631b88ef9758e46b23bb1730e020b9c5d696889740b284ffd4788e35` |
| SHA-256 (zip) | `1708333f79e274c7697285afe6d592ab39314e0b131e9ec6bea08ad27df62ebf` |
| SHA-256 (`caddy.exe`) | `5cb9ab71e5756ce72840b8234177a2f40c8b4ab47a806b8e841e2b784e9df62b` |
| Size (`caddy.exe`) | 49,535,488 bytes |
| Licence | Apache-2.0, shipped as `LICENSE-CADDY` beside the executable |

Caddy publishes **SHA-512** in `caddy_2.11.4_checksums.txt`; that is the
authoritative figure and the one verified against the upstream file. The
SHA-256 values are recorded here as a convenience for `sha256sum` and
`Get-FileHash`.

### Re-fetching and re-verifying the pin

```bash
mkdir -p installer/src/caddy && cd installer/src/caddy
curl -sL -o caddy.zip \
  https://github.com/caddyserver/caddy/releases/download/v2.11.4/caddy_2.11.4_windows_amd64.zip

# must match the SHA-512 above, and the upstream checksums file
sha512sum caddy.zip
curl -sL https://github.com/caddyserver/caddy/releases/download/v2.11.4/caddy_2.11.4_checksums.txt \
  | grep windows_amd64.zip

unzip -o caddy.zip          # yields caddy.exe, LICENSE, README.md
cp LICENSE LICENSE-CADDY
```

### Where it is installed, and why there

`C:\ProgramData\SimpleChat\caddy.exe` — **not** in `Program Files` beside the
server.

That is not a preference. `CADDY_FRONT_DOOR.make` resolves the executable as

```eiffel
executable := l_env.current_working_path.extended ("caddy.exe").name
```

so Caddy is looked for in the server's **working directory**. Every launcher
the installer ships (`run_server.cmd`, and the scheduled task through
`start_server_hidden.vbs`) sets that working directory to
`C:\ProgramData\SimpleChat`, which is also where `data\`, `server.toml` and
`server.log` live. Putting `caddy.exe` anywhere else means the front door
reports `caddy executable not found` and the server stays private.

---

## Noto Color Emoji artwork

| | |
|---|---|
| What | `assets/noto-emoji/png/128/` — 3,768 PNG files, ~30 MB on disk |
| Staged from | `$SIMPLE_EIFFEL/simple_shaping/assets/noto-emoji/png/128` |
| Licence | shipped as `LICENSE-ASSETS.md`, staged from `simple_shaping` |

`simple_shaping` owns this pin; the installer copies whatever that library
carries, together with its licence file. The licence **must** travel with the
artwork — that is the condition of redistributing it, and `stage_payload.sh`
fails the build rather than ship the PNGs without it.

`SW_SHAPING.make` looks for these beside the **running executable**, never in
the working directory, so they are installed into
`C:\Program Files\SimpleChat\assets\noto-emoji\png\128`. Their absence is not a
crash — `simple_shaping` degrades to a note and a box — but the robot marker
stops being a robot.

They are packed with Inno's `nocompression` flag: PNG is already a deflate
container, so re-compressing 3,768 of them under `lzma2/max` costs minutes of
build time for a negligible gain. This is the same call `RixQwen.iss` makes for
its quantized GGUF weights.

---

## cairo

| | |
|---|---|
| What | `cairo.dll`, 2,359,808 bytes |
| Staged from | `$SIMPLE_EIFFEL/simple_cairo/cairo.dll` |
| Licence | LGPL-2.1 / MPL-1.1 (dual), as upstream cairo |

`simple_cairo` owns this pin. The DLL is linked through an **import** library,
so it must resolve at process start: without it `SimpleChat.exe` does not
launch at all, and the failure looks exactly like a crash. There is no runtime
check to degrade through, which is why it is a hard failure in
`stage_payload.sh` too.

---

## What is *not* bundled

`usp10`, `gdi32`, `dwrite`, `winhttp`, `shell32`, `schtasks`, `wscript` and
`taskkill` are Windows' own. SQLite is compiled into the server through
`simple_sql`. Nothing else needs an installer.
