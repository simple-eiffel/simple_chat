note
	description: "[
		The one server configuration file (TOML), parsed and validated
		here and nowhere else. Invariants pin what the rest of the system
		relies on: localhost binding, a known door, a hostname when a door
		is public, positive limits, validated DDNS domains and a token when
		DDNS is on, unique participant handles, bot usernames and aliases
		(case-insensitively; an alias is never a handle, in either
		direction - M-D7). The lists are copies on the way out, so no
		caller can edit them past the `fresh_*' preconditions.

		A file that fails validation leaves `is_valid' False and names each
		field in `validation_errors'; the field values are then the
		defaults, never the file's - a server refuses to start on it.

		The file format (keys mirror the attribute names; `front_door'
		carries `front_door_kind' - the value IS the kind):

			port = 8080                          # 1..65535
			data_dir = "data"                    # never empty; the SQLite store lives at <data_dir>/simple_chat.db
			front_door = "none"                  # "caddy" | "eiffel" | "none"
			public_name = "chat.example.org"     # required (a hostname) when front_door is not "none"
			message_characters = 4000            # positive
			upload_bytes = 8388608               # positive
			ai_requests_per_hour = 5             # zero or more
			posts_per_minute = 30                # positive
			login_failures_per_10_minutes = 10   # positive
			session_days = 90                    # positive
			password_minimum = 8                 # at least {PASSWORD_HASHER}.Minimum_characters

			[ddns]                               # optional; a broken block never enables DDNS
			enabled = false
			provider = "duckdns"                 # the only provider
			domains = "example"                  # labels of a-z, 0-9, "-" joined by commas; required when enabled
			token = "..."                        # required when enabled
			interval_seconds = 300               # at least {DYNAMIC_DNS}.Minimum_interval_seconds

			[[participants]]                     # zero or more entries
			handle = "@claude"                   # required: "@" then 1..32 of a-z, 0-9, "_", "-"
			kind = "claude_code"                 # required: claude_code | ollama | bible_tool | shape_tool | none
			engine = "D:/sandbox"                # required unless kind is "none": the one setting the kind needs
			bot_username = "claude_bot"          # required: 1..32 of a-z, 0-9, "_"
			display_name = "Claude"              # required: without the marker; marker must still fit
			requests_per_hour = 5                # optional, positive
			max_characters = 1200                # optional, positive
			timeout_seconds = 120                # optional, positive
			query_shaper = "none"                # optional: "none", "plain" or an "@name"
			response_shaper = "none"             # optional: same shapes
			aliases = ["Claude:", "@cl"]         # optional; kept lowercase, unique across the whole file
			allow_via = ["plain", "@qwen"]       # optional via choices

		`bind_address' is deliberately NOT a key: the invariant pins
		127.0.0.1, and a file that tries gets a validation error. A broken
		participant identity (handle, kind, engine, bot_username,
		display_name, or a collision) skips that whole entry; a broken
		refinement (a limit, shaper, alias or via choice) is refused alone
		and that field's default stands. Either way the error names the
		field and `is_valid' is False (D6: file problems are validation
		outcomes, never crashes).
	]"
	author: "Larry Rix"

class
	SERVER_CONFIG

create
	make_defaults,
	make_from_file

feature {NONE} -- Initialization

	make_defaults
			-- A valid configuration for a local test: no door, no DDNS, no participants.
		do
			port := 8080
			bind_address := "127.0.0.1"
			data_dir := "data"
			create public_name.make_empty
			front_door_kind := Door_none.twin
			message_characters := 4000
			upload_bytes := 8388608
			ai_requests_per_hour := 5
			posts_per_minute := 30
			login_failures_per_10_minutes := 10
			session_days := 90
			password_minimum := 8
			ddns_provider := "duckdns"
			create ddns_domains.make_empty
			create ddns_token.make_empty
			ddns_interval_seconds := 300
			create participant_list.make (4)
			create error_list.make (0)
			create source_path.make_empty
		ensure
			valid: is_valid
			not_loaded: not is_loaded
			local_only: front_door_kind.same_string (Door_none)
			no_participants: participants.is_empty
		end

	make_from_file (a_path: READABLE_STRING_GENERAL)
			-- Parse the TOML at `a_path'; an invalid file leaves the defaults and names each bad field.
		require
			path_given: not a_path.is_empty
		local
			l_toml: SIMPLE_TOML
			l_file: PLAIN_TEXT_FILE
		do
			make_defaults
			source_path := a_path.to_string_32
			create l_file.make_with_name (source_path)
			if not l_file.exists or else not l_file.is_readable then
				note_error (source_path, "the file does not exist or cannot be read")
			elseif l_file.count = 0 then
					-- An empty document is valid TOML: every default stands.
					-- (SIMPLE_TOML.parse_text refuses empty text by precondition, so it is answered here.)
				is_loaded := True
			else
				create l_toml
				if attached l_toml.load_file (source_path) as l_root then
					load_server_settings (l_root)
					load_limit_settings (l_root)
					load_ddns_settings (l_root)
					load_participant_settings (l_root)
					is_loaded := error_list.is_empty
				elseif attached l_toml.first_error as l_reason and then not l_reason.is_empty then
					note_error (source_path, l_reason)
				else
					note_error (source_path, "not parseable TOML")
				end
			end
		ensure
			path_kept: source_path.same_string_general (a_path)
			loaded_or_explained: is_loaded = is_valid
			errors_name_fields: across validation_errors as e all not e.is_empty end
		end

