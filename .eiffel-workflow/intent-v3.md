# Intent v3: simple_chat — amendment for the thick client

Date: 2026-08-29 · After Phase 1m · Base: `intent-v2.md` (carried forward in full except where struck below) · Design: `spec/10-ADDENDUM-THICK-CLIENT.md`.

## The change
Larry: **thick first, no browser.** The client is a simple_widgets application; the server is found by the client (a service on the host's PC, or a remote host, or a member's own local replica later); live updates reach the thick client by long-poll on the doorbell; `simple_shaping` and an image decoder move to the front of the queue.

## Struck from intent-v2
- Acceptance: "a `<script>` body renders as text in the UI (XSS vector) and the page carries a CSP" — there is no page.
- Q4's cookie consequence (`cookie_secure`) — sessions are Bearer tokens only; `SERVER_CONFIG.is_public` remains for the door.
- Q6 (escaping, CSP, Alpine) — moot; the one-insertion-point discipline moves to `CHAT_JSON` (one codec, both directions).
- Q13: `VISION2_WEBVIEW_HOST`, Spike B.
- Dependency rows: `simple_browser`, `simple_htmx` SSE attributes.

## Added acceptance criteria
- [ ] The client renders `שלום 🤖 Χριστός` natively: Hebrew right-to-left, Greek intact, the marker as one picture identical on every member's screen; no browser process exists on the machine.
- [ ] With SSE disabled, a message from another member appears in the client within 2 s over the WAN by long-poll alone.
- [ ] The client, started with `prefers_local`, finds a running local service and uses it; with the service stopped it falls back to the configured URL and says which it is using.
- [ ] The client never writes the session token to disk in clear (DPAPI-protected when remembered; otherwise memory only) and never places it in a URL.

## Deep review of the new parts

### Q15. Long-poll and thread-per-connection: does the server run out of threads?
**Risk:** each waiting client pins a handler thread for up to 25 s. **Answer:** at this scale (a friend group, ≤ 50 clients) that is ≤ 50 mostly-sleeping threads — fine. The cap is `seconds ≤ 25` and one outstanding wait per session (a second wait from the same session releases the first), so a misbehaving client cannot multiply threads. Revisit only if the group grows past a hundred.

### Q16. GUI thread vs poller thread
**Risk:** `SW_*` widgets are not thread-safe; a poller thread touching the view crashes or corrupts. **Answer:** the poller only ever appends to `pending` under its MUTEX; the GUI timer calls `presenter.pump` → `poller.drain` on the GUI thread. The presenter is single-threaded by construction. Enforced by contract (`drain` is the only reader) and by the concurrent assault in Phase 5.

### Q17. Token at rest on the client
**Risk:** "stay logged in across restarts" means a token on disk; plain text in `client.toml` is readable by any process running as the user. **Answer:** remember it under DPAPI (`CryptProtectData`, user scope) — an addition to `simple_encryption` (`protect_for_user` / `unprotect_for_user`) — or don't remember it at all until that exists. Never in clear, never in a URL, never logged.

### Q18. Untrusted images decoded in-process
**Risk:** a browser sandboxes image decoding; WIC decodes inside our process. **Answer:** WIC is the decoder Windows itself uses for the shell, Photos and Explorer thumbnails, and it is patched with the OS; the server already validates magic bytes and size, and when re-encoding to PNG on the server exists (same WIC code) the client only ever decodes server-produced PNGs. Acceptable for a private friend group; recorded as a known trade-off.

### Q19. Which emoji picture?
**Risk:** color-font emoji need COLR/CBDT support cairo 1.17.2 lacks, and each member's fonts differ. **Answer (proposed, decided at the shaping research):** inline images from one open set shipped with the client, keyed by code-point sequence (with ZWJ and variation selectors handled). The 🤖 marker is then literally the same picture for everyone — which is what an identity badge wants.

### Q20. Failover without split-brain
**Risk:** two hosts accepting posts produce two histories with overlapping ids. **Answer:** v1 = one primary; replica mode later pulls the log by id and forwards posts; promotion manual; schema v2 reserves `epoch`. Automatic election is out of scope until someone actually needs it.

## Dependency audit — additions and changes
| Need | Result |
|---|---|
| simple_widgets (1.x: `SW_WINDOW`, `SW_CHAT_THREAD`, `SW_TEXT_BOX`, `SW_IMAGE`, `SW_TABS`, `SW_STATUS_BAR`, docking) | **present**; shaping/bidi/fallback BLOCKED (S05 §6), JPEG queued (S05 §7) |
| simple_cairo | present; PNG in; needs `show_glyphs` + `win32_font_face_for_logfont` for the shaping bridge |
| `CONDITION_VARIABLE.wait_with_timeout` | **present in EiffelBase** (`base/ise/synchronization`), so the long-poll waiter needs no ISE thread library |
| simple_shaping | **MISSING — Tier 2, now first** |
| WIC decoder | MISSING — codec in simple_shell or `simple_wic` |
| simple_winhttp | MISSING — promote `OCR_HTTP` (+HTTPS, headers, receive timeout, bytes POST) |
| DPAPI protect/unprotect | MISSING — addition to simple_encryption |
| SHELL_TRAY | MISSING — as before |
| simple_browser, simple_htmx | **no longer used** |

## MML Decision
Unchanged (YES-Optional); the client cluster adds `requests_model` (transport), `pending_model` (poller), `members_model` (presenter).

## Approval
Decided by Larry, 2026-08-29: "Thick first and no browser." Amendment applied to the Phase 1 skeletons; compile evidence in `evidence/phase1-thick-client.txt`.
