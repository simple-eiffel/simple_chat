note
	description: "[
		Phase 4 Task 9 under assault: the three freshly-landed libraries
		wired into the client stack. WINHTTP_TRANSPORT against a dead
		port and against input that could never go on the wire (results,
		never exceptions, counted every time); CLIENT_CONFIG round-tripped
		through a scratch client.toml, fed a hostile file (defaults stand,
		D6), and holding a session only as a DPAPI blob - the token is
		proved absent from the file's actual text; TRAY_NOTIFIER counting
		with or without an installed icon; and the first full client stack
		over real HTTP: the finalized server exe booted on a scratch
		configuration under C:\Users\Public\sc_wiring_test, then
		WINHTTP_TRANSPORT + CHAT_CLIENT: health, login (a real minted
		token), post, events - skipped, and passed, when the server exe
		is not built. The server exe is copied to a distinct name
		(sc_wiring_server.exe) before it is booted, because every target
		of this system finalizes to simple_chat.exe - a taskkill by that
		image name would kill this very test runner. The child's stdout
		goes to a FILE, not a pipe: a login makes the server log through
		CHAT_LOG, and a console write into an undrained pipe blocks the
		server mid-request - health keeps answering, every login times
		out, and the client sees a wedged server that looks alive
		(found the hard way; proved with a piped boot and a curl
		barrage: 8 x health 200, then every login timed out).
	]"
	author: "Larry Rix"

class
	WIRING_ASSAULT

inherit
	TEST_SET_BASE

feature -- WINHTTP_TRANSPORT: failures are results

	test_winhttp_transport_refuses_what_cannot_go_on_the_wire
			-- A URL with a blank and a header carrying CRLF are refused as failed
			-- replies before anything is sent - and still counted.
		local
			l_transport: WINHTTP_TRANSPORT
			l_headers: HASH_TABLE [STRING_8, STRING_8]
			l_reply: HTTP_REPLY
		do
			create l_transport.make
			create l_headers.make (0)
			l_reply := l_transport.send ("GET", "http://127.0.0.1:8080/a b", l_headers, Void, 2)
			assert ("a blank in the URL is a failed reply, not an exception", not l_reply.is_exchanged and not l_reply.error.is_empty)
			create l_headers.make (1)
			l_headers.force ("evil%R%NX-Injected: yes", "X-Test")
			l_reply := l_transport.send ("GET", "http://127.0.0.1:8080/ok", l_headers, Void, 2)
			assert ("CRLF in a header value is a failed reply: header injection cannot pass", not l_reply.is_exchanged and not l_reply.error.is_empty)
			assert ("both refusals were counted", l_transport.exchange_count = 2)
		end

	test_winhttp_transport_reports_a_dead_port_as_unexchanged
			-- Nothing listens on the discard port: the exchange fails cleanly, with
			-- an explanation, within the call's own timeout.
		local
			l_transport: WINHTTP_TRANSPORT
			l_headers: HASH_TABLE [STRING_8, STRING_8]
			l_reply: HTTP_REPLY
		do
			create l_transport.make
			create l_headers.make (0)
			l_reply := l_transport.send ("GET", "http://127.0.0.1:9/", l_headers, Void, 2)
			assert ("no exchange", not l_reply.is_exchanged and not l_reply.is_success)
			assert ("explained", not l_reply.error.is_empty)
			assert ("counted", l_transport.exchange_count = 1)
		end

