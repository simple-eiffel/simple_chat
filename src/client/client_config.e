note
	description: "[
		What the client remembers, in %APPDATA%\simple_chat\client.toml:
		the servers to try in order (the primary first, then any standby
		hosts - D-017), whether to look for a local service first and on
		which port, window placement. Never the password. The session
		token is never persisted in clear: `save_session' seals it to the
		current Windows user with DPAPI (simple_encryption, entropy
		`Session_entropy') and stores the ciphertext Base64-encoded under
		`Key_session'; no query yields the token in clear except
		`load_session', which unseals on demand and answers Void on any
		failure (intent-v3 Q17). CHAT_CLIENT never exposes its token, so
		the window hands it over at login time in a later UI pass.

		Loading mirrors SERVER_CONFIG's D6 posture: every read is
		validated, a hostile file changes nothing - the defaults stand -
		and never crashes; a valid field applies alone (the window
		placement applies only as a whole - a bad width or height keeps
		the whole placement). Every server URL passed CHAT_URL_RULES on
		the way in (https, or loopback http for tests; nothing that
		merely starts like either), and no two entries name the same
		server - `has_url' compares scheme and host without regard to
		case.
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
			storage_path := default_storage_path
		ensure
			no_server: not has_server
			looks_local_first: prefers_local
			no_session: not has_session
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

	storage_path: STRING_32
			-- Where `load' reads and `save' writes; %APPDATA%\simple_chat\client.toml
			-- unless a test pointed it elsewhere with `set_storage_path'.

	session_blob: detachable STRING_8
			-- The remembered session as it is stored: DPAPI ciphertext, Base64-encoded.
			-- Safe to expose - only the same Windows user on the same machine, with
			-- `Session_entropy', can unseal it - and never the token in clear.

feature -- Status report

	prefers_local: BOOLEAN
			-- Try the local service before the servers?

	has_server: BOOLEAN
		do
			Result := not server_urls.is_empty
		end

	has_session: BOOLEAN
			-- Is a sealed session remembered?
		do
			Result := session_blob /= Void
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

	set_storage_path (a_path: READABLE_STRING_GENERAL)
			-- Read and write at `a_path' from now on (tests point this at a scratch file).
		require
			path_given: not a_path.is_empty
		do
			storage_path := a_path.to_string_32
		ensure
			set: storage_path.same_string_general (a_path)
			servers_kept: servers_model |=| old servers_model
		end

	load
			-- From the file at `storage_path', when present: every value validated on
			-- the way in (D6, as SERVER_CONFIG loads); a hostile file - unparsable, or
			-- carrying wrong types, out-of-range numbers, unacceptable or duplicate
			-- URLs, or a session that is not Base64 - changes nothing and never
			-- crashes. A missing or empty file is simply the defaults.
		local
			l_toml: SIMPLE_TOML
			l_file: PLAIN_TEXT_FILE
		do
			create l_file.make_with_name (storage_path)
			if l_file.exists and then l_file.is_readable and then l_file.count > 0 then
					-- (SIMPLE_TOML.parse_text refuses empty text by precondition, so it is answered here.)
				create l_toml
				if attached l_toml.load_file (storage_path) as l_root then
					load_servers (l_root)
					load_preferences (l_root)
					load_window (l_root)
					load_session_blob (l_root)
				end
			end
		ensure
			path_kept: storage_path = old storage_path
		end

	save
			-- To the file at `storage_path' (its directory is created when missing):
			-- the servers, the preferences, the window placement, and - only when
			-- `has_session' - the sealed session. Nothing here ever writes a token
			-- in clear: `session_blob' is DPAPI ciphertext in Base64 from the moment
			-- `save_session' seals it.
		local
			l_toml: SIMPLE_TOML
			l_root: TOML_TABLE
			l_urls: TOML_ARRAY
		do
			ensure_storage_directory
			create l_root.make
			create l_urls.make
			across server_urls as ic loop
				l_urls.extend (create {TOML_STRING}.make (ic.to_string_32))
			end
			l_root.put (l_urls, Key_server_urls)
			l_root.put (create {TOML_BOOLEAN}.make (prefers_local), Key_prefers_local)
			l_root.put (create {TOML_INTEGER}.make (local_port), Key_local_port)
			l_root.put (create {TOML_INTEGER}.make (window_x), Key_window_x)
			l_root.put (create {TOML_INTEGER}.make (window_y), Key_window_y)
			l_root.put (create {TOML_INTEGER}.make (window_width), Key_window_width)
			l_root.put (create {TOML_INTEGER}.make (window_height), Key_window_height)
			if attached session_blob as l_blob then
				l_root.put (create {TOML_STRING}.make (l_blob.to_string_32), Key_session)
			end
			create l_toml
			l_toml.save_file (l_root, storage_path)
		ensure
			written: file_exists (storage_path)
			path_kept: storage_path = old storage_path
			servers_kept: servers_model |=| old servers_model
		end

