note
	description: "[
		The in-process door of Tier 1: simple_tls (SChannel server side) +
		simple_acme + a streaming proxy. Not in this build: `start' says so
		through `last_error', so the contract holds and the config switch
		`front_door = "eiffel"' is honest today and live later.
	]"
	author: "Larry Rix"

class
	EIFFEL_FRONT_DOOR

inherit
	FRONT_DOOR

create
	make

feature {NONE} -- Initialization

	make (a_config: SERVER_CONFIG)
		require
			eiffel_configured: a_config.front_door_kind.same_string ({SERVER_CONFIG}.Door_eiffel)
			named: not a_config.public_name.is_empty
		do
			public_name := a_config.public_name.twin
			upstream_port := a_config.port
		ensure
			name_set: public_name.same_string (a_config.public_name)
			not_serving: not is_serving
		end

feature -- Access

	public_name: STRING_8
	upstream_port: INTEGER
	last_error: detachable CHAT_ERROR

feature -- Status report

	is_serving: BOOLEAN
		do
			Result := False
		end

	is_public: BOOLEAN
		do
			Result := True
		end

	has_child_process: BOOLEAN
		do
			Result := False
		end

	sets_forwarded_headers: BOOLEAN
		do
			Result := True
		end

feature -- Basic operations

	start
		do
			create last_error.make ({CHAT_ERROR}.Code_unavailable, "The Eiffel front door is not in this build (Tier 1: simple_tls + simple_acme).", 503)
		end

	stop
		do
		end

	check_health
		do
			if last_error = Void then
				start
			end
		end

invariant
	named: not public_name.is_empty
	port_positive: upstream_port > 0

end