feature -- Model Queries (for MML postconditions)

	participants_model: MML_SEQUENCE [PARTICIPANT_CONFIG]
		do
			create Result
			across participant_list as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = participant_list.count
		end

	errors_model: MML_SEQUENCE [STRING_32]
			-- The validation errors, in the order found.
		do
			create Result
			across error_list as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = error_list.count
		end

feature -- Access: server

	port: INTEGER
	bind_address: STRING_8
	data_dir: STRING_32
	public_name: STRING_8
	front_door_kind: STRING_8
	source_path: STRING_32

	database_path: STRING_32
			-- Where the SQLite store lives: `data_dir' extended with `Database_file_name'.
		require
			data_dir_given: not data_dir.is_empty
		local
			l_path: PATH
		do
			create l_path.make_from_string (data_dir)
			Result := l_path.extended (Database_file_name).name
		ensure
			named: Result.ends_with (Database_file_name)
		end

feature -- Access: limits

	message_characters: INTEGER
	upload_bytes: INTEGER_64
	ai_requests_per_hour: INTEGER
	posts_per_minute: INTEGER
	login_failures_per_10_minutes: INTEGER
	session_days: INTEGER
	password_minimum: INTEGER

feature -- Access: dynamic DNS

	ddns_enabled: BOOLEAN
	ddns_provider: STRING_8
	ddns_domains: STRING_8
	ddns_token: STRING_8
	ddns_interval_seconds: INTEGER

feature -- Access: participants

	participants: ARRAYED_LIST [PARTICIPANT_CONFIG]
			-- A copy of the participant entries, in file order.
		do
			Result := participant_list.twin
		ensure
			a_copy: Result /= participant_list
			same_count: Result.count = participant_count
		end

	participant_count: INTEGER
		do
			Result := participant_list.count
		end

	validation_errors: ARRAYED_LIST [STRING_32]
			-- A copy of the errors found.
		do
			Result := error_list.twin
		ensure
			a_copy: Result /= error_list
			same_count: Result.count = error_count
		end

	error_count: INTEGER
		do
			Result := error_list.count
		end

