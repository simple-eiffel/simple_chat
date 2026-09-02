note
	description: "[
		Phase 4 Task 10 under assault: the VISIBLE client, proven with no
		desktop.

		SW_WINDOW allocates a cairo image surface and a painter in `make'
		and creates nothing native until `run', so the room pane and the
		door can both be built OFFSCREEN and driven exactly as a member
		drives them - a bubble added, a status replaced, an error shown, a
		badge set, a line typed and submitted, a login refused and then
		accepted. `is_foreground' answers False throughout, because there
		is no native window to be in front of anything: that is the honest
		answer AND the interesting branch, since it is the one where the
		presenter counts unread and the tray balloons.

		WHAT CANNOT BE PROVEN HERE, and is left to Larry's console smoke
		(RUNBOOK.md): that the pixels are right. A pane that is never shown
		paints nothing, so "the Hebrew is rightmost and the robot is a
		robot" is asserted one layer down - the layout the window's own
		SW_SHAPING kit produces for the acceptance line - and looked at, on
		a screen, by a human. simple_widgets already proves the paint half
		on pixels (evidence/shaped-d015.png).
	]"
	author: "Larry Rix"

class
	WINDOW_ASSAULT

inherit
	TEST_SET_BASE

feature -- The pane: CHAT_VIEW's contracts over simple_widgets

	test_view_shows_events_in_order_and_never_twice
			-- Three events, three bubbles, three ids in order - and the roles the
			-- thread draws them with: mine right, the system centred, the rest left.
		local
			v: SW_CHAT_VIEW
		do
			v := pane
			assert ("a fresh pane has shown nothing", v.shown_count = 0 and v.thread.count = 0)
			assert ("and says nothing about a server yet", not v.is_connected)
			v.show_event (message_event (1, 9, "hello"), "Nick", False)
			v.show_event (message_event (2, 5, "hello back"), "Larry", True)
			v.show_event (system_event (3, "Nick joined"), "system", False)
			assert ("three bubbles", v.thread.count = 3 and v.shown_count = 3)
			assert ("three ids, in order", v.shown_ids [1] = 1 and v.shown_ids [2] = 2 and v.shown_ids [3] = 3)
			assert ("theirs on the left", v.thread.messages [1].role = {SW_CHAT_THREAD}.Role_theirs)
			assert ("mine on the right", v.thread.messages [2].role = {SW_CHAT_THREAD}.Role_mine)
			assert ("the system in the middle", v.thread.messages [3].role = {SW_CHAT_THREAD}.Role_system)
			assert ("attributed", v.thread.messages [1].text.has_substring ({STRING_32} "Nick"))
			assert ("and carrying the body", v.thread.messages [1].text.has_substring ({STRING_32} "hello"))
			assert ("the thread still follows its tail", v.thread.is_sticky)
		end

	test_view_shows_an_image_as_an_attachment_line
			-- No WIC in this client, and the pane says so out loud: an image event
			-- becomes a named, sized attachment line carrying its caption.
		local
			v: SW_CHAT_VIEW
			l_event: CHAT_EVENT
		do
			v := pane
			l_event := image_event (7, 9, {STRING_32} "shofar.png", {STRING_32} "the horn")
			v.show_event (l_event, "Nick", False)
			assert ("one bubble, one id", v.shown_count = 1 and v.thread.count = 1)
			assert ("marked as an image", v.thread.messages [1].text.has_substring (v.Attachment_mark))
			assert ("named", v.thread.messages [1].text.has_substring ({STRING_32} "shofar.png"))
			assert ("sized", v.thread.messages [1].text.has_substring ({STRING_32} "64 bytes"))
			assert ("captioned", v.thread.messages [1].text.has_substring ({STRING_32} "the horn"))
		end

	test_view_badge_status_error_and_connection
			-- Everything the pane shows that is not an event, and the law that none of
			-- it disturbs the events: the badge, the ephemeral line, the error line and
			-- the connection state.
		local
			v: SW_CHAT_VIEW
			l_endpoint: CHAT_ENDPOINT
		do
			v := pane
			v.show_event (message_event (1, 9, "hello"), "Nick", False)
			v.set_unread (3)
			assert ("the badge shows the count", v.unread = 3)
			v.set_unread (0)
			assert ("and nothing at zero", v.unread = 0)
			v.show_status ({STRING_32} "Claude is thinking")
			assert ("the ephemeral line is the last one said", v.status_text.same_string ({STRING_32} "Claude is thinking"))
			v.show_status ({STRING_32} "Claude answered")
			assert ("and it replaces, never stacks", v.status_text.same_string ({STRING_32} "Claude answered"))
			v.show_error ({STRING_32} "the server is not answering")
			v.show_error ({STRING_32} "still not answering")
			assert ("errors are kept in order", v.errors.count = 2 and v.errors [2].same_string ({STRING_32} "still not answering"))
			create l_endpoint.make ("http://127.0.0.1:8080")
			v.show_connection (l_endpoint, True)
			assert ("the connection state is what it was last told", v.is_connected)
			v.show_connection (l_endpoint, False)
			assert ("and revised when it changes", not v.is_connected)
			assert ("none of it touched the events", v.shown_count = 1 and v.thread.count = 1)
		end

	test_view_is_never_in_front_without_a_window
			-- The presenter's whole unread law turns on this answer, and a pane that was
			-- never shown must never claim the member is looking at it.
		local
			v: SW_CHAT_VIEW
		do
			v := pane
			assert ("no native window, so not in front", not v.is_foreground)
			v.show_event (message_event (1, 9, "hello"), "Nick", False)
			assert ("and still not, after showing something", not v.is_foreground)
		end

	test_view_shaped_text_is_on_and_lays_out_the_acceptance_line
			-- The whole reason this task waited for simple_shaping: the window carries a
			-- kit, and the kit lays the D-015 acceptance line out with the Hebrew
			-- RIGHTMOST - which is what cairo's toy text API cannot do at all.
		local
			v: SW_CHAT_VIEW
			l_layout: SHAPED_LAYOUT
			l_line: SHAPED_LINE
		do
			v := pane
			assert ("the pane's window has a shaping kit", attached v.window.shaping)
			if attached v.window.shaping as l_kit then
				l_layout := l_kit.layout_for (acceptance_line, {SHAPING_CONSTANTS}.No_wrap, 16)
				assert ("every character was covered", l_layout.covers_all_characters)
				assert ("one unbounded line", l_layout.lines.count = 1)
				assert ("first-strong is Hebrew, so the paragraph is RTL",
					l_layout.base_direction = {SHAPING_CONSTANTS}.Direction_rtl)
				l_line := l_layout.lines [1]
				assert ("the leftmost run is the LTR Greek", not l_line.runs.first.is_rtl)
				assert ("the rightmost run is the RTL Hebrew", l_line.runs.last.is_rtl)
				assert ("the line has real height", l_layout.total_height > 0.0)
				print ("    pane: " + l_line.runs.count.out + " runs, width " + l_line.width.out
					+ ", total_height " + l_layout.total_height.out + "%N")
			end
		end

	test_input_box_submits_on_return_and_never_sends_an_empty_line
			-- Enter-to-send, the gesture SW_TEXT_BOX has no hook for; and the one line
			-- the pane refuses to hand on.
		local
			v: SW_CHAT_VIEW
		do
			v := pane
			sent.wipe_out
			v.set_on_send (agent record_sent)
			v.input.handle_char (13)
			assert ("an empty line goes nowhere", sent.is_empty)
			v.input.set_text ({STRING_32} "shalom")
			v.input.handle_char (13)
			assert ("Return sent the line", sent.count = 1 and sent [1].same_string ({STRING_32} "shalom"))
			assert ("and cleared the composer", v.input.text.is_empty)
			v.input.set_text ({STRING_32} "again")
			v.input.handle_char (65)
			assert ("an ordinary character types, it does not send", sent.count = 1 and v.input.text.count = 6)
		end

feature -- The pane under the presenter

	test_presenter_pumps_pages_into_the_real_pane
			-- CHAT_PRESENTER against SW_CHAT_VIEW rather than the double: the same laws,
			-- and the tray counting because a pane with no window is not in front.
		local
			t: MEMORY_HTTP_TRANSPORT
			c: CHAT_CLIENT
			v: SW_CHAT_VIEW
			n: MEMORY_NOTIFIER
			pr: CHAT_PRESENTER
			b: EVENT_INBOX
		do
			create t.make
			c := logged_in_client (t)
			v := pane
			create n.make
			create pr.make (c, v, n)
			create b.make
			pr.open_room (1, 0, b)
			assert ("opening a room says the server is answering", v.is_connected)
			b.put (wire_page (wire_message (1, 9, "one") + "," + wire_message (2, 9, "two"), ""))
			pr.pump
			assert ("both events reached the pane, in order",
				v.shown_count = 2 and v.shown_ids [1] = 1 and v.shown_ids [2] = 2)
			assert ("and became bubbles", v.thread.count = 2)
			assert ("not in front, so both counted unread", pr.unread = 2 and n.unread = 2 and n.notify_count = 2)
			b.put (wire_page ("", wire_status (1, "Claude", "thinking")))
			pr.pump
			assert ("a status is not an event", v.shown_count = 2 and v.status_text.has_substring ({STRING_32} "thinking"))
			b.put ("garbage")
			pr.pump
			assert ("a page that cannot be read is an error, not an exception",
				not v.errors.is_empty and v.shown_count = 2)
		end

feature -- The door

	test_login_window_validates_its_fields
			-- Three refusals this class owns, because CHAT_CLIENT's own preconditions
			-- would otherwise be violated rather than reported.
		local
			d: LOGIN_WINDOW
		do
			create d.make (Loopback_url, 0, 0)
			assert ("prefilled with the located server", d.server_url.same_string (Loopback_url))
			assert ("and nothing typed", d.username.is_empty and d.password.is_empty)
			assert ("empty name and password: not usable", not d.is_usable)
			d.set_fields (Loopback_url, "larry", {STRING_32} "", True)
			assert ("no password: not usable", not d.is_usable)
			d.set_fields (Loopback_url, "", {STRING_32} "open sesame", True)
			assert ("no name: not usable", not d.is_usable)
			d.set_fields (Loopback_url, "two words", {STRING_32} "open sesame", True)
			assert ("a name with a space: not usable", not d.is_usable)
			d.set_fields ("http://evil.example.com", "larry", {STRING_32} "open sesame", True)
			assert ("plain http to somewhere else: not usable", not d.is_usable)
			d.set_fields ("https://rixchat.duckdns.org", "larry", {STRING_32} "open sesame", True)
			assert ("https anywhere: usable", d.is_usable)
			d.set_fields (Loopback_url, "larry", {STRING_32} "open sesame", True)
			assert ("loopback http: usable", d.is_usable)
			assert ("and remembering, by default", d.remembers)
		end

	test_login_window_shows_a_refusal_and_accepts_a_success
			-- The button is `try_login' and nothing else; the verdict is the host's agent.
		local
			d: LOGIN_WINDOW
		do
			create d.make (Loopback_url, 0, 0)
			refusal := {STRING_32} "Wrong name or password"
			d.set_attempt (agent scripted_attempt)
			d.set_fields (Loopback_url, "larry", {STRING_32} "wrong", True)
			d.try_login
			assert ("refused, and the reason kept", not d.is_accepted and attached d.last_error as e and then e.same_string ({STRING_32} "Wrong name or password"))
			d.set_fields (Loopback_url, "", {STRING_32} "", True)
			d.try_login
			assert ("a validation refusal never reaches the host", not d.is_accepted and attached d.last_error as e2 and then not e2.same_string ({STRING_32} "Wrong name or password"))
			refusal := Void
			d.set_fields (Loopback_url, "larry", {STRING_32} "right", True)
			d.try_login
			assert ("accepted", d.is_accepted and d.last_error = Void and not d.is_cancelled)
		end

