note
	description: "[
		The HTTP face: routes on a SIMPLE_WEB_SERVER bound to 127.0.0.1,
		authentication of each request (Bearer token only - there is no
		browser and no cookie, intent-v3), and the client address behind
		the front door (X-Forwarded-For trusted only from localhost -
		DR-010). Every handler lives in CHAT_API and answers JSON. No EWF
		type appears here: simple_web only.
	]"
	author: "Larry Rix"

class
	CHAT_WEB_APP

create
	make

feature {NONE} -- Initialization

	make (a_service: CHAT_SERVICE; a_bus: EVENT_BUS; a_config: SERVER_CONFIG; a_log: CHAT_LOG)
		require
			valid_config: a_config.is_valid
		do
			service := a_service
			bus := a_bus
			config := a_config
			log := a_log
			create api.make (a_service, a_config)
		ensure
			set: service = a_service and bus = a_bus and config = a_config
			not_running: not is_running
		end

feature -- Access

	port: INTEGER
		do
			Result := config.port
		end

feature -- Status report

	is_running: BOOLEAN

feature -- Basic operations

	start
			-- Create the server on `port', register every route (06-INTERFACE-DESIGN).
		require
			not_running: not is_running
		do
			-- Implementation in Phase 4: create server.make (port); register routes; is_running := True
		ensure
			outcome: is_running xor (last_error /= Void)
		end

	run
			-- Serve until stopped (blocking); the application's main thread lives here.
		require
			running: is_running
		do
			-- Implementation in Phase 4: server.start
		end

	stop
		do
			is_running := False
			-- Implementation in Phase 4
		ensure
			stopped: not is_running
		end

	last_error: detachable CHAT_ERROR

feature -- Requests (contract support)

	authenticate_request (a_request: SIMPLE_WEB_SERVER_REQUEST): detachable CHAT_USER
			-- The user behind the Bearer token; Void when none, malformed or expired.
		do
			-- Implementation in Phase 4
		ensure
			active_if_attached: attached Result as u implies u.is_active
		end

	client_ip (a_request: SIMPLE_WEB_SERVER_REQUEST): STRING_8
			-- The peer address, or X-Forwarded-For when the peer is localhost (the door).
		do
			Result := "127.0.0.1"
			-- Implementation in Phase 4
		ensure
			given: not Result.is_empty
		end

	trusts_forwarded_headers (a_request: SIMPLE_WEB_SERVER_REQUEST): BOOLEAN
			-- Only when the immediate peer is 127.0.0.1 (DR-010).
		do
			-- Implementation in Phase 4
		end

	bearer_token (a_request: SIMPLE_WEB_SERVER_REQUEST): detachable STRING_8
			-- The 64-character token after "Bearer ", or Void.
		do
			if attached a_request.header ("Authorization") as h and then h.starts_with ("Bearer ") and then h.count = 7 + 64 then
				Result := h.substring (8, h.count).to_string_8
			end
		ensure
			shape: attached Result as t implies t.count = 64
		end

feature {NONE} -- Implementation

	service: CHAT_SERVICE
	bus: EVENT_BUS
	config: SERVER_CONFIG
	log: CHAT_LOG
	api: CHAT_API
	server: detachable SIMPLE_WEB_SERVER

invariant
	localhost_only: config.bind_address.same_string ("127.0.0.1")

end
