note
	description: "[
		The server executable: `simple_chat_server [config.toml]' serves;
		`simple_chat_server --create-admin <name> [config.toml]' creates
		the first admin (prompting for the password twice; refused when an
		admin exists, which CHAT_SERVICE.create_first_admin guarantees) -
		so no default password ever exists (intent-v2). Any other `--flag'
		prints usage instead of being mistaken for a configuration path.
		Warns when ANTHROPIC_API_KEY is set in its environment (RISK-016):
		that key would shadow the Claude subscription login for every
		participant.

		A configuration that fails validation refuses to serve and prints
		every named field (D6). The door is assembled by kind:
		CADDY_FRONT_DOOR for "caddy", NO_FRONT_DOOR for "none";
		"eiffel" is refused as not supported yet.
	]"
	author: "Larry Rix"

class
	SERVER_APP

create
	make,
	make_idle

feature {NONE} -- Initialization

	make
		local
			l_args: ARGUMENTS_32
		do
			create l_args
			if l_args.argument_count >= 2 and then l_args.argument (1).same_string ("--create-admin") then
				if is_acceptable_username (l_args.argument (2)) then
					create_admin (l_args.argument (2).to_string_8, admin_config_path_from (l_args))
				else
					print ("--create-admin: the username must be 1..32 characters of a-z, 0-9 and underscore.%N")
					usage
				end
			elseif l_args.argument_count >= 1 and then l_args.argument (1).starts_with ("--") then
				usage
			else
				serve (config_path_from (l_args))
			end
		end

	make_idle
			-- Read no arguments and serve nothing: for the assault to reach the queries below.
		do
		end

feature -- Commands

	serve (a_config_path: READABLE_STRING_GENERAL)
			-- Load the configuration, assemble the server with the ops
			-- implementations of the door and DNS, start, and run.
		require
			path_given: not a_config_path.is_empty
		local
			l_config: SERVER_CONFIG
			l_server: SIMPLE_CHAT_SERVER
			l_logger: SIMPLE_LOGGER
			l_log: CHAT_LOG
			l_updater: DUCKDNS_UPDATER
		do
			if has_api_key_in_environment then
				print ("WARNING: ANTHROPIC_API_KEY is set in this environment; it is cleared for every claude -p child so the subscription login is used (RISK-016).%N")
			end
			create l_config.make_from_file (a_config_path)
			if not l_config.is_valid then
				print ("simple_chat_server: the configuration is refused:%N")
				print_errors (l_config)
			elseif l_config.front_door_kind.same_string ({SERVER_CONFIG}.Door_eiffel) then
				print ("simple_chat_server: front_door %"eiffel%" is not supported yet; use %"caddy%" or %"none%".%N")
			else
				create l_server.make
				create l_logger
				create l_log.make (l_logger)
				l_server.set_config (l_config).do_nothing
				l_server.set_log (l_log).do_nothing
				l_server.set_front_door (new_front_door (l_config)).do_nothing
				if l_config.ddns_enabled then
					create l_updater.make (l_config.ddns_domains, l_config.ddns_token, l_config.ddns_interval_seconds)
					l_server.set_dynamic_dns (l_updater).do_nothing
				end
				l_server.start
				if l_server.is_running then
					print ("simple_chat_server: serving on http://127.0.0.1:" + l_config.port.out + "/%N")
					if l_config.is_public then
						print ("simple_chat_server: public at https://" + l_config.public_name + "/%N")
					end
					l_server.run
				elseif attached l_server.last_error as l_error then
					print ("simple_chat_server: failed to start - ")
					print_line_32 (l_error.message)
				else
					print ("simple_chat_server: failed to start.%N")
				end
			end
		end

	create_admin (a_username: READABLE_STRING_8; a_config_path: READABLE_STRING_GENERAL)
			-- Prompt for the password twice and create the first admin
			-- through CHAT_SERVICE.create_first_admin, against the same
			-- store `serve' would open. The password echoes: plain Eiffel
			-- console input has no echo suppression - acceptable for v1.
		require
			acceptable: is_acceptable_username (a_username)
			path_given: not a_config_path.is_empty
		local
			l_config: SERVER_CONFIG
			l_first, l_second: STRING_32
			l_result: CHAT_RESULT [CHAT_USER]
		do
			create l_config.make_from_file (a_config_path)
			if not l_config.is_valid then
				print ("--create-admin: the configuration is refused; fix it first:%N")
				print_errors (l_config)
			else
				print ("WARNING: the password will echo on this console (no echo suppression in v1).%N")
				print ("Password (at least " + l_config.password_minimum.out + " characters): ")
				io.read_line
				l_first := line_read
				print ("Again: ")
				io.read_line
				l_second := line_read
				if not passwords_acceptable (l_first, l_second, l_config.password_minimum) then
					if not l_first.same_string (l_second) then
						print ("--create-admin: the two entries do not match; nothing was created.%N")
					else
						print ("--create-admin: the password must be at least " + l_config.password_minimum.out + " characters; nothing was created.%N")
					end
				elseif attached new_service (l_config) as l_service then
					l_result := l_service.create_first_admin (a_username, a_username, l_first)
					if l_result.is_success then
						print ("--create-admin: administrator %"" + a_username + "%" created.%N")
					elseif attached l_result.error as l_error then
						print ("--create-admin: refused - ")
						print_line_32 (l_error.message)
					end
				else
						-- No memory fallback here: an admin created in a memory
						-- store would vanish with this process (unlike the serving
						-- path, which must stay up and logs its fallback).
					print ("--create-admin: the store cannot be opened; nothing was created.%N")
				end
			end
		end

	usage
		do
			print ("simple_chat_server [simple_chat_server.toml]%N")
			print ("simple_chat_server --create-admin <username> [simple_chat_server.toml]%N")
		end