feature -- CLIENT_APP: which door does it take?

	test_client_app_prefers_the_remembered_session
			-- A sealed blob that unseals AND that /me still honours: no password asked.
		local
			t: MEMORY_HTTP_TRANSPORT
			cf: CLIENT_CONFIG
			app: CLIENT_APP
			l_crypto: SIMPLE_ENCRYPTION
		do
			create l_crypto.make
			if not l_crypto.is_dpapi_available then
				print ("  SKIP: no DPAPI on this platform, so no session can be remembered at all%N")
				assert ("skipped cleanly without DPAPI", True)
			else
				create t.make
				cf := scratch_config ("remembered")
				cf.save_session (Hex_64)
				assert ("the blob was sealed", cf.has_session)
				create app.make_for_test (t, cf)
				assert ("nothing is logged in yet", not app.client.is_logged_in)
				assert ("the locator probed once and found nothing alive", t.exchange_count = 1)
				t.script (200, member_reply)
				app.try_remembered_session
				assert ("the remembered session was taken up", app.client.is_logged_in)
				assert ("through GET /me and nothing else", t.last_request.url.ends_with ("/me"))
				assert ("and it counts as remembering", app.remembers)
				cf.forget_session
			end
		end

	test_client_app_falls_back_to_the_door_and_logs_in
			-- No blob, or a blob the server will not honour: the door, and then a login
			-- through exactly the agent the door's button calls.
		local
			t: MEMORY_HTTP_TRANSPORT
			cf: CLIENT_CONFIG
			app: CLIENT_APP
			l_why: detachable STRING_32
		do
			create t.make
			cf := scratch_config ("door")
			create app.make_for_test (t, cf)
			app.try_remembered_session
			assert ("no blob, so no session", not app.client.is_logged_in)
			t.script (401, "{%"code%":%"unauthorized%",%"message%":%"Wrong name or password%"}")
			l_why := app.attempt_login (Loopback_url, "larry", {STRING_32} "wrong")
			assert ("a refusal comes back as the server's own message",
				not app.client.is_logged_in and attached l_why as w and then w.has_substring ({STRING_32} "Wrong"))
			t.script (200, login_reply (Hex_64))
			l_why := app.attempt_login (Loopback_url, "larry", {STRING_32} "right")
			assert ("and a good password opens the session", app.client.is_logged_in and l_why = Void)
			l_why := Void
		end

	test_client_app_refuses_to_send_a_password_to_a_plain_http_stranger
			-- The door validates, and so does the app: two gates, because the agent is
			-- reachable from a test and one day from a script.
		local
			t: MEMORY_HTTP_TRANSPORT
			cf: CLIENT_CONFIG
			app: CLIENT_APP
			l_why: detachable STRING_32
		do
			create t.make
			cf := scratch_config ("stranger")
			create app.make_for_test (t, cf)
			l_why := app.attempt_login ("http://evil.example.com", "larry", {STRING_32} "open sesame")
			assert ("refused before a byte went out",
				attached l_why and not app.client.is_logged_in and t.exchange_count = 1)
		end

	test_client_app_opens_the_first_room_and_ticks
			-- The whole assembled path short of a window: rooms, roster, poller, pump,
			-- badge - driven by hand exactly as `run' drives it from `on_tick'.
		local
			t: MEMORY_HTTP_TRANSPORT
			cf: CLIENT_CONFIG
			app: CLIENT_APP
			l_why: detachable STRING_32
		do
			create t.make
			cf := scratch_config ("room")
			create app.make_for_test (t, cf)
			t.script (200, login_reply (Hex_64))
			l_why := app.attempt_login (Loopback_url, "larry", {STRING_32} "right")
			assert ("logged in", app.client.is_logged_in and l_why = Void)
			t.script (200, "[{%"id%":4,%"name%":%"main%"}]")
			t.script (200, "{%"members%":[" + member_reply + "]}")
			app.open_room
			assert ("the first room was opened", app.presenter.is_room_open and app.room_id = 4)
			assert ("and named in the header", app.view.room_title.same_string ({STRING_32} "main"))
			app.tick
			assert ("a tick with nothing waiting shows nothing", app.view.shown_count = 0)
			assert ("and the badge matches the presenter", app.view.unread = app.presenter.unread)
			app.presenter.close_room
			assert ("closing the room stops the poller", not app.presenter.is_room_open)
		end

	test_client_app_reports_a_server_that_lists_no_room
			-- The pane opens anyway, carrying the reason: a member who is told nothing
			-- learns nothing.
		local
			t: MEMORY_HTTP_TRANSPORT
			cf: CLIENT_CONFIG
			app: CLIENT_APP
			l_why: detachable STRING_32
		do
			create t.make
			cf := scratch_config ("noroom")
			create app.make_for_test (t, cf)
			t.script (200, login_reply (Hex_64))
			l_why := app.attempt_login (Loopback_url, "larry", {STRING_32} "right")
			assert ("logged in", app.client.is_logged_in and l_why = Void)
			t.script (200, "[]")
			app.open_room
			assert ("no room opened", not app.presenter.is_room_open)
			assert ("and the pane was told why", not app.view.errors.is_empty)
		end

