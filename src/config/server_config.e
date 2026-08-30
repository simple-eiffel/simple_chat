note
	description: "[
		The one server configuration file (TOML), parsed and validated
		here and nowhere else. Invariants pin what the rest of the system
		relies on: localhost binding, a known front door, a public name
		when a door is public, positive limits, a DDNS token when DDNS is
		on, unique participant handles.
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
			front_door_kind := Door_none
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
			create participants.make (4)
			create validation_errors.make (0)
			create source_path.make_empty
		ensure
			valid: is_valid
			local_only: front_door_kind.same_string (Door_none)
			no_participants: participants.is_empty
		end

	make_from_file (a_path: READABLE_STRING_GENERAL)
			-- Parse the TOML at `a_path'; invalid files leave `validation_errors' naming each field.
		require
			path_given: not a_path.is_empty
		do
			make_defaults
			source_path := a_path.to_string_32
			-- Implementation in Phase 4 (simple_toml)
		ensure
			path_kept: source_path.same_string_general (a_path)
			valid_or_explained: is_valid or not validation_errors.is_empty
		end

feature -- Model Queries (for MML postconditions)

	participants_model: MML_SEQUENCE [PARTICIPANT_CONFIG]
		do
			create Result
			across participants as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = participants.count
		end

	errors_model: MML_SEQUENCE [STRING_32]
			-- The validation errors, in the order found.
		do
			create Result
			across validation_errors as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = validation_errors.count
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

feature -- Status report

	is_valid: BOOLEAN
		do
			Result := validation_errors.is_empty
		ensure
			definition: Result = validation_errors.is_empty
		end

	validation_errors: ARRAYED_LIST [STRING_32]

	is_public: BOOLEAN
			-- Is a front door forwarding the internet to us? (Sessions are Bearer tokens either way - intent-v3.)
		do
			Result := not front_door_kind.same_string (Door_none)
		ensure
			definition: Result = not front_door_kind.same_string (Door_none)
		end

	ai_enabled: BOOLEAN
		do
			Result := not participants.is_empty
		end

	has_participant_handle (a_handle: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := across participants as p some p.handle.same_string_general (a_handle) end
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
		end

	set_front_door (a_kind: READABLE_STRING_8; a_public_name: READABLE_STRING_8)
		require
			known: is_known_door (a_kind)
			named_when_doored: not a_kind.same_string (Door_none) implies not a_public_name.is_empty
		do
			front_door_kind := a_kind.to_string_8
			public_name := a_public_name.to_string_8
		ensure
			set: front_door_kind.same_string (a_kind) and public_name.same_string (a_public_name)
			lists_unchanged: participants_model |=| old participants_model and errors_model |=| old errors_model
		end

	set_ddns (a_domains, a_token: READABLE_STRING_8; a_interval_seconds: INTEGER)
		require
			given: not a_domains.is_empty and not a_token.is_empty
			positive: a_interval_seconds > 0
		do
			ddns_enabled := True
			ddns_domains := a_domains.to_string_8
			ddns_token := a_token.to_string_8
			ddns_interval_seconds := a_interval_seconds
		ensure
			enabled: ddns_enabled
			set: ddns_domains.same_string (a_domains) and ddns_interval_seconds = a_interval_seconds
			lists_unchanged: participants_model |=| old participants_model and errors_model |=| old errors_model
		end

	add_participant (a_participant: PARTICIPANT_CONFIG)
		require
			fresh_handle: not has_participant_handle (a_participant.handle)
		do
			participants.extend (a_participant)
		ensure
			added: participants_model |=| ((old participants_model) & a_participant)
			errors_unchanged: errors_model |=| old errors_model
			still_unique: has_participant_handle (a_participant.handle)
		end

feature -- Validation (contract support)

	is_known_door (a_kind: READABLE_STRING_8): BOOLEAN
		do
			Result := a_kind.same_string (Door_caddy) or a_kind.same_string (Door_eiffel) or a_kind.same_string (Door_none)
		end

feature -- Constants

	Door_caddy: STRING_8 = "caddy"
	Door_eiffel: STRING_8 = "eiffel"
	Door_none: STRING_8 = "none"

invariant
	port_in_range: port >= 1 and port <= 65535
	localhost_only: bind_address.same_string ("127.0.0.1")
	known_door: is_known_door (front_door_kind)
	public_when_doored: not front_door_kind.same_string (Door_none) implies not public_name.is_empty
	limits_positive: message_characters > 0 and upload_bytes > 0 and ai_requests_per_hour >= 0 and posts_per_minute > 0
	login_backoff_positive: login_failures_per_10_minutes > 0
	session_lifetime_positive: session_days > 0
	password_minimum_sane: password_minimum >= 8
	ddns_needs_token: ddns_enabled implies not ddns_token.is_empty and not ddns_domains.is_empty
	ddns_interval_positive: ddns_interval_seconds > 0
	unique_handles: across participants as p all
		(across participants as q all (p.handle.same_string (q.handle)) implies (p = q) end) end
	models_consistent: participants_model.count = participants.count and errors_model.count = validation_errors.count
	valid_means_no_errors: is_valid = errors_model.is_empty

end
