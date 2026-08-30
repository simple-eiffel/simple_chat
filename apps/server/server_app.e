note
	description: "[
		The server executable: `simple_chat_server [config.toml]' serves;
		`simple_chat_server --create-admin <name>' creates the first admin
		(prompting for the password; refused when an admin exists) - so no
		default password ever exists (intent-v2). Warns when
		ANTHROPIC_API_KEY is set in its environment (RISK-016).
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
				create_admin (l_args.argument (2).to_string_32)
			elseif l_args.argument_count >= 1 and then l_args.argument (1).same_string ("--help") then
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
			print ("simple_chat_server: Phase 1 skeleton - nothing is served yet.%N")
			-- Implementation in Phase 4
		end

	create_admin (a_username: READABLE_STRING_GENERAL)
		require
			given: not a_username.is_empty
		do
			print ("simple_chat_server --create-admin: Phase 1 skeleton.%N")
			-- Implementation in Phase 4: prompt twice, refuse if an admin exists, create_user with is_admin
		end

	usage
		do
			print ("simple_chat_server [simple_chat_server.toml]%N")
			print ("simple_chat_server --create-admin <username>%N")
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
