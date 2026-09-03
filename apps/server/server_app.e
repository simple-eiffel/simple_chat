note
	description: "[
		The server executable: `simple_chat_server [config.toml]' serves;
		`simple_chat_server --create-admin <name> [config.toml]' creates
		the first admin (prompting for the password twice; refused when an
		admin exists, which CHAT_SERVICE.create_first_admin guarantees) -
		so no default password ever exists (intent-v2);
		`simple_chat_server --create-user <name> [config.toml]' mints an
		ordinary member the same way, prompting for a display name and the
		password twice, and refused until an admin exists. There is no
		self-registration: the host makes every account, which is what
		those two flags are for.
		`simple_chat_server --reset-password <name> [config.toml]' gives an
		EXISTING member a new password - prompting for it twice, and asking
		for no display name, because the account already has one. Every live
		session of that member is signed out, which is
		CHAT_SERVICE.reset_password's own postcondition and the point of the
		command: a password that leaked is taken away, not merely replaced.
		A username this room does not know, or one naming a bot (a bot has
		no password, only a token), is refused with a clear line and a
		NON-ZERO exit status, so the shipped wrapper can tell a refusal from
		a reset. Before this flag existed, a host who forgot the password had
		no way back in but to delete the database and lose the room.
		Any other `--flag'
		prints usage instead of being mistaken for a configuration path.

		NO PASSWORD EVER ECHOES. All three flags read every password - and
		the %"Again:%" confirmation - through SIMPLE_CONSOLE.read_masked_line_default (one dot per key, Backspace erases)
		(simple_console 1.1.0), which clears ENABLE_ECHO_INPUT for the read
		and restores the console mode on every exit path. Backspace still
		edits and Enter still ends the line. When standard input is
		REDIRECTED from a file or a pipe - which is how the installer's
		verification script and the shipped .cmd wrappers feed one in - the
		line is read the ordinary way and no console mode is touched: there
		is no terminal to hide it from. The display name is NOT hidden; it
		is read the ordinary echoing way, because a person has to see the
		name they are giving themselves.

		END OF INPUT BEFORE A PASSWORD is refused, changing nothing, with
		EXIT STATUS 1 - so a wrapper whose here-document ran short is told
		so instead of being handed a silent success. A line the person
		ended by pressing Enter alone is the EMPTY password, not end of
		input, and it is refused by `password_minimum' as it always was.

		Only the username travels in argv, and the rules confine it to
		a-z, 0-9 and underscore - so nothing non-ASCII is ever put on a
		Windows command line. The display name is typed at the console and
		decoded as UTF-8 (`line_read_text'), so a Hebrew or Greek name
		survives when the console is at code page 65001.

		CONCURRENCY: all three flags open their own connection to the same
		SQLite file. The store is WAL, which does admit a second process,
		but nothing here sets a busy timeout - so a write racing the
		running server's can come back SQLITE_BUSY and fail the creation.
		`--reset-password' carries the same exposure and a worse
		consequence: the new hash would not land, the old password would
		still let a person in, and the sessions the running server is
		holding would never be revoked - a reset announced on the console
		and absent from the room. Stop the server first. The shipped
		wrappers say so and check, this one included.
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
			elseif l_args.argument_count >= 2 and then l_args.argument (1).same_string ("--create-user") then
				if is_acceptable_username (l_args.argument (2)) then
					create_member (l_args.argument (2).to_string_8, admin_config_path_from (l_args))
				else
					print ("--create-user: the username must be 1..32 characters of a-z, 0-9 and underscore.%N")
					usage
				end
			elseif l_args.argument_count >= 2 and then l_args.argument (1).same_string ("--reset-password") then
				if is_acceptable_username (l_args.argument (2)) then
					reset_member_password (l_args.argument (2).to_string_8, admin_config_path_from (l_args))
				else
					print ("--reset-password: the username must be 1..32 characters of a-z, 0-9 and underscore.%N")
					usage
						-- Every `--reset-password' refusal leaves non-zero, this
						-- one included: a wrapper that cannot tell a refusal from
						-- a reset would tell the host the password had changed
						-- when it had not.
					exit_with_failure
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
			-- Prompt for a display name and the password twice, then create
			-- the first admin through CHAT_SERVICE.create_first_admin,
			-- against the same store `serve' would open.
			--
			-- The password does NOT echo: both entries are read with
			-- `hidden_line'. End of input before either one is refused,
			-- creating nothing, with exit status 1 (`exit_with_failure').
			--
			-- The display name is read as UTF-8 (`line_read_text') and
			-- defaults to the username, so the old behaviour is what an
			-- empty answer still gives.
		require
			acceptable: is_acceptable_username (a_username)
			path_given: not a_config_path.is_empty
		local
			l_config: SERVER_CONFIG
			l_display: STRING_32
			l_first, l_second: detachable STRING_32
			l_result: CHAT_RESULT [CHAT_USER]
			l_no_input: BOOLEAN
		do
			create l_config.make_from_file (a_config_path)
			if not l_config.is_valid then
				print ("--create-admin: the configuration is refused; fix it first:%N")
				print_errors (l_config)
			else
				print ("Display name (press Enter to use %"" + a_username + "%"): ")
				io.read_line
				l_display := line_read_text
				if l_display.is_empty then
					l_display := a_username.to_string_32
				end
				if not is_acceptable_display_name (l_display) then
					print ("--create-admin: that display name is refused (1..64 characters, no control or bidi-override characters, and it may not carry the bot marker); nothing was created.%N")
				else
					print ("Password (at least " + l_config.password_minimum.out + " characters, shown as dots): ")
					l_first := hidden_line
					if l_first /= Void then
						print ("Again: ")
						l_second := hidden_line
					end
					if attached l_first as l_typed and then attached l_second as l_again then
						if not passwords_acceptable (l_typed, l_again, l_config.password_minimum) then
							if not l_typed.same_string (l_again) then
								print ("--create-admin: the two entries do not match; nothing was created.%N")
							else
								print ("--create-admin: the password must be at least " + l_config.password_minimum.out + " characters; nothing was created.%N")
							end
						elseif attached new_service (l_config) as l_service then
							l_result := l_service.create_first_admin (a_username, l_display, l_typed)
							if l_result.is_success then
								print ("--create-admin: administrator %"" + a_username + "%" created.%N")
							elseif attached l_result.error as l_error then
								print ("--create-admin: refused - ")
								print_line_32 (l_error.message)
							end
							if l_service.store.is_open then
									-- Close before teardown: an open SQLite handle disposed during
									-- run-time shutdown segfaulted after every successful run.
								l_service.store.close
							end
						else
								-- No memory fallback here: an admin created in a memory
								-- store would vanish with this process (unlike the serving
								-- path, which must stay up and logs its fallback).
							print ("--create-admin: the store cannot be opened; nothing was created.%N")
						end
					else
							-- End of input, never a partial line (read_masked_line's own
							-- rule): a wrapper whose here-document ran short is told so,
							-- not handed a silent success.
						print ("--create-admin: no password was given (standard input ended before one arrived); nothing was created.%N")
						l_no_input := True
					end
				end
			end
			if l_no_input then
					-- No store was ever opened on this path, so there is nothing to
					-- close before leaving; `reset_member_password' dies after its
					-- close for exactly the reason there is none to make here.
				exit_with_failure
			end
		end

	create_member (a_username: READABLE_STRING_8; a_config_path: READABLE_STRING_GENERAL)
			-- Prompt for a display name and a password twice, then create an
			-- ORDINARY member through CHAT_SERVICE.create_user, against the
			-- same store `serve' would open. There is no self-registration:
			-- the host mints every account, which is why this exists.
			--
			-- Refused until an administrator exists, so the first account on a
			-- fresh database is always the admin's own (`--create-admin').
			-- The password does NOT echo, exactly as `create_admin' says: both
			-- entries come through `hidden_line'. End of input before either
			-- one is refused, creating nothing, with exit status 1 - taken
			-- AFTER the store is closed, which is the discipline
			-- `reset_member_password' set.
			--
			-- The display name is read as UTF-8 (see `line_read_text'), so a
			-- Hebrew or Greek name survives when the console is at code page
			-- 65001 - which the shipped console wrapper sets. It is never
			-- passed as a command-line argument: only the username, which the
			-- rules confine to a-z, 0-9 and underscore, travels in argv.
		require
			acceptable: is_acceptable_username (a_username)
			path_given: not a_config_path.is_empty
		local
			l_config: SERVER_CONFIG
			l_display: STRING_32
			l_first, l_second: detachable STRING_32
			l_result: CHAT_RESULT [CHAT_USER]
			l_no_input: BOOLEAN
		do
			create l_config.make_from_file (a_config_path)
			if not l_config.is_valid then
				print ("--create-user: the configuration is refused; fix it first:%N")
				print_errors (l_config)
			elseif attached new_service (l_config) as l_service then
				if not l_service.store.has_admin then
						-- An ordinary member before there is anyone to administer
						-- them is the wrong order, and it would quietly make the
						-- database's first account a non-admin one.
					print ("--create-user: there is no administrator yet; nothing was created.%N")
					print ("Create the first admin first:%N")
					print ("  simple_chat_server --create-admin <username> [simple_chat_server.toml]%N")
				else
					print ("Display name (press Enter to use %"" + a_username + "%"): ")
					io.read_line
					l_display := line_read_text
					if l_display.is_empty then
						l_display := a_username.to_string_32
					end
					if not is_acceptable_display_name (l_display) then
						print ("--create-user: that display name is refused (1..64 characters, no control or bidi-override characters, and it may not carry the bot marker); nothing was created.%N")
					else
						print ("Password (at least " + l_config.password_minimum.out + " characters, shown as dots): ")
						l_first := hidden_line
						if l_first /= Void then
							print ("Again: ")
							l_second := hidden_line
						end
						if attached l_first as l_typed and then attached l_second as l_again then
							if not passwords_acceptable (l_typed, l_again, l_config.password_minimum) then
								if not l_typed.same_string (l_again) then
									print ("--create-user: the two entries do not match; nothing was created.%N")
								else
									print ("--create-user: the password must be at least " + l_config.password_minimum.out + " characters; nothing was created.%N")
								end
							else
								l_result := l_service.create_user (a_username, l_display, l_typed, False)
								if l_result.is_success then
									print ("--create-user: member %"" + a_username + "%" created.%N")
								elseif attached l_result.error as l_error then
									print ("--create-user: refused - ")
									print_line_32 (l_error.message)
								end
							end
						else
								-- End of input, never a partial line. The store is OPEN on
								-- this path, so the exit waits until it is closed below.
							print ("--create-user: no password was given (standard input ended before one arrived); nothing was created.%N")
							l_no_input := True
						end
					end
				end
				if l_service.store.is_open then
						-- Close before teardown: an open SQLite handle disposed
						-- during run-time shutdown segfaulted after every
						-- successful run (the same reason `create_admin' closes).
					l_service.store.close
				end
			else
				print ("--create-user: the store cannot be opened; nothing was created.%N")
			end
			if l_no_input then
					-- AFTER the store is closed, exactly as `reset_member_password'
					-- dies: `exit_with_failure' leaves at once and would strand an
					-- open SQLite handle for the run-time shutdown to dispose.
				exit_with_failure
			end
		end

	reset_member_password (a_username: READABLE_STRING_8; a_config_path: READABLE_STRING_GENERAL)
			-- Prompt for a new password twice, then give it to the EXISTING
			-- member `a_username' through CHAT_SERVICE.reset_password,
			-- against the same store `serve' would open - which also signs
			-- out every live session that member holds (`sessions_revoked').
			--
			-- This is the way back in for a host who forgot the password.
			-- Until it existed the only remedy was to delete
			-- `data/simple_chat.db*' and lose the room with it.
			--
			-- No display name is asked for: the account already has one, and
			-- nothing here may quietly rename a person. The password does NOT
			-- echo, exactly as `create_admin' says: both entries come through
			-- `hidden_line'.
			--
			-- Refused, each time with a non-zero exit status and nothing
			-- changed: a configuration that will not load, a store that will
			-- not open, a username this room does not know, a username that
			-- names a BOT (a bot has no password to reset - revoke and
			-- reissue its token instead), END OF INPUT before a password
			-- arrived, two entries that differ, and an entry shorter than
			-- `password_minimum'.
			--
			-- The username arrives from argv, so the rules confine it to
			-- a-z, 0-9 and underscore and nothing non-ASCII is ever put on a
			-- Windows command line; the shipped wrapper lowercases what the
			-- host types before handing it over, as `create_user.cmd' does.
			--
			-- STOP THE SERVER FIRST. This opens the store directly, and
			-- nothing here sets a busy timeout: a write that races the
			-- running server's comes back SQLITE_BUSY, so the new hash never
			-- lands, the old password still works, and the sessions the
			-- running server is holding are never revoked. The wrapper
			-- checks for a running server and refuses; from a bare console
			-- the host has to know.
		require
			acceptable: is_acceptable_username (a_username)
			path_given: not a_config_path.is_empty
		local
			l_config: SERVER_CONFIG
			l_first, l_second: detachable STRING_32
			l_result: CHAT_RESULT [CHAT_USER]
			l_user: detachable CHAT_USER
			l_reset: BOOLEAN
		do
			create l_config.make_from_file (a_config_path)
			if not l_config.is_valid then
				print ("--reset-password: the configuration is refused; fix it first:%N")
				print_errors (l_config)
			elseif attached new_service (l_config) as l_service then
				l_user := l_service.store.user_by_username (a_username)
				if attached l_user as u then
					if not is_resettable_member (u) then
							-- A bot authenticates with a token, and its stored
							-- hash is empty by CHAT_USER's own invariant; there
							-- is no password here to reset.
						print ("--reset-password: %"" + a_username + "%" is a bot; a bot has no password, only a token. Revoke and reissue that token instead; nothing was changed.%N")
					else
						print ("New password for %"" + a_username + "%" (at least " + l_config.password_minimum.out + " characters, shown as dots): ")
						l_first := hidden_line
						if l_first /= Void then
							print ("Again: ")
							l_second := hidden_line
						end
						if attached l_first as l_typed and then attached l_second as l_again then
							if not passwords_acceptable (l_typed, l_again, l_config.password_minimum) then
								if not l_typed.same_string (l_again) then
									print ("--reset-password: the two entries do not match; nothing was changed.%N")
								else
									print ("--reset-password: the password must be at least " + l_config.password_minimum.out + " characters; nothing was changed.%N")
								end
							else
								l_result := l_service.reset_password (u, l_typed)
								if l_result.is_success then
									l_reset := True
									print ("--reset-password: the password for %"" + a_username + "%" was reset, and every live session that member had was signed out.%N")
								elseif attached l_result.error as l_error then
									print ("--reset-password: refused - ")
									print_line_32 (l_error.message)
								end
							end
						else
								-- End of input, never a partial line. `l_reset' stays False,
								-- so the store is closed and then this leaves with status 1 -
								-- the wrapper hears "nothing was changed", which is true.
							print ("--reset-password: no password was given (standard input ended before one arrived); nothing was changed.%N")
						end
					end
				else
					print ("--reset-password: this room has no member %"" + a_username + "%"; nothing was changed.%N")
					print ("Usernames are 1..32 characters of a-z, 0-9 and underscore - check the spelling, and note there are no capitals in one.%N")
				end
				if l_service.store.is_open then
						-- Close before teardown: an open SQLite handle disposed
						-- during run-time shutdown segfaulted after every
						-- successful run (the same reason `create_admin' closes),
						-- and `exit_with_failure' below leaves at once.
					l_service.store.close
				end
			else
				print ("--reset-password: the store cannot be opened; nothing was changed.%N")
			end
			if not l_reset then
				exit_with_failure
			end
		end

	usage
		do
			print ("simple_chat_server [simple_chat_server.toml]%N")
			print ("simple_chat_server --create-admin <username> [simple_chat_server.toml]%N")
			print ("simple_chat_server --create-user <username> [simple_chat_server.toml]%N")
			print ("simple_chat_server --reset-password <username> [simple_chat_server.toml]%N")
			print ("%N")
			print ("The two create flags ask for a display name, then for the password twice;%N")
			print ("--reset-password asks for the password twice and for no display name.%N")
			print ("NO PASSWORD ECHOES: it is read with simple_console.read_masked_line, which shows one dot per key and%N")
			print ("leaves Backspace and Enter working and puts the console mode back. Standard%N")
			print ("input redirected from a file or a pipe is read the ordinary way, so the%N")
			print ("shipped scripts still work. The display name is not hidden.%N")
			print ("End of input before a password changes nothing and leaves with status 1.%N")
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

	is_acceptable_display_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Would CHAT_SERVICE.create_user accept `a_name' as a display name?
			-- Asked BEFORE the call, so the precondition `valid_display' is
			-- discharged by this application rather than tripped by it: a
			-- person typing at a console is not a programming error.
		do
			Result := (create {CHAT_USER_RULES}).is_valid_human_display_name (a_name)
		ensure
			definition: Result = (create {CHAT_USER_RULES}).is_valid_human_display_name (a_name)
		end

	is_resettable_member (a_user: CHAT_USER): BOOLEAN
			-- Would CHAT_SERVICE.reset_password accept `a_user'?
			-- Asked BEFORE the call, so the preconditions `person' and
			-- `stored' are discharged by this application rather than
			-- tripped by it: a host who names the room's bot at the console
			-- has made a typing mistake, not a programming error.
		do
			Result := not a_user.is_bot and a_user.is_stored
		ensure
			definition: Result = (not a_user.is_bot and a_user.is_stored)
		end

	passwords_acceptable (a_first, a_second: READABLE_STRING_GENERAL; a_minimum: INTEGER): BOOLEAN
			-- The same entry twice, and long enough? (The pure gate `create_admin' applies.)
		do
			Result := a_first.same_string (a_second) and a_first.count >= a_minimum
		ensure
			definition: Result = (a_first.same_string (a_second) and a_first.count >= a_minimum)
		end

feature -- Text decoding

	decoded_text (a_raw: READABLE_STRING_GENERAL): STRING_32
			-- `a_raw' as text: the UTF-8 bytes decoded when that is what it
			-- holds, and widened byte-for-byte when it is not.
			--
			-- THE READING PATH, ISOLATED SO IT CAN BE ASSAULTED WITHOUT A
			-- CONSOLE. `line_read_text' is this function applied to whatever
			-- `io.read_line' last read; feeding the same bytes here proves the
			-- same behaviour, and the console cannot be driven from a test.
			--
			-- Every code point at 256 or above means the source already handed
			-- over decoded text, so it is returned unchanged. Otherwise the
			-- code points ARE bytes: rebuilt into a byte string and decoded
			-- when they form valid UTF-8. A redirected stdin and a
			-- code-page-65001 console both arrive here as bytes; a console
			-- left at a legacy code page produces bytes that are not valid
			-- UTF-8, and the byte-for-byte widening is then exactly right.
			--
			-- Note the bytes are rebuilt with `append_code' rather than taken
			-- from `to_string_8': the conversion depends on the dynamic type
			-- of what the runtime handed back, and this does not.
			--
			-- A trailing carriage return or space is dropped: `io.read_line'
			-- strips the newline but a CRLF stream leaves the CR, and a
			-- display name ending in one is refused by `is_forbidden_in_name'.
			-- Control characters INSIDE the text are left alone - refusing
			-- those is the naming rule's job, not this one's.
		local
			l_bytes: STRING_8
			i: INTEGER
			l_all_bytes: BOOLEAN
		do
			l_all_bytes := True
			from i := 1 until i > a_raw.count or not l_all_bytes loop
				if a_raw.code (i) > 255 then
					l_all_bytes := False
				end
				i := i + 1
			end
			if l_all_bytes then
				create l_bytes.make (a_raw.count)
				from i := 1 until i > a_raw.count loop
					l_bytes.append_code (a_raw.code (i))
					i := i + 1
				end
				if {UTF_CONVERTER}.is_valid_utf_8_string_8 (l_bytes) then
					Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (l_bytes)
				else
					Result := l_bytes.to_string_32
				end
			else
					-- `twin': never hand back the caller's own object, which
					-- the trimming below would then mutate under them.
				Result := a_raw.to_string_32.twin
			end
			from
			until
				Result.is_empty or else (Result.item (Result.count) /= '%R' and Result.item (Result.count) /= ' ')
			loop
				Result.remove_tail (1)
			end
		ensure
			no_trailing_blank: not Result.is_empty implies (Result.item (Result.count) /= '%R' and Result.item (Result.count) /= ' ')
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

	exit_with_failure
			-- Leave with exit status 1, having printed the reason already.
			--
			-- `--reset-password' is the one command here whose caller has to
			-- be able to tell a refusal from a success WITHOUT reading the
			-- console: `reset_password.cmd' tests `errorlevel' and prints
			-- either "the password was changed" or "nothing was changed",
			-- and a wrapper that always saw 0 would tell the host the
			-- password had changed when it had not.
			--
			-- `die' terminates without raising, so nothing has to be
			-- unwound; the store is already closed above, which is what
			-- keeps the disposal segfault `create_admin' documents away
			-- from this path too.
		local
			l_exceptions: EXCEPTIONS
		do
			create l_exceptions
			l_exceptions.die (1)
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

	hidden_line: detachable STRING_32
			-- One line of standard input, read WITHOUT echoing it when standard
			-- input is a real console, and read the ORDINARY way - console modes
			-- untouched - when it is redirected from a file or a pipe, which is
			-- how the shipped .cmd wrappers and the installer's verification
			-- script feed a password in. SIMPLE_CONSOLE decides which; nothing
			-- here has to know.
			--
			-- Void on END OF INPUT or on failure, NEVER a partial line. A line
			-- the person ended by pressing Enter alone is the EMPTY string, not
			-- Void, so a blank password and a missing one stay distinguishable:
			-- the first is refused by `password_minimum', the second by the
			-- callers' own "nothing was created/changed" line and exit status 1.
			--
			-- Read as UTF-8 on both paths, so a Hebrew or Greek password arrives
			-- as the code points it was typed as. PASSWORD_HASHER encodes those
			-- back to UTF-8 before hashing, so an ASCII password hashes exactly
			-- as it did under the old byte-for-byte `line_read', and a non-ASCII
			-- one now hashes the bytes that were actually typed rather than a
			-- double encoding of them.
			--
			-- WHY IT MATTERS: a `--create-admin' that reads a password with
			-- `io.read_line' leaves it in the console's scrollback and in any
			-- transcript of that session.
		local
			l_console: SIMPLE_CONSOLE
		do
			create l_console.make
			Result := l_console.read_masked_line_default
		end

	line_read_text: STRING_32
			-- What the last `io.read_line' read, DECODED AS UTF-8 when the
			-- bytes are valid UTF-8, and byte-for-byte otherwise.
			--
			-- Widening each byte to a character instead - which is what this
			-- feature did before `decoded_text' was pulled out of it, and what
			-- the now-deleted `line_read' did for the password - is wrong for a
			-- name a person reads: at code page 65001 the console hands over
			-- UTF-8, so a three-letter Hebrew name (U+05DE U+05E9 U+05D4)
			-- arrives as six bytes that widening would turn into six mojibake
			-- characters. The shipped console wrapper sets 65001; the fallback
			-- covers a console left at its default, where the bytes will not be
			-- valid UTF-8 and the old behaviour is exactly what is wanted.
			--
			-- A trailing carriage return is dropped: `io.read_line' strips the
			-- newline but a CRLF stream can leave the CR behind, and a display
			-- name ending in one would be refused by `is_forbidden_in_name'.
		do
			if attached io.last_string as l_line then
				Result := decoded_text (l_line)
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
