# Phase 2b — targeted re-review: participants cluster (after the Phase 1b repair)
# Reviewer: adversarial contract reviewer (OOSC2 / DbC / SCOOP, security focus). READ-ONLY.
# Date: 2026-08-29. Source state: files dated Aug 29 22:28; Phase 1b evidence: 50/50 PASS, 0 warnings.

Scope read in full: every class under `src/participants/` (19 files), `src/service/address_parser.e`,
`src/service/addressed_request.e`, `src/config/participant_config.e`, the `feature {PARTICIPANT_DISPATCHER}`
section of `src/web/chat_api.e` (lines 391-520), `testing/participants_assault.e`, `testing/mock_*.e`,
`testing/test_app.e` (registration), `phase1b-participants.txt`, `09-ADDENDUM-PARTICIPANTS.md`,
`approach.md` §8, `phase2-chain.txt`. Read for evidence outside the cluster: `src/bus/event_bus.e`,
`src/bus/event_subscriber.e`, `src/bus/poll_wait.e`, `src/web/chat_shared.e`, `src/web/chat_web_app.e`,
`src/facade/simple_chat_server.e`, `src/domain/chat_event.e`, `src/domain/chat_json.e` (page_from_bytes),
`src/service/rate_limiter.e`, `src/service/chat_user_rules.e`, `src/store/chat_store.e`,
`D:\prod\simple_ai_client\src\providers\claude_code\claude_code_client.e`, `...\ollama\ollama_client.e`,
`D:\prod\simple_process\src\simple_process.e`, `simple_async_process.e`, `D:\prod\simple_scholar\cli\bible_repl.e`
(what `bible.exe` actually does with its argument), EiffelBase 25.02 `string_32.e` / `readable_string_general.e`.

Verdict key: FIXED = the clause now says the right thing and is non-vacuous; DISSOLVED = the defect no longer
exists by construction; PARTIAL = the contract exists but a named part is still missing, vacuous or unsound;
OPEN = not addressed. NEW-* = not in the Phase 2 report.

---

## A. The Phase 2 HIGHs located in this cluster

### [ISSUE 31]: The argv gate had no postcondition on the shaped path (vacuous with a query shaper)
- LOCATION: TOOL_PARTICIPANT.answer / run_tool / arguments_of (tool_participant.e:303-416, 220-236)
- VERDICT: FIXED
- EVIDENCE:
  - One gate for both paths: `arguments_of` (220-236) — `all_safe: across Result as a all is_safe_argument (a) end`,
    `gated: Result.is_empty = not is_safe_argument (trimmed (a_text))`, `one_at_most`. The body (339) feeds it
    `l_query`, which is the raw text (327) or the shaper's output (331) — never anything else.
  - What ran is recorded before it runs: run_tool 403-406 (`executed_arguments := l_copy` … `Result := run_arguments (l_copy)`),
    `recorded: executed_model |=| sequence_of (a_arguments)` (411), `counted: runs = old runs + 1` (413).
  - `answer` now promises over the record, not over the input:
    370 `only_safe_ran: across executed_arguments as a all is_safe_argument (a) end`
    371 `raw_gate: (tier_none and Result.is_success) implies executed_model |=| arguments_model_of (a_request.text)`
    373 `shaped_gate: (tier > none and Result.is_success) implies executed_model |=| arguments_model_of (last_shaped_query)`
    374 `shaped_refused: (tier > none and arguments_of (last_shaped_query).is_empty) implies not Result.is_success`
    375 `ran_when_success: Result.is_success implies runs = old runs + 1`
  - Invariant 506 `only_safe_recorded` keeps it true between calls; `last_shaped_query` is reset per call (317)
    so `shaped_refused` also covers a failed shaper (empty → refused).
  - Non-vacuity checked: with a query shaper at Tier_local, `raw_gate`/`refused_when_unsafe` are vacuous but
    `shaped_gate`/`shaped_refused` bind; with none, the reverse. A body that ran the raw text while a shaper was
    active would fail `shaped_gate` (executed ≠ arguments of the shaped text). Test
    `test_tool_gates_raw_and_shaped` (participants_assault.e:134-162) exercises an "evil" shaper emitting
    `Gen 1:1 | dir` and asserts `runs = 1` unchanged and the last run still the safe one.
- REMAINING/SUGGESTION: `only_safe_ran` speaks of the last run only; a body that ran twice on a failure path is
  excluded only by the preconditions `all_safe` of `run_tool` (395) / `run_arguments` (425). Acceptable: the
  precondition is monitored in Phase 5 and nothing unsafe can pass it. Optional strengthening:
  `no_extra_runs: not Result.is_success implies runs <= old runs + 1`.

### [ISSUE 32]: `refused_when_unsafe` / `phrasing_disclosed` bound to the configured shapers and ignored `via`
- LOCATION: TOOL_PARTICIPANT.effective_query_shaper / effective_response_shaper / answer (tool_participant.e:159-183, 320-386)
- VERDICT: FIXED
- EVIDENCE:
  - 159-183: both `effective_*_shaper (a_request)` are pure, return `shaper_for (v)` when `via` is allowed, else the
    configured one; postconditions `chosen_when_allowed` / `configured_otherwise`.
  - 320-321 the body uses exactly those; 324-325 an unknown `via` is refused first; 377 `unknown_via_refused`.
  - 383 `disclosure_consistent: Result.is_success implies last_response_shaped = (effective_response_shaper (a_request).cost_tier > Tier_none)`
    384 `phrasing_disclosed: (success and last_response_shaped) implies Result.text.has_substring (Phrased_by_prefix + effective_response_shaper (a_request).name)`
    385 `no_false_disclosure: (success and not last_response_shaped) implies not Result.text.has_substring (Footer_break + Phrased_by_prefix)`
    386 `shaper_failure_is_error: attached last_shaper_error as e implies (not Result.is_success and Result.error = e)`
  - `via plain` on a `@qwen`-phrased tool is now raw and undisclosed; `via @mock` on a plain tool is phrased and
    names `@mock` (test `test_via_plain_disclosure_law`, 164-183). `via` must be a configured choice:
    `allows_via` (187-193) is `shapers.has (lowercased)`; `shapers` is filled only by `add_shaper` (288-299) and
    always holds "plain" (invariant 508).
- REMAINING/SUGGESTION: design notes, not defects: (a) one `via` choice selects BOTH edges (query and response) —
  `via @claude` on a tool with a plain query shaper now also sends the raw text to Claude for query shaping (still
  gated). State it in the class note or split into `via` (response) / `ask via` (query). (b) `no_false_disclosure`
  is unsatisfiable for a correct body if the raw tool output itself contains "%Nphrased by " — see NEW-8.

