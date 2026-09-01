note
	description: "[
		The domain under assault (Phase 1: skeletal). Data classes and the
		contract-support engines are exercised for real; behaviour that
		waits for Phase 4 is listed as TODO so nothing can be forgotten.
	]"

class
	CHAT_ASSAULT

inherit
	TEST_SET_BASE

feature -- Domain data

	test_user_creation_and_storage_id
			-- A person with a PBKDF2-shaped hash; id assigned once.
		local
			u: CHAT_USER
		do
			u := person ("nick", {STRING_32} "Nick %/127928/")
			assert ("not stored yet", not u.is_stored)
			assert ("active", u.is_active)
			u.set_id (7)
			assert ("stored", u.is_stored and u.id = 7)
			assert ("username kept", u.username.same_string ("nick"))
		end

	test_username_rules
		local
			r: CHAT_USER_RULES
		do
			create r
			assert ("lowercase ok", r.is_valid_username ("nick_1"))
			assert ("uppercase refused", not r.is_valid_username ("Nick"))
			assert ("space refused", not r.is_valid_username ("ni ck"))
			assert ("empty refused", not r.is_valid_username (""))
			assert ("33 refused", not r.is_valid_username ("abcdefghijabcdefghijabcdefghijabc"))
		end

	test_display_name_rejects_bidi_controls_and_blank
		local
			r: CHAT_USER_RULES
			l_spoof: STRING_32
		do
			create r
			create l_spoof.make_from_string ({STRING_32} "Nick")
			l_spoof.append_code (0x202E)
			assert ("bidi override refused", not r.is_valid_display_name (l_spoof))
			assert ("blank refused", not r.is_valid_display_name ({STRING_32} "   "))
			assert ("hebrew ok", r.is_valid_display_name ({STRING_32} "%/1513/%/1500/%/1493/%/1501/"))
		end

	test_result_success_xor_error
		local
			ok: CHAT_RESULT [STRING_8]
			bad: CHAT_RESULT [STRING_8]
		do
			create ok.make_success ("yes")
			assert ("success", ok.is_success and attached ok.value as v and then v.same_string ("yes"))
			create bad.make_error (create {CHAT_ERROR}.make ("exists", "already there", 409))
			assert ("failure", not bad.is_success and attached bad.error as e and then e.http_status = 409)
		end

	test_bot_event_carries_marker
		local
			e: CHAT_EVENT
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_now.make_now
			create l_payload.make
			create e.make (1, 1, 2, {CHAT_EVENT_KINDS}.Kind_message, l_now, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " hello", Void, l_payload, True)
			assert ("bot authored", e.is_bot_authored)
			assert ("marked", e.body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker))
			assert ("message kind", e.is_message and not e.is_image and not e.is_system)
		end

	test_session_fields
		local
			s: CHAT_SESSION
			l_now: SIMPLE_DATE_TIME
		do
			create l_now.make_now
			create s.make (0, 3, hex64, l_now, l_now.plus_seconds (3600), False)
			assert ("not expired now", not s.is_expired_at (l_now))
			assert ("expired later", s.is_expired_at (l_now.plus_seconds (7200)))
		end

