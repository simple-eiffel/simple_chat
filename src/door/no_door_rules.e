note
	description: "FRONT_DOOR's validation rules (hostnames) usable without a door - SERVER_CONFIG checks names before any door exists. Never serves; says so."
	author: "Larry Rix"

class
	NO_DOOR_RULES

inherit
	FRONT_DOOR

feature -- Access

	public_name: STRING_8
		once
			create Result.make_empty
		end

	upstream_port: INTEGER
		do
			Result := 1
		end

	last_error: detachable CHAT_ERROR

feature -- Status report

	is_serving: BOOLEAN
		do
		end

	is_public: BOOLEAN
		do
		end

	has_child_process: BOOLEAN
		do
		end

	sets_forwarded_headers: BOOLEAN
		do
		end

feature -- Basic operations

	start
		do
			last_error := rules_only
		end

	stop
		do
		end

	check_health
		do
			last_error := rules_only
		end

feature {NONE} -- Implementation

	rules_only: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, "validation rules only - not a door", 503)
		end

end