feature -- Status report

	has_api_key_in_environment: BOOLEAN
			-- Is ANTHROPIC_API_KEY set (non-empty) for this process?
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			Result := attached l_env.item ("ANTHROPIC_API_KEY") as v and then not v.is_empty
		end

	is_acceptable_username (a_name: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := a_name.is_valid_as_string_8 and then (create {CHAT_USER_RULES}).is_valid_username (a_name.to_string_8)
		end

	passwords_acceptable (a_first, a_second: READABLE_STRING_GENERAL; a_minimum: INTEGER): BOOLEAN
			-- The same entry twice, and long enough? (The pure gate `create_admin' applies.)
		do
			Result := a_first.same_string (a_second) and a_first.count >= a_minimum
		ensure
			definition: Result = (a_first.same_string (a_second) and a_first.count >= a_minimum)
		end

feature -- Factory

	new_front_door (a_config: SERVER_CONFIG): FRONT_DOOR
			-- The ops door for `a_config': CADDY_FRONT_DOOR for "caddy",
			-- NO_FRONT_DOOR otherwise ("eiffel" is refused before this).
		require
			valid: a_config.is_valid
			supported: not a_config.front_door_kind.same_string ({SERVER_CONFIG}.Door_eiffel)
		do
			if a_config.front_door_kind.same_string ({SERVER_CONFIG}.Door_caddy) then
				create {CADDY_FRONT_DOOR} Result.make (a_config)
			else
				create {NO_FRONT_DOOR} Result.make (a_config)
			end
		ensure
			door_matches_config: Result.is_public = a_config.is_public
		end

feature {NONE} -- Implementation

	new_service (a_config: SERVER_CONFIG): detachable CHAT_SERVICE
			-- A service over the same store `serve' uses: the SQLite file at
			-- `a_config.database_path' when the configuration came from a
			-- file, a memory store otherwise; Void when that store cannot open.
		require
			valid: a_config.is_valid
		local
			l_store: detachable CHAT_STORE
			l_sqlite: SQLITE_CHAT_STORE
			l_memory: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_logger: SIMPLE_LOGGER
			l_log: CHAT_LOG
			l_directory: DIRECTORY
		do
			if a_config.is_loaded and then not a_config.data_dir.is_empty then
				create l_directory.make (a_config.data_dir)
				if not l_directory.exists then
					l_directory.recursive_create_dir
				end
				create l_sqlite.make (a_config.database_path)
				l_sqlite.open
				if l_sqlite.is_open then
					l_store := l_sqlite
				end
			else
				create l_memory.make
				l_memory.open
				l_store := l_memory
			end
			if attached l_store as s then
				create l_bus.make
				create l_limits.make (3600)
				create l_logger
				create l_log.make (l_logger)
				create Result.make (s, l_bus, l_limits, a_config, l_log)
			end
		ensure
			open_when_built: attached Result as r implies r.store.is_open
		end

	print_errors (a_config: SERVER_CONFIG)
			-- Every validation error, one per line.
		do
			across a_config.validation_errors as ic loop
				print ("  - ")
				print_line_32 (ic)
			end
		end

	print_line_32 (a_text: READABLE_STRING_32)
			-- `a_text' as UTF-8, then a newline.
		do
			print ({UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text))
			print ("%N")
		end

	line_read: STRING_32
			-- What the last `io.read_line' read.
		do
			if attached io.last_string as l_line then
				Result := l_line.to_string_32
			else
				create Result.make_empty
			end
		end

	config_path_from (a_args: ARGUMENTS_32): STRING_32
		do
			if a_args.argument_count >= 1 and then not a_args.argument (1).is_empty then
				Result := a_args.argument (1).to_string_32
			else
				Result := Default_config_path
			end
		ensure
			given: not Result.is_empty
		end

	admin_config_path_from (a_args: ARGUMENTS_32): STRING_32
			-- The optional third argument of `--create-admin', else the default.
		do
			if a_args.argument_count >= 3 and then not a_args.argument (3).is_empty then
				Result := a_args.argument (3).to_string_32
			else
				Result := Default_config_path
			end
		ensure
			given: not Result.is_empty
		end

	Default_config_path: STRING_32 = "simple_chat_server.toml"

end