feature {NONE} -- Fixtures: the pane

	pane: SW_CHAT_VIEW
			-- An offscreen room pane, 900 x 700 at the origin.
		do
			create Result.make ({STRING_32} "main", 0, 0, 900, 700)
		end

	sent: ARRAYED_LIST [STRING_32]
			-- What `record_sent' was handed, in order.
		once
			create Result.make (4)
		end

	record_sent (a_text: READABLE_STRING_GENERAL)
			-- The pane's `on_send', for the assault.
		do
			sent.extend (a_text.to_string_32)
		end

	refusal: detachable STRING_32
			-- What the next `scripted_attempt' answers; Void means success.

	scripted_attempt (a_url, a_username: READABLE_STRING_8; a_password: READABLE_STRING_GENERAL): detachable STRING_32
			-- The door's `attempt', scripted: whatever `refusal' says.
		do
			Result := refusal
		end

feature {NONE} -- Fixtures: events

	message_event (a_id, a_sender: INTEGER_64; a_body: STRING_8): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_now.make_now
			create l_payload.make
			create Result.make (a_id, 1, a_sender, {CHAT_EVENT_KINDS}.Kind_message, l_now, a_body.to_string_32, Void, l_payload, False)
		end

	system_event (a_id: INTEGER_64; a_body: STRING_8): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_now.make_now
			create l_payload.make
			create Result.make (a_id, 1, 0, {CHAT_EVENT_KINDS}.Kind_system, l_now, a_body.to_string_32, Void, l_payload, False)
		end

	image_event (a_id, a_sender: INTEGER_64; a_file_name, a_caption: STRING_32): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
			l_attachment: CHAT_ATTACHMENT
		do
			create l_now.make_now
			create l_payload.make
			create l_attachment.make (3, a_sender, a_file_name, {CHAT_ATTACHMENT}.Mime_png, 64, Sha_256_of_nothing, l_now)
			create Result.make (a_id, 1, a_sender, {CHAT_EVENT_KINDS}.Kind_image, l_now, a_caption, l_attachment, l_payload, False)
		end

