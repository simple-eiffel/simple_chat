# ADDENDUM: Addressable Participants — tools as room members

Date: 2026-08-29 (Larry's idea, mid-spec). Supersedes the `AI_PARTICIPANT` / `TRIGGER_PARSER` / `AI_DISPATCHER` naming in 04–07; the contracts there carry over unchanged to the generalized classes below.

## The idea
Besides Claude, the room should be able to address Larry's **Eiffel Bible tools** the way Messenger addresses apps: `@TOOLS-LARRY Gen 1:1`, `@SHAPE-LARRY en_christo`. A participant may be an AI, a plain tool with no AI at all, or a tool whose raw output is phrased by the cheapest local model available (Ollama / Qwen on the host GPU). Every one of them is an ordinary room member with a 🤖-marked identity, its own rate limit, and its own engine.

## Design

### PARTICIPANT (deferred) — replaces AI_PARTICIPANT
```eiffel
deferred class PARTICIPANT
feature -- Access
	handle: STRING_32            -- "@tools-larry", "@shape-larry", "@claude" (also matched as "Claude:" / "ROBOT:")
	bot_user: CHAT_USER          -- is_bot; display_name carries the marker, e.g. "🤖 Tools (Larry)"
	limit_key: STRING_8          -- "p:<handle>:<asker id>"
	calls: INTEGER
feature -- Basic operations
	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		require asked: not a_request.text.is_empty
		deferred
		ensure counted: calls = old calls + 1
		       outcome: Result.is_success xor (Result.error /= Void)
		       bounded: Result.is_success implies Result.text.count <= a_request.max_characters
invariant
	handle_shape: handle.starts_with ("@") and handle.count >= 2
	bot_is_bot: bot_user.is_bot
end
```

### Descendants
| Class | Engine | AI? | Notes |
|---|---|---|---|
| `CLAUDE_CODE_PARTICIPANT` | `CLAUDE_CODE_CLIENT` (`claude -p`, subscription) | yes | as specified; aliases `Claude:` / `ROBOT:` |
| `OLLAMA_PARTICIPANT` | `OLLAMA_CLIENT` (simple_ai_client) → local Qwen/Llama | yes, cheapest | host GPU/CPU; persona per handle |
| `TOOL_PARTICIPANT` (deferred) | runs a command with **argv**, never a shell string | no | output bounded; runtime bounded; argument allowlist |
| `BIBLE_TOOL_PARTICIPANT` | `bible.exe <command>` (simple_scholar one-shot mode: verses, `/entity`, `/ddd`, `/define`, `/dss`) | no | `@TOOLS-LARRY Gen 1:1`; a friend gets the WLC + KJV + gloss in the room |
| `SHAPE_TOOL_PARTICIPANT` | Eiffel over simple_sql, read-only on `shape.db` | no | `@SHAPE-LARRY en_christo` → FITS/PARTIAL/FAILS/NO_DATA counts and the top instances |
| `PHRASED_PARTICIPANT` | decorator: a `TOOL_PARTICIPANT` whose raw output is rewritten for chat by an `OLLAMA_PARTICIPANT` | tool + cheap AI | "make this readable" without spending Claude |
| `NULL_PARTICIPANT` | never answers | — | tests; "off" |

### PARTICIPANT_REGISTRY, ADDRESS_PARSER, PARTICIPANT_DISPATCHER
- `PARTICIPANT_REGISTRY`: handle → participant; built from config; invariant `unique_handles`; `find (a_handle): detachable PARTICIPANT`.
- `ADDRESS_PARSER.parse (a_body): detachable ADDRESSED_REQUEST` — matches, at message start, `@handle` followed by the request, **or** a configured alias such as `Claude:` / `ROBOT:`; case-insensitive; returns `(handle, text)`.
- `PARTICIPANT_DISPATCHER` (the `AI_DISPATCHER` of 05, generalized): on each event, parse; look up; check `limits.is_allowed (p.limit_key + asker)`; publish status `"🤖 <display> thinking…"`; `p.answer`; post as `p.bot_user` with the marker. Contracts as in 05 (`ignores_bots`, `asked_once`, `always_answers`, `one_at_a_time` per participant — Claude at 1, tools may allow more).

### Safety contracts for tools (new — user text becomes process arguments)
```eiffel
-- TOOL_PARTICIPANT
answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
	require
		asked: not a_request.text.is_empty
	ensure
		refused_when_unsafe: not is_safe_argument (a_request.text) implies not Result.is_success   -- allowlist per tool
		bounded_output: Result.is_success implies Result.text.count <= a_request.max_characters
		bounded_runtime: elapsed_seconds <= timeout_seconds
invariant
	argv_not_shell: True   -- documented: SIMPLE_PROCESS argument list, never a concatenated command line
	no_secrets_in_argv: True
```
`BIBLE_TOOL_PARTICIPANT.is_safe_argument`: a verse reference (`[1-3]?[A-Za-z ]+ \d+(:\d+(-\d+)?)?`), an optional version prefix from the known list, or one of an allowlisted set of slash commands with a single word argument. Anything else — including `|`, `&`, `>` — is refused with a help line.

### Configuration
```toml
[[participants]]
handle = "@claude"
aliases = ["Claude:", "ROBOT:"]
kind = "claude_code"
bot_username = "claude"
bot_display_name = "🤖 Claude"
requests_per_hour = 5
max_characters = 1200
working_directory = "…/Scholars"

[[participants]]
handle = "@tools-larry"
kind = "bible_tool"
bot_username = "tools_larry"
bot_display_name = "🤖 Tools (Larry)"
executable = "C:/Program Files/BibleREPL/bible.exe"
requests_per_hour = 60
timeout_seconds = 20
max_characters = 2000

[[participants]]
handle = "@shape-larry"
kind = "shape_tool"
bot_username = "shape_larry"
bot_display_name = "🤖 Shape (Larry)"
database = "…/Scholars/Rix/Data/data/shape.db"
requests_per_hour = 60
phrase_with = "@qwen"          # optional: a PHRASED_PARTICIPANT wrapping this tool

[[participants]]
handle = "@qwen"
kind = "ollama"
model = "qwen2.5:7b"
bot_username = "qwen"
bot_display_name = "🤖 Qwen (local)"
requests_per_hour = 30
```

### Consequences for the rest of the spec
- `SERVER_CONFIG` gains `participants: LIST [PARTICIPANT_CONFIG]` with invariant `unique_handles`.
- `SIMPLE_CHAT_SERVER.set_participant` becomes `set_registry (a_registry: PARTICIPANT_REGISTRY)`; the default registry is built from config.
- `CHAT_UI` renders each bot identity distinctly; the composer offers `@` completion from `/participants` (a new read-only route: handles and display names).
- Friends' own bots (I-002) are unchanged: a relay on another PC is just a participant whose engine lives elsewhere.
- No change to `CHAT_EVENT`, the store, the bus, or the front door.

### Why this is right for the product
It is the Messenger `@app` pattern with Larry's actual instruments behind it, and it separates cost tiers explicitly: a verse lookup costs nothing, a shape census costs nothing, a phrasing pass costs local GPU time, and a Claude answer costs subscription quota — each visible in the room as its own 🤖 member, each with its own limit.

## Query and response shaping (Larry, 2026-08-29)

A tool's argument grammar is strict; people are not. And a tool's output is mechanical; people want sentences. Both edges get an optional **shaper** — a cheap local model by default, Claude on request, or nothing.

```
member text ──► QUERY_SHAPER? ──► is_safe_argument ──► tool (argv) ──► raw ──► RESPONSE_SHAPER? ──► reply (+ "looked up: …" echo)
                (Ollama/Claude/none)      the ONLY gate                          (none/Ollama/Claude)
```

### SHAPER (deferred)
```eiffel
deferred class SHAPER
feature
	shape (a_text: READABLE_STRING_32; a_brief: SHAPING_BRIEF): SHAPED_TEXT
		require given: not a_text.is_empty
		deferred
		ensure outcome: Result.is_success xor (Result.error /= Void)
		       bounded: Result.is_success implies Result.text.count <= a_brief.max_characters
	cost_tier: INTEGER          -- 0 none, 1 local (Ollama), 2 subscription (Claude)
end
```
Descendants: `NULL_SHAPER` (returns the text unchanged; tier 0), `OLLAMA_SHAPER` (`OLLAMA_CLIENT`, model from config; tier 1), `CLAUDE_SHAPER` (`CLAUDE_CODE_CLIENT`; tier 2). A `SHAPING_BRIEF` carries the tool's description, its accepted forms with examples (for query shaping), or the audience and register (for response shaping), and `max_characters`.

### How a tool participant uses them
```eiffel
-- TOOL_PARTICIPANT
query_shaper: SHAPER          -- default from config; overridable per request with "via <handle>"
response_shaper: SHAPER

answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
	ensure
		shaper_never_bypasses_gate: True   -- documented: the shaped query is validated by `is_safe_argument'
		                                   -- exactly as raw text would be; a rejected shaping is refused with the help line
		reply_echoes_query: Result.is_success implies Result.text.has_substring (executed_query_echo)
		                                   -- the member sees what was actually run: "Looked up: Gen 1:1 (WLC, KJV)"
		phrasing_disclosed: Result.is_success and response_shaper.cost_tier > 0 implies Result.text.has_substring (Phrased_by_footer)
```

### The one place to watch
A query shaper is an LLM reading untrusted chat text. It can be told, inside that text, to produce something else. That is why the shaper sits **before** the allowlist and never replaces it: the worst a manipulated shaper can do is emit a *different valid* query, which the echo line exposes to everyone in the room. Nothing an LLM writes ever reaches `argv` without passing `is_safe_argument`. The same holds for the response shaper: it only ever sees the tool's output, and it cannot call anything.

### Per-request selection
`ADDRESS_PARSER` accepts an optional trailing `via <handle>` on the request, stripped before validation:

- `@shape-larry en_christo` — tool default (config)
- `@shape-larry en_christo via claude` — response phrased by Claude, costs quota, rate-limited under the asker's Claude key
- `@shape-larry en_christo via plain` — mechanical output, no model at all
- `@tools-larry what does genesis one verse one say in hebrew and english?` — query shaped by the local model into `WLC KJV Gen 1:1`, echoed in the reply

### Configuration
```toml
[[participants]]
handle = "@shape-larry"
kind = "shape_tool"
query_shaper = "@qwen"          # a handle whose engine is ollama or claude_code; or "none"
response_shaper = "@qwen"       # default phrasing: local, cheap
allow_via = ["plain", "@qwen", "@claude"]   # what "via" may select

[[participants]]
handle = "@tools-larry"
kind = "bible_tool"
query_shaper = "@qwen"
response_shaper = "none"        # verse text is already readable; mechanical works here
allow_via = ["plain", "@qwen", "@claude"]
```

### Status line while it works
Ephemeral statuses keep the room informed through a multi-step answer: "🤖 Tools understanding the question…", "🤖 Tools looking up Gen 1:1…", "🤖 Tools phrasing…". Each is a `CHAT_STATUS`; none is stored.

### Cost picture
| Step | Engine | Cost |
|---|---|---|
| verse / shape lookup | Eiffel tool | none |
| query shaping | Ollama (Qwen 7B, or smaller) on the host GPU/CPU | electricity |
| response phrasing | Ollama by default | electricity |
| `via claude` | `CLAUDE_CODE_CLIENT` | subscription quota, under the asker's Claude rate limit |
