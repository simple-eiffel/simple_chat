note
	description: "[
		The degenerate door: nothing in front of the chat - a tunnel or a
		proxy elsewhere owns the public side, or this is a bare LAN test.
		Serving as soon as started; not public, so it promises no
		forwarded headers. Once stopped it stays stopped: `check_health'
		reports through `last_error' instead of resurrecting it.
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
		require
			none_configured: a_config.front_door_kind.same_string ({SERVER_CONFIG}.Door_none)
		do
			create public_name.make_empty
			upstream_port := a_config.port
		ensure
			port_set: upstream_port = a_config.port
			not_serving: not is_serving
			unnamed: public_name.is_empty
		end

feature -- Access

	public_name: STRING_8
	upstream_port: INTEGER
	last_error: detachable CHAT_ERROR

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
			last_error := Void
		ensure then
			serving: is_serving
		end

	stop
		do
			is_serving := False
			last_error := stopped
		ensure then
			explained: last_error /= Void
		end

	check_health
		do
			if not is_serving and last_error = Void then
				last_error := stopped
			end
		ensure then
			unchanged: is_serving = old is_serving
		end

feature {NONE} -- Implementation

	stopped: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, "door stopped", 503)
		end

invariant
	port_positive: upstream_port > 0
	never_named: public_name.is_empty

end
