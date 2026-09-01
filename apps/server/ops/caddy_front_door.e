note
	description: "[
		FRONT_DOOR as a supervised Caddy: writes the Caddyfile under the
		data folder, spawns `executable' (an absolute path, never whatever
		sits in the current directory) as a hidden-window child through
		SIMPLE_ASYNC_PROCESS, confirms the child survives a bounded settle
		wait, and never leaves it behind on stop: the child is killed and
		its exit is confirmed by a bounded wait before the reference is
		dropped (Issue 27). Certificates are Caddy's business entirely.
		The generated Caddyfile has exactly one site, proxies only to
		127.0.0.1, and turns Caddy's admin API off.

		`has_child_process' means alive: it is read from the child process
		handle itself, never from a remembered flag. `check_health' reports
		an exited child honestly - the exit code lands in `last_error' and
		`is_serving' drops - and it never resurrects a stopped door;
		restart with backoff is a later refinement. Tests drive the same
		supervision against a stand-in child (`set_arguments_text'),
		because caddy.exe is not required on a development machine.
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
			-- Is the Caddy child alive right now? Read from the process
			-- handle itself, never from a remembered flag (Issue 27).
		do
			Result := attached process as l_process and then l_process.is_running
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

feature {CHAT_TEST_BRIDGE} -- Test support

	set_arguments_text (a_text: READABLE_STRING_GENERAL)
			-- Launch the child with `a_text' instead of the caddy-shaped
			-- "run --config <caddyfile_path>": lets tests supervise a
			-- stand-in child on machines without caddy.exe.
		require
			not_serving: not is_serving
			text_given: not a_text.is_empty
		do
			custom_arguments := a_text.to_string_32
		ensure
			taken: attached custom_arguments as al_arguments and then al_arguments.same_string_general (a_text)
		end

	child_process_id: NATURAL_32
			-- The child's process id; 0 when there is no child. Lets tests
			-- kill the child behind the door's back.
		do
			if attached process as l_process and then l_process.is_started then
				Result := l_process.process_id
			end
		end

feature -- Basic operations

	start
			-- Write the Caddyfile, launch the child hidden, and call the
			-- door serving only once the child has survived a bounded
			-- settle wait. A missing executable, a failed launch or a
			-- child that exits at once are error results, never exceptions.
		local
			l_process: SIMPLE_ASYNC_PROCESS
		do
			last_error := Void
			if not executable_exists then
				last_error := missing_executable
			else
				write_caddyfile
				if caddyfile_exists then
					create l_process.make
					l_process.set_show_window (False)
					l_process.start (command_line)
					if l_process.was_started_successfully then
						if l_process.wait (Settle_milliseconds) = 1 then
								-- The child exited during the settle wait.
							last_error := exited_at_start (l_process.exit_code)
							l_process.close
						else
							process := l_process
							child_is_alive := True
							is_serving := True
						end
					else
						last_error := launch_failed (l_process.last_error)
						l_process.close
					end
				else
					last_error := caddyfile_unwritten
				end
			end
		ensure then
			caddyfile_written: is_serving implies caddyfile_exists
			child_when_serving: is_serving implies has_child_process
		end

	stop
			-- Kill the child and confirm it is gone before dropping the
			-- reference: `no_orphan' is proved by the dead process, not by
			-- forgetting it (Issue 27). Harmless without a child.
		do
			is_serving := False
			if attached process as l_process then
				if l_process.is_running then
					l_process.kill.do_nothing
					if l_process.wait (Kill_wait_milliseconds) /= 1 and then l_process.is_running then
							-- One more attempt before conceding.
						l_process.kill.do_nothing
						l_process.wait (Kill_wait_milliseconds).do_nothing
					end
				end
				if l_process.is_running then
						-- The wait could not confirm the exit: say so, and let
						-- `no_orphan' fail loudly rather than lie.
					last_error := kill_unconfirmed
				else
					l_process.close
					process := Void
				end
			end
			child_is_alive := False
		ensure then
			child_gone: not child_is_alive
		end

	check_health
			-- A live child keeps serving; a dead one is reported with its
			-- exit code and the door drops `is_serving' honestly. A stopped
			-- door stays stopped and explains itself.
		do
			if is_serving then
				if attached process as l_process then
					if not l_process.is_running then
						last_error := child_exited (l_process.exit_code)
						l_process.close
						process := Void
						child_is_alive := False
						is_serving := False
					end
				else
						-- Unreachable while serving; answer honestly anyway.
					last_error := door_stopped
					child_is_alive := False
					is_serving := False
				end
			elseif last_error = Void then
				last_error := door_stopped
			end
		ensure then
			serving_means_alive: is_serving implies child_is_alive
		end