feature -- CLIENT_CONFIG: the file

	test_client_config_round_trip
			-- Everything the class persists comes back from its own file.
		local
			l_saved, l_loaded: CLIENT_CONFIG
		do
			create l_saved.make_defaults
			l_saved.set_storage_path (scratch_path ("client_roundtrip"))
			l_saved.set_only_server_url ("https://chat.example.org")
			l_saved.add_server_url ("https://standby.example.org:8443")
			l_saved.set_prefers_local (False)
			l_saved.set_local_port (9099)
			l_saved.set_window (12, 34, 800, 600)
			l_saved.save
			assert ("written where pointed", l_saved.file_exists (l_saved.storage_path) and l_saved.stored_file_text.has_substring ("server_urls"))
			create l_loaded.make_defaults
			l_loaded.set_storage_path (l_saved.storage_path)
			l_loaded.load
			assert ("servers back in order", l_loaded.server_urls.count = 2
				and l_loaded.server_url.same_string ("https://chat.example.org")
				and l_loaded.server_urls [2].same_string ("https://standby.example.org:8443"))
			assert ("preferences back", not l_loaded.prefers_local and l_loaded.local_port = 9099)
			assert ("window back", l_loaded.window_x = 12 and l_loaded.window_y = 34
				and l_loaded.window_width = 800 and l_loaded.window_height = 600)
			assert ("no session invented", not l_loaded.has_session and l_loaded.load_session = Void)
		end

	test_client_config_hostile_file_yields_defaults
			-- Junk that does not parse, then a parseable file of wrong types and
			-- hostile values: the defaults stand, nothing crashes (D6).
		local
			l_config: CLIENT_CONFIG
		do
			create l_config.make_defaults
			l_config.set_storage_path (write_scratch ("client_junk", "[
				= nonsense without a key
				??? this is not TOML {{{
				]"))
			l_config.load
			assert ("junk leaves the defaults", not l_config.has_server and l_config.prefers_local
				and l_config.local_port = 8080 and l_config.window_x = 100 and l_config.window_y = 100
				and l_config.window_width = 900 and l_config.window_height = 700 and not l_config.has_session)
			create l_config.make_defaults
			l_config.set_storage_path (write_scratch ("client_hostile", "[
				server_urls = ["http://evil.example.org", "https://ok.example.org", "https://OK.example.org", "not a url"]
				prefers_local = "yes"
				local_port = 700000
				window_x = 5
				window_y = 6
				window_width = -50
				window_height = 400
				session = "not*base64*text"
				]"))
			l_config.load
			assert ("only the acceptable, fresh URL joined", l_config.server_urls.count = 1
				and l_config.server_url.same_string ("https://ok.example.org"))
			assert ("a string is not a boolean: preference kept", l_config.prefers_local)
			assert ("an impossible port kept the default", l_config.local_port = 8080)
			assert ("a hostile width kept the whole placement", l_config.window_x = 100 and l_config.window_y = 100
				and l_config.window_width = 900 and l_config.window_height = 700)
			assert ("what is not Base64 is not a session", not l_config.has_session and l_config.load_session = Void)
		end

	test_client_config_session_sealed_never_in_clear
			-- The session round trip: sealed on `save_session', absent from the
			-- file's text in clear, unsealed by `load_session' - here and by a
			-- fresh instance - and gone after `forget_session'.
		local
			l_crypto: SIMPLE_ENCRYPTION
			l_config, l_again, l_third: CLIENT_CONFIG
			l_text: STRING_8
		do
			create l_crypto.make
			if not l_crypto.is_dpapi_available then
				print ("  (session sealing skipped: DPAPI is not available on this platform)%N")
				assert ("nothing to prove without DPAPI", True)
			else
				create l_config.make_defaults
				l_config.set_storage_path (scratch_path ("client_session"))
				l_config.save_session (Wiring_token)
				assert ("sealed and remembered", l_config.has_session)
				l_text := l_config.stored_file_text
				assert ("the file carries a session key", l_text.has_substring ("session"))
				assert ("the token is nowhere in the file", not l_text.has_substring (Wiring_token))
				assert ("unsealed here", attached l_config.load_session as l_here and then l_here.same_string (Wiring_token))
				create l_again.make_defaults
				l_again.set_storage_path (l_config.storage_path)
				l_again.load
				assert ("a fresh instance unseals the same token", l_again.has_session
					and attached l_again.load_session as l_fresh and then l_fresh.same_string (Wiring_token))
				l_again.forget_session
				assert ("forgotten", not l_again.has_session and l_again.load_session = Void)
				assert ("and gone from the file", not l_again.stored_file_text.has_substring ("session"))
				create l_third.make_defaults
				l_third.set_storage_path (l_config.storage_path)
				l_third.load
				assert ("nothing to remember afterwards", not l_third.has_session)
			end
		end

feature -- TRAY_NOTIFIER

	test_tray_notifier_counts_with_or_without_a_shell
			-- Over a real SHELL_TRAY when the shell accepts an icon; the degrade
			-- path otherwise - the counts hold either way, exactly as NOTIFIER's
			-- contracts demand (the head-cut and tooltip contracts fire under DBC).
		local
			l_tray: SHELL_TRAY
			l_notifier: TRAY_NOTIFIER
		do
			create l_tray.make ({STRING_32} "simple_chat wiring test")
			if not l_tray.is_installed then
				print ("  (no icon: the shell refused it; exercising the degrade path)%N")
			end
			create l_notifier.make (l_tray)
			l_notifier.notify ({STRING_32} "A sender whose name runs far past the forty-eight character head cut of the balloon title",
				{STRING_32} "And a snippet that likewise runs on and on, well past the two hundred characters the balloon body is head-cut to, so that the cut itself is exercised under contract rather than merely claimed in a comment - which takes a while.")
			l_notifier.notify ({STRING_32} "Larry", {STRING_32} "")
			assert ("both notices counted", l_notifier.notify_count = 2)
			l_notifier.badge (7)
			assert ("badged", l_notifier.unread = 7)
			l_notifier.badge (0)
			assert ("badge at zero", l_notifier.unread = 0)
			l_notifier.badge (12)
			l_notifier.clear
			assert ("cleared", l_notifier.unread = 0)
			l_tray.remove
			assert ("icon removed, or never installed", not l_tray.is_installed)
			l_notifier.notify ({STRING_32} "After removal", {STRING_32} "degrades to silence, still counted")
			assert ("counted without an icon", l_notifier.notify_count = 3)
		end

feature -- The live round trip

	test_live_client_stack_round_trip
			-- The first full client stack over real HTTP: the finalized server exe,
			-- booted on a scratch configuration, answered through WINHTTP_TRANSPORT
			-- + SERVICE_LOCATOR + CHAT_CLIENT: health, login with a real minted
			-- token, post, an image whose Hebrew file name and emoji caption ride
			-- percent-encoded header lines (Task 9b), events. Skips, and passes,
			-- when the exe is not built - the SKIP line says so out loud.
			-- Teardown runs before the verdict so a failure never strands a server.
		local
			l_exe: RAW_FILE
			l_process: SIMPLE_PROCESS
			l_server: SIMPLE_ASYNC_PROCESS
			l_transport: WINHTTP_TRANSPORT
			l_locator: SERVICE_LOCATOR
			l_endpoint: CHAT_ENDPOINT
			l_client: detachable CHAT_CLIENT
			l_login: detachable CHAT_RESULT [CHAT_MEMBER]
			l_posted, l_image: detachable CHAT_RESULT [CHAT_EVENT]
			l_name, l_caption: STRING_32
			l_image_ok: BOOLEAN
			l_page: detachable CHAT_RESULT [CHAT_PAGE]
			l_transcript: STRING_8
			l_environment: EXECUTION_ENVIRONMENT
			l_tries: INTEGER
			l_alive, l_found: BOOLEAN
			l_stamp: SIMPLE_DATE_TIME
			l_started_at: INTEGER_64
		do
			create l_exe.make_with_name (Server_exe_path)
			if not l_exe.exists then
				print ("  SKIP: the live round trip needs " + Server_exe_path + ", which is not built%N")
				assert ("skipped cleanly without a server exe", True)
			else
				create l_transcript.make (512)
				create l_process.make
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				prepare_scratch
				create l_server.make
					-- cmd redirects the server's stdout to a file: piped stdout wedges
					-- the server on its first login log line (see the class note).
				l_server.start ("cmd /c " + Scratch_root + "\" + Scratch_server_name + " " + Scratch_root + "\server.toml > " + Scratch_root + "\server_boot.log 2>&1")
				assert ("server process started", l_server.was_started_successfully)
				create l_transport.make
				create l_endpoint.make (Base_url)
				create l_locator.make (l_transport)
				create l_environment
				from
					l_tries := 0
				until
					l_alive or l_tries >= 40
				loop
					l_locator.probe (l_endpoint)
					l_alive := l_locator.last_probe_alive
					if not l_alive then
						l_environment.sleep (500_000_000)
					end
					l_tries := l_tries + 1
				variant
					41 - l_tries
				end
				if l_alive then
					l_transcript.append ("    GET  /health          -> " + l_locator.last_probe_status.out + " " + l_locator.last_probe_body + "%N")
					create l_client.make (l_transport, l_endpoint)
					create l_stamp.make_now
					l_started_at := l_stamp.to_timestamp
					l_login := l_client.login (Admin_username, Admin_password)
					create l_stamp.make_now
					if not l_login.is_success and then attached l_login.error as l_login_error then
						l_transcript.append ("    POST /login           -> FAILED after ~"
							+ (l_stamp.to_timestamp - l_started_at).out + " s: " + error_line (l_login_error) + "%N")
					end
					if l_login.is_success and then attached l_client.me as l_me then
						l_transcript.append ("    POST /login           -> success: member #" + l_me.id.out
							+ " (" + Admin_username + "), a real minted token held in memory only%N")
						l_posted := l_client.post_message (seeded_room_id, Round_trip_body)
						if not l_posted.is_success and then attached l_posted.error as l_post_error then
							l_transcript.append ("    POST /rooms/" + seeded_room_id.out + "/messages -> FAILED: " + error_line (l_post_error) + "%N")
						end
						if l_posted.is_success and then attached l_posted.value as l_echo then
							l_transcript.append ("    POST /rooms/" + seeded_room_id.out + "/messages -> echo id " + l_echo.id.out + "%N")
						end
						l_name := hebrew_file_name
						l_caption := hebrew_caption
						l_image := l_client.post_image (seeded_room_id, live_png_bytes (64), l_name, l_caption)
						if not l_image.is_success and then attached l_image.error as l_image_error then
							l_transcript.append ("    POST /rooms/" + seeded_room_id.out + "/images   -> FAILED: " + error_line (l_image_error) + "%N")
						end
						if l_image.is_success and then attached l_image.value as l_shot then
							l_image_ok := l_shot.is_image and then l_shot.body.same_string (l_caption)
								and then (attached l_shot.attachment as l_att and then l_att.original_name.same_string (l_name))
							l_transcript.append ("    POST /rooms/" + seeded_room_id.out + "/images   -> image event id " + l_shot.id.out
								+ "; name and caption came back "
								+ (if l_image_ok then "byte for byte" else "MANGLED" end)
								+ " (" + utf8_head (l_shot.body, 40) + ")%N")
						end
						l_page := l_client.events_since (seeded_room_id, 0, 100)
						if not l_page.is_success and then attached l_page.error as l_page_error then
							l_transcript.append ("    GET  /rooms/" + seeded_room_id.out + "/events   -> FAILED: " + error_line (l_page_error) + "%N")
						end
						if l_page.is_success and then attached l_page.value as l_events then
							l_found := across l_events.events as l_event some l_event.body.same_string_general (Round_trip_body) end
							l_transcript.append ("    GET  /rooms/" + seeded_room_id.out + "/events   -> "
								+ l_events.events.count.out + " event(s); the posted message is "
								+ (if l_found then "among them" else "MISSING" end) + "%N")
						end
						l_client.logout
						l_transcript.append ("    POST /logout          -> token dropped before the request went out%N")
					end
				end
				if not l_alive then
					l_transcript.append ("    /health never alive after " + l_tries.out + " probes; last status "
						+ l_locator.last_probe_status.out + ", body: " + l_locator.last_probe_body + "%N")
				end
					-- Teardown first: no assert may strand the scratch server.
				l_transcript.append ("    server said: " + head_of_file (Scratch_root + "\server_boot.log", 600) + "%N")
				if l_server.is_running then
					l_server.kill.do_nothing
				end
				l_server.close
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				print (l_transcript)
				assert ("the server answered /health with the health shape", l_alive)
				assert ("login succeeded against the live server with a real token", attached l_login as l_l and then l_l.is_success)
				assert ("the post was echoed as a stored event", attached l_posted as l_p and then l_p.is_success)
				assert ("the posted message came back through /events", l_found)
				assert ("the image posted and its hebrew name and emoji caption survived the header line", l_image_ok)
			end
		end

feature -- The live round trip, through CLIENT_APP and the real pane

	test_live_client_app_shows_an_event_in_the_real_pane
			-- Task 10, end to end and for real: the finalized server booted, then
			-- CLIENT_APP - the very class the exe roots on - taken through the path its
			-- window takes, with the GUI's two blocking calls (the door's `run', the
			-- pane's `run') replaced by the calls those windows make. `attempt_login' is
			-- the door's own button agent; `open_room' is what `run' calls next; `tick'
			-- is what SW_WINDOW fires every 250 ms. The event comes back through the
			-- REAL poller, on its own SCOOP processor, into the REAL SW_CHAT_VIEW - not
			-- a double - and is looked for in the thread's bubbles.
			--
			-- Then the second half of D-018: the session sealed with DPAPI, a SECOND
			-- CLIENT_APP built over the same file, and no password asked - proven
			-- against a live server that really does honour the token at GET /me.
			--
			-- Skips, and passes, when the exe is not built. Teardown runs before the
			-- verdict so a failure never strands a server.
		local
			l_exe: RAW_FILE
			l_process: SIMPLE_PROCESS
			l_server: SIMPLE_ASYNC_PROCESS
			l_transport: WINHTTP_TRANSPORT
			l_locator: SERVICE_LOCATOR
			l_endpoint: CHAT_ENDPOINT
			l_environment: EXECUTION_ENVIRONMENT
			l_config, l_second_config: CLIENT_CONFIG
			l_app, l_second_app: detachable CLIENT_APP
			l_why: detachable STRING_32
			l_transcript: STRING_8
			l_tries: INTEGER
			l_alive, l_logged_in, l_opened, l_shown, l_sealed, l_resumed: BOOLEAN
		do
			create l_exe.make_with_name (Server_exe_path)
			if not l_exe.exists then
				print ("  SKIP: the live pane round trip needs " + Server_exe_path + ", which is not built%N")
				assert ("skipped cleanly without a server exe", True)
			else
				create l_transcript.make (512)
				create l_process.make
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				prepare_scratch
				delete_file (client_scratch_toml)
				create l_server.make
				l_server.start ("cmd /c " + Scratch_root + backslash + Scratch_server_name + " " + Scratch_root + backslash + "server.toml > " + Scratch_root + backslash + "pane_boot.log 2>&1")
				assert ("server process started", l_server.was_started_successfully)
				create l_transport.make
				create l_endpoint.make (Base_url)
				create l_locator.make (l_transport)
				create l_environment
				from
					l_tries := 0
				until
					l_alive or l_tries >= 40
				loop
					l_locator.probe (l_endpoint)
					l_alive := l_locator.last_probe_alive
					if not l_alive then
						l_environment.sleep (500_000_000)
					end
					l_tries := l_tries + 1
				variant
					41 - l_tries
				end
				if l_alive then
					create l_config.make_defaults
					l_config.set_storage_path (client_scratch_toml)
					l_config.set_prefers_local (False)
					l_config.set_only_server_url (Base_url)
					create l_app.make_for_test (l_transport, l_config)
					l_transcript.append ("    CLIENT_APP located " + l_app.endpoint.base_url + "%N")
					l_why := l_app.attempt_login (Base_url, Admin_username, Admin_password)
					l_logged_in := l_app.client.is_logged_in
					if attached l_why as w then
						l_transcript.append ("    the door was refused: " + utf8_head (w, 80) + "%N")
					end
					if l_logged_in then
						l_transcript.append ("    the door opened: attempt_login answered Void and the session is live%N")
						l_app.client.remember_session_in (l_config)
						l_sealed := l_config.has_session
						l_transcript.append ("    remember me: " + (if l_sealed then "sealed as a DPAPI blob" else "no DPAPI here, so nothing remembered" end) + "%N")
						l_app.open_room
						l_opened := l_app.presenter.is_room_open
						l_transcript.append ("    open_room -> room " + l_app.room_id.out
							+ " (" + utf8_head (l_app.view.room_title, 40) + "), poller running: "
							+ l_opened.out + "%N")
						if l_opened then
							l_app.send_text (Pane_body)
							from
								l_tries := 0
							until
								l_shown or l_tries >= 40
							loop
								l_app.tick
								l_shown := across l_app.view.thread.messages as m some m.text.has_substring (Pane_body) end
								if not l_shown then
									l_environment.sleep (250_000_000)
								end
								l_tries := l_tries + 1
							variant
								41 - l_tries
							end
							l_transcript.append ("    the pane after " + l_tries.out + " ticks: "
								+ l_app.view.shown_count.out + " event(s), " + l_app.view.thread.count.out
								+ " bubble(s); the posted line is "
								+ (if l_shown then "among them" else "MISSING" end) + "%N")
							l_app.presenter.close_room
						end
						if l_sealed then
							create l_second_config.make_defaults
							l_second_config.set_storage_path (client_scratch_toml)
							l_second_config.load
							create l_second_app.make_for_test (l_transport, l_second_config)
							l_second_app.try_remembered_session
							l_resumed := l_second_app.client.is_logged_in
							l_transcript.append ("    a second CLIENT_APP over the same client.toml: "
								+ (if l_resumed then "logged in with no password (GET /me honoured the blob)" else "was NOT resumed" end) + "%N")
							if l_resumed and then attached l_second_app as l_sa then
								l_sa.client.logout
							end
						end
					end
				else
					l_transcript.append ("    /health never alive after " + l_tries.out + " probes%N")
				end
					-- Teardown first: no assert may strand the scratch server.
				if l_server.is_running then
					l_server.kill.do_nothing
				end
				l_server.close
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				delete_file (client_scratch_toml)
				print (l_transcript)
				assert ("the server answered /health with the health shape", l_alive)
				assert ("the door agent opened a live session", l_logged_in)
				assert ("the first room opened and the poller started", l_opened)
				assert ("the posted line came back through the poller into the real pane", l_shown)
				assert ("a sealed session was taken up by a second CLIENT_APP with no password",
					l_resumed or not l_sealed)
			end
		end

	Pane_body: STRING_8 = "The first line ever to reach a simple_chat window"

	client_scratch_toml: STRING_32
			-- The scratch client.toml, beside the scratch server's data.
		do
			create Result.make_from_string_general (Scratch_root)
			Result.append_character (backslash_character)
			Result.append ({STRING_32} "client.toml")
		ensure
			given: not Result.is_empty
		end

	backslash: STRING_8
			-- One path separator, written as a code so no tool between here and the
			-- compiler can eat it.
		do
			create Result.make (1)
			Result.append_character ('%/92/')
		end

	backslash_character: CHARACTER_32 = '%/92/'

feature {NONE} -- Transcript support

	error_line (a_error: CHAT_ERROR): STRING_8
			-- "http <status> <code>: <message>" - for the transcript; never a token.
		do
			create Result.make (64)
			Result.append ("http ")
			Result.append (a_error.http_status.out)
			Result.append (" ")
			Result.append (a_error.code)
			Result.append (": ")
			Result.append ({UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_error.message))
		end

	utf8_head (a_text: READABLE_STRING_32; a_maximum: INTEGER): STRING_8
			-- The first `a_maximum' characters of `a_text', UTF-8 encoded.
		require
			positive: a_maximum > 0
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.substring (1, a_text.count.min (a_maximum)))
		end

feature -- The freeze hunt: what holds the GUI's own thread (phase4/freeze)

	test_live_gui_latency_through_a_quiet_poll
			-- THE FREEZE, measured. The finalized server booted on the scratch
			-- port, CLIENT_APP taken down the path its window takes, and then the
			-- two things the GUI thread ever does timed to the millisecond:
			-- `send_text' (what the composer's Return does) and `tick' (what
			-- SW_WINDOW fires every 250 ms).
			--
			-- Twenty lines go out as fast as a member could type them - the room
			-- is busy, so every long poll returns at once - and then the room
			-- goes QUIET and the poller settles into a full 25 s wait. If any
			-- call on the GUI's own processor waits on the poller's, the
			-- heartbeat stops here for as long as that poll lasts, and the
			-- window would be frozen for exactly that long.
			--
			-- Skips, and passes, when the exe is not built. Teardown runs before
			-- the verdict so a failure never strands a server.
		local
			l_exe: RAW_FILE
			l_process: SIMPLE_PROCESS
			l_server: SIMPLE_ASYNC_PROCESS
			l_transport: WINHTTP_TRANSPORT
			l_locator: SERVICE_LOCATOR
			l_endpoint: CHAT_ENDPOINT
			l_environment: EXECUTION_ENVIRONMENT
			l_config: CLIENT_CONFIG
			l_app: detachable CLIENT_APP
			l_why: detachable STRING_32
			l_transcript: STRING_8
			l_line: STRING_32
			l_tries, l_i, l_k, l_slow_ticks, l_traced: INTEGER
			l_hits, l_at, l_last_at: INTEGER
			l_alive, l_logged_in, l_opened, l_each_once, l_in_order, l_all_intact: BOOLEAN
			t0, l_span: INTEGER_64
			l_send_worst, l_busy_tick_worst, l_quiet_tick_worst: INTEGER_64
			l_send_worst_at, l_quiet_worst_at, l_alloc_worst_at: INTEGER
			l_alloc_worst: INTEGER_64
			l_junk: ARRAYED_LIST [STRING_8]
		do
			create l_exe.make_with_name (Server_exe_path)
			if not l_exe.exists then
				print ("  SKIP: the freeze hunt needs " + Server_exe_path + ", which is not built%N")
				assert ("skipped cleanly without a server exe", True)
			else
				create l_transcript.make (2048)
				create l_process.make
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				prepare_scratch
				delete_file (client_scratch_toml)
				create l_server.make
				l_server.start ("cmd /c " + Scratch_root + backslash + Scratch_server_name + " " + Scratch_root + backslash + "server.toml > " + Scratch_root + backslash + "freeze_boot.log 2>&1")
				assert ("server process started", l_server.was_started_successfully)
				create l_transport.make
				create l_endpoint.make (Base_url)
				create l_locator.make (l_transport)
				create l_environment
				from
					l_tries := 0
				until
					l_alive or l_tries >= 40
				loop
					l_locator.probe (l_endpoint)
					l_alive := l_locator.last_probe_alive
					if not l_alive then
						l_environment.sleep (500_000_000)
					end
					l_tries := l_tries + 1
				variant
					41 - l_tries
				end
				if l_alive then
					create l_config.make_defaults
					l_config.set_storage_path (client_scratch_toml)
					l_config.set_prefers_local (False)
					l_config.set_only_server_url (Base_url)
					create l_app.make_for_test (l_transport, l_config)
					l_why := l_app.attempt_login (Base_url, Admin_username, Admin_password)
					l_logged_in := l_app.client.is_logged_in
					if attached l_why as w then
						l_transcript.append ("    the door was refused: " + utf8_head (w, 80) + "%N")
					end
					if l_logged_in then
						l_app.open_room
						l_opened := l_app.presenter.is_room_open
						l_transcript.append ("    open_room -> room " + l_app.room_id.out + ", poller running: " + l_opened.out + "%N")
						if l_opened then
								-- BUSY: twenty lines out, a heartbeat after each.
							from
								l_i := 1
							until
								l_i > Freeze_posts
							loop
								l_line := freeze_line (l_i)
								t0 := freeze_now_ms
								l_app.send_text (l_line)
								l_span := freeze_now_ms - t0
								if l_span > l_send_worst then
									l_send_worst := l_span
									l_send_worst_at := l_i
								end
								t0 := freeze_now_ms
								l_app.tick
								l_span := freeze_now_ms - t0
								l_busy_tick_worst := l_busy_tick_worst.max (l_span)
								l_i := l_i + 1
							variant
								Freeze_posts + 1 - l_i
							end
							l_transcript.append ("    BUSY  " + Freeze_posts.out + " posts: worst send_text " + l_send_worst.out
								+ " ms (post " + l_send_worst_at.out + "), worst tick " + l_busy_tick_worst.out + " ms%N")
								-- QUIET: nobody speaks, so the poller settles into a full 25 s wait.
							from
								l_i := 1
							until
								l_i > Freeze_quiet_ticks
							loop
									-- A pure allocation burst, touching nothing of the client's:
									-- if THIS stops for as long as a long poll, nothing the
									-- presenter does is to blame.
								t0 := freeze_now_ms
								create l_junk.make (200)
								from
									l_k := 1
								until
									l_k > 200
								loop
									l_junk.extend (create {STRING_8}.make_filled ('x', 1024))
									l_k := l_k + 1
								variant
									201 - l_k
								end
								l_span := freeze_now_ms - t0
								if l_span > l_alloc_worst then
									l_alloc_worst := l_span
									l_alloc_worst_at := l_i
								end
								t0 := freeze_now_ms
								l_app.tick
								l_span := freeze_now_ms - t0
								if l_span > Slow_tick_ms then
									l_slow_ticks := l_slow_ticks + 1
									if l_traced < 12 then
										l_traced := l_traced + 1
										l_transcript.append ("      tick " + l_i.out + " held the GUI thread " + l_span.out + " ms%N")
									end
								end
								if l_span > l_quiet_tick_worst then
									l_quiet_tick_worst := l_span
									l_quiet_worst_at := l_i
								end
								l_environment.sleep (250_000_000)
								l_i := l_i + 1
							variant
								Freeze_quiet_ticks + 1 - l_i
							end
							l_transcript.append ("    QUIET " + Freeze_quiet_ticks.out + " ticks: worst tick " + l_quiet_tick_worst.out
								+ " ms (tick " + l_quiet_worst_at.out + "), " + l_slow_ticks.out + " over " + Slow_tick_ms.out + " ms%N")
								-- WHAT ARRIVED. A window Windows has ghosted throws keystrokes away,
								-- so a stall is not a delay: it is lost and doubled input. Every
								-- line must be in the pane exactly once, whole, and in the order
								-- it was typed.
							l_each_once := True
							l_in_order := True
							l_last_at := 0
							from
								l_i := 1
							until
								l_i > Freeze_posts
							loop
								l_hits := 0
								l_at := 0
								l_k := 0
								across l_app.view.thread.messages as m loop
									l_k := l_k + 1
									if m.text.has_substring (freeze_line (l_i)) then
										l_hits := l_hits + 1
										l_at := l_k
									end
								end
								if l_hits /= 1 then
									l_each_once := False
									l_transcript.append ("      line " + l_i.out + " is in the pane " + l_hits.out + " time(s)%N")
								end
								if l_at <= l_last_at then
									l_in_order := False
								end
								l_last_at := l_at
								l_i := l_i + 1
							variant
								Freeze_posts + 1 - l_i
							end
							l_all_intact := l_each_once and l_in_order and l_app.view.shown_count = Freeze_posts
							l_transcript.append ("    INPUT " + Freeze_posts.out + " distinct lines: "
								+ l_app.view.shown_count.out + " shown, each exactly once: " + l_each_once.out
								+ ", in the order typed: " + l_in_order.out + "%N")
							l_transcript.append ("    ALLOC worst allocation burst " + l_alloc_worst.out
								+ " ms (tick " + l_alloc_worst_at.out + ")%N")
							l_transcript.append ("    the pane took " + l_app.presenter.pages_pumped.out + " page(s) and showed "
								+ l_app.view.shown_count.out + " event(s)%N")
							if l_app.presenter.is_room_open then
								l_app.presenter.close_room
							end
						end
					end
				else
					l_transcript.append ("    /health never alive after " + l_tries.out + " probes%N")
				end
					-- Teardown first: no assert may strand the scratch server.
				if l_server.is_running then
					l_server.kill.do_nothing
				end
				l_server.close
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				delete_file (client_scratch_toml)
				print (l_transcript)
				assert ("the server answered /health with the health shape", l_alive)
				assert ("the door agent opened a live session", l_logged_in)
				assert ("the room opened and the poller started", l_opened)
				assert ("no post ever held the GUI thread past the send budget", l_send_worst <= Slow_send_ms)
				assert ("no heartbeat held the GUI thread past the tick budget while the room was busy", l_busy_tick_worst <= Slow_tick_ms)
				assert ("no heartbeat held the GUI thread past the tick budget through a quiet long poll", l_quiet_tick_worst <= Slow_tick_ms)
				assert ("no allocation on the GUI's own processor waited out a poll", l_alloc_worst <= Slow_tick_ms)
				assert ("every line typed came back whole, exactly once, in the order it was typed", l_all_intact)
			end
		end

	freeze_line (a_index: INTEGER): STRING_32
			-- One of the rapid-fire lines: two digits, so no line's mark is a prefix of
			-- another's, and long enough that a truncation could not hide.
		require
			in_range: a_index >= 1 and a_index <= Freeze_posts
		do
			create Result.make (72)
			Result.append ({STRING_32} "freeze line ")
			if a_index < 10 then
				Result.append_character ('0')
			end
			Result.append_string_general (a_index.out)
			Result.append ({STRING_32} " of 20 - the quick brown fox jumps over the lazy dog")
		ensure
			marked: Result.has_substring ({STRING_32} "freeze line ")
		end

	Freeze_posts: INTEGER = 20
			-- Lines sent as fast as the composer could ever send them.

	Freeze_quiet_ticks: INTEGER = 140
			-- 250 ms apart: 35 s, longer than a whole 25 s long poll, with nobody speaking.

	Slow_tick_ms: INTEGER_64 = 250
			-- A heartbeat that takes longer than the heartbeat's own period has stopped the window.

	Slow_send_ms: INTEGER_64 = 1000
			-- One loopback POST; a second is already a stutter a member would see.

	freeze_now_ms: INTEGER_64
			-- Milliseconds off the machine's high-resolution counter: the clock the
			-- GUI thread is measured against, since a 250 ms budget is below the
			-- resolution of a wall clock in seconds.
		external
			"C inline use <windows.h>"
		alias
			"LARGE_INTEGER c, f; QueryPerformanceCounter(&c); QueryPerformanceFrequency(&f); return (EIF_INTEGER_64) ((c.QuadPart * 1000) / f.QuadPart);"
		end

feature {NONE} -- Non-ASCII fixtures (Phase 4 Task 9b)

	hebrew_file_name: STRING_32
			-- A file name in Hebrew letters, then ".png": nothing a header line
			-- could carry raw, so the live post proves the encoding both ways.
		do
			create Result.make_empty
			Result.append_code ({NATURAL_32} 0x05E9)
			Result.append_code ({NATURAL_32} 0x05DC)
			Result.append_code ({NATURAL_32} 0x05D5)
			Result.append_code ({NATURAL_32} 0x05DD)
			Result.append_string_general (".png")
		end

	hebrew_caption: STRING_32
			-- Hebrew, then U+1F916 - an astral code point, four UTF-8 bytes, and
			-- outside Latin-1 in both directions.
		do
			create Result.make_empty
			Result.append_code ({NATURAL_32} 0x05E9)
			Result.append_code ({NATURAL_32} 0x05DC)
			Result.append_code ({NATURAL_32} 0x05D5)
			Result.append_code ({NATURAL_32} 0x05DD)
			Result.append_string_general (" ")
			Result.append_code ({NATURAL_32} 0x1F916)
		end

	live_png_bytes (a_count: INTEGER): SPECIAL [NATURAL_8]
			-- `a_count' bytes opening with the eight-byte PNG signature, so
			-- CHAT_SERVICE.store_upload accepts them by signature.
		require
			room_for_signature: a_count >= 8
		do
			create Result.make_filled ({NATURAL_8} 0, a_count)
			Result [0] := 0x89
			Result [1] := 0x50
			Result [2] := 0x4E
			Result [3] := 0x47
			Result [4] := 0x0D
			Result [5] := 0x0A
			Result [6] := 0x1A
			Result [7] := 0x0A
		ensure
			sized: Result.count = a_count
		end

feature {NONE} -- Live-server fixtures

	prepare_scratch
			-- A clean C:\Users\Public\sc_wiring_test: the server exe copied to its
			-- distinct name, a minimal server.toml, and a fresh store seeded with
			-- the default room and the first admin (the same seam SERVER_APP's
			-- --create-admin uses: CHAT_SERVICE.create_first_admin).
		local
			l_directory: DIRECTORY
			l_db: RAW_FILE
			l_process: SIMPLE_PROCESS
			l_file: PLAIN_TEXT_FILE
			l_copied: RAW_FILE
			l_store: SQLITE_CHAT_STORE
			l_service: CHAT_SERVICE
			l_config: SERVER_CONFIG
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_logger: SIMPLE_LOGGER
			l_log: CHAT_LOG
			l_now: SIMPLE_DATE_TIME
			l_result: CHAT_RESULT [CHAT_USER]
		do
			create l_directory.make (Scratch_root + "\data")
			if not l_directory.exists then
				l_directory.recursive_create_dir
			end
			create l_db.make_with_name (Scratch_db_path)
			if l_db.exists then
				l_db.delete
			end
			delete_file (Scratch_root + "\server_boot.log")
			create l_process.make
			l_process.command_output ("cmd /c copy /Y %"" + Server_exe_path + "%" %"" + Scratch_root + "\" + Scratch_server_name + "%"").do_nothing
			create l_copied.make_with_name (Scratch_root + "\" + Scratch_server_name)
			check server_exe_copied: l_copied.exists end
			create l_file.make_create_read_write (Scratch_root + "\server.toml")
			l_file.put_string ("port = " + Port.out + "%Ndata_dir = %"" + Scratch_data_dir_toml + "%"%N")
			l_file.close
			create l_store.make (Scratch_db_path)
			l_store.open
			check store_open: l_store.is_open end
			create l_now.make_now
			if l_store.room_count = 0 then
				l_store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", l_now))
			end
			seeded_room_id := l_store.default_room_id
			create l_config.make_defaults
			create l_bus.make
			create l_limits.make (3600)
			create l_logger
			create l_log.make (l_logger)
			create l_service.make (l_store, l_bus, l_limits, l_config, l_log)
			l_result := l_service.create_first_admin (Admin_username, {STRING_32} "Wiring", Admin_password)
			check admin_created: l_result.is_success end
			l_store.close
		ensure
			room_seeded: seeded_room_id > 0
		end

	seeded_room_id: INTEGER_64
			-- The default room `prepare_scratch' seeded; the room the round trip uses.

	Scratch_root: STRING_8 = "C:\Users\Public\sc_wiring_test"

	Scratch_server_name: STRING_8 = "sc_wiring_server.exe"
			-- Every target of this system finalizes to simple_chat.exe, this test
			-- runner included: killing by that image name would kill the runner.

	Server_exe_path: STRING_8 = "EIFGENs\simple_chat_server\F_code\simple_chat.exe"
			-- Relative to the project root, where the assault runs.

	Scratch_db_path: STRING_32 = "C:\Users\Public\sc_wiring_test\data\simple_chat.db"
			-- <data_dir>/simple_chat.db, exactly where the server will open it.

	Scratch_data_dir_toml: STRING_8 = "C:/Users/Public/sc_wiring_test/data"
			-- Forward slashes: a TOML basic string treats backslash as an escape.

	Port: INTEGER = 18213

	Base_url: STRING_8 = "http://127.0.0.1:18213"

	Admin_username: STRING_8 = "wiring"

	Admin_password: STRING_32 = "open sesame 42"

	Round_trip_body: STRING_8 = "The first full client-stack round trip over real HTTP"

	Wiring_token: STRING_8 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
			-- 64 lowercase hex digits - the shape SESSION_ISSUER mints - and found
			-- nowhere else, so a file-text search for it is conclusive.

feature {NONE} -- Scratch files

	Scratch_directory: STRING_8 = "testing/config_scratch"

	scratch_path (a_tag: STRING_8): STRING_32
			-- testing/config_scratch/<tag>.toml, wiped of any leftover.
		local
			l_directory: DIRECTORY
		do
			create l_directory.make (Scratch_directory)
			if not l_directory.exists then
				l_directory.recursive_create_dir
			end
			create Result.make (Scratch_directory.count + a_tag.count + 6)
			Result.append_string_general (Scratch_directory)
			Result.append_string_general ("/")
			Result.append_string_general (a_tag)
			Result.append_string_general (".toml")
			delete_file (Result)
		ensure
			named: Result.ends_with ({STRING_32} ".toml")
		end

	write_scratch (a_tag: STRING_8; a_text: STRING_8): STRING_32
			-- Write `a_text' to a fresh scratch file; its path.
		local
			l_file: PLAIN_TEXT_FILE
		do
			Result := scratch_path (a_tag)
			create l_file.make_create_read_write (Result)
			l_file.put_string (a_text)
			l_file.close
		end

	delete_file (a_path: READABLE_STRING_GENERAL)
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.delete
			end
		end

	head_of_file (a_path: READABLE_STRING_GENERAL; a_maximum: INTEGER): STRING_8
			-- The first `a_maximum' bytes at `a_path'; a note when there is no file.
		require
			positive: a_maximum > 0
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists and then l_file.is_readable and then l_file.count > 0 then
				l_file.open_read
				l_file.read_stream (l_file.count.min (a_maximum))
				Result := l_file.last_string.twin
				l_file.close
			else
				Result := "(no server output was written)"
			end
		ensure
			bounded: Result.count <= a_maximum.max (40)
		end

end
