note
	description: "[
		The HTTP face: a SIMPLE_WEB_HANDLER_SERVER bound on `config.port'
		that creates one CHAT_REQUEST_HANDLER per request on the request's
		processor (SCOOP-clean, D1). Handlers reach the API through
		CHAT_SHARED; this class only owns the server's lifetime. No EWF
		type appears here: simple_web only.

		THE LISTENER IS LOOPBACK-ONLY, and this is where that becomes true.
		SERVER_CONFIG pins `bind_address' to 127.0.0.1, refuses the key in
		server.toml and asserts it in an invariant - but a value is not a
		bound socket until it reaches the transport, and until simple_web
		0.4.0 there was nothing to hand it to: EWF's standalone connector
		binds every interface (0.0.0.0) when no address is configured, and
		the live room was observed doing exactly that on 0.0.0.0:8090.
		`start' now calls `set_bind_address (config.bind_address)', so the
		socket itself is bound to 127.0.0.1 and nothing off this machine can
		reach it. BIND_ASSAULT proves it against a real server exe.
	]"
	author: "Larry Rix"

class
	CHAT_WEB_APP

create
	make

feature {NONE} -- Initialization

	make (a_config: SERVER_CONFIG)
		require
			valid_config: a_config.is_valid
		do
			config := a_config
		ensure
			set: config = a_config
			not_running: not is_running
		end

feature -- Access

	port: INTEGER
		do
			Result := config.port
		end

	last_error: detachable CHAT_ERROR

feature -- Status report

	is_running: BOOLEAN

feature -- Basic operations

	start
			-- Assemble the server on `config.bind_address':`port' - the loopback
			-- address alone, never every interface; the pool is sized for the
			-- connections that stay open (long-polls, streams), not for the rate.
			-- `is_running' means ASSEMBLED AND READY here: the socket itself binds
			-- inside `run' (EWF's launch), so a port conflict surfaces there, not
			-- here - the re-review's pre-bind note, kept honest by saying so.
		require
			not_running: not is_running
		local
			l_server: SIMPLE_WEB_HANDLER_SERVER [CHAT_REQUEST_HANDLER]
		do
			create l_server.make (port)
				-- The bind address, at last handed to the thing that binds. Without
				-- this line `config.bind_address' is a contracted value nobody reads
				-- and the connector listens on every interface.
			l_server.set_bind_address (config.bind_address)
			l_server.set_max_concurrent_connections (Max_connections)
			server := l_server
			is_running := True
			last_error := Void
		ensure
			outcome: is_running xor (last_error /= Void)
			cleared_on_success: is_running implies last_error = Void
		end

	run
			-- Serve until the process ends (blocking on the caller's processor).
		require
			running: is_running
		do
			if attached server as s then
				s.start
			end
		end

	stop
		do
			is_running := False
			server := Void
		ensure
			stopped: not is_running
		end

feature -- Constants

	Max_connections: INTEGER = 64
			-- Members holding a long-poll at once, plus room to spare (approach.md S3).

feature {NONE} -- Implementation

	config: SERVER_CONFIG

	server: detachable SIMPLE_WEB_HANDLER_SERVER [CHAT_REQUEST_HANDLER]

invariant
	localhost_only: config.bind_address.same_string ("127.0.0.1")
	server_when_running: is_running = (server /= Void)

end
