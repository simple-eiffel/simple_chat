note
	description: "[
		The degenerate door: nothing in front of the chat - a tunnel or a
		proxy elsewhere owns the public side, or this is a bare LAN test.
		Serving at once; not public, so it promises no forwarded headers.
	]"
	author: "Larry Rix"

class
	NO_FRONT_DOOR

inherit
	FRONT_DOOR

create
	make

feature {NONE} -- Initialization

	make (a_config: SERVER_CONFIG)
		do
			public_name := a_config.public_name.twin
			upstream_port := a_config.port
		ensure
			port_set: upstream_port = a_config.port
			not_serving: not is_serving
		end

feature -- Access

	public_name: STRING_8
	upstream_port: INTEGER

	last_error: detachable CHAT_ERROR
		do
		end

feature -- Status report

	is_serving: BOOLEAN

	is_public: BOOLEAN
		do
			Result := False
		end

	has_child_process: BOOLEAN
		do
			Result := False
		end

	sets_forwarded_headers: BOOLEAN
		do
			Result := False
		end

feature -- Basic operations

	start
		do
			is_serving := True
		ensure then
			serving: is_serving
		end

	stop
		do
			is_serving := False
		end

	check_health
		do
			is_serving := True
		end

invariant
	port_positive: upstream_port > 0

end