feature -- Contract-support engines

	test_password_hasher_round_trip
		local
			h: PASSWORD_HASHER
			l_hash: STRING_8
		do
			create h.make
			l_hash := h.hash ({STRING_32} "correct horse battery staple")
			assert ("verifies", h.verify ({STRING_32} "correct horse battery staple", l_hash))
			assert ("rejects", not h.verify ({STRING_32} "wrong", l_hash))
			assert ("owasp floor", h.iterations_of (l_hash) >= {PASSWORD_HASHER}.Minimum_iterations)
			assert ("32-hex salt", h.salt_of (l_hash).count = 32)
		end

	test_session_issuer_token_shape
		local
			i: SESSION_ISSUER
			u: CHAT_USER
			t: TUPLE [token: STRING_8; session: CHAT_SESSION]
		do
			create i.make
			u := person ("mike", {STRING_32} "Mike")
			u.set_id (5)
			t := i.issue (u, 86400, False)
			assert ("64 hex token", t.token.count = 64)
			assert ("hash stored, not token", t.session.token_hash.count = 64 and not t.session.token_hash.same_string (t.token))
			assert ("hash matches", t.session.token_hash.same_string (i.hash_of (t.token)))
			assert ("expiry ahead", t.session.created_at < t.session.expires_at)
		end

	test_registry_register_and_find
		local
			r: PARTICIPANT_REGISTRY
			p: NULL_PARTICIPANT
		do
			create r.make
			create p.make ({STRING_32} "@off", bot ("off", {STRING_32} "Off"))
			r.register (p)
			assert ("has", r.has ({STRING_32} "@off"))
			assert ("finds", r.find ({STRING_32} "@off") = p)
			assert ("model", r.handles_model.count = 1)
			assert ("unknown", r.find ({STRING_32} "@nobody") = Void)
		end

	test_null_shaper_honours_limit
		local
			s: NULL_SHAPER
			b: SHAPING_BRIEF
			t: SHAPED_TEXT
		do
			create s.make
			create b.make ({SHAPING_BRIEF}.Purpose_response, {STRING_32} "test", 5)
			t := s.shape ({STRING_32} "hello world", b)
			assert ("cut", t.is_success and t.text.same_string ({STRING_32} "hello"))
			assert ("free", s.cost_tier = {SHAPER}.Tier_none)
		end

	test_null_and_mock_participants
		local
			n: NULL_PARTICIPANT
			m: MOCK_PARTICIPANT
			q: PARTICIPANT_REQUEST
			a: PARTICIPANT_ANSWER
		do
			create q.make ({STRING_32} "Nick", {STRING_32} "Gen 1:1", 1, {STRING_32} "main", 10, Void)
			create n.make ({STRING_32} "@off", bot ("off", {STRING_32} "Off"))
			a := n.answer (q)
			assert ("null never answers", not a.is_success and n.calls = 1)
			create m.make ({STRING_32} "@mock", bot ("mock", {STRING_32} "Mock"), {STRING_32} "In the beginning God created")
			a := m.answer (q)
			assert ("mock answers within limit", a.is_success and a.text.count <= 10)
		end

	test_config_defaults_and_public_flag
		local
			c: SERVER_CONFIG
		do
			create c.make_defaults
			assert ("valid", c.is_valid)
			assert ("private without a door", not c.is_public)
			c.set_front_door ({SERVER_CONFIG}.Door_caddy, "rixchat.duckdns.org")
			assert ("public behind door", c.is_public)
			assert ("port", c.port = 8080)
		end

	test_memory_store_models_start_empty
		local
			s: MEMORY_CHAT_STORE
		do
			create s.make
			s.open
			assert ("open", s.is_open)
			assert ("no events", s.events_model.is_empty and s.event_count = 0)
			assert ("no users", s.users_model.count = 0)
			assert ("schema current", s.schema_version = {CHAT_SCHEMA}.Current_version)
		end

	test_memory_sink_counts_bytes
		local
			k: MEMORY_STREAM_SINK
		do
			create k.make
			k.write ("id: 1%N%N")
			assert ("counted", k.bytes_written = 7)
			assert ("kept", k.content.same_string ("id: 1%N%N"))
			k.close
			assert ("closed", not k.is_open)
		end

	test_caddyfile_targets_localhost
		local
			c: SERVER_CONFIG
			d: CADDY_FRONT_DOOR
		do
			create c.make_defaults
			c.set_front_door ({SERVER_CONFIG}.Door_caddy, "rixchat.duckdns.org")
			create d.make (c)
			assert ("site", d.caddyfile_text.has_substring ("rixchat.duckdns.org {"))
			assert ("upstream", d.caddyfile_text.has_substring ("127.0.0.1:8080"))
			assert ("sse passthrough", d.caddyfile_text.has_substring ("flush_interval -1"))
		end

