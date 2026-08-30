note
	description: "[
		Finds the server the GUI should talk to (D-016, D-017). When the
		config prefers a local service, GET /health on the loopback port
		with a short timeout; if it answers, that is the endpoint. Else
		each configured server in order - the primary, then the standbys
		- and the first that answers wins. If none answers, the primary
		is returned anyway so the window can say "unreachable" and the
		poller can keep trying. Same client code either way: the endpoint
		is the only difference between the host's GUI and a friend's.
	]"
	author: "Larry Rix"

class
	SERVICE_LOCATOR

create
	make

feature {NONE} -- Initialization

	make (a_transport: HTTP_TRANSPORT)
		do
			transport := a_transport
		ensure
			set: transport = a_transport
			nothing_probed: probe_count = 0
		end

feature -- Access

	probe_count: INTEGER
			-- Health probes sent by the last `locate'.

	last_probe_status: INTEGER
			-- HTTP status of the last probe; 0 when none answered.

feature -- Status report

	found_alive: BOOLEAN
			-- Did the last `locate' end on a server that answered /health?

feature -- Basic operations

	locate (a_config: CLIENT_CONFIG): CHAT_ENDPOINT
		local
			l_url: detachable STRING_8
			l_is_local: BOOLEAN
		do
			probe_count := 0
			last_probe_status := 0
			found_alive := False
			if a_config.prefers_local and then is_alive (a_config.local_url) then
				l_url := a_config.local_url
				l_is_local := True
			else
				across a_config.server_urls as ic until l_url /= Void loop
					if is_alive (ic) then
						l_url := ic
					end
				end
			end
			found_alive := l_url /= Void
			if l_url = Void then
				if a_config.has_server then
					l_url := a_config.server_url
				else
					l_url := a_config.local_url
					l_is_local := True
				end
			end
			create Result.make (l_url, l_is_local)
		ensure
			local_when_alive: (a_config.prefers_local and probe_count = 1 and found_alive) implies Result.is_local
			configured_otherwise: (not Result.is_local) implies a_config.has_url (Result.base_url)
			never_remote_unasked: not a_config.has_server implies Result.is_local
			primary_when_all_dead: (not found_alive and a_config.has_server) implies Result.base_url.same_string (a_config.server_url)
			bounded_probes: probe_count <= a_config.server_urls.count + 1
		end

feature -- Validation (contract support)

	is_alive (a_base_url: READABLE_STRING_8): BOOLEAN
			-- Does GET `a_base_url'/health answer 2xx within `Probe_timeout_seconds'?
		require
			web_url: a_base_url.starts_with ("http://") or a_base_url.starts_with ("https://")
		local
			l_reply: HTTP_REPLY
			l_headers: HASH_TABLE [STRING_8, STRING_8]
		do
			create l_headers.make (1)
			l_headers.force ("application/json", "Accept")
			l_reply := transport.send ("GET", a_base_url + Health_path, l_headers, Void, Probe_timeout_seconds)
			probe_count := probe_count + 1
			last_probe_status := l_reply.status
			Result := l_reply.is_success
		ensure
			probed: probe_count = old probe_count + 1
			definition: Result = (last_probe_status >= 200 and last_probe_status <= 299)
		end

feature -- Constants

	Health_path: STRING_8 = "/health"
	Probe_timeout_seconds: INTEGER = 2

feature {NONE} -- Implementation

	transport: HTTP_TRANSPORT

invariant
	status_range: last_probe_status = 0 or (last_probe_status >= 100 and last_probe_status <= 599)
	probes_non_negative: probe_count >= 0

end
