# Phase 2 — cluster review: participants + apps/server (reviewer report, verbatim)
# Adjudication by the orchestrator follows in phase2-claude-response.md

Scope read in full: 17 classes under `src/participants/`, 5 under `apps/server/`, plus `address_parser.e`, `addressed_request.e`, `participant_config.e`, `front_door.e`, `dynamic_dns.e`, `event_subscriber.e`, `mock_participant.e`, `chat_assault.e`.

### ISSUE: The security gate has no postcondition on the shaped path — `refused_when_unsafe` is vacuous whenever a query shaper is configured
- LOCATION: TOOL_PARTICIPANT.answer — tool_participant.e line 67: `refused_when_unsafe: (not is_safe_argument (a_request.text) and query_shaper.cost_tier = {SHAPER}.Tier_none) implies not Result.is_success`; run_tool line 77: `all_safe: across a_arguments as a all is_safe_argument (a) end`
- SEVERITY: HIGH
- DESCRIPTION: The spec's contract was `not is_safe_argument (a_request.text) implies not Result.is_success` and the shaping addendum promised "nothing an LLM writes ever reaches argv without passing is_safe_argument". The moment `query_shaper.cost_tier > Tier_none`, line 67 is `False implies …` and `answer` promises nothing about what ran. The only remaining gate is `all_safe` — a precondition of a deferred feature, an obligation on the caller inside `answer`'s body, not a guarantee of `answer`. A shaper reading untrusted chat emits `Gen 1:1 | dir`; a body that forgets the check satisfies every postcondition. No query records what was executed, so the contract cannot name the thing it must constrain.
- SUGGESTION: `executed_arguments` + `executed_model: MML_SEQUENCE [STRING_32]`; `run_tool` ensure `recorded`; `answer` ensure `only_safe_ran: across executed_arguments as a all is_safe_argument (a) end`; `raw_gate` and `shaped_gate` (see full text in the orchestrator's response file).

### ISSUE: `refused_when_unsafe` and `phrasing_disclosed` bind to the configured shapers and ignore `via` — contradictory under `via plain` / `via @qwen`
- LOCATION: tool_participant.e line 67 (`query_shaper.cost_tier`), line 70 (`phrasing_disclosed: (Result.is_success and response_shaper.cost_tier > Tier_none) implies Result.text.has_substring (Phrased_by_prefix)`); participant_request.e line 41 (`via`)
- SEVERITY: HIGH
- DESCRIPTION: (a) default query shaper plain, request `… via @qwen`: line 67 demands failure for any text not already a verse reference — `via` query-shaping contractually dead. (b) default response shaper `@qwen`, request `… via plain`: line 70 demands a "phrased by" footer on an answer nothing phrased — the implementer must lie or fail. No `no_false_disclosure` clause; the footer need not name the shaper.
- SUGGESTION: `effective_query_shaper (a_request)` / `effective_response_shaper (a_request)` pure; `last_response_shaped: BOOLEAN`; rewrite both clauses against the effective shaper; add `no_false_disclosure` and `shaper_failure_is_error`.

### ISSUE: Dispatcher re-enters itself through the doorbell and races across rooms; `unseen` precondition fires in normal operation and the bus then unsubscribes the dispatcher for good
- LOCATION: participant_dispatcher.e lines 43-44 (`cursor`), 57, 70 (`unseen: a_event.id > cursor`), 72 (`cursor := a_event.id`); event_subscriber.e line 38 (`counted`); event_bus.e lines 7-8 ("a subscriber that raises is unsubscribed … never retried")
- SEVERITY: HIGH
- DESCRIPTION: The bus wakes subscribers synchronously on the poster's thread. The dispatcher posts its answer from inside `wake` → `post_message` → `bus.ring` → `wake` re-entered on the same thread mid-loop; the inner wake handles the outer loop's not-yet-handled events and advances `cursor`; the outer loop resumes and calls `handle_event` with `a_event.id <= cursor` → precondition violation (deterministic), and the outer `wake`'s `counted` fails too. Independently, two members posting in two rooms give two concurrent wakes on threads reading one global cursor with per-room pulls — double answers. Either exception → the bus unsubscribes the dispatcher: every participant goes silent. A single global cursor over per-room pulls also drops events below a cursor advanced by another room.
- SUGGESTION: `wake` only enqueues the room id (`pending_rooms_model: MML_SET`); a single worker drains; per-room cursors (`cursors_model: MML_MAP [INTEGER_64, INTEGER_64]`); make `handle_event` idempotent (drop `unseen`; `skipped_when_seen`); `answered_model: MML_SET [INTEGER_64]` with `seen_once`.

### ISSUE: Restart replay — `cursor = 0` at creation means the first wake re-answers history
- LOCATION: participant_dispatcher.e line 35: `fresh: cursor = 0 and requests_seen = 0 and answers_posted = 0`; line 57
- SEVERITY: HIGH
- DESCRIPTION: After a restart the first wake pulls everything after 0 (≤ 500 per pull) and every historical human `@claude …` must be answered again by `always_answers`.
- SUGGESTION: `make (…; a_start_after)` ensure `starts_where_told: cursor = a_start_after`; SIMPLE_CHAT_SERVER.start passes `store.last_event_id`.

### ISSUE: The rate limit is not in the dispatcher's contract — a body that calls Claude before checking `limits` passes
- LOCATION: participant_dispatcher.e lines 74-80; spec 05-CONTRACT-DESIGN.md lines 192-195 (`rate_limited_not_asked`, `asked_once`)
- SEVERITY: HIGH
- DESCRIPTION: The generalization dropped the clauses tying the engine call to the limiter. `always_answers` was weakened from the store-observed form to a self-incremented counter.
- SUGGESTION: `target_of (a_event): detachable PARTICIPANT` pure; `rate_limited_not_asked`, `asked_once`, store-observed `always_answers`, `limit_recorded`, `via_charged`.

### ISSUE: `no_orphan` is satisfiable by forgetting the child — `has_child_process` is a reference test
- LOCATION: caddy_front_door.e lines 68-71 (`Result := process /= Void`), 87-92 (`stop`: `process := Void`); front_door.e line 72 (`no_orphan: not has_child_process`)
- SEVERITY: HIGH
- DESCRIPTION: A body that fails to kill, or kills without waiting, passes identically. The spec's `supervised: is_serving implies child_is_alive` and `caddyfile_written` were dropped.
- SUGGESTION: `has_child_process` = `attached process as p and then p.is_running`; `stop` ensure `child_gone`; invariant `serving_has_child`; `start` ensure `caddyfile_written`.

### ISSUE: No runtime bound on OLLAMA_PARTICIPANT / OLLAMA_SHAPER; CLAUDE_CODE_PARTICIPANT has the attribute but no contract
- LOCATION: ollama_participant.e line 16 (no timeout), 41-46; ollama_shaper.e line 16, 41-45; claude_code_participant.e line 47 (`timeout_seconds`), 54-59 (`answer`, no `ensure then`)
- SEVERITY: HIGH
- DESCRIPTION: PARTICIPANT_CONFIG carries `timeout_seconds` (default 120) but the Ollama engines never receive it; with `max_concurrent = 1` a hung local model silences that participant forever and pins the dispatcher.
- SUGGESTION: `timeout_seconds`, `elapsed_seconds`, `last_timed_out` on both; `bounded_runtime`, `timeout_is_error`; note the bound is advisory until simple_process can kill.

### ISSUE: Chat text drives `claude -p` inside the vault with skills and memory; `image_path` is a model-chosen path the dispatcher will read and post — neither is constrained
- LOCATION: claude_code_participant.e lines 3-7, 22-23, 58; participant_answer.e line 17 (`path_given_if_attached`), 43 (`image_path`)
- SEVERITY: HIGH
- DESCRIPTION: The argv-only invariant holds syntactically, but the argument is an agent that may run Bash and read MEMORY.md; no contract pins its tool policy. `image_path` is whatever the model returns; `store_upload` bounds it to PNG/JPEG by signature, so the floor is exfiltration of any image on the host via a prompt-injected path. The vault working directory exposes private memory notes to anyone who can type `@claude` — an intent-level choice, flagged so it is made knowingly.
- SUGGESTION: `is_safe_image_path` (relative, no `..`, no drive/UNC, `.png`/`.jpg`, ≤ 200 chars) as precondition + invariant; the dispatcher resolves only under `<data_dir>/participants/<handle>/`; `tools_disabled` invariant; a dedicated working directory with a curated CLAUDE.md, not the vault root.

### MEDIUM (14): handle alphabet/case unconstrained (`limit_key` `to_string_8` on non-Latin-1 handles violates a precondition); ADDRESS_PARSER `parse` untied to the body, no boundary rule, handle-only body contradictory; aliases have no home (registry/parser/config disagree; one-letter aliases accepted); `via` has no runtime home (`allow_via` unused; case-sensitive); `max_concurrent`/bounded FIFO have no contract; `always_answers` forces a count when the post cannot happen, system/image events reach `limit_key` with asker 0; echo/footer contracts self-reported, jointly unsatisfiable for small limits, footer forgeable by a human (add `humans_unmarked` to post_message); `is_safe_argument` has no postcondition and whole-text vs per-element uses disagree; tool output unbounded; PARTICIPANT does not require its bot user stored/active; PARTICIPANT_CONFIG invariants do not match the constructors (`requests_per_hour = 0` cannot reach `set_limit`); NO_FRONT_DOOR.check_health resurrects a stopped door; Caddyfile takes `public_name` unescaped, resolves `caddy.exe`/`Caddyfile` relative to CWD, no `admin off`; `--create-admin` rules have no contract home (no `has_admin`); one `last_session_id` for all rooms.

### LOW (8): `update_url.no_token` wrong predicate; `limit_key` prefix collision with longest-prefix limits; PARTICIPANT_REQUEST looser than ADDRESSED_REQUEST and no asker id; SHAPING_BRIEF frame omits `description`, exported mutable `examples`; missing frames on small commands; mutable STRING_32 handles as registry keys; NO_FRONT_DOOR.make accepts a doored config; `bounded_runtime`/`timed` restate the invariant; dispatcher postconditions reference `{NONE}` features.

### INFO: no `MML_MAP.has` misuse in this cluster; `aliases_model`/`allow_via_model` are SEQUENCEs with set semantics (MML_SET would say what is meant); `models_consistent` invariants are tautologies over the builders; `PARTICIPANT.answer`/`SHAPER.shape` are state-changing functions (document); self-wake through the doorbell is harmless once re-entrancy is removed; no contract references an API key; a human quoting "Claude: …" at line start triggers the alias; Phase 5 assault gaps listed.

(Coverage table: 28 classes; see the reviewer transcript. Notable: no test yet for any HIGH item above.)