feature -- Thick client stack (intent-v3): real tests against the scripted transport

	test_poll_waiter_counts_only_its_room
			-- The SCOOP flag object: wakes for its room count, others do not; statuses of its room are kept; the alarm readies it.
		local
			w: POLL_WAITER
		do
			create w.make (1)
			w.wake (2)
			assert ("other room ignored", not w.has_news and w.wake_count = 1 and not w.is_ready)
			w.wake (1)
			assert ("own room counted", w.has_news and w.news_count = 1 and w.is_ready)
			w.receive_status (create {CHAT_STATUS}.make (1, {STRING_32} "Claude", {STRING_32} "thinking"))
			w.receive_status (create {CHAT_STATUS}.make (2, {STRING_32} "Claude", {STRING_32} "elsewhere"))
			assert ("only my statuses kept", w.status_count = 1 and w.statuses_json.has_substring ("thinking") and not w.statuses_json.has_substring ("elsewhere"))
			create w.make (3)
			assert ("quiet waiter is not ready", not w.is_ready)
			w.time_out
			assert ("alarm readies it without news", w.is_ready and w.is_timed_out and not w.has_news)
		end

	test_event_bus_tickets
			-- Subscriptions are tickets; ring reaches every subscriber; unsubscribe is idempotent.
		local
			b: EVENT_BUS
			w1, w2: POLL_WAITER
			t1: INTEGER
		do
			create b.make
			create w1.make (1)
			create w2.make (2)
			b.subscribe (w1)
			t1 := b.last_ticket
			b.subscribe (w2)
			assert ("two tickets", t1 = 1 and b.last_ticket = 2 and b.subscriber_count = 2 and b.is_subscribed (1) and b.is_subscribed (2))
			b.ring (1)
			assert ("both woken, only room 1 has news", w1.wake_count = 1 and w2.wake_count = 1 and w1.has_news and not w2.has_news)
			b.ring_status (create {CHAT_STATUS}.make (2, {STRING_32} "Claude", {STRING_32} "queued"))
			assert ("status delivered to room 2 only", w2.status_count = 1 and w1.status_count = 0 and b.status_count = 1)
			b.unsubscribe (t1)
			b.unsubscribe (99)
			assert ("one left, unknown ticket harmless", b.subscriber_count = 1 and not b.is_subscribed (1) and b.is_subscribed (2))
			b.ring (1)
			assert ("unsubscribed waiter not woken", w1.wake_count = 1 and w2.wake_count = 2 and b.ring_count = 2)
		end

	test_sse_stream_delivers_in_order
		local
			k: MEMORY_STREAM_SINK
			s: SSE_STREAM
			l_events: ARRAYED_LIST [CHAT_EVENT]
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
		do
			create k.make
			create s.make (k)
			s.open (1, 0)
			assert ("preamble", k.content.starts_with (": simple_chat stream"))
			create l_now.make (2026, 8, 29, 12, 0, 0)
			create l_payload.make
			create l_events.make (2)
			l_events.extend (create {CHAT_EVENT}.make (1, 1, 5, {CHAT_EVENT_KINDS}.Kind_message, l_now, {STRING_32} "one", Void, l_payload, False))
			l_events.extend (create {CHAT_EVENT}.make (2, 1, 5, {CHAT_EVENT_KINDS}.Kind_message, l_now, {STRING_32} "two", Void, l_payload, False))
			s.deliver (create {CHAT_PAGE}.make (l_events, create {ARRAYED_LIST [CHAT_STATUS]}.make (0)))
			assert ("two delivered in order", s.delivered_model.count = 2 and s.last_delivered_id = 2 and k.content.has_substring ("id: 1%Nevent: message%N") and k.content.has_substring ("id: 2%N"))
			s.heartbeat
			assert ("heartbeat written", k.content.ends_with (": hb%N%N"))
			s.close
			assert ("closed", not s.is_open and not k.is_open)
		end

	test_web_stream_sink_over_mock_response
			-- The three Phase-1 stubs live: chunks recorded, counts honest, close honest.
		local
			l_response: SIMPLE_WEB_SERVER_RESPONSE
			k: WEB_STREAM_SINK
		do
			create l_response.make_mock
			l_response.send_stream_head (200, "text/event-stream")
			create k.make (l_response)
			assert ("open with nothing", k.is_open and k.bytes_written = 0)
			k.write ("abc")
			k.write ("de")
			k.flush
			assert ("counted", k.bytes_written = 5)
			assert ("recorded in order", l_response.mock_body.same_string ("abcde"))
			k.close
			assert ("closed", not k.is_open)
			assert ("bytes kept after close", k.bytes_written = 5)
		end

	test_sse_stream_over_web_sink
			-- The full SSE law over the real adapter (mock response behind it).
		local
			l_response: SIMPLE_WEB_SERVER_RESPONSE
			k: WEB_STREAM_SINK
			s: SSE_STREAM
			l_events: ARRAYED_LIST [CHAT_EVENT]
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_response.make_mock
			l_response.send_stream_head (200, "text/event-stream")
			create k.make (l_response)
			create s.make (k)
			s.open (1, 0)
			assert ("preamble on the wire", l_response.mock_body.starts_with (": simple_chat stream"))
			create l_now.make (2026, 9, 1, 12, 0, 0)
			create l_payload.make
			create l_events.make (1)
			l_events.extend (create {CHAT_EVENT}.make (1, 1, 5, {CHAT_EVENT_KINDS}.Kind_message, l_now, {STRING_32} "one", Void, l_payload, False))
			s.deliver (create {CHAT_PAGE}.make (l_events, create {ARRAYED_LIST [CHAT_STATUS]}.make (0)))
			s.heartbeat
			assert ("event then heartbeat on the wire", l_response.mock_body.has_substring ("id: 1%Nevent: message%N") and l_response.mock_body.ends_with (": hb%N%N"))
			s.close
			assert ("all closed", not s.is_open and not k.is_open)
		end

	test_client_address_door_rule
			-- M-F closed: the peer wins except behind the public loopback door (DR-010).
		local
			h: CHAT_REQUEST_HANDLER
			r: SIMPLE_WEB_SERVER_REQUEST
		do
			create h.make
				-- No peer supplied (an in-process request): the "local" bucket, never empty.
			create r.make_mock ("GET", "/login")
			assert ("local when unknown", h.client_address (r, False).same_string ("local"))
				-- A public peer is itself; X-Forwarded-For from a non-door peer is ignored.
			create r.make_mock ("GET", "/login")
			r.set_mock_remote_address ("203.0.113.9")
			r.set_mock_header ("X-Forwarded-For", "10.0.0.1, 10.0.0.2")
			assert ("peer wins", h.client_address (r, True).same_string ("203.0.113.9"))
				-- The loopback door on a public server: the rightmost forwarded entry wins.
			create r.make_mock ("GET", "/login")
			r.set_mock_remote_address ("127.0.0.1")
			r.set_mock_header ("X-Forwarded-For", "10.0.0.1, 198.51.100.7")
			assert ("rightmost behind the door", h.client_address (r, True).same_string ("198.51.100.7"))
				-- The same door peer on a private server: no trust, the peer itself.
			create r.make_mock ("GET", "/login")
			r.set_mock_remote_address ("127.0.0.1")
			r.set_mock_header ("X-Forwarded-For", "10.0.0.1")
			assert ("no trust when private", h.client_address (r, False).same_string ("127.0.0.1"))
				-- Different addresses land in different lockout buckets (M-F).
			assert ("distinct buckets", not h.client_address (r, False).same_string ("203.0.113.9"))
		end

	test_event_json_round_trip
		local
			j: CHAT_JSON
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
			e, back: CHAT_EVENT
			a: CHAT_ATTACHMENT
			l_bytes: STRING_8
			l_events: ARRAYED_LIST [CHAT_EVENT]
			l_statuses: ARRAYED_LIST [CHAT_STATUS]
		do
			create j.make
			create l_now.make (2026, 8, 29, 12, 0, 0)
			create l_payload.make
			create e.make (7, 1, 99, {CHAT_EVENT_KINDS}.Kind_message, l_now, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " %/1513/%/1500/%/1493/%/1501/ world", Void, l_payload, True)
			l_bytes := j.bytes_of (e.to_json)
			assert ("bytes are utf-8 json", l_bytes.starts_with ("{") and l_bytes.has_substring ("is_bot"))
			if attached j.event_from_bytes (l_bytes) as b then
				back := b
				assert ("id/room/sender", back.id = 7 and back.room_id = 1 and back.sender_id = 99)
				assert ("hebrew and marker survive", back.body.same_string (e.body))
				assert ("bot flag", back.is_bot_authored and back.is_message)
			else
				assert ("message decodes", False)
			end
			create a.make (3, 99, {STRING_32} "meme.png", {CHAT_ATTACHMENT}.Mime_png, 2048, hex64, l_now)
			create e.make (8, 1, 99, {CHAT_EVENT_KINDS}.Kind_image, l_now, {STRING_32} "caption", a, l_payload, False)
			if attached j.event_from_bytes (j.bytes_of (e.to_json)) as b and then attached b.attachment as ba then
				assert ("image kind", b.is_image)
				assert ("attachment rebuilt", ba.id = 3 and ba.size = 2048 and ba.mime.same_string ({CHAT_ATTACHMENT}.Mime_png) and ba.stored_relpath.same_string (a.stored_relpath))
			else
				assert ("image decodes", False)
			end
			create l_events.make (2)
			l_events.extend (e)
			create l_statuses.make (1)
			l_statuses.extend (create {CHAT_STATUS}.make (1, {STRING_32} "Claude", {STRING_32} "thinking"))
			if attached j.page_from_bytes (j.bytes_of (j.page_to_json (l_events, l_statuses))) as p then
				assert ("page events", p.events.count = 1 and p.last_id = 8)
				assert ("page statuses", p.statuses.count = 1 and p.statuses.first.text.same_string ({STRING_32} "thinking"))
			else
				assert ("page decodes", False)
			end
			assert ("garbage is void", j.event_from_bytes ("not json") = Void and j.page_from_bytes ("{%"events%": 5}") = Void)
			assert ("unmarked bot message refused", j.event_from_bytes ("{%"id%":1,%"room_id%":1,%"sender_id%":1,%"kind%":%"message%",%"created_at%":%"2026-08-29T12:00:00%",%"body%":%"hi%",%"is_bot%":true}") = Void)
		end

