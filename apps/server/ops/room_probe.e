note
	description: "[
		Is the room running right now? Asked the only honest way: GET /health
		on the loopback port over a real transport, and the answer believed
		only when it is CHAT_API's own health shape (SERVICE_LOCATOR's
		`is_health_reply'). `tasklist' can only say that SOME server
		executable is running somewhere on this PC - which is how a
		verification build and the real room were once confused - and a 200
		from whatever else holds the port is not a room either.

		SERVER_APP asks it before --create-user, to choose between the running
		room's administrator API and opening the database directly. Over a
		MEMORY_HTTP_TRANSPORT in the assault; over WINHTTP_TRANSPORT in
		production.
	]"
	author: "Larry Rix"

class
	ROOM_PROBE

create
	make

feature {NONE} -- Initialization

	make (a_transport: HTTP_TRANSPORT)
			-- Probe through `a_transport'.
		do
			transport := a_transport
		ensure
			set: transport = a_transport
			fresh: probe_count = 0
		end

feature -- Status report

	is_up (a_port: INTEGER): BOOLEAN
			-- Does a chat room answer /health on the loopback address at `a_port'?
		require
			valid_port: a_port > 0 and a_port <= 65535
		local
			l_headers: HASH_TABLE [STRING_8, STRING_8]
			l_reply: HTTP_REPLY
			l_locator: SERVICE_LOCATOR
		do
			create l_headers.make (0)
			l_reply := transport.send ("GET", base_url (a_port) + "/health", l_headers, Void, Timeout_seconds)
			create l_locator.make (transport)
			Result := l_reply.is_exchanged and then l_reply.is_success and then l_locator.is_health_reply (l_reply.body)
			probe_count := probe_count + 1
		ensure
			counted: probe_count = old probe_count + 1
		end

	probe_count: INTEGER
			-- How many times the room was asked.

feature -- Access

	base_url (a_port: INTEGER): STRING_8
			-- Where the room is asked: the loopback address, never a name.
		require
			valid_port: a_port > 0 and a_port <= 65535
		do
			Result := "http://127.0.0.1:" + a_port.out
		ensure
			loopback: Result.starts_with ("http://127.0.0.1:")
			ported: Result.ends_with (a_port.out)
		end

feature {NONE} -- Implementation

	transport: HTTP_TRANSPORT
			-- The wire.

	Timeout_seconds: INTEGER = 3
			-- A room on this PC answers /health in milliseconds; a silent port
			-- is refused at once. Three seconds is for a room that is busy.

end