### [ISSUE 9 — participants part]: dispatcher re-entered itself through the doorbell; one global cursor; `unseen` fired in normal operation
- LOCATION: PARTICIPANT_DISPATCHER.wake / dispatch_pending / handle_page / handle_event (participant_dispatcher.e:235-376)
- VERDICT: DISSOLVED (by SCOOP, approach.md §8) + FIXED (the contracts that remained)
- EVIDENCE:
  - `wake` (235-246) only notes the room: `queued`, `only_queued: pending_rooms_model |=| ((old pending_rooms_model) & a_room_id)`,
    `no_work: cursors_model |=| old … and answered_model |=| old … and requests_seen = old requests_seen`.
    EVENT_BUS.wake_one (event_bus.e:143-149) is an asynchronous command on a `separate EVENT_SUBSCRIBER`, so the
    poster never waits and the dispatcher's processor serializes wakes with `dispatch_pending`.
  - Per-room cursors: `cursors: HASH_TABLE [INTEGER_64, INTEGER_64]` (444), `cursor_of` (146-158) defaulting to
    `start_after`, `handle_page` 299 `e.room_id = a_room_id and e.id > cursor_of (a_room_id)`, 301 `cursors.force (e.id, a_room_id)`;
    `cursor_never_backwards` (310), `other_cursors_untouched` (313), `dispatch_pending.monotone` (282-284),
    invariant `cursors_after_start` (528).
  - `unseen` is gone; `handle_event` is idempotent: 327 `if not answered.has (a_event.id) and then attached target_of (a_event)`,
    355 `skipped_when_seen`, 357 `seen_once: … answered_model |=| ((old answered_model) & a_event.id)`, 358 `others_unmarked`.
  - Self-wake is harmless: the bot's own post is `is_bot_authored` → `target_of` = Void (186 `never_bots`).
  - The chain is exercised on one processor in `test_dispatcher_ignores_bots_and_answers_once` (334-368: the same page
    twice is taken once) and `test_dispatcher_per_room_cursors` (383-402).
- REMAINING/SUGGESTION: none for this finding. The driver that calls `dispatch_pending` does not exist yet — see NEW-1.

### [ISSUE 15]: the rate limit was not in the dispatcher's contract; `always_answers` counted a self-incremented integer
- LOCATION: PARTICIPANT_DISPATCHER.handle_event (participant_dispatcher.e:319-376), CHAT_API.dispatcher_try_ask (chat_api.e:437-454)
- VERDICT: PARTIAL
- EVIDENCE (what is right):
  - `dispatcher_try_ask` IS on the path, not only contracted: handle_event 337-338
    `last_ask_key := l_target.limit_key (a_event.sender_id); last_ask_granted := try_ask (api, last_ask_key)`;
    the engine call (343) is inside `if last_ask_granted`. The API decides and counts in one step on the limiter's
    processor (chat_api.e:445-449) with `granted_when_allowed` (451), `recorded` (452), `nothing_when_refused` (453).
  - Clauses: 367 `rate_limited_not_asked: not last_ask_granted implies target_calls (a_event) = old target_calls (a_event)`,
    368 `asked_once: (new request and last_ask_granted) implies (target_calls = old + 1 and asks = old asks + 1)`,
    370 `limit_recorded: … last_ask_key.same_string (p.limit_key (a_event.sender_id))`.
  - `always_answers` is replaced by an accounting chain that reaches the store: 363 `accounted: answers_posted + answer_failures = old … + 1`,
    post_answer 466 `posted_when_created: (answers_posted = old + 1) = (last_post_status = 201)`, and
    CHAT_API.dispatcher_post 487 `appended_on_success: Result = 201 implies service.store.last_event_id = old … + 1`.
    A refusal (Limited_text 340), a busy notice (335) and an apology (349) are all posts. Good.
