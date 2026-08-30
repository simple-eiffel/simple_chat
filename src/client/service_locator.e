note
	description: "[
		Finds the server the GUI should talk to (D-016, D-017). When the
		config prefers a local service, GET /health on the loopback port
		with a short timeout; if it answers, that is the endpoint. Else
		each configured server in order - the primary, then the standbys
		- and the first that answers wins. If none answers, the primary
		is returned anyway so the window can say "unreachable" and the
		poller can keep trying; with no server configured at all, the
		local endpoint, never anything remote. Same client code either
		way: the endpoint is the only difference between the host's GUI
		and a friend's.

		Every candidate is a CHAT_ENDPOINT before it is probed, so the
		result is secure by construction and no path is concatenated
		outside `url_for'. `probe' is a command; `last_probe_alive' and
		`last_probe_status' say what it found.
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
			nothing_found: not last_probe_alive and not found_alive
		end

feature -- Access

	probe_count: INTEGER
			-- Health probes sent by the last `locate'.

	last_probe_status: INTEGER
			-- HTTP status of the last probe; 0 before any probe, or when it failed at the transport.

feature -- Status report

	found_alive: BOOLEAN
			-- Did the last `locate' end on a server that answered /health?

	last_probe_alive: BOOLEAN
			-- Did the last probe answer 2xx?

feature -- Basic operations

	locate (a_config: CLIENT_CONFIG): CHAT_ENDPOINT
			-- The endpoint to use: the first live candidate, else the primary, else the local service.
		local
			l_found: detachable CHAT_ENDPOINT
			l_candidate: CHAT_ENDPOINT
		do
			probe_count := 0
			last_probe_status := 0
			last_probe_alive := False
			if a_config.prefers_local then
				create l_candidate.make (a_config.local_url)
				probe (l_candidate)
				if last_probe_alive then
					l_found := l_candidate
				end
			end
			across a_config.server_urls as u until l_found /= Void loop
				create l_candidate.make (u)
				probe (l_candidate)
				if last_probe_alive then
					l_found := l_candidate
				end
			end
			found_alive := l_found /= Void
			if attached l_found as f then
				Result := f
			elseif a_config.has_server then
				create Result.make (a_config.server_url)
			else
				create Result.make (a_config.local_url)
			end
		ensure
			secure: Result.is_secure
			alive_means_answered: found_alive implies last_probe_alive
			local_when_alive: (a_config.prefers_local and probe_count = 1 and found_alive) implies Result.is_local
			configured_otherwise: (not Result.is_local) implies a_config.has_url (Result.base_url)
			never_remote_unasked: not a_config.has_server implies Result.is_local
			primary_when_all_dead: (not found_alive and a_config.has_server) implies Result.base_url.same_string (a_config.server_url)
			bounded_probes: probe_count <= a_config.server_urls.count + 1
			nothing_to_probe: (not a_config.prefers_local and not a_config.has_server) implies probe_count = 0
		end

	probe (a_endpoint: CHAT_ENDPOINT)
			-- GET /health at `a_endpoint' within `Probe_timeout_seconds'; `last_probe_alive' says whether it answered 2xx.
		local
			l_reply: HTTP_REPLY
			l_headers: HASH_TABLE [STRING_8, STRING_8]
		do
			create l_headers.make (1)
			l_headers.force ("application/json", "Accept")
			l_reply := transport.send ("GET", a_endpoint.url_for (Health_path), l_headers, Void, Probe_timeout_seconds)
			probe_count := probe_count + 1
			last_probe_status := l_reply.status
			last_probe_alive := l_reply.is_success
		ensure
			probed: probe_count = old probe_count + 1
			alive_definition: last_probe_alive = (last_probe_status >= 200 and last_probe_status <= 299)
		end

feature -- Constants

	Health_path: STRING_8 = "/health"
	Probe_timeout_seconds: INTEGER = 2

feature {NONE} -- Implementation

	transport: HTTP_TRANSPORT

invariant
	status_range: last_probe_status = 0 or (last_probe_status >= 200 and last_probe_status <= 599)
	alive_is_2xx: last_probe_alive = (last_probe_status >= 200 and last_probe_status <= 299)
	probes_non_negative: probe_count >= 0

end
