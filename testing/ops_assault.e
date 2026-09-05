note
	description: "[
		The doors, DNS and configuration under assault (Phase 1b + Phase 4
		Task 6): the Caddyfile is one loopback site with the admin API off;
		the caddy door supervises a real child - start proves it alive,
		stop proves it dead (Issue 27), check_health reports a child killed
		behind the door's back; a stopped door stays stopped; hostnames and
		DDNS domains are validated where they enter; the DuckDNS update
		fails closed against an unroutable address and the token never
		appears in the update URL or any result; the configuration's lists
		are copies. Supervision runs against ping.exe as a stand-in child:
		caddy.exe is not required on a development machine, and the suite
		never touches the real network.
	]"
	author: "Larry Rix"

class
	OPS_ASSAULT

inherit
	TEST_SET_BASE

	CHAT_TEST_BRIDGE
			-- Grants access to the ops test hooks: `set_arguments_text',
			-- `child_process_id', `set_service_base'.
		undefine
			default_create
		end

feature -- Tests

	test_caddyfile_is_one_loopback_site_with_admin_off
			-- And, since 0.3.1, with Caddy's log sent to a file beside the
			-- Caddyfile: the supervisor never drains the child's stderr pipe,
			-- and a Caddy that fills it stops mid-certificate (class note).
		local
			c: SERVER_CONFIG
			d: CADDY_FRONT_DOOR
			l_text: STRING_8
		do
			create c.make_defaults
			c.set_front_door ({SERVER_CONFIG}.Door_caddy, "rixchat.duckdns.org")
			create d.make (c)
			l_text := d.caddyfile_text
			assert ("admin off first", l_text.starts_with ("{%N    admin off%N    log {"))
			assert ("the log goes to a file, quoted, forward slashes, beside the Caddyfile",
				l_text.has_substring ("output file %"") and l_text.has_substring ("/caddy.log%" {")
				and not l_text.has ('\') and d.caddy_log_path.ends_with ({STRING_32} "caddy.log"))
			assert ("rolled, so a year of Caddy does not fill the disk", l_text.has_substring ("roll_size 2MiB") and l_text.has_substring ("roll_keep 3"))
			assert ("site named", l_text.has_substring ("rixchat.duckdns.org {"))
			assert ("loopback upstream", l_text.has_substring ("reverse_proxy 127.0.0.1:8080"))
			assert ("exactly one site, braces balanced", l_text.substring_index ("rixchat.duckdns.org {", 1) > 0
				and then l_text.substring_index ("rixchat.duckdns.org {", l_text.substring_index ("rixchat.duckdns.org {", 1) + 1) = 0
				and l_text.occurrences ('{') = l_text.occurrences ('}') and l_text.occurrences ('{') = 5)
			assert ("absolute executable", d.executable.has (':') or d.executable.starts_with ("/"))
			assert ("no child before start", not d.has_child_process and not d.is_serving)
			d.stop
			assert ("stop without a child is harmless", not d.has_child_process)
		end

	test_hostnames_are_validated
		local
			c: SERVER_CONFIG
		do
			create c.make_defaults
			assert ("plain host", c.is_hostname ("rixchat.duckdns.org"))
			assert ("caddyfile injection refused", not c.is_hostname ("x {%N  reverse_proxy evil:1"))
			assert ("space refused", not c.is_hostname ("rix chat.org"))
			assert ("leading dash refused", not c.is_hostname ("-rix.org"))
			assert ("uppercase refused", not c.is_hostname ("RixChat.org"))
			assert ("door needs a hostname", not sets_door (c, "x {evil}"))
		end

	test_null_door_stays_stopped
		local
			c: SERVER_CONFIG
			d: NO_FRONT_DOOR
		do
			create c.make_defaults
			create d.make (c)
			d.start
			assert ("serving after start", d.is_serving and d.last_error = Void)
			d.stop
			d.check_health
			assert ("check_health does not resurrect a stopped door", not d.is_serving and d.last_error /= Void)
		end

	test_duckdns_url_masks_the_token
		local
			u: DUCKDNS_UPDATER
			c: SERVER_CONFIG
		do
			create u.make ("rixchat", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", 300)
			assert ("exact masked url", u.update_url.same_string ("https://www.duckdns.org/update?domains=rixchat&token=****"))
			assert ("domains validated", u.is_valid_domains ("rixchat,sue-chat") and not u.is_valid_domains ("rixchat&clear=true") and not u.is_valid_domains (""))
			create c.make_defaults
			assert ("config refuses a smuggled parameter", not sets_ddns (c, "rixchat&clear=true"))
			assert ("config refuses a short interval", not sets_ddns_interval (c, 5))
			u.set_service_base (Unroutable_base)
				-- The suite never touches the real service (Task 6).
			u.update
			assert ("update reports", u.update_count = 1 and not u.last_result.same_string ({DYNAMIC_DNS}.Result_never))
		end

	test_caddy_door_supervises_a_stand_in_child
			-- Task 6: start launches a real hidden child, and serving means
			-- alive; stop kills it and proves it is gone (Issue 27). The
			-- stand-in is ping -n 60 (alive for about a minute, so a failed
			-- test cannot strand it forever); caddy.exe is not on this machine.
		local
			c: SERVER_CONFIG
			d: CADDY_FRONT_DOOR
		do
			create c.make_defaults
			c.set_front_door ({SERVER_CONFIG}.Door_caddy, "rixchat.duckdns.org")
			create d.make (c)
			d.set_executable ("C:\Windows\System32\ping.exe")
			d.set_arguments_text ("-n 60 127.0.0.1")
			d.start
			assert ("serving after start", d.is_serving and d.last_error = Void)
			assert ("child alive", d.has_child_process and d.child_process_id > 0)
			assert ("caddyfile written", d.caddyfile_exists)
			d.check_health
			assert ("health keeps a live child", d.is_serving and d.has_child_process)
			d.stop
			assert ("no orphan: the child is really gone", not d.has_child_process)
			assert ("stopped", not d.is_serving)
			d.stop
			assert ("stop is idempotent", not d.has_child_process and not d.is_serving)
		end

	test_caddy_door_refuses_a_missing_executable
			-- A missing caddy.exe is an error result, never an exception.
		local
			c: SERVER_CONFIG
			d: CADDY_FRONT_DOOR
		do
			create c.make_defaults
			c.set_front_door ({SERVER_CONFIG}.Door_caddy, "rixchat.duckdns.org")
			create d.make (c)
			d.set_executable ("C:\Windows\System32\no_such_caddy_here.exe")
			d.start
			assert ("an error, not an exception", not d.is_serving and d.last_error /= Void)
			assert ("no child", not d.has_child_process)
			d.check_health
			assert ("still stopped and still explained", not d.is_serving and d.last_error /= Void)
		end

	test_caddy_door_reports_a_child_killed_behind_its_back
			-- taskkill the child from outside; check_health must report the
			-- exit code and drop `is_serving' honestly - and never restart
			-- a door that then stays stopped.
		local
			c: SERVER_CONFIG
			d: CADDY_FRONT_DOOR
			l_killer: SIMPLE_ASYNC_PROCESS
			l_pid: NATURAL_32
		do
			create c.make_defaults
			c.set_front_door ({SERVER_CONFIG}.Door_caddy, "rixchat.duckdns.org")
			create d.make (c)
			d.set_executable ("C:\Windows\System32\ping.exe")
			d.set_arguments_text ("-n 60 127.0.0.1")
			d.start
			assert ("serving", d.is_serving)
			l_pid := d.child_process_id
			assert ("pid known", l_pid > 0)
			create l_killer.make
			l_killer.set_show_window (False)
			l_killer.start ("C:\Windows\System32\taskkill.exe /PID " + l_pid.out + " /F")
			assert ("killer started", l_killer.was_started_successfully)
			assert ("killer finished", l_killer.wait (5000) = 1)
			l_killer.close
			assert ("the child is gone behind the door's back", child_leaves (d))
			assert ("the door has not noticed yet", d.is_serving)
			d.check_health
			assert ("health reports the death with its exit code", not d.is_serving and attached d.last_error as l_error and then l_error.message.has_substring ("exit code"))
			assert ("no child after health", not d.has_child_process)
			d.check_health
			assert ("a dead door stays dead", not d.is_serving and d.last_error /= Void)
			d.stop
			assert ("stop after the death is harmless", not d.has_child_process)
		end

	test_duckdns_update_fails_closed_and_never_leaks_the_token
			-- Against an unroutable address the update is a failed result,
			-- not an exception, and nothing reachable carries the token.
			-- The real service is never touched by tests.
		local
			u: DUCKDNS_UPDATER
		do
			create u.make ("rixchat", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", 300)
			u.set_service_base (Unroutable_base)
			u.update
			assert ("one attempt", u.update_count = 1)
			assert ("timed", u.last_update_at /= Void)
			assert ("unreachable, not raised", u.last_result.same_string ({DYNAMIC_DNS}.Result_unreachable))
			assert ("the result carries no token", not u.last_result.has_substring ("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
			assert ("the inspectable url is still the masked one", u.update_url.same_string ("https://www.duckdns.org/update?domains=rixchat&token=****"))
			u.update
			assert ("attempts accumulate", u.update_count = 2 and u.last_update_at /= Void)
		end

	test_config_lists_are_copies
		local
			c: SERVER_CONFIG
			l_list: ARRAYED_LIST [PARTICIPANT_CONFIG]
		do
			create c.make_defaults
			l_list := c.participants
			l_list.extend (create {PARTICIPANT_CONFIG}.make ("@x", {PARTICIPANT_CONFIG}.Kind_none, "xbot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " X", ""))
			assert ("mutating the copy changes nothing", c.participant_count = 0 and not c.ai_enabled)
			assert ("no file, so not loaded", not c.is_loaded and c.is_valid)
		end

feature {NONE} -- Fixtures

	sets_door (a_config: SERVER_CONFIG; a_name: STRING_8): BOOLEAN
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				a_config.set_front_door ({SERVER_CONFIG}.Door_caddy, a_name)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

	sets_ddns (a_config: SERVER_CONFIG; a_domains: STRING_8): BOOLEAN
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				a_config.set_ddns (a_domains, "token", 300)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

	sets_ddns_interval (a_config: SERVER_CONFIG; a_seconds: INTEGER): BOOLEAN
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				a_config.set_ddns ("rixchat", "token", a_seconds)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

	child_leaves (a_door: CADDY_FRONT_DOOR): BOOLEAN
			-- Does `a_door''s child disappear within a bounded wait?
		local
			l_env: EXECUTION_ENVIRONMENT
			l_tries: INTEGER
		do
			create l_env
			from
				l_tries := 0
			until
				not a_door.has_child_process or l_tries >= 20
			loop
				l_env.sleep (100_000_000)
				l_tries := l_tries + 1
			end
			Result := not a_door.has_child_process
		end

	Unroutable_base: STRING_8 = "http://127.0.0.1:9/update?domains="
			-- Loopback discard port: nothing listens, the connection is
			-- refused at once, and no packet leaves this machine.

end