- EVIDENCE (what is missing):
  1. `via_charged` (the reviewer's clause; addendum 09: "`via claude` … rate-limited under the asker's Claude key")
     does not exist. `limit_key` (participant.e:314-323) is the TOOL's key only; a `via @claude` request on
     `@shape-larry` spends subscription quota under `p:@shape-larry:<asker>`.
  2. The configured `requests_per_hour` (participant_config.e:101, `limits_positive` 281) has no runtime home:
     PARTICIPANT has no such attribute, nothing calls `RATE_LIMITER.set_limit ("p:…")` anywhere in src/ (grep),
     and `limit_for` returns `Default_limit = 1_000_000` (rate_limiter.e:65, 128). Today every clause above is
     satisfied by a limiter that never limits — the Issue 14 problem, reproduced for participants.
  3. `limit_key` prefix collision (Phase 2 LOW, still open): `set_limit ("p:@claude", n)` also governs `p:@claude2:…`.
- REMAINING/SUGGESTION (Eiffel):
  ```eiffel
  -- PARTICIPANT
  requests_per_hour: INTEGER            -- from PARTICIPANT_CONFIG; > 0
  limit_prefix: STRING_8
      -- "p:<handle>:" — the prefix the limiter is configured with; the trailing ":" ends the handle.
      ensure definition: Result.same_string ("p:" + handle.to_string_8 + ":")
  limit_key (a_asker_id: INTEGER_64): STRING_8
      ensure prefixed: Result.starts_with (limit_prefix)
  invariant limit_positive: requests_per_hour > 0

  -- CHAT_API feature {PARTICIPANT_DISPATCHER}
  dispatcher_set_limit (a_prefix: separate READABLE_STRING_8; a_per_hour: INTEGER)
      require positive: a_per_hour > 0
      ensure set: service.limits.limit_for (local_8 (a_prefix) + "x") = a_per_hour
  dispatcher_try_ask_both (a_key, a_via_key: separate READABLE_STRING_8): BOOLEAN
      -- One ask under both keys, or under neither (a via choice is charged to the asker's key for that engine).
      ensure both_or_none: Result = (old service.limits.is_allowed (local_8 (a_key)) and old service.limits.is_allowed (local_8 (a_via_key)))
             nothing_when_refused: not Result implies service.limits.counts_model |=| old service.limits.counts_model

  -- PARTICIPANT_DISPATCHER
  via_target_of (a_event: CHAT_EVENT): detachable PARTICIPANT   -- registry.find (parse (body).via) when the via names a participant
  last_via_key: STRING_8
  handle_event ensure
      via_charged: (not (old answered_model).has (a_event.id) and last_ask_granted and attached via_target_of (a_event) as vt)
                   implies last_via_key.same_string (vt.limit_key (a_event.sender_id))
  make ensure limits_configured: across registry.participants as p all dispatcher_limit_for (p.limit_prefix) = p.requests_per_hour end
  ```
  Phase 5: `test_dispatcher_refuses_past_requests_per_hour` (a real `set_limit`, the (n+1)-th ask posts Limited_text and `asks = n`).

### [ISSUE 16]: restart cursor 0 — the first wake re-answered history
- LOCATION: PARTICIPANT_DISPATCHER.make / cursor_of (participant_dispatcher.e:42-67, 146-158); CHAT_API.dispatcher_start_after (chat_api.e:393-400)
- VERDICT: FIXED
- EVIDENCE: `make (…; a_start_after: INTEGER_64)` with `start_non_negative` (46), 62 `starts_where_told: start_after = a_start_after`,
  `cursor_of` returns `start_after` for a room never pulled (152, 157 `start_when_unknown`), 155 `at_least_start`,
  invariant 528 `cursors_after_start: across cursors as ic all ic >= start_after end`; `dispatcher_start_after =
  service.store.last_event_id` (chat_api.e:397-399). `answered` need not survive a restart: everything at or below
  `start_after` is never taken, so "never twice" holds across restarts; the accepted cost is that a request whose
  answer was in flight at the crash is never answered. Test `test_dispatcher_restart_cursor_honoured` (370-381).
- REMAINING/SUGGESTION: no production code reads `dispatcher_start_after` (it is exported to
  `{PARTICIPANT_DISPATCHER}` only, and the dispatcher never calls it — its creator must). See NEW-1 for the
  creation/wiring path; add `dispatcher_start_after` to the creator's export set or make the dispatcher read it
  in its own creation procedure.

### [ISSUE 26]: no runtime bound on the Ollama participant / shaper; Claude's `timeout_seconds` had no contract
- LOCATION: TIMED_ENGINE (timed_engine.e), OLLAMA_PARTICIPANT.make/answer (ollama_participant.e:24-63),
  OLLAMA_SHAPER (ollama_shaper.e:96-131), CLAUDE_SHAPER (claude_shaper.e:163-194), CLAUDE_CODE_PARTICIPANT.answer (claude_code_participant.e:165-175)
- VERDICT: PARTIAL
- EVIDENCE (right): every engine inherits TIMED_ENGINE (`timeout_seconds`, `elapsed_seconds`, `last_timed_out`,
  `record_run` 461-472 with `timed_out_when_over`, invariant `overrun_is_timeout` 477); each `make` takes
  `a_timeout_seconds > 0` and sets it (ollama_participant.e:33, 40; ollama_shaper.e:100, 105; claude_shaper.e:166, 170);
  each `answer`/`shape` has `ensure then bounded_runtime … timeout_is_error` (ollama_participant.e:61-62,
  ollama_shaper.e:129-130, claude_shaper.e:192-193, claude_code_participant.e:172-173, tool_participant.e:380-381).
  Honest by design: nothing clamps `elapsed_seconds`.
- EVIDENCE (missing):
  1. The bound has no mechanism: `OLLAMA_CLIENT` (simple_ai_client) has no timeout API at all (its curl call carries
     `--connect-timeout 2` only for the availability probe; the chat request has no `--max-time`), and neither
     participant nor shaper passes anything to the client. A hung local model still pins the dispatcher's processor
     for as long as curl waits; `timeout_is_error` then makes the (late) answer an error. The reviewer accepted
     "advisory until simple_process can kill" — but `SIMPLE_ASYNC_PROCESS` already has `wait_seconds` (234) and
     `kill` (244), so the TIMED_ENGINE note (timed_engine.e:5-7) is out of date for tools, and for Ollama the fix is
     one curl flag.
  2. CLAUDE_CODE_PARTICIPANT never propagates its timeout to the client: `make` (32-62) calls
     `set_working_directory` but not `a_client.set_timeout_seconds (a_timeout_seconds)`; the client keeps
     `Default_timeout_seconds = 300` (claude_code_client.e:418). No invariant ties the two.
  3. `bounded_runtime` is the contrapositive of invariant `overrun_is_timeout` (Phase 2 LOW; still restated).
- REMAINING/SUGGESTION:
  ```eiffel
  -- CLAUDE_CODE_PARTICIPANT invariant
  client_timed: client.timeout_seconds = timeout_seconds
  -- OLLAMA_PARTICIPANT / OLLAMA_SHAPER invariant (needs OLLAMA_CLIENT.set_timeout_seconds → curl --max-time <n>)
  client_bounded: client.timeout_seconds = timeout_seconds
  -- TIMED_ENGINE note: "for child processes the bound is real (SIMPLE_ASYNC_PROCESS.wait_seconds + kill); for
  -- HTTP engines it is the client's --max-time; `elapsed_seconds' is never clamped either way."
  ```
  Dependency task (simple_ai_client): `OLLAMA_CLIENT.set_timeout_seconds` honored by the request.

### [ISSUE 33 / D3]: `@claude` in the vault with tools and memory; `image_path` a model-chosen path the dispatcher would read
- LOCATION: CLAUDE_CODE_PARTICIPANT (claude_code_participant.e:32-62, 96-147, 183-189); PARTICIPANT_ANSWER (participant_answer.e:211-225, 245-263, 269-273)
- VERDICT: PARTIAL — (a) directory: PARTIAL; (b) tools: OPEN in substance; (c) image_path: FIXED at construction, OPEN at the read
- EVIDENCE:
  (a) Directory. `make` requires `sandboxed: is_sandbox_directory_for (a_working_directory, a_handle)` (41);
      invariant `sandboxed` (184) and `client_sandboxed: client.working_directory.same_string (working_directory)` (185);
      the client is pinned in `make` (49). Test `test_claude_vault_directory_refused` (284-299) proves the vault
      path is refused. But read what the predicate actually tests (104-117): the last two path segments are
      "participants" and the handle name, and the lowercased path contains neither "obsidian" nor "vault". It does
      NOT test "under `<data_dir>`" (the class note, lines 8-10, and the D3 decision say `<data_dir>/participants/<handle>`;
      the predicate has no `data_dir`), does NOT reject `..`/`.` segments, does NOT require an absolute path (the
      test at 276 asserts `data/participants/claude/` is accepted — relative to whatever the server's CWD is at
      launch), and its blacklist is a substring match:
        - `C:\Users\LJR19\OneDrive\DOCUME~1\OBSIDI~1\Scholars\participants\claude` (8.3 short names) passes;
        - any junction/symlink/`subst` drive named `participants\claude` passes;
        - `C:\Users\LJR19\.claude\participants\claude` passes (a directory under Claude's own config root).
      Also a correctness point on the promise itself (note lines 10-11 "no skill, memory or private note loads"):
      `claude -p` loads `~/.claude` (user-level CLAUDE.md, settings.json permissions, MCP servers, hooks, plugins)
      regardless of the working directory, and CLAUDE.md files from every ANCESTOR of the working directory.
      `D:\prod\CLAUDE.md` exists (12.7 KB), so a sandbox at `D:\prod\simple_chat\data\participants\claude` inherits
      it. The directory rule limits *project* context; it does not, and cannot, give "no context".
  (b) Tools. `tools_disabled := True` (53), invariant `no_tools: tools_disabled` (186). Nothing reads this
      attribute. `CLAUDE_CODE_CLIENT` has no tool-policy feature; the command it runs is
      `claude -p --output-format json --model "…" [--append-system-prompt-file "…"] < prompt` (claude_code_client.e:294-302)
      via `cmd.exe /c run.bat` (270). No `--disallowedTools`, no `--tools`, no `--setting-sources`. The child runs
      with the default headless policy PLUS whatever `permissions.allow` Larry's user-level settings grant to every
      claude process on this machine. `no_tools` is a renamed clause: a boolean that constrains nothing. This is
      the D3 promise "tools disabled" — not delivered.
  (c) image_path. `is_safe_image_path` (245-263): 5..200 chars, no "..", no ":", no leading "\" or "/", ".png"/".jpg"
      — as precondition of `make_success` (214) and invariant (272); `answer` repeats it (174). Test
      `test_image_path_rules` (229-244) covers drive, parent, UNC, root, extension, length. Good. But:
        - no feature anywhere resolves or reads the image (no `dispatcher_post_image`, no `store_upload` path in the
          `{PARTICIPANT_DISPATCHER}` section; the dispatcher posts text only). "The dispatcher resolves only under
          the participant's own output directory" (note 194-197) is a sentence, not a clause.
        - Windows reserved device names pass: `CON.png`, `NUL.png`, `COM1.png`, `AUX.png`, `PRN.png`, `LPT1.png`
          (a basename before the first dot that is a device name refers to the device in Win32). Opening `CON.png`
          for reading blocks on console input forever — the dispatcher's processor, and with it every participant,
          hangs on a model-chosen name. See NEW-5.
- REMAINING/SUGGESTION (Eiffel):
  ```eiffel
  -- PARTICIPANT_RULES (so PARTICIPANT_CONFIG can refuse at load time, D6)
  is_sandbox_directory_for (a_path, a_data_dir, a_handle: READABLE_STRING_GENERAL): BOOLEAN
      -- `a_path' is `a_data_dir' + "\participants\" + name of `a_handle', both absolute, after separator
      -- normalization; no "." / ".." segment; no 8.3 short-name segment ("~" followed by digits).
      ensure absolute: Result implies is_absolute_path (a_path)
             clean: Result implies not has_dot_or_short_segment (a_path)
             under_data_dir: Result implies normalized (a_path).starts_with (normalized (a_data_dir) + "\participants\")
             own_directory: Result implies normalized (a_path).ends_with ("\participants\" + a_handle.substring (2, a_handle.count))
  -- CLAUDE_CODE_PARTICIPANT.make (…; a_data_dir …) require sandboxed: rules.is_sandbox_directory_for (a_working_directory, a_data_dir, a_handle)
  -- Tools: make the flag a property of the command, not of the participant:
  invariant
      no_tools: client.tools_disabled                         -- CLAUDE_CODE_CLIENT gains it; its batch_script_preview
      project_only: client.ignores_user_settings              --   ensures the corresponding CLI flags are present
      client_timed: client.timeout_seconds = timeout_seconds
  ```
  Dependency task (simple_ai_client): `CLAUDE_CODE_CLIENT.set_tools_disabled` / `set_ignores_user_settings` with
  `build_batch_script ensure tools_off: tools_disabled implies Result.has_substring (Tools_off_flag)`; verify the
  flag names against the installed CLI (`--disallowedTools` / `--tools ""` / `--setting-sources`), and keep a
  curated CLAUDE.md in the sandbox with a note that ancestor CLAUDE.md files still load.
  Image read (when Phase 4 adds it): `resolved_image (a_relative): STRING_32 require is_safe_image_path ensure
  under_sandbox: Result.starts_with (working_directory + "\")`, plus `no_device_name` (NEW-5) and "exists and is a
  regular file, ≤ upload_bytes" before `store_upload`.

### [ISSUE 38]: `is_safe_argument` unspecified (empty, controls, NUL, a leading `-`); whole-text vs per-element uses disagreed
- LOCATION: TOOL_PARTICIPANT.is_safe_argument / is_printable_ascii / arguments_of (tool_participant.e:195-236);
  BIBLE_TOOL_PARTICIPANT.is_safe_argument / is_reference_shape / is_command_shape (bible_tool_participant.e:345-398);
  SHAPE_TOOL_PARTICIPANT.is_slug (shape_tool_participant.e:468-488)
- VERDICT: PARTIAL
- EVIDENCE (right): the deferred feature now carries the laws every allowlist obeys (199-204):
  `never_empty`, `bounded: … <= Argument_maximum` (512), `printable: is_printable_ascii (a_text)` (32..126 — no
  NUL, no tab, no line break), `no_option: a_text.code (1) /= 45`. Both descendants effect it with
  `ensure then definition`. The whole-text/per-element split is gone: `arguments_of` is the single gate and both
  `answer` (339) and `run_tool` (395) speak of its elements. Bible: letters/digits/space/`:.,-` with a digit, or
  `/[a-z]{1,16}` plus at most one word (382 letters only; 387-395 one word ≤ 32) — `Gen 1:1 | dir`, `-rf`, `""`,
  `/lex a b`, `Genesis` refused (test 208-226). Shape: `[a-z0-9_]{1,64}`.
- EVIDENCE (still open):
  1. The Bible command allowlist is a SHAPE, not a SET. `bible.exe` (D:\prod\simple_scholar\cli\bible_repl.e:54-61)
     joins all argv with spaces into one line and dispatches on `/<cmd>` (529, 558-600, 3576-3690). Commands
     admitted by `/[a-z]{1,16}` today include the state-changing `/reload`, `/cache clear`, `/default <ver>`,
     `/load <abbr>` (the two-word form is refused, the one-word form prints usage), and the process commands
     `/quit`, `/exit`, `/help`, `/repl` (`/repl` alone would enter the interactive REPL and hang the tool until
     the timeout). None of these is a member's business. The class note (349-350) defers the closed set to Phase 4;
     the addendum asked for "an allowlisted set of slash commands". The gate the whole design leans on should be
     closed now, in the contract.
  2. A leading `/` is admitted by design (bible.exe's own command prefix, not a Windows option) — fine for
     bible.exe; state it in `no_option`'s comment so the general law is not mistaken for "no `/`".
  3. The general law admits cmd metacharacters (`"`, `%`, `^`, `&`, `|`, `<`, `>`, `;`, `(`, `)`, `!`, backtick);
     the two real allowlists exclude them, the mock does not. See NEW-2: simple_process has no argv launch.
- REMAINING/SUGGESTION (Eiffel):
  ```eiffel
  -- BIBLE_TOOL_PARTICIPANT
  Allowed_commands: ARRAY [STRING_32]
      -- Exactly bible.exe's read-only one-shot commands; never quit/exit/help/repl/load/default/reload/cache/clear.
      once Result := <<"define", "search", "entity", "episode", "scholar", "assertions", "ddd", "overlap", "ane", "web",
                      "compare", "etymology", "xref", "people", "dss", "pseudepigrapha", "list", "versions">> end
  is_command_shape (a_text): BOOLEAN
      ensure only_allowed: Result implies across Allowed_commands as c some
                 (a_text.count = c.count + 1 or else a_text.code (c.count + 2) = 32) and a_text.substring (2, c.count + 1).same_string (c) end
  -- TOOL_PARTICIPANT.is_safe_argument (general law)
      no_shell_metacharacters: Result implies not has_any_of (a_text, "%"%%^&|<>;()!`")
  ```

---

## B. The Phase 2 MEDIUMs located in this cluster

### [M-1]: handle alphabet/case unconstrained; `limit_key`'s `to_string_8` on a non-Latin-1 handle
- LOCATION: PARTICIPANT_RULES.is_valid_handle (participant_rules.e:387-402); PARTICIPANT invariant `handle_valid` (participant.e:355); limit_key (314-323)
- VERDICT: FIXED
- EVIDENCE: `@[a-z0-9_-]{1,32}` with `at_sign`, `bounded`, `lowercase`, `no_blank`; every constructor requires it;
  the invariant makes `handle.to_string_8` legal (ASCII ⇒ `is_valid_as_string_8`). `limit_key` requires `a_asker_id > 0`
  and messages always have a sender > 0 (CHAT_EVENT invariant `sender_or_system`, chat_event.e:120). Test `test_handle_rules`.

### [M-2]: `parse` untied to the body, no boundary rule, handle-only body contradictory; `via train`, `@claude,`, `@claudette`, bare `@claude`
- LOCATION: ADDRESS_PARSER.leading_handle / parse / via_of (address_parser.e:38-60, 109-141, 166-183)
- VERDICT: FIXED
- EVIDENCE: the leading token is the whole run of handle characters and must be followed by end/blank/`,`/`:`
  (52 + `whole_token` 59); `parse` ensures `known_handle`, `from_body`, `text_in_body`, `text_not_blank`,
  `via_in_body`, `boundary` (134-140); a handle with nothing after it gives Void (129); `via` is honored only when
  the choice is `plain` or handle-shaped (176, `choice_shaped` 181). Tests `test_prefix_spoof_and_boundary`,
  `test_handle_only_body_is_not_a_request`, `test_via_parsing`. Unicode probes: a leading bidi control (U+200E…)
  makes `code (1) /= 64` → not addressed (a false negative, never a false positive); `@handle` inside a word
  ("email@claude", "ask @claude") is not addressed; `＠` (U+FF20) is not `@`. Note that EiffelBase's STRING_32
  `to_lower` is Unicode-aware (string_32.e:1650 → `character_properties`), so "@\u212Aevin" (KELVIN SIGN) folds
  to "@kevin" — it resolves to the real participant, not to a different one; harmless.

### [M-3]: aliases had no home; registry/parser/config disagreed; one-letter aliases accepted
- LOCATION: PARTICIPANT_REGISTRY.register / register_alias / invariant (participant_registry.e:255-297); PARTICIPANT_CONFIG.add_alias (198-210)
- VERDICT: FIXED
- EVIDENCE: aliases live in the registry, lowercase (`aliases_lowercase` 296), each targeting a registered handle
  (`alias_targets_exist` 294) and never itself a handle (`aliases_are_not_handles` 295; `register` requires
  `not_an_alias` 258, `register_alias` requires `not_a_handle` 275) — an alias cannot shadow a handle in either
  order. `is_valid_alias` requires ≥ 2 characters (407). Test `test_registry_alias_resolution`.
- REMAINING: LOW — `register_alias` accepts "@" aliases that `leading_handle` can never produce (e.g. "@ro bot",
  uppercase inside is folded but a blank is not): dead entries. Require `is_valid_handle (a_alias.as_lower)` when
  the alias starts with "@". And the alias-vs-handle collision across participants is detected only by these
  preconditions at startup — a config typo is a crash, not an explained refusal (NEW-3).

### [M-4]: `via` had no runtime home (`allow_via` unused; case-sensitive)
- LOCATION: TOOL_PARTICIPANT.shapers / allows_via / add_shaper / shaper_for (tool_participant.e:88-97, 147-157, 187-193, 288-299)
- VERDICT: FIXED
- EVIDENCE: `shapers_model: MML_MAP`, `allows_via` = `shapers.has (lowercased)`, `shaper_for` requires `allowed`,
  `add_shaper` ensures `added`/`allowed`; `unknown_via_refused` on `answer` (377); case folded (190). The wiring
  from `PARTICIPANT_CONFIG.allow_via` to `add_shaper` is Phase 4 (the registry builder does not exist yet).

### [M-5]: `max_concurrent` / bounded FIFO had no contract
- LOCATION: PARTICIPANT_DISPATCHER.queue_depth_of / enqueue / dequeue / Max_queue_depth (participant_dispatcher.e:167-176, 483-499, 511); handle_event 334-335, 372-373
- VERDICT: FIXED (contract) — vacuous in this design (INFO)
- EVIDENCE: `Max_queue_depth = 8`, `queues_bounded` invariant (529), `refused_when_full` (372), `queue_settled` (373),
  Busy_text posted when full (335). On one dispatcher processor `enqueue → answer → dequeue` is a straight line
  (342-344), so the depth never exceeds 1 and the busy branch is unreachable; PARTICIPANT.in_flight is never
  changed by anyone, so `capacity: has_capacity` (participant.e:340) is always true and `max_concurrent := 2`
  (tool_participant.e:58) is decoration. Not wrong; record it in the class notes so nobody relies on it.

### [M-6]: `always_answers` forced a count when the post could not happen; system/image events reached `limit_key` with asker 0
- LOCATION: PARTICIPANT_DISPATCHER.target_of / handle_event (178-190, 319-376)
- VERDICT: FIXED
- EVIDENCE: `target_of` is Void for bots, non-messages and unaddressed bodies (186-189); `ignores_non_messages`
  (362), `nothing_for_non_requests` (364); a room the bot cannot post in is an `answer_failure` with no ask
  (`only_member_rooms` 365-366); `limit_key` is reached only inside the request branch with a message sender.
  Test 334-368 covers bot, system and unaddressed events.

### [M-7]: echo/footer self-reported; jointly unsatisfiable for small limits; footer forgeable by a human
- LOCATION: TOOL_PARTICIPANT (echo_recorded 505, ran_when_success 375, Minimum_reply_characters 497, too_small_refused 378, echo_fits 379, composed 443-462)
- VERDICT: FIXED
- EVIDENCE: `executed_query` is derived from the record (`echo_recorded` invariant; `echoed` 412); a limit under
  200 is refused rather than lied about (322-323, 378); `Reply_overhead = 64` ≥ prefix + break + "phrased by " +
  a 33-char name; `composed` ensures `bounded`, `echoes`, `disclosed`. The human-forged "footer" is moot: a human
  message is `is_bot_authored = False` by the store (`bot_flag_truthful`, chat_store.e:119) and `humans_unmarked`
  (chat_service.e:122); the dispatcher decides on the flag, never on the glyph.

### [M-8]: tool output unbounded
- LOCATION: TOOL_PARTICIPANT.run_tool (407-409, 414 `output_bounded`), Output_maximum 494
- VERDICT: FIXED — 65 536 characters, cut before the response shaper sees it (test `test_tool_reply_limits`).

### [M-9]: PARTICIPANT did not require its bot user stored/active/marked
- LOCATION: PARTICIPANT invariant (participant.e:356-359); every `make`; CHAT_API.dispatcher_can_post (427-435)
- VERDICT: FIXED
- EVIDENCE: `bot_is_bot`, `bot_stored`, `bot_active`, `bot_marked` invariants and creation preconditions; and,
  because `bot_user` is a copy, the store is re-asked at every request (`dispatcher_can_post`: stored, bot,
  active, member — 430-431) and again inside `dispatcher_post` (465-466). Bot answers carry the marker and the
  flag by the service's `marker_enforced` / `right_event` (chat_service.e:117, 121).

### [M-10]: PARTICIPANT_CONFIG invariants did not match the constructors (`requests_per_hour = 0` could not reach `set_limit`)
- LOCATION: PARTICIPANT_CONFIG.make / set_limits / is_complete / invariant (participant_config.e:24-68, 159-170, 241-258, 277-285)
- VERDICT: FIXED
- EVIDENCE: born complete for its kind (`engine_given_for_kind` 33, `complete` 64/280), `limits_positive` (281),
  `set_limits require positive` (161), shapers/aliases/via shaped and lowercase (282-284). Test
  `test_participant_config_completeness`.
- REMAINING: the sandbox rule and cross-participant address uniqueness are not config-level outcomes (NEW-3).

### [M-11]: one `last_session_id` for all rooms
- LOCATION: CLAUDE_CODE_PARTICIPANT.sessions_model / session_of / remember_session (claude_code_participant.e:66-92, 151-161)
- VERDICT: FIXED — per-room map with `mapped`/`findable`; test 277-282.

### [M-12] (server_config, adjacent): handle uniqueness case-sensitive vs a case-insensitive parser
- VERDICT: DISSOLVED — handles are lowercase by rule (`is_valid_handle.lowercase`); the parser folds once (address_parser.e:48).

### Phase 2 LOWs in this cluster, briefly
- `limit_key` prefix collision — OPEN (see ISSUE 15 item 3).
- PARTICIPANT_REQUEST looser than ADDRESSED_REQUEST / no asker id — FIXED (`via_shape` 35/56, `asker_id`, `make_addressed`).
- SHAPING_BRIEF frame omits `description`, exported mutable `examples` — FIXED (`rest_unchanged` 590; `examples` is `{NONE}`, read by `example (i)`).
- Missing frames on small commands — FIXED (`set_query_shaper`/`set_response_shaper`/`add_shaper` 269-298; `set_limits`/`set_engine`/`set_shapers` 166-196).
- Mutable STRING_32 handles as registry keys — FIXED (`handle.twin` 260; `handles_are_keys` 293).
- `bounded_runtime`/`timed` restate the invariant — OPEN (cosmetic; ISSUE 26 item 3).
- Dispatcher postconditions reference `{NONE}` features — OPEN, legal (only preconditions are export-checked): `parser` in
  `ignores_unaddressed` (361) and `only_addressed` (188). Export `parser` (or `is_addressed (a_body)`) to ANY to make the contracts readable by clients.

---

## C. Standing security invariants, checked clause by clause

| Invariant | Where it lives | Holds? |
|---|---|---|
| Chat text reaches a tool only as argv elements | `arguments_of` (220-236) → `run_tool` (389-416) → `run_arguments (a_arguments: ARRAYED_LIST)` (420-429) | Yes in the contract; the engine body is Phase 4 and simple_process offers no argv API (NEW-2) |
| …each passing `is_safe_argument` | `all_safe` at 233, 395, 425; `only_safe_ran` 370; `only_safe_recorded` 506 | Yes |
| …never a shell string | class note 5-7; no clause can say it; the only launch API is a command line (NEW-2) | Not provable yet |
| …never an option | `no_option` (203, `-` only); `/` admitted for bible.exe by design (ISSUE 38) | Yes for `-`; `/` is the tool's own prefix |
| …bounded | `bounded` 201 (512), `Output_maximum` 494, `Minimum_reply_characters` 497 | Yes |
| Shaped output gated exactly like raw text | `shaped_gate` 373 / `shaped_refused` 374 vs `raw_gate` 371 / `refused_when_unsafe` 372; one `arguments_of` | Yes |
| `via` must be a configured choice | `allows_via` 187-193, `unknown_via_refused` 377, `PARTICIPANT_REQUEST.via_shape` 56 | Yes (config→`add_shaper` wiring is Phase 4) |
| CLAUDE_CODE_PARTICIPANT sandboxed by construction | directory: `sandboxed` 41/184 (weak predicate, no data_dir, relative/`..`/8.3 pass); tools: `no_tools` 186 is a free boolean; user-level `~/.claude` always loads | Partly (ISSUE 33) |
| `image_path` relative, no parent, image extension, bounded | `is_safe_image_path` 245-263, precondition 214, invariant 272 | Yes at construction; no read path exists; device names pass (NEW-5) |
| Bot answers carry the marker and `is_bot` | `dispatcher_post` → `service.post_message (u, r, …)` with `u.is_bot` (465-471); service `marker_enforced`/`right_event` | Yes |
| Dispatcher never answers bots | `target_of.never_bots` 186; `ignores_bots` 360; the flag comes from the store, not the glyph | Yes |
| Never answers twice | `answered` set (327-328, `seen_once` 357, `skipped_when_seen` 355); restart: `start_after` = store's last id | Yes (set need not survive a restart) |
| Rate-limited per asker, on the path | `try_ask (api, …)` at 338 before `answer` at 343; `dispatcher_try_ask` atomic on the limiter's processor | Called, yes; but no `p:` limit is ever configured and `Default_limit` = 1 000 000 (ISSUE 15) |
| Bounded queues | `Max_queue_depth` 511, `queues_bounded` 529 | Yes (unreachable on one processor) |
| Per-room cursors monotone | `cursor_never_backwards` 310, `monotone` 282, `cursors_after_start` 528 | Yes |
| Registry aliases cannot shadow handles | `not_an_alias` 258, `not_a_handle` 275, invariants 294-295 | Yes |
| ADDRESS_PARSER vs look-alikes / bidi / in-word `@` | `code (1) = 64` (47), ASCII handle codes after folding (49), boundary (52) | Yes — folding of Kelvin/İ-type look-alikes maps to the real handle, never to another |

SCOOP (the point the task asked to check exactly): `api: separate CHAT_API` (380) is never called directly. Every
touch is through a routine whose formal is `separate CHAT_API`: `pull_page` (276→383), `can_post` (331→393),
`try_ask` (338→399), `post_reply` (458→407), `display_name_of`/`room_name_of` (475-476→417/425). Each such routine
holds the API's processor only for its own duration and returns copies (`make_from_separate`) or scalars.
`request_of (a_event, l_target)` (343) is fully evaluated — its two brief API calls done and released — before
`l_target.answer (…)` starts; `answer` therefore runs on the dispatcher's processor with NO separate reference
held. A two-minute `claude -p` or a hung Ollama call pins only the dispatcher (and the driver waiting on it), never
the API: every HTTP request keeps being served. Wakes issued by the API's bus during `dispatcher_post` are
asynchronous commands queued on the dispatcher's processor (lock passing on the synchronous `dispatcher_post`
makes the back-call legal); they run after `dispatch_pending` returns. `receive_status (a_status: separate CHAT_STATUS)`
locks the status's processor only for its empty body. Non-separate `a_key`/`a_text` actuals attach to the API's
`separate READABLE_STRING_*` formals and are copied there with `local_8`/`local_32`. Verdict on the stall concern:
FIXED. What SCOOP does NOT yet have is a way to bring the dispatcher up — NEW-1.

---

## D. New findings

### [NEW-1]: The dispatcher cannot be created, subscribed or driven on its own processor — the SCOOP design has no code home
- LOCATION: PARTICIPANT_DISPATCHER.make (participant_dispatcher.e:42-67), note 5-7 ("the dispatcher's driver, whose
  SCOOP wait condition is `has_pending'"); CHAT_API `feature {PARTICIPANT_DISPATCHER}` (chat_api.e:391-520);
  CHAT_API.subscribe (209-221); CHAT_WEB_APP.start (chat_web_app.e:46-62); SIMPLE_CHAT_SERVER.start (simple_chat_server.e:81-113)
- VERDICT: NEW-MEDIUM
- EVIDENCE:
  1. No production caller of `dispatch_pending` (grep: only the dispatcher and the tests); no driver class in
     src/ or apps/; approach.md §8 names "the dispatcher processor" but no driver.
  2. No subscription path: `CHAT_API.subscribe` needs a member's token and a room; the dispatcher has neither.
     The `{PARTICIPANT_DISPATCHER}` section has `dispatcher_page/can_post/try_ask/post/display_name/room_name` but
     no `dispatcher_subscribe`. Without it the bus never wakes the dispatcher.
  3. `dispatcher_start_after` (393-400) is exported to `{PARTICIPANT_DISPATCHER}` only; the dispatcher never calls
     it and its creator (root/facade) cannot.
  4. `make (a_api: separate CHAT_API; a_parser: ADDRESS_PARSER; a_log: CHAT_LOG; …)`: a creator on another
     processor cannot pass a non-separate ADDRESS_PARSER/CHAT_LOG to a `separate PARTICIPANT_DISPATCHER` creation —
     the actuals would be separate from the dispatcher's viewpoint and the formals are not (compile error under
     SCOOP). The tests pass because they create everything on one processor (fixture 410-436). The note (13-14)
     already says "Phase 4 builds the registry, parser and log on this processor", i.e. a different creation
     procedure is intended but does not exist.
- REMAINING/SUGGESTION:
  ```eiffel
  -- CHAT_API feature {PARTICIPANT_DISPATCHER, SIMPLE_CHAT_SERVER}
  dispatcher_subscribe (a_subscriber: separate EVENT_SUBSCRIBER)
      -- The dispatcher is this process: no token, every room.
      ensure live: last_subscription > 0 and service.bus.is_subscribed (last_subscription)
  dispatcher_start_after: INTEGER_64   -- as now, with the wider export

  -- PARTICIPANT_DISPATCHER
  make_on_own_processor (a_api: separate CHAT_API)
      -- Build registry, parser and log here from the shared settings; start after the store's last id; subscribe.
      ensure starts_at_store: start_after = start_after_read_from (a_api)
             subscribed: is_subscribed

  -- DISPATCHER_DRIVER (its own processor; the POLL_WAIT idiom, poll_wait.e:42-53)
  drain (a_dispatcher: separate PARTICIPANT_DISPATCHER)
      require ready: a_dispatcher.has_pending          -- SCOOP wait condition
      do a_dispatcher.dispatch_pending end
      ensure drained: not a_dispatcher.has_pending      -- exact: the driver still holds the dispatcher here
  run  -- from until stopped loop drain (dispatcher) end
  ```

### [NEW-2]: "argv, never a shell string" has no implementation path — simple_process launches command lines only; the general allowlist law admits cmd metacharacters
- LOCATION: TOOL_PARTICIPANT.is_printable_ascii / is_safe_argument (tool_participant.e:195-216), note 5-7, 23-25;
  D:\prod\simple_process\src\simple_process.e:100 `launch (a_command: READABLE_STRING_GENERAL)`, 116 `launch_in`,
  186 `shell_output`; simple_async_process.e:139 `start (a_command: READABLE_STRING_GENERAL)`; MOCK_TOOL_PARTICIPANT.is_safe_argument (mock_tool_participant.e:162-174)
- VERDICT: NEW-MEDIUM
- EVIDENCE: neither SIMPLE_PROCESS nor SIMPLE_ASYNC_PROCESS accepts an argument list; both take one command
  string (CreateProcess takes a command line; the quoting is the caller's). The base law `printable` (202) admits
  `"`, `%`, `^`, `&`, `|`, `<`, `>`, `;`, `(`, `)`, `!` and the backtick; BIBLE and SHAPE happen to exclude them,
  the mock admits all but `| ; & < > \` $`. When Phase 4 joins `executed_arguments` into a command line, the
  invariant the design leans on rests on each descendant's private charset, not on a law of the deferred class.
  (bible.exe itself re-joins argv with spaces — bible_repl.e:54-61 — so for it argv-vs-string is moot; the
  spawning is what matters.)
- REMAINING/SUGGESTION: add to `is_safe_argument`'s ensure:
  `no_shell_metacharacters: Result implies not has_any_of (a_text, "%"%%^&|<>;()!`")` (a pure helper in
  TOOL_PARTICIPANT), and either (dependency task) `SIMPLE_PROCESS.launch_with_arguments (a_program: READABLE_STRING_GENERAL; a_arguments: LIST [READABLE_STRING_GENERAL])`
  with Windows-rule quoting proven in its own tests, or a `command_line_of (a_program, a_arguments): STRING_32`
  in TOOL_PARTICIPANT with `ensure quoted_each: across a_arguments as a all Result.has_substring ("%"" + a + "%"") end`
  and `require all_safe` so the joining can only ever see allowlisted text.

### [NEW-3]: Configuration mistakes about the sandbox and about alias/handle collisions are preconditions (a crash at startup), not explained refusals (D6)
- LOCATION: PARTICIPANT_CONFIG.make / invariant (participant_config.e:24-68, 277-285: `working_directory` for
  `Kind_claude_code` is only "non-empty"); SERVER_CONFIG invariant `unique_handles` (server_config.e:290-291; no
  alias/handle uniqueness); PARTICIPANT_REGISTRY.register/register_alias preconditions (participant_registry.e:257-258, 273-275);
  CLAUDE_CODE_PARTICIPANT.make `sandboxed` (41)
- VERDICT: NEW-MEDIUM
- EVIDENCE: a TOML with `working_directory = "…/Scholars"` or an alias equal to another participant's handle is
  `is_valid` at load time; the first violation is a PRECONDITION_VIOLATION while the registry is being built —
  the server dies without a message naming the entry. The Phase 2 synopsis decision D6 asks that user-facing
  rules be outcomes.
- REMAINING/SUGGESTION: move the sandbox predicate to PARTICIPANT_RULES (see ISSUE 33) and add
  `PARTICIPANT_CONFIG invariant sandboxed: kind.same_string (Kind_claude_code) implies rules.is_sandbox_directory_for (working_directory, data_dir, handle)`
  (the config knows `data_dir`); `SERVER_CONFIG invariant unique_addresses: across participant_list as p all across p.aliases_model as a all not has_participant_handle (a) and not is_alias_elsewhere (a, p) end end`;
  `make_from_file` appends an explained `validation_errors` entry instead of building the entry.

### [NEW-4]: A human's display name may carry the bot marker — the badge that `bot_marked` relies on is not reserved for bots
- LOCATION: PARTICIPANT invariant `bot_marked` (participant.e:359); PARTICIPANT_CONFIG.marked_display_name (111-119);
  CHAT_USER_RULES.is_valid_display_name / is_forbidden_in_name (chat_user_rules.e:40-72: controls, zero-width, bidi — U+1F916 allowed);
  CHAT_SERVICE.create_user / create_first_admin `valid_display` (chat_service.e:246, 263) — cross-cluster
- VERDICT: NEW-MEDIUM (cross-cluster; recorded here because this cluster defines the badge)
- EVIDENCE: D4 made the marker authenticate MESSAGES (`bot_flag_truthful`, `humans_unmarked`). Identities are the
  other channel: an admin (or a rename route, when it exists) can give a person the display name
  "🤖 Claude"; the roster and the view show a second Claude. Nothing in the rules forbids it.
- REMAINING/SUGGESTION: `CHAT_USER_RULES.is_valid_human_display_name (a_name): BOOLEAN` = `is_valid_display_name (a_name) and not a_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)`;
  `create_user`/`create_first_admin`/any rename: `require valid_display: rules.is_valid_human_display_name (a_display_name)`;
  `CHAT_USER invariant humans_unmarked: not is_bot implies not display_name.has_substring (Bot_marker)`.

### [NEW-5]: `is_safe_image_path` admits Windows reserved device names — a blocking read from a model-chosen name
- LOCATION: PARTICIPANT_ANSWER.is_safe_image_path (participant_answer.e:245-263)
- VERDICT: NEW-MEDIUM
- EVIDENCE: `CON.png`, `NUL.png`, `PRN.png`, `AUX.png`, `COM1.png`…`COM9.png`, `LPT1.png`…`LPT9.png` (and the
  same with a subdirectory prefix) satisfy every clause. Win32 resolves a basename whose part before the first
  dot is a device name to the device; `CON.png` opened for reading waits for console input — forever, on the
  dispatcher's processor, i.e. every participant stops. `NUL.png` yields an empty file. With tools disabled the
  model cannot create files, but it can still name one.
- REMAINING/SUGGESTION:
  ```eiffel
  is_reserved_device_basename (a_path: READABLE_STRING_GENERAL): BOOLEAN
      -- Is the last segment's part before its first "." one of CON, PRN, AUX, NUL, COM1-9, LPT1-9 (any case)?
  is_safe_image_path ensure then
      no_device_name: Result implies not is_reserved_device_basename (a_path)
      no_trailing_dot_or_blank: Result implies (a_path.code (a_path.count) /= 32 and a_path.code (a_path.count) /= 46)
  ```
  and, at the read (Phase 4), "exists, is a regular file, size ≤ upload_bytes" before opening.

### [NEW-6]: `answered` grows without bound
- LOCATION: PARTICIPANT_DISPATCHER.answered / handle_event 328 (participant_dispatcher.e:447-448)
- VERDICT: NEW-LOW
- EVIDENCE: every request id ever taken stays in the table for the process lifetime (a long-running server with
  a chatty room: unbounded memory, slow `answered_model`).
- REMAINING/SUGGESTION: ids below every room's cursor can never be handled again (`handle_page` 299), so
  `prune_answered` in `dispatch_pending` may drop `answered` entries `< min cursor`, with
  `ensure kept_above_min: across answered as ic all @ic.key >= minimum_cursor end` and the idempotence clauses
  restated over `answered_model + (ids <= minimum_cursor)`.

### [NEW-7]: No rescue around a participant's `answer`; an exception leaks the queue slot and kills the processor
- LOCATION: PARTICIPANT_DISPATCHER.handle_event 342-344 (enqueue / answer / dequeue), no `rescue`; PARTICIPANT.answer note "Never raises" (participant.e:338)
- VERDICT: NEW-LOW
- EVIDENCE: "never raises" is a comment; a precondition failure inside an engine (e.g. CHAT_ERROR.make with an
  empty message from a client library) propagates out of `dispatch_pending`, `dequeue` is skipped (depth stays
  at 1 forever for that participant), and the driver's next call on the dispatcher raises. One bad answer silences
  every participant.
- REMAINING/SUGGESTION: `handle_event` gets a `rescue` that records `answer_failures := answer_failures + 1`,
  dequeues, logs (`log.error`), and `retry`s into the accounting branch; contract `accounted` then holds on
  the exceptional path too. Test: a MOCK_PARTICIPANT whose `answer` raises.

### [NEW-8]: `no_false_disclosure` is unsatisfiable when the raw output contains the footer text
- LOCATION: TOOL_PARTICIPANT.answer 385; composed 443-462
- VERDICT: NEW-LOW
- EVIDENCE: a mechanical output containing "%Nphrased by " (a verse quoting the phrase, a shape instance) makes a
  correct body violate the clause.
- REMAINING/SUGGESTION: keep a fact instead of a text search: `last_footer: STRING_32` set in `composed`;
  `no_false_disclosure: (success and not last_response_shaped) implies last_footer.is_empty`;
  `phrasing_disclosed: … implies (last_footer.same_string (Phrased_by_prefix + name) and Result.text.ends_with (last_footer))`.

### [NEW-9]: CLAUDE_CODE_PARTICIPANT takes an externally owned client and never propagates its timeout
- LOCATION: claude_code_participant.e:32-62 (`a_client` kept as `client`, 47; `set_working_directory` 49; no `set_timeout_seconds`); invariant `client_sandboxed` 185
- VERDICT: NEW-LOW
- EVIDENCE: whoever else holds `a_client` can call `set_working_directory` later; the invariant then fails at the
  participant's next call (a crash, not a refusal). `client.timeout_seconds` stays 300 while the participant says 120.
- REMAINING/SUGGESTION: create the client inside (`create client.make_in_directory (working_directory)`), or copy
  it; `client_timed: client.timeout_seconds = timeout_seconds` (also under ISSUE 26).

### [NEW-10]: `via` semantics at the edges (design notes)
- LOCATION: TOOL_PARTICIPANT.effective_query_shaper 159-170 (one choice for both edges); ADDRESS_PARSER.parse 123-125 (via stripped for every participant); PARTICIPANT.answer (non-tools ignore `via`)
- VERDICT: NEW-LOW
- EVIDENCE: `@claude tell me about X via @qwen` reaches Claude as "tell me about X" — the member's `via` is
  silently dropped for non-tool participants; and for tools one `via` selects both shapers.
- REMAINING/SUGGESTION: `PARTICIPANT.honours_via: BOOLEAN` (False for AI participants) and in the dispatcher
  `via_ignored_is_told: (attached request via and not target.honours_via) implies the reply text has a one-line note`,
  or keep `via` in the text for participants that do not honor it (`parse` takes the registry's answer).

### [NEW-11]: Assault gaps for this cluster (Phase 5)
- VERDICT: NEW-LOW
- The granted path is untested: no test where `dispatcher_can_post` is True (a memory-store bot member), so
  `try_ask → answer → post_answer`, `asked_once`, `limit_recorded`, `Limited_text` and `Busy_text` never run;
  `dispatcher_try_ask` is untested; `is_sandbox_directory_for` has no `..`, 8.3 or absolute/relative case;
  `is_safe_image_path` has no device-name case; no test that a participant raising leaves the dispatcher alive;
  no test that `via @claude` is charged to the asker's Claude key (once it exists).

### [NEW-12]: INFO
- `bible.exe` writes one file per one-shot call into its `data/output/` (bible_repl.e:5056-5095, sanitized
  name, timestamped) — disk growth bounded only by the participant's rate limit, which today is unbounded (ISSUE 15).
- `/repl` is admitted by `is_command_shape` and would start bible.exe's interactive loop on the dispatcher's
  processor until the timeout kills it (ISSUE 38 closed-set fix removes it).
- PARTICIPANT.in_flight / has_capacity / max_concurrent and Max_queue_depth are decoration on one processor (M-5).
- `EVENT_BUS.unsubscribe (a_ticket)` in CHAT_API (223-228) is not token-gated — any client with a ticket number
  can unsubscribe another's waiter; outside this cluster, noted in passing.

---

## Summary

| Verdict | HIGH (Phase 2) | MEDIUM (Phase 2) | LOW (Phase 2) | NEW |
|---|---|---|---|---|
| FIXED | 3 (31, 32, 16) | 11 (M-1…M-11) | 4 | — |
| DISSOLVED | 1 (9, participants part) | 1 (M-12) | — | — |
| PARTIAL | 4 (15, 26, 33, 38) | 0 | — | — |
| OPEN | 0 | 0 | 3 (prefix collision; restated invariant; `{NONE}` in ensure) | — |
| NEW-HIGH | — | — | — | 0 |
| NEW-MEDIUM | — | — | — | 5 (NEW-1…NEW-5) |
| NEW-LOW | — | — | — | 6 (NEW-6…NEW-11) |
| INFO | — | — | — | NEW-12 |

**Assessment: PASS WITH CONDITIONS.** The repair did what the review asked where it mattered most: the argv gate
is one feature (`arguments_of`) with a recorded model and non-vacuous postconditions on both the raw and the
shaped path; `via` has a home at both edges with honest disclosure; the dispatcher is idempotent, per-room,
starts after the store's last id, calls the limiter on the real path, and — the SCOOP point — never holds the
API's processor while an engine runs. The conditions are the places where a clause was written but nothing
underneath it is true yet: (1) `no_tools: tools_disabled` is a free boolean — CLAUDE_CODE_CLIENT runs
`claude -p` with no tool or setting-source flag and the child inherits Larry's user-level `~/.claude` permissions,
so the D3 promise "tools disabled" is not delivered (ISSUE 33 b; a dependency task on simple_ai_client);
(2) the sandbox predicate must test "exactly `<data_dir>\participants\<handle>`, absolute, dot-free,
short-name-free" rather than a last-two-segments + substring blacklist, and the class note must stop claiming
that no context loads (ISSUE 33 a); (3) the participant rate limit is a chain of true clauses over a limiter
whose default is one million per hour, with `requests_per_hour` unwired and `via` uncharged (ISSUE 15);
(4) the dispatcher has no creation, subscription or driver path a separate creator can use (NEW-1);
(5) the Bible command allowlist must be a closed set and the base law must forbid shell metacharacters,
because the only process launcher takes a command line (ISSUE 38, NEW-2); (6) device names in `image_path`
(NEW-5). None of these requires undoing anything in the repair; each is an added clause plus, for (1) and (5),
a small library task outside this repository.