feature -- Session

	save_session (a_token: READABLE_STRING_8)
			-- Remember the session: `a_token' sealed to the current Windows user
			-- (DPAPI, entropy `Session_entropy'), Base64-encoded, and written to
			-- `storage_path' under `Key_session'. On a platform without DPAPI, or
			-- on any sealing failure, nothing is remembered at all - a session is
			-- never written in clear, and the postconditions prove it against the
			-- file's actual text.
		require
			token_given: not a_token.is_empty
		local
			l_crypto: SIMPLE_ENCRYPTION
			l_encoder: SIMPLE_BASE64
		do
			create l_crypto.make
			if attached l_crypto.dpapi_protect (a_token, Session_entropy) as l_sealed then
				create l_encoder.make
				session_blob := l_encoder.encode (l_sealed)
			else
				session_blob := Void
			end
			save
		ensure
			blob_never_the_token: attached session_blob as l_b implies not l_b.has_substring (a_token)
			file_never_carries_the_token: not stored_file_text.has_substring (a_token)
			written: file_exists (storage_path)
			nothing_without_dpapi: not (create {SIMPLE_ENCRYPTION}.make).is_dpapi_available implies not has_session
			servers_kept: servers_model |=| old servers_model
		end

	load_session: detachable STRING_8
			-- The remembered session token, unsealed on demand (same Windows user,
			-- same machine, same entropy); Void when none is remembered or the blob
			-- does not unseal (tampered, foreign user, DPAPI absent) - never an
			-- exception, never a partial value.
		local
			l_crypto: SIMPLE_ENCRYPTION
			l_encoder: SIMPLE_BASE64
			l_sealed: STRING_8
		do
			if attached session_blob as l_blob then
				create l_encoder.make
				if l_encoder.is_valid_base64 (l_blob) then
					l_sealed := l_encoder.decode (l_blob)
					if not l_sealed.is_empty then
						create l_crypto.make
						Result := l_crypto.dpapi_unprotect (l_sealed, Session_entropy)
					end
				end
			end
		ensure
			nothing_without_a_blob: not has_session implies Result = Void
			never_empty: attached Result as l_r implies not l_r.is_empty
		end

	forget_session
			-- Forget the remembered session and rewrite the file without it.
		do
			session_blob := Void
			save
		ensure
			gone: not has_session
			written: file_exists (storage_path)
			servers_kept: servers_model |=| old servers_model
		end

