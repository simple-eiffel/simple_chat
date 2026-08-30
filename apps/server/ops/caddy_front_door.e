note
	description: "[
		FRONT_DOOR as a supervised Caddy: writes the Caddyfile, spawns
		caddy.exe as a child with a hidden window, probes /health until it
		serves, restarts it with backoff if it exits, and never leaves it
		behind on stop. Certificates are Caddy's business entirely.
	]"
	author: "Larry Rix"

class
	CADDY_FRONT_DOOR

inherit
	FRONT_DOOR

create
	make

feature {NONE} -- Initialization

	make (a_config: SERVER_CONFIG)
		require
			caddy_configured: a_config.front_door_kind.same_string ({SERVER_CONFIG}.Door_caddy)
			named: not a_config.public_name.is_empty
		do
			public_name := a_config.public_name.twin
			upstream_port := a_config.port
			caddyfile_path := "Caddyfile"
			executable := "caddy.exe"
		ensure
			name_set: public_name.same_string (a_config.public_name)
			port_set: upstream_port = a_config.port
			not_serving: not is_serving
		end

feature -- Access

	public_name: STRING_8
	upstream_port: INTEGER
	last_error: detachable CHAT_ERROR
	caddyfile_path: STRING_32
	executable: STRING_32

	caddyfile_text: STRING_8
			-- The configuration Caddy runs: TLS for `public_name', proxy to
			-- localhost, SSE passed through unbuffered.
		do
			create Result.make (128)
			Result.append (public_name)
			Result.append (" {%N    reverse_proxy 127.0.0.1:")
			Result.append (upstream_port.out)
			Result.append (" {%N        flush_interval -1%N    }%N}%N")
		ensure
			names_site: Result.starts_with (public_name)
			targets_upstream: Result.has_substring ("127.0.0.1:" + upstream_port.out)
			streams_pass: Result.has_substring ("flush_interval -1")
		end

feature -- Status report

	is_serving: BOOLEAN

	is_public: BOOLEAN
		do
			Result := True
		end

	has_child_process: BOOLEAN
		do
			Result := process /= Void
		end

	sets_forwarded_headers: BOOLEAN
			-- Caddy's reverse_proxy sets X-Forwarded-For and X-Forwarded-Proto.
		do
			Result := True
		end

feature -- Basic operations

	start
		do
			last_error := not_implemented
			-- Implementation in Phase 4: write caddyfile_text; launch; probe; is_serving := True
		end

	stop
		do
			is_serving := False
			process := Void
			-- Implementation in Phase 4: terminate the child and wait
		end

	check_health
		do
			if not is_serving then
				last_error := not_implemented
			end
			-- Implementation in Phase 4: restart an exited child with backoff
		end

feature {NONE} -- Implementation

	process: detachable SIMPLE_PROCESS

	not_implemented: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501)
		end

invariant
	named: not public_name.is_empty
	port_positive: upstream_port > 0

end