feature {NONE} -- Fixtures: the wire

	loopback: CHAT_ENDPOINT
		do
			create Result.make (Loopback_url)
		end

	logged_in_client (a_transport: MEMORY_HTTP_TRANSPORT): CHAT_CLIENT
			-- A client logged in as user 5 ("larry") through one scripted reply.
		local
			r: CHAT_RESULT [CHAT_MEMBER]
		do
			create Result.make (a_transport, loopback)
			a_transport.script (200, login_reply (Hex_64))
			r := Result.login ("larry", {STRING_32} "correct horse battery staple")
			check logged_in: Result.is_logged_in end
		end

	login_reply (a_token: STRING_8): STRING_8
		do
			Result := "{%"token%":%"" + a_token + "%",%"member%":" + member_reply + "}"
		end

	member_reply: STRING_8
			-- User 5, "larry" - what GET /me answers, and what a roster entry looks like.
		do
			Result := "{%"id%":5,%"username%":%"larry%",%"display_name%":%"Larry%",%"is_admin%":true,%"is_bot%":false}"
		end

	wire_event (a_id, a_room, a_sender: INTEGER_64; a_kind, a_body: STRING_8): STRING_8
		do
			Result := "{%"id%":" + a_id.out + ",%"room_id%":" + a_room.out + ",%"sender_id%":" + a_sender.out
				+ ",%"kind%":%"" + a_kind + "%",%"created_at%":%"2026-09-02T12:00:00%",%"body%":%"" + a_body + "%",%"attachment%":null,%"payload%":{},%"is_bot%":false}"
		end

	wire_message (a_id, a_sender: INTEGER_64; a_body: STRING_8): STRING_8
		do
			Result := wire_event (a_id, 1, a_sender, "message", a_body)
		end

	wire_status (a_room: INTEGER_64; a_from, a_text: STRING_8): STRING_8
		do
			Result := "{%"room_id%":" + a_room.out + ",%"from%":%"" + a_from + "%",%"text%":%"" + a_text + "%"}"
		end

	wire_page (a_events, a_statuses: STRING_8): STRING_8
		do
			Result := "{%"events%":[" + a_events + "],%"statuses%":[" + a_statuses + "]}"
		end

