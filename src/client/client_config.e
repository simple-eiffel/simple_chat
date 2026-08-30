note
	description: "[
		What the client remembers, in %APPDATA%\simple_chat\client.toml:
		the servers to try in order (the primary first, then any standby
		hosts - D-017), whether to look for a local service first and on
		which port, window placement. Never the password; the session
		token only under DPAPI (intent-v3 Q17), never in clear.
	]"
	author: "Larry Rix"

class
	CLIENT_CONFIG

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
		end

	local_port: INTEGER
			-- Where a local service would listen.

	window_x, window_y, window_width, window_height: INTEGER

	local_url: STRING_8
			-- The local service's base URL.
		do
			Result := "http://127.0.0.1:" + local_port.out
		ensure
			loopback: Result.starts_with ("http://127.0.0.1:")
		end

feature -- Status report

	prefers_local: BOOLEAN
			-- Try the local service before the servers?

	has_server: BOOLEAN
		do
			Result := not server_urls.is_empty
		end

	has_url (a_url: READABLE_STRING_8): BOOLEAN
		do
			Result := across server_urls as ic some ic.same_string (a_url) end
		end

	is_acceptable_url (a_url: READABLE_STRING_8): BOOLEAN
			-- https, or loopback http; no trailing slash.
		do
			Result := (a_url.starts_with ("https://") or a_url.starts_with ("http://127.0.0.1") or a_url.starts_with ("http://localhost"))
				and not a_url.ends_with ("/")
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
		end

	set_server_url (a_url: READABLE_STRING_8)
			-- Make `a_url' the only server (the primary).
		require
			acceptable: is_acceptable_url (a_url)
		do
			server_urls.wipe_out
			server_urls.extend (a_url.to_string_8)
		ensure
			only_one: servers_model.count = 1 and server_url.same_string (a_url)
		end

	set_prefers_local (a_value: BOOLEAN)
		do
			prefers_local := a_value
		ensure
			set: prefers_local = a_value
		end

	set_local_port (a_port: INTEGER)
		require
			in_range: a_port >= 1 and a_port <= 65535
		do
			local_port := a_port
		ensure
			set: local_port = a_port
		end

	set_window (a_x, a_y, a_width, a_height: INTEGER)
		require
			sized: a_width > 0 and a_height > 0
		do
			window_x := a_x
			window_y := a_y
			window_width := a_width
			window_height := a_height
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
	model_consistent: servers_model.count = server_urls.count

end
