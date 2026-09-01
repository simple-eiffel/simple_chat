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
			-- token, post, events. Skips, and passes, when the exe is not built.
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
			l_posted: detachable CHAT_RESULT [CHAT_EVENT]
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
				print ("  (live round trip skipped: " + Server_exe_path + " is not built)%N")
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
			end
		end

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
