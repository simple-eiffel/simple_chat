note
	description: "[
		The server executable: `simple_chat_server [config.toml]' serves;
		`simple_chat_server --create-admin <name>' creates the first admin
		(prompting for the password twice; refused when an admin exists,
		which CHAT_SERVICE.create_first_admin guarantees) - so no default
		password ever exists (intent-v2). Any other `--flag' prints usage
		instead of being mistaken for a configuration path. Warns when
		ANTHROPIC_API_KEY is set in its environment (RISK-016): that key
		would shadow the Claude subscription login for every participant.
	]"
	author: "Larry Rix"

class
	SERVER_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			l_args: ARGUMENTS_32
		do
			create l_args
			if l_args.argument_count >= 2 and then l_args.argument (1).same_string ("--create-admin") then
				if is_acceptable_username (l_args.argument (2)) then
					create_admin (l_args.argument (2).to_string_8)
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

feature -- Commands

	serve (a_config_path: READABLE_STRING_GENERAL)
			-- Load the configuration, assemble the server with the ops
			-- implementations of the door and DNS, start, and run.
		require
			path_given: not a_config_path.is_empty
		do
			if has_api_key_in_environment then
				print ("WARNING: ANTHROPIC_API_KEY is set in this environment; it is cleared for every claude -p child so the subscription login is used (RISK-016).%N")
			end
			print ("simple_chat_server: Phase 1 skeleton - nothing is served yet.%N")
			-- Implementation in Phase 4: SERVER_CONFIG.make_from_file; refuse if not is_valid; facade with the ops door and DNS; start; run
		end

	create_admin (a_username: READABLE_STRING_8)
			-- Prompt for the password twice and create the first admin through CHAT_SERVICE.create_first_admin.
		require
			acceptable: is_acceptable_username (a_username)
		do
			print ("simple_chat_server --create-admin: Phase 1 skeleton.%N")
			-- Implementation in Phase 4: prompt twice, refuse a mismatch or a short password, create_first_admin
		end

	usage
		do
			print ("simple_chat_server [simple_chat_server.toml]%N")
			print ("simple_chat_server --create-admin <username>%N")
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

feature {NONE} -- Implementation

	config_path_from (a_args: ARGUMENTS_32): STRING_32
		do
			if a_args.argument_count >= 1 then
				Result := a_args.argument (1).to_string_32
			else
				Result := Default_config_path
			end
		ensure
			given: not Result.is_empty
		end

	Default_config_path: STRING_32 = "simple_chat_server.toml"

end