feature {NONE} -- Fixtures: the config

	scratch_config (a_tag: STRING_8): CLIENT_CONFIG
			-- A config that reads and writes testing/window_scratch/<tag>.toml, wiped first.
		local
			l_directory: DIRECTORY
			l_file: RAW_FILE
			l_path: STRING_32
		do
			create l_directory.make (Scratch_directory)
			if not l_directory.exists then
				l_directory.recursive_create_dir
			end
			create l_path.make_from_string_general (Scratch_directory + "/" + a_tag + ".toml")
			create l_file.make_with_name (l_path)
			if l_file.exists then
				l_file.delete
			end
			create Result.make_defaults
			Result.set_storage_path (l_path)
		ensure
			nothing_remembered: not Result.has_session
		end

feature {NONE} -- Constants

	Loopback_url: STRING_8 = "http://127.0.0.1:8080"

	Hex_64: STRING_8 = "a3f1c07d5b9e2846afd310c6b47e59182d0ab7c4e6f5901324578badc0ffee11"
			-- 64 lowercase hex digits: the shape SESSION_ISSUER mints.

	Sha_256_of_nothing: STRING_8 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
			-- The SHA-256 of the empty input; a valid hash shape for a fixture attachment.

	Scratch_directory: STRING_8 = "testing/window_scratch"

	acceptance_line: STRING_32
			-- The D-015 acceptance line: Hebrew, the robot, Greek.
		do
			create Result.make (16)
			Result.append_character ('%/1513/')
			Result.append_character ('%/1500/')
			Result.append_character ('%/1493/')
			Result.append_character ('%/1501/')
			Result.append_character (' ')
			Result.append_character ('%/129302/')
			Result.append_character (' ')
			Result.append_character ('%/935/')
			Result.append_character ('%/961/')
			Result.append_character ('%/953/')
			Result.append_character ('%/963/')
			Result.append_character ('%/964/')
			Result.append_character ('%/972/')
			Result.append_character ('%/962/')
		ensure
			given: not Result.is_empty
		end

end
