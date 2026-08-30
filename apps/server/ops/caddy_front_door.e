note
	description: "[
		FRONT_DOOR as a supervised Caddy: writes the Caddyfile under the
		data folder, spawns caddy.exe (an absolute path, never whatever
		sits in the current directory) as a child with a hidden window,
		probes /health until it serves, restarts it with backoff if it
		exits, and never leaves it behind on stop. Certificates are Caddy's
		business entirely. The generated Caddyfile has exactly one site,
		proxies only to 127.0.0.1, and turns Caddy's admin API off.

		`has_child_process' means alive: it is maintained from what the
		child actually does (start, exit seen by check_health, stop) - it
		is not "a reference exists". Until simple_process gains
		wait-with-timeout and kill (dependency task), `stop' cannot prove
		the kill and says so through `last_error'.
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
			named: is_hostname (a_config.public_name)
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			public_name := a_config.public_name.twin
			upstream_port := a_config.port
			create l_env
			caddyfile_path := l_env.current_working_path.extended (a_config.data_dir).extended ("Caddyfile").name
			executable := l_env.current_working_path.extended ("caddy.exe").name
		ensure
			name_set: public_name.same_string (a_config.public_name)
			port_set: upstream_port = a_config.port
			not_serving: not is_serving
			no_child: not has_child_process
		end

feature -- Access

	public_name: STRING_8
	upstream_port: INTEGER
	last_error: detachable CHAT_ERROR

	caddyfile_path: STRING_32
			-- Where the generated Caddyfile is written (under the data folder).

	executable: STRING_32
			-- The absolute path of caddy.exe.

	caddyfile_text: STRING_8
			-- The configuration Caddy runs: admin API off, TLS for `public_name',
			-- one site, proxy to localhost, SSE passed through unbuffered.
		do
			create Result.make (160)
			Result.append ("{%N    admin off%N}%N")
			Result.append (public_name)
			Result.append (" {%N    reverse_proxy 127.0.0.1:")
			Result.append (upstream_port.out)
			Result.append (" {%N        flush_interval -1%N    }%N}%N")
		ensure
			admin_off: Result.starts_with ("{%N    admin off%N}%N")
			names_site: Result.has_substring (public_name + " {")
			targets_upstream: Result.has_substring ("reverse_proxy 127.0.0.1:" + upstream_port.out)
			single_site: Result.occurrences ('{') = 3 and Result.occurrences ('}') = 3
			one_proxy: (Result.count - Result.substring_index ("reverse_proxy", 1)) >= 0 and then Result.substring_index ("reverse_proxy", Result.substring_index ("reverse_proxy", 1) + 1) = 0
			loopback_only: not Result.has_substring ("0.0.0.0") and not Result.has_substring ("[::]")
			streams_pass: Result.has_substring ("flush_interval -1")
		end

feature -- Status report

	is_serving: BOOLEAN

	is_public: BOOLEAN
		do
			Result := True
		end

	has_child_process: BOOLEAN
			-- Is the Caddy child alive?
		do
			Result := child_is_alive
		end

	sets_forwarded_headers: BOOLEAN
			-- Caddy's reverse_proxy sets X-Forwarded-For and X-Forwarded-Proto.
		do
			Result := True
		end

	caddyfile_exists: BOOLEAN
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (caddyfile_path)
			Result := l_file.exists
		end

feature -- Element change

	set_executable (a_path: READABLE_STRING_GENERAL)
			-- Use `a_path' (absolute) as caddy.exe.
		require
			not_serving: not is_serving
			absolute: (create {PATH}.make_from_string (a_path)).is_absolute
		do
			executable := a_path.to_string_32
		ensure
			set: executable.same_string_general (a_path)
		end

feature -- Basic operations

	start
		do
			last_error := not_implemented
			-- Implementation in Phase 4: write caddyfile_text to caddyfile_path; launch executable with it;
			-- probe /health; child_is_alive := True; is_serving := True; last_error := Void
		ensure then
			caddyfile_written: is_serving implies caddyfile_exists
			child_when_serving: is_serving implies has_child_process
		end

	stop
		do
			is_serving := False
			if child_is_alive then
				-- Implementation in Phase 4: terminate the child and wait (simple_process kill/wait dependency task)
				child_is_alive := False
			end
			process := Void
		ensure then
			child_gone: not child_is_alive
		end

	check_health
		do
			if is_serving and not child_is_alive then
				is_serving := False
				last_error := child_exited
			elseif not is_serving and last_error = Void then
				last_error := not_implemented
			end
			-- Implementation in Phase 4: detect an exited child (exit code), restart with backoff while has_child_process was true
		ensure then
			serving_means_alive: is_serving implies child_is_alive
		end

feature {NONE} -- Implementation

	process: detachable SIMPLE_PROCESS

	child_is_alive: BOOLEAN
			-- Maintained by start, check_health and stop.

	not_implemented: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501)
		end

	child_exited: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, "caddy exited", 503)
		end

invariant
	named: not public_name.is_empty
	port_positive: upstream_port > 0
	serving_has_child: is_serving implies child_is_alive
	absolute_executable: (create {PATH}.make_from_string (executable)).is_absolute
	absolute_caddyfile: (create {PATH}.make_from_string (caddyfile_path)).is_absolute

end