feature -- TODO: Phase 5

	test_post_message_appends_and_rings
			-- Skeletal: post_message appends exactly one event and rings the bus once.
		do
			-- TODO: Phase 5
		end

	test_doorbell_no_loss_under_concurrency
			-- Skeletal: 8 posters, 4 streams; every event delivered exactly once, no deadlock (intent-v2 Q3).
		do
			-- TODO: Phase 5
		end

	test_dispatcher_ignores_bots_and_answers_once
		do
			-- TODO: Phase 5
		end

	test_tool_refuses_unsafe_argument
			-- Skeletal: "@tools-larry Gen 1:1 | dir" is refused; "Gen 1:1" is accepted.
		do
			-- TODO: Phase 5
		end

	test_sse_replays_since_then_live
		do
			-- TODO: Phase 5
		end

	test_log_never_contains_secrets
		local
			l_logger: SIMPLE_LOGGER
			l_log: CHAT_LOG
		do
			create l_logger.make
			create l_log.make (l_logger)
			l_log.info ({STRING_32} "login larry password=hunter2 token=" + hex64.to_string_32 + {STRING_32} " ok")
			assert ("one line", l_log.lines_written = 1)
			assert ("password masked", not l_log.last_line.has_substring ({STRING_32} "hunter2") and l_log.last_line.has_substring ({STRING_32} "password=****"))
			assert ("token masked", not l_log.last_line.has_substring (hex64.to_string_32) and l_log.last_line.ends_with ({STRING_32} " ok"))
			l_log.warn ({STRING_32} "{%"password%": %"pa ss%", %"hash%":%"" + hex64.to_string_32 + {STRING_32} "%"} Authorization: Bearer abc.def rest")
			assert ("json and bearer forms masked", not l_log.last_line.has_substring ({STRING_32} "pa ss") and not l_log.last_line.has_substring (hex64.to_string_32)
				and not l_log.last_line.has_substring ({STRING_32} "abc.def") and l_log.last_line.ends_with ({STRING_32} " rest"))
			assert ("nothing secret left", not l_log.has_secret_field (l_log.last_line) and l_log.lines_written = 2)
			l_log.error ("plain text stays, sha " + hex32)
			assert ("plain text unchanged", l_log.last_line.same_string ({STRING_32} "plain text stays, sha " + hex32.to_string_32) and l_log.lines_written = 3)
		end

	test_limiter_prefixes_windows_and_totals
		local
			l: RATE_LIMITER
		do
			create l.make (3600)
			l.set_limit ("post:", 2, 60)
			l.set_limit ("login:ip:", 3, 600)
			l.set_limit ("login:", 1, 10)
			assert ("longest prefix wins", l.limit_for ("login:ip:1.2.3.4") = 3 and l.window_for ("login:ip:1.2.3.4") = 600)
			assert ("shorter prefix for the rest", l.limit_for ("login:user:larry") = 1 and l.window_for ("login:user:larry") = 10)
			assert ("unconfigured is the default", l.limit_for ("other:x") = {RATE_LIMITER}.Default_limit and not l.has_rule_for ("other:x") and l.window_for ("other:x") = 3600)
			l.record ("post:5")
			l.record ("post:5")
			assert ("two posts fill the minute", not l.is_allowed ("post:5") and l.count ("post:5") = 2 and l.total ("post:5") = 2 and l.live_count ("post:5") = 2)
			assert ("another key is free", l.is_allowed ("post:6") and l.count ("post:6") = 0)
			l.advance (61)
			assert ("the minute passed", l.is_allowed ("post:5") and l.live_count ("post:5") = 0 and l.count ("post:5") = 2)
			l.record ("post:5")
			assert ("record pruned the expired two", l.last_pruned = 2 and l.count ("post:5") = 1 and l.total ("post:5") = 3 and l.records = 3)
			l.record ("login:ip:9.9.9.9")
			l.advance (601)
			l.prune
			assert ("a sweep forgets idle keys", l.count ("login:ip:9.9.9.9") = 0 and l.total ("login:ip:9.9.9.9") = 0 and l.count ("post:5") = 0 and l.counts_model.is_empty)
		end

	test_json_refuses_empty_deep_and_impossible_dates
		local
			j: CHAT_JSON
			l_deep: STRING_8
			i: INTEGER
		do
			create j.make
			assert ("empty bytes are void, not an exception", j.object_from_bytes ("") = Void and j.array_from_bytes ("") = Void
				and j.error_from_bytes ("", 502) = Void and j.page_from_bytes ("") = Void and j.members_from_bytes ("") = Void)
			create l_deep.make (100)
			from i := 1 until i > 40 loop
				l_deep.append_character ('[')
				i := i + 1
			end
			from i := 1 until i > 40 loop
				l_deep.append_character (']')
				i := i + 1
			end
			assert ("forty deep is refused", j.array_from_bytes (l_deep) = Void and j.max_nesting (l_deep) = 40)
			assert ("brackets inside strings do not count", j.max_nesting ("{%"body%":%"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[ \%" [[%"}") = 1)
			assert ("four deep is fine", attached j.object_from_bytes ("{%"a%":[{%"b%":[1]}]}"))
			assert ("impossible dates refused", not j.is_iso8601 ("2026-02-30T00:00:00") and not j.is_iso8601 ("2026-13-01T00:00:00")
				and not j.is_iso8601 ("2026-08-29T24:00:00") and not j.is_iso8601 ("0000-01-01T00:00:00Z") and not j.is_iso8601 ("2027-02-29T00:00:00"))
			assert ("real dates accepted", j.is_iso8601 ("2028-02-29T23:59:59Z") and j.is_iso8601 ("2026-08-29T12:00:00"))
			assert ("an impossible created_at refuses the event", j.event_from_bytes ("{%"id%":1,%"room_id%":1,%"sender_id%":9,%"kind%":%"message%",%"created_at%":%"2026-02-30T00:00:00%",%"body%":%"x%"}") = Void)
		end

	test_long_poll_returns_within_deadline
			-- Skeletal: wait_for_events with nothing new returns empty in about `seconds', and at once when the doorbell rings.
		do
			-- TODO: Phase 5
		end

	test_sw_view_renders_hebrew_and_marker
			-- Skeletal: SW_CHAT_VIEW shows "%/1513/%/1500/%/1493/%/1501/ %/129302/ %/935/%/961/%/953/%/963/%/964/%/972/%/962/" right-to-left with the marker picture (needs simple_shaping).
		do
			-- TODO: Phase 5
		end

feature {NONE} -- Fixtures

	person (a_username: STRING_8; a_display: STRING_32): CHAT_USER
		local
			l_now: SIMPLE_DATE_TIME
		do
			create l_now.make_now
			create Result.make (0, a_username, a_display, hex32 + "$600000$" + hex64, False, False, l_now)
		end

	bot (a_username: STRING_8; a_display: STRING_32): CHAT_USER
		local
			l_now: SIMPLE_DATE_TIME
		do
			create l_now.make_now
			create Result.make (0, a_username, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " " + a_display, "", False, True, l_now)
			Result.set_id (99)
		end

	hex64: STRING_8
		do
			Result := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
		end

	hex32: STRING_8
		do
			Result := "0123456789abcdef0123456789abcdef"
		end

end