feature -- Validation (contract support)

	file_exists (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Is there a file at `a_path'?
		require
			path_given: not a_path.is_empty
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists
		end

	stored_file_text: STRING_8
			-- The raw text at `storage_path'; empty when the file is missing or unreadable.
		local
			l_file: RAW_FILE
		do
			create Result.make_empty
			create l_file.make_with_name (storage_path)
			if l_file.exists and then l_file.is_readable and then l_file.count > 0 then
				l_file.open_read
				l_file.read_stream (l_file.count)
				Result := l_file.last_string.twin
				l_file.close
			end
		end

feature -- Constants

	Key_server_urls: STRING_32 = "server_urls"
	Key_prefers_local: STRING_32 = "prefers_local"
	Key_local_port: STRING_32 = "local_port"
	Key_window_x: STRING_32 = "window_x"
	Key_window_y: STRING_32 = "window_y"
	Key_window_width: STRING_32 = "window_width"
	Key_window_height: STRING_32 = "window_height"
	Key_session: STRING_32 = "session"

	Session_entropy: STRING_8 = "simple_chat"
			-- What binds the DPAPI blob to this application; `dpapi_unprotect'
			-- must be shown the same bytes.

feature {NONE} -- File loading (simple_toml; D6: every read is validated, no setter precondition is reachable)

	load_servers (a_root: TOML_TABLE)
			-- The `Key_server_urls' array: each entry that is a string, passes
			-- CHAT_URL_RULES and is fresh joins the list; anything else is skipped.
		local
			i: INTEGER
			l_url: STRING_8
		do
			if attached a_root.item (Key_server_urls) as l_value and then l_value.is_array then
				from
					i := 1
				until
					i > l_value.as_array.count
				loop
					if l_value.as_array.item (i).is_string and then l_value.as_array.item (i).as_string.is_valid_as_string_8 then
						l_url := l_value.as_array.item (i).as_string.to_string_8
						if is_acceptable_url (l_url) and then not has_url (l_url) then
							add_server_url (l_url)
						end
					end
					i := i + 1
				variant
					l_value.as_array.count - i + 1
				end
			end
		end

	load_preferences (a_root: TOML_TABLE)
			-- `Key_prefers_local' (a boolean) and `Key_local_port' (1..65535).
		do
			if attached a_root.item (Key_prefers_local) as l_flag and then l_flag.is_boolean then
				set_prefers_local (l_flag.as_boolean)
			end
			if attached a_root.item (Key_local_port) as l_port and then l_port.is_integer
				and then l_port.as_integer >= 1 and then l_port.as_integer <= 65535
			then
				set_local_port (l_port.as_integer.to_integer_32)
			end
		end

	load_window (a_root: TOML_TABLE)
			-- The placement, applied only as a whole: a missing coordinate keeps its
			-- current value; a width or height that is absent, hostile or not positive
			-- keeps the whole placement.
		local
			l_x, l_y, l_width, l_height: INTEGER
		do
			l_x := loaded_coordinate (a_root, Key_window_x, window_x)
			l_y := loaded_coordinate (a_root, Key_window_y, window_y)
			l_width := loaded_coordinate (a_root, Key_window_width, window_width)
			l_height := loaded_coordinate (a_root, Key_window_height, window_height)
			if l_width > 0 and l_height > 0 then
				set_window (l_x, l_y, l_width, l_height)
			end
		end

	loaded_coordinate (a_root: TOML_TABLE; a_key: STRING_32; a_current: INTEGER): INTEGER
			-- The integer under `a_key' when it is one and fits INTEGER_32; else `a_current'.
		do
			Result := a_current
			if attached a_root.item (a_key) as l_value and then l_value.is_integer
				and then l_value.as_integer >= {INTEGER_32}.Min_value.to_integer_64
				and then l_value.as_integer <= {INTEGER_32}.Max_value.to_integer_64
			then
				Result := l_value.as_integer.to_integer_32
			end
		end

	load_session_blob (a_root: TOML_TABLE)
			-- The `Key_session' string, kept only when it is non-empty Base64 text
			-- (what `save_session' writes); it is not unsealed here - `load_session'
			-- does that on demand.
		local
			l_encoder: SIMPLE_BASE64
			l_text: STRING_8
		do
			if attached a_root.item (Key_session) as l_value and then l_value.is_string
				and then l_value.as_string.is_valid_as_string_8
			then
				l_text := l_value.as_string.to_string_8
				create l_encoder.make
				if not l_text.is_empty and then l_encoder.is_valid_base64 (l_text) then
					session_blob := l_text
				end
			end
		end

	ensure_storage_directory
			-- Create `storage_path's directory when it is missing.
		local
			l_last_separator, i: INTEGER
			l_directory: DIRECTORY
		do
			from
				i := storage_path.count
			until
				i < 1 or l_last_separator > 0
			loop
				if storage_path [i] = '\' or storage_path [i] = '/' then
					l_last_separator := i
				end
				i := i - 1
			end
			if l_last_separator > 1 then
				create l_directory.make (storage_path.substring (1, l_last_separator - 1))
				if not l_directory.exists then
					l_directory.recursive_create_dir
				end
			end
		end

	default_storage_path: STRING_32
			-- %APPDATA%\simple_chat\client.toml; the working directory's client.toml
			-- when APPDATA is not in the environment.
		local
			l_environment: EXECUTION_ENVIRONMENT
		do
			create l_environment
			if attached l_environment.item ("APPDATA") as l_appdata and then not l_appdata.is_empty then
				create Result.make_from_string_general (l_appdata)
				Result.append_string_general ("\simple_chat\client.toml")
			else
				create Result.make_from_string_general ("client.toml")
			end
		ensure
			named: not Result.is_empty
		end

invariant
	sized: window_width > 0 and window_height > 0
	port_in_range: local_port >= 1 and local_port <= 65535
	servers_acceptable: across server_urls as ic all is_acceptable_url (ic) end
	servers_distinct: not has_duplicate_url
	model_consistent: servers_model.count = server_urls.count
	storage_named: not storage_path.is_empty
	blob_never_empty: attached session_blob as l_b implies not l_b.is_empty

end
