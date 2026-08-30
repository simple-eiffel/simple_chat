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
		do
			-- TODO: Phase 5
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
			create Result.make (0, a_username, a_display, "", False, True, l_now)
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
