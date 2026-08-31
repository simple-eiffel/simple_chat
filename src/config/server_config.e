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
		do
			make_defaults
			source_path := a_path.to_string_32
			-- Implementation in Phase 4 (simple_toml): is_loaded := True only after a successful parse
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
