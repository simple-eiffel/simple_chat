note
	description: "[
		The doors, DNS and configuration under assault (Phase 1b): the
		Caddyfile is one loopback site with the admin API off; a stopped
		door stays stopped; hostnames and DDNS domains are validated where
		they enter; the token never appears in the update URL; the
		configuration's lists are copies.
	]"
	author: "Larry Rix"

class
	OPS_ASSAULT

inherit
	TEST_SET_BASE

feature -- Tests

	test_caddyfile_is_one_loopback_site_with_admin_off
		local
			c: SERVER_CONFIG
			d: CADDY_FRONT_DOOR
			l_text: STRING_8
		do
			create c.make_defaults
			c.set_front_door ({SERVER_CONFIG}.Door_caddy, "rixchat.duckdns.org")
			create d.make (c)
			l_text := d.caddyfile_text
			assert ("admin off first", l_text.starts_with ("{%N    admin off%N}%N"))
			assert ("site named", l_text.has_substring ("rixchat.duckdns.org {"))
			assert ("loopback upstream", l_text.has_substring ("reverse_proxy 127.0.0.1:8080"))
			assert ("exactly one site", l_text.occurrences ('{') = 3)
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
			u.update
			assert ("update reports", u.update_count = 1 and not u.last_result.same_string ({DYNAMIC_DNS}.Result_never))
		end

	test_config_lists_are_copies
		local
			c: SERVER_CONFIG
			l_list: ARRAYED_LIST [PARTICIPANT_CONFIG]
		do
			create c.make_defaults
			l_list := c.participants
			l_list.extend (create {PARTICIPANT_CONFIG}.make ("@x", {PARTICIPANT_CONFIG}.Kind_none, "xbot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " X"))
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

end
