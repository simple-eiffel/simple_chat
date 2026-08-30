note
	description: "[
		What the client remembers, in %APPDATA%\simple_chat\client.toml:
		the servers to try in order (the primary first, then any standby
		hosts - D-017), whether to look for a local service first and on
		which port, window placement. Never the password. The session
		token is never persisted in clear: if a remembered session ever
		exists it will be DPAPI ciphertext produced inside CHAT_CLIENT
		(Phase 4, dependency task DPAPI in simple_encryption), and no
		query yields the token in clear (intent-v3 Q17).

		Every server URL passed CHAT_URL_RULES on the way in (https, or
		loopback http for tests; nothing that merely starts like either),
		and no two entries name the same server - `has_url' compares
		scheme and host without regard to case.
	]"
	author: "Larry Rix"

class
	CLIENT_CONFIG

inherit
	CHAT_URL_RULES

create
	make_defaults

feature {NONE} -- Initialization

	make_defaults
		do
			create server_urls.make (2)
			server_urls.compare_objects
			prefers_local := True
			local_port := 8080
			window_x := 100
			window_y := 100
			window_width := 900
			window_height := 700
		ensure
			no_server: not has_server
			looks_local_first: prefers_local
		end

feature -- Model Queries (for MML postconditions)

	servers_model: MML_SEQUENCE [STRING_8]
			-- The servers, in the order they are tried.
		do
			create Result
			across server_urls as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = server_urls.count
		end

feature -- Access

	server_urls: ARRAYED_LIST [STRING_8]
			-- Primary first, then standbys; https, or loopback http for tests.

	server_url: STRING_8
			-- The primary; empty when none is configured.
		do
			if server_urls.is_empty then
				create Result.make_empty
			else
				Result := server_urls.first
			end
		ensure
			empty_iff_none: Result.is_empty = not has_server
			the_first: has_server implies Result = server_urls.first
		end

	local_port: INTEGER
			-- Where a local service would listen.

	window_x, window_y, window_width, window_height: INTEGER

	local_url: STRING_8
			-- The local service's base URL.
		do
			Result := "http://127.0.0.1:" + local_port.out
		ensure
			loopback: is_loopback_url (Result)
			acceptable: is_acceptable_url (Result)
		end

feature -- Status report

	prefers_local: BOOLEAN
			-- Try the local service before the servers?

	has_server: BOOLEAN
		do
			Result := not server_urls.is_empty
		end

	has_url (a_url: READABLE_STRING_8): BOOLEAN
			-- Is `a_url' listed (scheme and host compared without regard to case)?
		do
			Result := across server_urls as ic some same_url (ic, a_url) end
		end

	has_duplicate_url: BOOLEAN
			-- Do two entries name the same server?
		local
			i, j: INTEGER
		do
			from i := 1 until i > server_urls.count or Result loop
				from j := i + 1 until j > server_urls.count or Result loop
					Result := same_url (server_urls [i], server_urls [j])
					j := j + 1
				end
				i := i + 1
			end
		end

feature -- Element change

	add_server_url (a_url: READABLE_STRING_8)
			-- Another server to try, after those already listed.
		require
			acceptable: is_acceptable_url (a_url)
			fresh: not has_url (a_url)
		do
			server_urls.extend (a_url.to_string_8)
		ensure
			appended: servers_model |=| ((old servers_model) & a_url.to_string_8)
			listed: has_url (a_url)
			preference_kept: prefers_local = old prefers_local
			port_kept: local_port = old local_port
			window_kept: window_x = old window_x and window_y = old window_y and window_width = old window_width and window_height = old window_height
		end

	set_only_server_url (a_url: READABLE_STRING_8)
			-- Make `a_url' the only server (the primary); any standbys are forgotten.
		require
			acceptable: is_acceptable_url (a_url)
		do
			server_urls.wipe_out
			server_urls.extend (a_url.to_string_8)
		ensure
			only_one: servers_model.count = 1 and server_url.same_string (a_url)
			preference_kept: prefers_local = old prefers_local
			port_kept: local_port = old local_port
			window_kept: window_x = old window_x and window_y = old window_y and window_width = old window_width and window_height = old window_height
		end

	set_primary_url (a_url: READABLE_STRING_8)
			-- Make `a_url' the primary; the standbys stay, in their order (an entry already
			-- naming the same server moves to the front rather than appearing twice).
		require
			acceptable: is_acceptable_url (a_url)
		local
			l_kept: ARRAYED_LIST [STRING_8]
		do
			create l_kept.make (server_urls.count + 1)
			l_kept.compare_objects
			l_kept.extend (a_url.to_string_8)
			across server_urls as ic loop
				if not same_url (ic, a_url) then
					l_kept.extend (ic)
				end
			end
			server_urls := l_kept
		ensure
			primary: server_url.same_string (a_url)
			listed: has_url (a_url)
			one_more_when_new: (not old has_url (a_url)) implies servers_model.count = (old servers_model).count + 1
			same_count_when_known: (old has_url (a_url)) implies servers_model.count = (old servers_model).count
			standbys_kept: across old (server_urls.twin) as u all has_url (u) end
			preference_kept: prefers_local = old prefers_local
			port_kept: local_port = old local_port
			window_kept: window_x = old window_x and window_y = old window_y and window_width = old window_width and window_height = old window_height
		end

	set_prefers_local (a_value: BOOLEAN)
		do
			prefers_local := a_value
		ensure
			set: prefers_local = a_value
			servers_kept: servers_model |=| old servers_model
		end

	set_local_port (a_port: INTEGER)
		require
			in_range: a_port >= 1 and a_port <= 65535
		do
			local_port := a_port
		ensure
			set: local_port = a_port
			servers_kept: servers_model |=| old servers_model
		end

	set_window (a_x, a_y, a_width, a_height: INTEGER)
		require
			sized: a_width > 0 and a_height > 0
		do
			window_x := a_x
			window_y := a_y
			window_width := a_width
			window_height := a_height
		ensure
			set: window_x = a_x and window_y = a_y and window_width = a_width and window_height = a_height
			servers_kept: servers_model |=| old servers_model
			preference_kept: prefers_local = old prefers_local
			port_kept: local_port = old local_port
		end

	load
			-- From the config file, when present.
		do
			-- Implementation in Phase 4 (simple_toml)
		end

	save
		do
			-- Implementation in Phase 4
		end

invariant
	sized: window_width > 0 and window_height > 0
	port_in_range: local_port >= 1 and local_port <= 65535
	servers_acceptable: across server_urls as ic all is_acceptable_url (ic) end
	servers_distinct: not has_duplicate_url
	model_consistent: servers_model.count = server_urls.count

end