feature -- Status report

	is_valid: BOOLEAN
		do
			Result := error_list.is_empty
		ensure
			definition: Result = error_list.is_empty
		end

	is_loaded: BOOLEAN
			-- Did a file parse successfully (as opposed to the defaults standing in)?

	is_public: BOOLEAN
			-- Is a front door forwarding the internet to us? (Sessions are Bearer tokens either way - intent-v3.)
		do
			Result := not front_door_kind.same_string (Door_none)
		ensure
			definition: Result = not front_door_kind.same_string (Door_none)
		end

	ai_enabled: BOOLEAN
		do
			Result := not participant_list.is_empty
		ensure
			definition: Result = (participant_count > 0)
		end

	has_participant_handle (a_handle: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_handle' (any case) already a participant's handle?
		do
			Result := across participant_list as p some p.handle.same_string_general (a_handle.as_lower) end
		end

	has_participant_bot_username (a_username: READABLE_STRING_8): BOOLEAN
			-- Is `a_username' already some entry's bot username? (Bot
			-- usernames are lowercase by CHAT_USER_RULES, so exact
			-- comparison is case-insensitive comparison.)
		do
			Result := across participant_list as p some p.bot_username.same_string (a_username) end
		end

	has_participant_alias (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_text' (any case) one of some entry's aliases?
		do
			Result := across participant_list as p some p.has_alias (a_text) end
		end

	is_free_address (a_text: STRING_32): BOOLEAN
			-- Is `a_text' (any case) neither a participant handle nor an
			-- alias here? (M-D7: every way to address a participant is
			-- unique across the whole configuration.)
		do
			Result := not has_participant_handle (a_text) and not has_participant_alias (a_text)
		ensure
			definition: Result = (not has_participant_handle (a_text) and not has_participant_alias (a_text))
		end

feature -- Element change (tests and the CLI)

	set_port (a_port: INTEGER)
		require
			in_range: a_port >= 1 and a_port <= 65535
		do
			port := a_port
		ensure
			set: port = a_port
			lists_unchanged: participants_model |=| old participants_model and errors_model |=| old errors_model
			door_unchanged: front_door_kind.same_string (old front_door_kind.twin) and ddns_enabled = old ddns_enabled
		end

	set_front_door (a_kind: READABLE_STRING_8; a_public_name: READABLE_STRING_8)
		require
			known: is_known_door (a_kind)
			hostname_when_doored: not a_kind.same_string (Door_none) implies is_hostname (a_public_name)
		do
			front_door_kind := a_kind.to_string_8
			public_name := a_public_name.to_string_8
		ensure
			set: front_door_kind.same_string (a_kind) and public_name.same_string (a_public_name)
			lists_unchanged: participants_model |=| old participants_model and errors_model |=| old errors_model
			port_unchanged: port = old port
		end

	set_ddns (a_domains, a_token: READABLE_STRING_8; a_interval_seconds: INTEGER)
		require
			domains_valid: is_valid_domains (a_domains)
			token_given: not a_token.is_empty
			at_least_a_minute: a_interval_seconds >= {DYNAMIC_DNS}.Minimum_interval_seconds
		do
			ddns_enabled := True
			ddns_domains := a_domains.to_string_8
			ddns_token := a_token.to_string_8
			ddns_interval_seconds := a_interval_seconds
		ensure
			enabled: ddns_enabled
			set: ddns_domains.same_string (a_domains) and ddns_interval_seconds = a_interval_seconds
			lists_unchanged: participants_model |=| old participants_model and errors_model |=| old errors_model
			door_unchanged: front_door_kind.same_string (old front_door_kind.twin) and port = old port
		end

	add_participant (a_participant: PARTICIPANT_CONFIG)
		require
			fresh_handle: not has_participant_handle (a_participant.handle)
			handle_not_an_alias: not has_participant_alias (a_participant.handle)
			fresh_bot_username: not has_participant_bot_username (a_participant.bot_username)
			fresh_aliases: a_participant.aliases_model.for_all (agent is_free_address)
		do
			participant_list.extend (a_participant)
		ensure
			added: participants_model |=| ((old participants_model) & a_participant)
			errors_unchanged: errors_model |=| old errors_model
			present: has_participant_handle (a_participant.handle)
			bot_username_present: has_participant_bot_username (a_participant.bot_username)
		end

feature -- Validation (contract support)

	is_known_door (a_kind: READABLE_STRING_8): BOOLEAN
		do
			Result := a_kind.same_string (Door_caddy) or a_kind.same_string (Door_eiffel) or a_kind.same_string (Door_none)
		end

	is_hostname (a_name: READABLE_STRING_8): BOOLEAN
			-- As FRONT_DOOR.is_hostname: labels of [a-z0-9-] joined by dots.
		do
			Result := hostname_rules.is_hostname (a_name)
		end

	is_valid_domains (a_domains: READABLE_STRING_8): BOOLEAN
		do
			Result := dns_rules.is_valid_domains (a_domains)
		end

feature -- Constants

	Door_caddy: STRING_8 = "caddy"
	Door_eiffel: STRING_8 = "eiffel"
	Door_none: STRING_8 = "none"
	Provider_duckdns: STRING_8 = "duckdns"

	Database_file_name: STRING_32 = "simple_chat.db"

feature -- Constants (the file's keys, mirroring the attribute names)

	Key_port: STRING_32 = "port"
	Key_bind_address: STRING_32 = "bind_address"
	Key_data_dir: STRING_32 = "data_dir"
	Key_front_door: STRING_32 = "front_door"
	Key_public_name: STRING_32 = "public_name"
	Key_message_characters: STRING_32 = "message_characters"
	Key_upload_bytes: STRING_32 = "upload_bytes"
	Key_ai_requests_per_hour: STRING_32 = "ai_requests_per_hour"
	Key_posts_per_minute: STRING_32 = "posts_per_minute"
	Key_login_failures: STRING_32 = "login_failures_per_10_minutes"
	Key_session_days: STRING_32 = "session_days"
	Key_password_minimum: STRING_32 = "password_minimum"
	Key_ddns: STRING_32 = "ddns"
	Key_ddns_enabled: STRING_32 = "enabled"
	Key_ddns_provider: STRING_32 = "provider"
	Key_ddns_domains: STRING_32 = "domains"
	Key_ddns_token: STRING_32 = "token"
	Key_ddns_interval: STRING_32 = "interval_seconds"
	Key_participants: STRING_32 = "participants"
	Key_handle: STRING_32 = "handle"
	Key_kind: STRING_32 = "kind"
	Key_engine: STRING_32 = "engine"
	Key_bot_username: STRING_32 = "bot_username"
	Key_display_name: STRING_32 = "display_name"
	Key_requests_per_hour: STRING_32 = "requests_per_hour"
	Key_max_characters: STRING_32 = "max_characters"
	Key_timeout_seconds: STRING_32 = "timeout_seconds"
	Key_query_shaper: STRING_32 = "query_shaper"
	Key_response_shaper: STRING_32 = "response_shaper"
	Key_aliases: STRING_32 = "aliases"
	Key_allow_via: STRING_32 = "allow_via"

feature {NONE} -- Implementation

	participant_list: ARRAYED_LIST [PARTICIPANT_CONFIG]
	error_list: ARRAYED_LIST [STRING_32]

	hostname_rules: NO_DOOR_RULES
			-- FRONT_DOOR's validation, without a door.
		once
			create Result
		end

	dns_rules: NO_DNS_RULES
			-- DYNAMIC_DNS's validation, without an updater.
		once
			create Result
		end

feature {NONE} -- File loading (simple_toml; D6: every read is validated, no setter precondition is reachable)

	load_server_settings (a_root: TOML_TABLE)
			-- port, data_dir, front_door and public_name; a bind_address key is refused.
		local
			l_door: detachable STRING_8
			l_name: detachable STRING_32
		do
			if a_root.has (Key_bind_address) then
				note_error (Key_bind_address, "not configurable; the server always binds 127.0.0.1")
			end
			if attached integer_setting (a_root, Key_port, Key_port) as l_port then
				if l_port.item >= 1 and l_port.item <= 65535 then
					port := l_port.item.to_integer_32
				else
					note_error (Key_port, "must be between 1 and 65535")
				end
			end
			if attached string_setting (a_root, Key_data_dir, Key_data_dir) as l_dir then
				if l_dir.is_empty then
					note_error (Key_data_dir, "must not be empty")
				else
					data_dir := l_dir
				end
			end
			if attached string_setting (a_root, Key_front_door, Key_front_door) as l_kind then
				if l_kind.is_valid_as_string_8 and then is_known_door (l_kind.to_string_8) then
					l_door := l_kind.to_string_8
				else
					note_error (Key_front_door, "must be %"caddy%", %"eiffel%" or %"none%"")
				end
			end
			l_name := string_setting (a_root, Key_public_name, Key_public_name)
			if attached l_door as k and then not k.same_string (Door_none) then
				if attached l_name as n and then n.is_valid_as_string_8 and then is_hostname (n.to_string_8) then
					set_front_door (k, n.to_string_8)
				else
					note_error (Key_public_name, "must be a hostname (labels of a-z, 0-9 and %"-%" joined by dots) when a front door is on")
				end
			elseif l_name /= Void then
				note_error (Key_public_name, "set while front_door is %"none%"; nothing would serve it")
			end
		end

	load_limit_settings (a_root: TOML_TABLE)
			-- The seven limits, each validated against its own invariant before it is kept.
		do
			if attached integer_setting (a_root, Key_message_characters, Key_message_characters) as l_messages then
				if is_positive_int_32 (l_messages.item) then
					message_characters := l_messages.item.to_integer_32
				else
					note_error (Key_message_characters, "must be a positive integer")
				end
			end
			if attached integer_setting (a_root, Key_upload_bytes, Key_upload_bytes) as l_upload then
				if l_upload.item > 0 then
					upload_bytes := l_upload.item
				else
					note_error (Key_upload_bytes, "must be a positive integer")
				end
			end
			if attached integer_setting (a_root, Key_ai_requests_per_hour, Key_ai_requests_per_hour) as l_ai then
				if l_ai.item >= 0 and l_ai.item <= {INTEGER_32}.Max_value.to_integer_64 then
					ai_requests_per_hour := l_ai.item.to_integer_32
				else
					note_error (Key_ai_requests_per_hour, "must be zero or a positive integer")
				end
			end
			if attached integer_setting (a_root, Key_posts_per_minute, Key_posts_per_minute) as l_posts then
				if is_positive_int_32 (l_posts.item) then
					posts_per_minute := l_posts.item.to_integer_32
				else
					note_error (Key_posts_per_minute, "must be a positive integer")
				end
			end
			if attached integer_setting (a_root, Key_login_failures, Key_login_failures) as l_failures then
				if is_positive_int_32 (l_failures.item) then
					login_failures_per_10_minutes := l_failures.item.to_integer_32
				else
					note_error (Key_login_failures, "must be a positive integer")
				end
			end
			if attached integer_setting (a_root, Key_session_days, Key_session_days) as l_days then
				if is_positive_int_32 (l_days.item) then
					session_days := l_days.item.to_integer_32
				else
					note_error (Key_session_days, "must be a positive integer")
				end
			end
			if attached integer_setting (a_root, Key_password_minimum, Key_password_minimum) as l_minimum then
				if l_minimum.item >= {PASSWORD_HASHER}.Minimum_characters and l_minimum.item <= {INTEGER_32}.Max_value.to_integer_64 then
					password_minimum := l_minimum.item.to_integer_32
				else
					note_error (Key_password_minimum, "must be at least " + {PASSWORD_HASHER}.Minimum_characters.out)
				end
			end
		end

	load_ddns_settings (a_root: TOML_TABLE)
			-- The optional [ddns] table; any error inside the block leaves DDNS disabled.
		local
			l_enabled: BOOLEAN
			l_domains, l_token: detachable STRING_8
			l_interval: INTEGER
			l_errors_before: INTEGER
		do
			if a_root.has (Key_ddns) then
				l_errors_before := error_list.count
				if attached a_root.table_item (Key_ddns) as l_ddns then
					l_interval := ddns_interval_seconds
					if attached boolean_setting (l_ddns, Key_ddns_enabled, ddns_field (Key_ddns_enabled)) as l_flag then
						l_enabled := l_flag.item
					end
					if attached string_setting (l_ddns, Key_ddns_provider, ddns_field (Key_ddns_provider)) as l_provider then
						if not (l_provider.is_valid_as_string_8 and then l_provider.to_string_8.same_string (Provider_duckdns)) then
							note_error (ddns_field (Key_ddns_provider), "only %"duckdns%" is supported")
						end
					end
					if attached string_setting (l_ddns, Key_ddns_domains, ddns_field (Key_ddns_domains)) as l_given_domains then
						if l_given_domains.is_valid_as_string_8 and then is_valid_domains (l_given_domains.to_string_8) then
							l_domains := l_given_domains.to_string_8
						else
							note_error (ddns_field (Key_ddns_domains), "must be labels of a-z, 0-9 and %"-%" joined by commas")
						end
					end
					if attached string_setting (l_ddns, Key_ddns_token, ddns_field (Key_ddns_token)) as l_given_token then
						if l_given_token.is_valid_as_string_8 and then not l_given_token.is_empty then
							l_token := l_given_token.to_string_8
						else
							note_error (ddns_field (Key_ddns_token), "must not be empty")
						end
					end
					if attached integer_setting (l_ddns, Key_ddns_interval, ddns_field (Key_ddns_interval)) as l_given_interval then
						if l_given_interval.item >= {DYNAMIC_DNS}.Minimum_interval_seconds and l_given_interval.item <= {INTEGER_32}.Max_value.to_integer_64 then
							l_interval := l_given_interval.item.to_integer_32
						else
							note_error (ddns_field (Key_ddns_interval), "must be at least " + {DYNAMIC_DNS}.Minimum_interval_seconds.out + " seconds")
						end
					end
					if l_enabled then
						if l_domains = Void and then not l_ddns.has (Key_ddns_domains) then
							note_error (ddns_field (Key_ddns_domains), "required when ddns is enabled")
						end
						if l_token = Void and then not l_ddns.has (Key_ddns_token) then
							note_error (ddns_field (Key_ddns_token), "required when ddns is enabled")
						end
						if error_list.count = l_errors_before and then attached l_domains as d and then attached l_token as t then
							set_ddns (d, t, l_interval)
						end
					end
				else
					note_error (Key_ddns, "must be a [ddns] table")
				end
			end
		end

	load_participant_settings (a_root: TOML_TABLE)
			-- The [[participants]] entries, in file order.
		local
			i: INTEGER
		do
			if a_root.has (Key_participants) then
				if attached a_root.item (Key_participants) as l_value and then l_value.is_array then
					from
						i := 1
					until
						i > l_value.as_array.count
					loop
						if l_value.as_array.item (i).is_table then
							load_participant (l_value.as_array.item (i).as_table, i)
						else
							note_error (participant_field (i, ""), "must be a [[participants]] table")
						end
						i := i + 1
					variant
						l_value.as_array.count - i + 1
					end
				else
					note_error (Key_participants, "must be an array of [[participants]] tables")
				end
			end
		end

	load_participant (a_entry: TOML_TABLE; a_index: INTEGER)
			-- One [[participants]] entry: a broken identity or collision skips it whole.
		local
			l_participant: PARTICIPANT_CONFIG
			l_handle: detachable STRING_32
			l_kind: detachable STRING_8
			l_username: detachable STRING_8
			l_display: detachable STRING_32
			l_engine: STRING_32
			l_rules: PARTICIPANT_RULES
			l_user_rules: CHAT_USER_RULES
		do
			create l_rules
			create l_user_rules
			if attached string_setting (a_entry, Key_handle, participant_field (a_index, Key_handle)) as h then
				if l_rules.is_valid_handle (h) then
					l_handle := h
				else
					note_error (participant_field (a_index, Key_handle), "must be %"@%" then 1..32 characters of a-z, 0-9, %"_%" or %"-%"")
				end
			elseif not a_entry.has (Key_handle) then
				note_error (participant_field (a_index, Key_handle), "required")
			end
			if attached string_setting (a_entry, Key_kind, participant_field (a_index, Key_kind)) as k then
				if k.is_valid_as_string_8 and then is_known_participant_kind (k.to_string_8) then
					l_kind := k.to_string_8
				else
					note_error (participant_field (a_index, Key_kind), "must be %"claude_code%", %"ollama%", %"bible_tool%", %"shape_tool%" or %"none%"")
				end
			elseif not a_entry.has (Key_kind) then
				note_error (participant_field (a_index, Key_kind), "required")
			end
			if attached string_setting (a_entry, Key_bot_username, participant_field (a_index, Key_bot_username)) as u then
				if u.is_valid_as_string_8 and then l_user_rules.is_valid_username (u.to_string_8) then
					l_username := u.to_string_8
				else
					note_error (participant_field (a_index, Key_bot_username), "must be 1..32 characters of a-z, 0-9 or %"_%"")
				end
			elseif not a_entry.has (Key_bot_username) then
				note_error (participant_field (a_index, Key_bot_username), "required")
			end
			if attached string_setting (a_entry, Key_display_name, participant_field (a_index, Key_display_name)) as d then
				if l_user_rules.is_valid_display_name (d) and then d.count + 2 <= {CHAT_USER}.Display_name_maximum then
					l_display := d
				else
					note_error (participant_field (a_index, Key_display_name), "must be a display name short enough to carry the bot marker")
				end
			elseif not a_entry.has (Key_display_name) then
				note_error (participant_field (a_index, Key_display_name), "required")
			end
			create l_engine.make_empty
			if attached string_setting (a_entry, Key_engine, participant_field (a_index, Key_engine)) as e then
				l_engine := e
			end
			if attached l_kind as k2 and then not k2.same_string ({PARTICIPANT_CONFIG}.Kind_none) and then l_engine.is_empty then
				note_error (participant_field (a_index, Key_engine), "required for this kind (the executable, database, model or working directory)")
				l_kind := Void
			end
			if attached l_handle as h2 and then attached l_kind as k3 and then attached l_username as u2 and then attached l_display as d2 then
				if has_participant_handle (h2) or has_participant_alias (h2) then
					note_error (participant_field (a_index, Key_handle), "already addresses another participant")
				elseif has_participant_bot_username (u2) then
					note_error (participant_field (a_index, Key_bot_username), "already used by another participant")
				else
					create l_participant.make (h2, k3, u2, d2, l_engine)
					load_participant_limits (a_entry, l_participant, a_index)
					load_participant_shapers (a_entry, l_participant, a_index)
					load_participant_aliases (a_entry, l_participant, a_index)
					load_participant_via (a_entry, l_participant, a_index)
					add_participant (l_participant)
				end
			end
		end

	load_participant_limits (a_entry: TOML_TABLE; a_participant: PARTICIPANT_CONFIG; a_index: INTEGER)
			-- The optional limits; a bad one keeps its default alone.
		local
			l_requests, l_characters, l_timeout: INTEGER
		do
			l_requests := a_participant.requests_per_hour
			l_characters := a_participant.max_characters
			l_timeout := a_participant.timeout_seconds
			if attached integer_setting (a_entry, Key_requests_per_hour, participant_field (a_index, Key_requests_per_hour)) as l_cell then
				if is_positive_int_32 (l_cell.item) then
					l_requests := l_cell.item.to_integer_32
				else
					note_error (participant_field (a_index, Key_requests_per_hour), "must be a positive integer")
				end
			end
			if attached integer_setting (a_entry, Key_max_characters, participant_field (a_index, Key_max_characters)) as l_cell2 then
				if is_positive_int_32 (l_cell2.item) then
					l_characters := l_cell2.item.to_integer_32
				else
					note_error (participant_field (a_index, Key_max_characters), "must be a positive integer")
				end
			end
			if attached integer_setting (a_entry, Key_timeout_seconds, participant_field (a_index, Key_timeout_seconds)) as l_cell3 then
				if is_positive_int_32 (l_cell3.item) then
					l_timeout := l_cell3.item.to_integer_32
				else
					note_error (participant_field (a_index, Key_timeout_seconds), "must be a positive integer")
				end
			end
			a_participant.set_limits (l_requests, l_characters, l_timeout)
		end

	load_participant_shapers (a_entry: TOML_TABLE; a_participant: PARTICIPANT_CONFIG; a_index: INTEGER)
			-- The optional shapers; a bad one keeps its default alone.
		local
			l_query, l_response: STRING_32
		do
			l_query := a_participant.query_shaper
			l_response := a_participant.response_shaper
			if attached string_setting (a_entry, Key_query_shaper, participant_field (a_index, Key_query_shaper)) as q then
				if a_participant.is_known_shaper_name (q) then
					l_query := q
				else
					note_error (participant_field (a_index, Key_query_shaper), "must be %"none%", %"plain%" or an %"@name%"")
				end
			end
			if attached string_setting (a_entry, Key_response_shaper, participant_field (a_index, Key_response_shaper)) as r then
				if a_participant.is_known_shaper_name (r) then
					l_response := r
				else
					note_error (participant_field (a_index, Key_response_shaper), "must be %"none%", %"plain%" or an %"@name%"")
				end
			end
			a_participant.set_shapers (l_query, l_response)
		end

	load_participant_aliases (a_entry: TOML_TABLE; a_participant: PARTICIPANT_CONFIG; a_index: INTEGER)
			-- The optional aliases array; a bad or colliding alias is refused alone (M-D7).
		local
			i: INTEGER
			l_rules: PARTICIPANT_RULES
			l_field: STRING_32
			l_lower: STRING_32
		do
			create l_rules
			l_field := participant_field (a_index, Key_aliases)
			if a_entry.has (Key_aliases) then
				if attached a_entry.item (Key_aliases) as l_value and then l_value.is_array then
					from
						i := 1
					until
						i > l_value.as_array.count
					loop
						if l_value.as_array.item (i).is_string then
							l_lower := l_value.as_array.item (i).as_string.as_lower
							if not l_rules.is_valid_alias (l_lower) then
								note_error (l_field, quoted_reason (l_lower, "must end in %":%" or begin with %"@%""))
							elseif l_lower.same_string (a_participant.handle) or a_participant.has_alias (l_lower) then
								note_error (l_field, quoted_reason (l_lower, "repeats this participant's own address"))
							elseif not is_free_address (l_lower) then
								note_error (l_field, quoted_reason (l_lower, "already addresses another participant"))
							else
								a_participant.add_alias (l_lower)
							end
						else
							note_error (l_field, "every alias must be a string")
						end
						i := i + 1
					variant
						l_value.as_array.count - i + 1
					end
				else
					note_error (l_field, "must be an array of strings")
				end
			end
		end

	load_participant_via (a_entry: TOML_TABLE; a_participant: PARTICIPANT_CONFIG; a_index: INTEGER)
			-- The optional allow_via array; a bad or repeated choice is refused alone.
		local
			i: INTEGER
			l_rules: PARTICIPANT_RULES
			l_field: STRING_32
			l_lower: STRING_32
		do
			create l_rules
			l_field := participant_field (a_index, Key_allow_via)
			if a_entry.has (Key_allow_via) then
				if attached a_entry.item (Key_allow_via) as l_value and then l_value.is_array then
					from
						i := 1
					until
						i > l_value.as_array.count
					loop
						if l_value.as_array.item (i).is_string then
							l_lower := l_value.as_array.item (i).as_string.as_lower
							if not l_rules.is_via_choice (l_lower) then
								note_error (l_field, quoted_reason (l_lower, "must be %"plain%" or an %"@name%""))
							elseif a_participant.allows_via (l_lower) then
								note_error (l_field, quoted_reason (l_lower, "repeated"))
							else
								a_participant.add_allow_via (l_lower)
							end
						else
							note_error (l_field, "every via choice must be a string")
						end
						i := i + 1
					variant
						l_value.as_array.count - i + 1
					end
				else
					note_error (l_field, "must be an array of strings")
				end
			end
		end

	string_setting (a_table: TOML_TABLE; a_key: STRING_32; a_field: READABLE_STRING_GENERAL): detachable STRING_32
			-- The string under `a_key'; Void when absent; a present non-string is an error named `a_field'.
		do
			if attached a_table.item (a_key) as l_value then
				if l_value.is_string then
					Result := l_value.as_string
				else
					note_error (a_field, "must be a string")
				end
			end
		end

	integer_setting (a_table: TOML_TABLE; a_key: STRING_32; a_field: READABLE_STRING_GENERAL): detachable CELL [INTEGER_64]
			-- The integer under `a_key'; Void when absent; a present non-integer is an error named `a_field'.
		do
			if attached a_table.item (a_key) as l_value then
				if l_value.is_integer then
					create Result.put (l_value.as_integer)
				else
					note_error (a_field, "must be an integer")
				end
			end
		end

	boolean_setting (a_table: TOML_TABLE; a_key: STRING_32; a_field: READABLE_STRING_GENERAL): detachable CELL [BOOLEAN]
			-- The boolean under `a_key'; Void when absent; a present non-boolean is an error named `a_field'.
		do
			if attached a_table.item (a_key) as l_value then
				if l_value.is_boolean then
					create Result.put (l_value.as_boolean)
				else
					note_error (a_field, "must be true or false")
				end
			end
		end

	note_error (a_field: READABLE_STRING_GENERAL; a_reason: READABLE_STRING_GENERAL)
			-- Record "`a_field': `a_reason'" (D6: a file problem is a validation outcome, never a crash).
		require
			field_given: not a_field.is_empty
			reason_given: not a_reason.is_empty
		local
			l_line: STRING_32
		do
			create l_line.make (a_field.count + a_reason.count + 2)
			l_line.append_string_general (a_field)
			l_line.append_string_general (": ")
			l_line.append_string_general (a_reason)
			error_list.extend (l_line)
		ensure
			one_more: error_count = old error_count + 1
			participants_unchanged: participants_model |=| old participants_model
		end

	ddns_field (a_key: READABLE_STRING_GENERAL): STRING_32
			-- "ddns.`a_key'", the name an error inside the [ddns] table carries.
		require
			key_given: not a_key.is_empty
		do
			create Result.make (5 + a_key.count)
			Result.append_string_general (Key_ddns)
			Result.append_string_general (".")
			Result.append_string_general (a_key)
		ensure
			named: not Result.is_empty
		end

	participant_field (a_index: INTEGER; a_key: READABLE_STRING_GENERAL): STRING_32
			-- "participants[`a_index']", with ".`a_key'" when a key is given.
		require
			positive: a_index >= 1
		do
			create Result.make (16 + a_key.count)
			Result.append_string_general ("participants[")
			Result.append_string_general (a_index.out)
			Result.append_string_general ("]")
			if not a_key.is_empty then
				Result.append_string_general (".")
				Result.append_string_general (a_key)
			end
		ensure
			named: not Result.is_empty
		end

	quoted_reason (a_text: READABLE_STRING_GENERAL; a_reason: READABLE_STRING_GENERAL): STRING_32
			-- "%"`a_text'%" `a_reason'", for errors about one element of a list.
		do
			create Result.make (a_text.count + a_reason.count + 3)
			Result.append_string_general ("%"")
			Result.append_string_general (a_text)
			Result.append_string_general ("%" ")
			Result.append_string_general (a_reason)
		ensure
			reasoned: not Result.is_empty
		end

	is_positive_int_32 (a_value: INTEGER_64): BOOLEAN
			-- Positive and small enough for an INTEGER attribute?
		do
			Result := a_value >= 1 and a_value <= {INTEGER_32}.Max_value.to_integer_64
		end

	is_known_participant_kind (a_kind: READABLE_STRING_8): BOOLEAN
			-- One of PARTICIPANT_CONFIG's kinds? (Its own `is_known_kind' needs an instance.)
		do
			Result := a_kind.same_string ({PARTICIPANT_CONFIG}.Kind_claude_code)
				or a_kind.same_string ({PARTICIPANT_CONFIG}.Kind_ollama)
				or a_kind.same_string ({PARTICIPANT_CONFIG}.Kind_bible_tool)
				or a_kind.same_string ({PARTICIPANT_CONFIG}.Kind_shape_tool)
				or a_kind.same_string ({PARTICIPANT_CONFIG}.Kind_none)
		end

invariant
	port_in_range: port >= 1 and port <= 65535
	localhost_only: bind_address.same_string ("127.0.0.1")
	known_door: is_known_door (front_door_kind)
	public_when_doored: not front_door_kind.same_string (Door_none) implies is_hostname (public_name)
	limits_positive: message_characters > 0 and upload_bytes > 0 and ai_requests_per_hour >= 0 and posts_per_minute > 0
	login_backoff_positive: login_failures_per_10_minutes > 0
	session_lifetime_positive: session_days > 0
	password_minimum_sane: password_minimum >= {PASSWORD_HASHER}.Minimum_characters
	known_provider: ddns_provider.same_string (Provider_duckdns)
	ddns_needs_token: ddns_enabled implies (not ddns_token.is_empty and is_valid_domains (ddns_domains))
	ddns_interval_sane: ddns_interval_seconds >= {DYNAMIC_DNS}.Minimum_interval_seconds
	unique_handles: across participant_list as p all
		(across participant_list as q all (p.handle.same_string (q.handle)) implies (p = q) end) end
	unique_bot_usernames: across participant_list as p all
		(across participant_list as q all (p.bot_username.same_string (q.bot_username)) implies (p = q) end) end
	aliases_never_handles: across participant_list as p all
		(across participant_list as q all not p.has_alias (q.handle) end) end
	models_consistent: participants_model.count = participant_list.count and errors_model.count = error_list.count
	valid_means_no_errors: is_valid = errors_model.is_empty
	loaded_is_valid: is_loaded implies is_valid

end