feature {NONE} -- Implementation

	process: detachable SIMPLE_ASYNC_PROCESS
			-- The supervised child; attached only between a confirmed start
			-- and the confirmed exit or kill that ends it.

	child_is_alive: BOOLEAN
			-- The supervisor's belief, maintained by start, check_health and
			-- stop; `has_child_process' asks the process handle instead.

	custom_arguments: detachable STRING_32
			-- Stand-in arguments from `set_arguments_text'; Void in production.

	arguments_text: STRING_32
			-- What the child is launched with: caddy's own
			-- "run --config <caddyfile_path>" unless a test substituted a
			-- stand-in through `set_arguments_text'.
		do
			if attached custom_arguments as l_arguments then
				Result := l_arguments.twin
			else
				create Result.make (caddyfile_path.count + 16)
				Result.append ({STRING_32} "run --config ")
				Result.append (quoted (caddyfile_path))
			end
		ensure
			given: not Result.is_empty
		end

	command_line: STRING_32
			-- The full child command: the quoted executable and `arguments_text'.
		do
			create Result.make (executable.count + 32)
			Result.append (quoted (executable))
			Result.append_character (' ')
			Result.append (arguments_text)
		end

	quoted (a_path: READABLE_STRING_32): STRING_32
			-- `a_path' wrapped in double quotes (paths may hold spaces).
		do
			create Result.make (a_path.count + 2)
			Result.append_character ('%"')
			Result.append (a_path)
			Result.append_character ('%"')
		end

	executable_exists: BOOLEAN
			-- Is there a file at `executable'?
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (executable)
			Result := l_file.exists
		end

	write_caddyfile
			-- Write `caddyfile_text' to `caddyfile_path', creating the data
			-- folder when it is absent.
		local
			l_path: PATH
			l_directory: DIRECTORY
			l_file: PLAIN_TEXT_FILE
		do
			create l_path.make_from_string (caddyfile_path)
			if attached l_path.parent as l_parent then
				create l_directory.make_with_path (l_parent)
				if not l_directory.exists then
					l_directory.recursive_create_dir
				end
			end
			create l_file.make_with_name (caddyfile_path)
			l_file.create_read_write
			l_file.put_string (caddyfile_text)
			l_file.close
		end

	Settle_milliseconds: INTEGER = 1500
			-- How long a fresh child must survive before the door calls itself serving.

	Kill_wait_milliseconds: INTEGER = 2000
			-- How long `stop' waits to confirm one kill.

	missing_executable: CHAT_ERROR
		local
			l_message: STRING_32
		do
			create l_message.make (executable.count + 32)
			l_message.append ({STRING_32} "caddy executable not found: ")
			l_message.append (executable)
			create Result.make ({CHAT_ERROR}.Code_unavailable, l_message, 503)
		end

	launch_failed (a_detail: detachable READABLE_STRING_32): CHAT_ERROR
		local
			l_message: STRING_32
		do
			create l_message.make (64)
			l_message.append ({STRING_32} "caddy failed to launch")
			if attached a_detail as l_detail and then not l_detail.is_empty then
				l_message.append ({STRING_32} ": ")
				l_message.append (l_detail)
			end
			create Result.make ({CHAT_ERROR}.Code_unavailable, l_message, 503)
		end

	caddyfile_unwritten: CHAT_ERROR
		local
			l_message: STRING_32
		do
			create l_message.make (caddyfile_path.count + 40)
			l_message.append ({STRING_32} "the Caddyfile could not be written to ")
			l_message.append (caddyfile_path)
			create Result.make ({CHAT_ERROR}.Code_unavailable, l_message, 503)
		end

	exited_at_start (a_exit_code: INTEGER): CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, "caddy exited during startup (exit code " + a_exit_code.out + ")", 503)
		end

	child_exited (a_exit_code: INTEGER): CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, "caddy exited (exit code " + a_exit_code.out + ")", 503)
		end

	kill_unconfirmed: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, "the caddy child did not die within the kill wait", 503)
		end

	door_stopped: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, "the caddy front door is stopped", 503)
		end

invariant
	named: not public_name.is_empty
	port_positive: upstream_port > 0
	serving_has_child: is_serving implies child_is_alive
	absolute_executable: (create {PATH}.make_from_string (executable)).is_absolute
	absolute_caddyfile: (create {PATH}.make_from_string (caddyfile_path)).is_absolute

end
