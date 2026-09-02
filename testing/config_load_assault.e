note
	description: "[
		SERVER_CONFIG.make_from_file under assault (Phase 4 Task 5, D6): a
		missing, junk or hostile file is a set of named validation errors,
		never a crash - the defaults stand and every invariant holds; a
		valid file loads every setting it names. Files are written under
		testing/config_scratch, wiped by each test's own setup (and so by
		the next run, should an assault die mid-way). SERVER_APP's pure
		gates ride along: the password double-entry rule and the door
		factory whose door agrees with the configuration (M-G).
	]"
	author: "Larry Rix"

class
	CONFIG_LOAD_ASSAULT

inherit
	TEST_SET_BASE

feature -- Tests: files that do not parse

	test_config_missing_file_is_one_named_error
			-- No file: one error naming the path; defaults stand; nothing loaded.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (scratch_path ("absent"))
			assert ("not loaded", not c.is_loaded and not c.is_valid)
			assert ("one error", c.error_count = 1)
			assert ("names the file", c.validation_errors.first.has_substring ({STRING_32} "absent.toml"))
			assert_defaults_stand (c)
		end

	test_config_junk_file_is_one_named_error
			-- Unparsable text: one error naming the path; defaults stand.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (write_config ("junk", "[
				= nonsense without a key
				??? this is not TOML {{{
				]"))
			assert ("not loaded", not c.is_loaded and not c.is_valid)
			assert ("one error", c.error_count = 1)
			assert ("names the file", c.validation_errors.first.has_substring ({STRING_32} "junk.toml"))
			assert_defaults_stand (c)
		end

feature -- Tests: valid files

	test_config_minimal_file_loads
			-- One key loads; everything else keeps its default. An empty file is a valid empty document.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (write_config ("minimal", "[
				port = 9090
				]"))
			assert ("loaded", c.is_loaded and c.is_valid and c.error_count = 0)
			assert ("port taken", c.port = 9090)
			assert ("rest default", c.front_door_kind.same_string ({SERVER_CONFIG}.Door_none)
				and not c.ddns_enabled and c.participant_count = 0 and c.password_minimum = 8
				and c.message_characters = 4000)
			create c.make_from_file (write_config ("empty", ""))
			assert ("empty file is a valid empty document", c.is_loaded and c.is_valid)
			assert_defaults_stand (c)
		end

	test_config_full_file_loads_two_participants
			-- Every setting the class exposes, from one file, two participants deep.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (write_config ("full", "[
				port = 9443
				data_dir = "chat_data"
				front_door = "caddy"
				public_name = "chat.example.org"
				message_characters = 2000
				upload_bytes = 1048576
				ai_requests_per_hour = 9
				posts_per_minute = 12
				login_failures_per_10_minutes = 7
				session_days = 30
				password_minimum = 12

				[ddns]
				enabled = true
				provider = "duckdns"
				domains = "example"
				token = "abc123"
				interval_seconds = 600

				[[participants]]
				handle = "@claude"
				kind = "claude_code"
				engine = "D:/sandbox"
				bot_username = "claude_bot"
				display_name = "Claude"
				requests_per_hour = 3
				max_characters = 900
				timeout_seconds = 60
				query_shaper = "none"
				response_shaper = "plain"
				aliases = ["Claude:", "@cl"]
				allow_via = ["plain", "@qwen"]

				[[participants]]
				handle = "@bible"
				kind = "bible_tool"
				engine = "bible_repl.exe"
				bot_username = "bible_bot"
				display_name = "Bible"
				]"))
			assert ("loaded with nothing to explain - " + first_error_text (c), c.is_loaded and c.is_valid)
			assert ("server settings", c.port = 9443 and c.data_dir.same_string ({STRING_32} "chat_data"))
			assert ("database path under data_dir", c.database_path.ends_with ({STRING_32} "simple_chat.db"))
			assert ("caddy door", c.front_door_kind.same_string ({SERVER_CONFIG}.Door_caddy)
				and c.is_public and c.public_name.same_string ("chat.example.org"))
			assert ("limits", c.message_characters = 2000 and c.upload_bytes = 1048576
				and c.ai_requests_per_hour = 9 and c.posts_per_minute = 12
				and c.login_failures_per_10_minutes = 7 and c.session_days = 30 and c.password_minimum = 12)
			assert ("ddns", c.ddns_enabled and c.ddns_domains.same_string ("example")
				and c.ddns_token.same_string ("abc123") and c.ddns_interval_seconds = 600)
			assert ("two participants", c.participant_count = 2 and c.ai_enabled)
			assert ("first identity", attached c.participants.first as p1 and then
				(p1.handle.same_string ({STRING_32} "@claude")
				and p1.kind.same_string ({PARTICIPANT_CONFIG}.Kind_claude_code)
				and p1.working_directory.same_string ({STRING_32} "D:/sandbox")
				and p1.bot_username.same_string ("claude_bot")
				and p1.bot_display_name.same_string ({STRING_32} "Claude")))
			assert ("first refinements", attached c.participants.first as p2 and then
				(p2.requests_per_hour = 3 and p2.max_characters = 900 and p2.timeout_seconds = 60
				and p2.query_shaper.same_string ({STRING_32} "none")
				and p2.response_shaper.same_string ({STRING_32} "plain")
				and p2.has_alias ({STRING_32} "@CL") and p2.allows_via ({STRING_32} "@qwen")
				and p2.allows_via ({STRING_32} "plain")))
			assert ("aliases tracked config-wide, any case", c.has_participant_alias ({STRING_32} "Claude:")
				and not c.is_free_address ({STRING_32} "@cl"))
			assert ("second identity", attached c.participants.i_th (2) as p3 and then
				(p3.handle.same_string ({STRING_32} "@bible")
				and p3.kind.same_string ({PARTICIPANT_CONFIG}.Kind_bible_tool)
				and p3.executable.same_string ({STRING_32} "bible_repl.exe")
				and p3.alias_count = 0 and p3.requests_per_hour = 5))
		end

feature -- Tests: hostile files

	test_config_hostile_numbers_keep_defaults
			-- Out-of-range and mistyped values: each named, each default kept.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (write_config ("numbers", "[
				port = 99999
				password_minimum = 4
				message_characters = 0
				session_days = "many"
				upload_bytes = -5
				]"))
			assert ("refused", not c.is_loaded and not c.is_valid)
			assert ("port named", has_error_naming (c, "port"))
			assert ("password_minimum named", has_error_naming (c, "password_minimum"))
			assert ("message_characters named", has_error_naming (c, "message_characters"))
			assert ("session_days named", has_error_naming (c, "session_days"))
			assert ("upload_bytes named", has_error_naming (c, "upload_bytes"))
			assert_defaults_stand (c)
		end

	test_config_hostile_door_and_ddns
			-- A door without a hostname, a lone public_name, an unknown door,
			-- DDNS without its token, a foreign provider, a too-fast interval.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (write_config ("doorless", "[
				front_door = "caddy"
				]"))
			assert ("hostname demanded", not c.is_valid and has_error_naming (c, "public_name"))
			assert ("door stays closed", c.front_door_kind.same_string ({SERVER_CONFIG}.Door_none) and not c.is_public)
			create c.make_from_file (write_config ("lone_name", "[
				public_name = "chat.example.org"
				]"))
			assert ("lone public_name refused", not c.is_valid and has_error_naming (c, "public_name"))
			create c.make_from_file (write_config ("gate", "[
				front_door = "gate"
				]"))
			assert ("unknown door refused", not c.is_valid and has_error_naming (c, "front_door"))
			create c.make_from_file (write_config ("tokenless", "[
				[ddns]
				enabled = true
				domains = "example"
				]"))
			assert ("token demanded", not c.is_valid and has_error_naming (c, "ddns.token"))
			assert ("ddns stays off", not c.ddns_enabled)
			create c.make_from_file (write_config ("noip", "[
				[ddns]
				provider = "noip"
				]"))
			assert ("foreign provider refused", not c.is_valid and has_error_naming (c, "ddns.provider"))
			assert ("provider default stands", c.ddns_provider.same_string ({SERVER_CONFIG}.Provider_duckdns))
			create c.make_from_file (write_config ("hasty", "[
				[ddns]
				enabled = true
				domains = "example"
				token = "abc"
				interval_seconds = 30
				]"))
			assert ("interval refused", not c.is_valid and has_error_naming (c, "ddns.interval_seconds"))
			assert ("a broken block never enables ddns", not c.ddns_enabled and c.ddns_interval_seconds = 300)
		end

	test_config_hostile_participants
			-- Duplicate handles, aliases crossing handles (M-D7), a bad bot
			-- username, a missing engine: named, and the broken entry or alias is out.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (write_config ("twins", "[
				[[participants]]
				handle = "@claude"
				kind = "none"
				bot_username = "claude_bot"
				display_name = "Claude"

				[[participants]]
				handle = "@claude"
				kind = "none"
				bot_username = "other_bot"
				display_name = "Other"
				]"))
			assert ("duplicate handle named", not c.is_valid and has_error_naming (c, "participants[2].handle"))
			assert ("first entry alone stands", c.participant_count = 1)
			create c.make_from_file (write_config ("alias_takes_handle", "[
				[[participants]]
				handle = "@claude"
				kind = "none"
				bot_username = "claude_bot"
				display_name = "Claude"

				[[participants]]
				handle = "@qwen"
				kind = "none"
				bot_username = "qwen_bot"
				display_name = "Qwen"
				aliases = ["@claude"]
				]"))
			assert ("alias colliding with a handle named", not c.is_valid and has_error_naming (c, "participants[2].aliases"))
			assert ("entry stands without the alias", c.participant_count = 2
				and attached c.participants.i_th (2) as p and then p.alias_count = 0)
			create c.make_from_file (write_config ("handle_takes_alias", "[
				[[participants]]
				handle = "@claude"
				kind = "none"
				bot_username = "claude_bot"
				display_name = "Claude"
				aliases = ["@cl"]

				[[participants]]
				handle = "@cl"
				kind = "none"
				bot_username = "cl_bot"
				display_name = "Cl"
				]"))
			assert ("handle colliding with an alias named", not c.is_valid and has_error_naming (c, "participants[2].handle"))
			assert ("only the first entry stands", c.participant_count = 1)
			create c.make_from_file (write_config ("broken_identity", "[
				[[participants]]
				handle = "@qwen"
				kind = "ollama"
				bot_username = "Bad Bot"
				display_name = "Qwen"
				]"))
			assert ("bot_username named", not c.is_valid and has_error_naming (c, "participants[1].bot_username"))
			assert ("engine named", has_error_naming (c, "participants[1].engine"))
			assert ("broken entry is out", c.participant_count = 0)
		end

	test_config_bind_address_refused
			-- The invariant pins 127.0.0.1; a file that tries is told so.
		local
			c: SERVER_CONFIG
		do
			create c.make_from_file (write_config ("bind", "[
				bind_address = "0.0.0.0"
				]"))
			assert ("refused", not c.is_loaded and not c.is_valid)
			assert ("bind_address named", has_error_naming (c, "bind_address"))
			assert ("still localhost", c.bind_address.same_string ("127.0.0.1"))
		end

feature -- Tests: the server app's pure gates

	test_server_app_gates_and_door_match
			-- The password double-entry gate, the door factory, and the
			-- facade's door/config coherence query behind `start' (M-G).
		local
			l_app: SERVER_APP
			l_config, l_caddy_config: SERVER_CONFIG
			l_door: FRONT_DOOR
			l_server: SIMPLE_CHAT_SERVER
		do
			create l_app.make_idle
			assert ("matching long passwords pass", l_app.passwords_acceptable ({STRING_32} "open sesame 42", {STRING_32} "open sesame 42", 8))
			assert ("mismatch refused", not l_app.passwords_acceptable ({STRING_32} "open sesame 42", {STRING_32} "open sesame 43", 8))
			assert ("short refused", not l_app.passwords_acceptable ({STRING_32} "short", {STRING_32} "short", 8))
			create l_config.make_defaults
			l_door := l_app.new_front_door (l_config)
			assert ("no door for a local config", not l_door.is_public and attached {NO_FRONT_DOOR} l_door)
			create l_caddy_config.make_defaults
			l_caddy_config.set_front_door ({SERVER_CONFIG}.Door_caddy, "chat.example.org")
			l_door := l_app.new_front_door (l_caddy_config)
			assert ("caddy door for a doored config", l_door.is_public and attached {CADDY_FRONT_DOOR} l_door)
			create l_server.make
			assert ("unconfigured matches", l_server.is_door_matching_config)
			l_server.set_config (l_config).do_nothing
			assert ("local config with no door matches", l_server.is_door_matching_config)
			l_server.set_front_door (l_app.new_front_door (l_caddy_config)).do_nothing
			assert ("public door under a local config is a mismatch (M-G)", not l_server.is_door_matching_config)
			l_server.set_config (l_caddy_config).do_nothing
			assert ("public door under a public config matches", l_server.is_door_matching_config)
		end

	test_server_app_display_name_gate
			-- The gate `--create-user' puts in front of
			-- CHAT_SERVICE.create_user's `valid_display' precondition. A
			-- person typing at a console is not a programming error, so the
			-- application asks first and refuses politely; these are the
			-- cases it has to get right.
		local
			l_app: SERVER_APP
		do
			create l_app.make_idle

				-- Ordinary names pass.
			assert ("a plain name passes", l_app.is_acceptable_display_name ({STRING_32} "Nick"))
			assert ("a name with a space passes", l_app.is_acceptable_display_name ({STRING_32} "Larry Rix"))

				-- Non-ASCII is the whole point of reading the console as UTF-8:
				-- a Hebrew or Greek display name must be acceptable.
				--
				-- Written as CODE POINT ESCAPES, never as literal glyphs: this
				-- compiler reads a source file byte-for-byte, so a literal
				-- a Hebrew literal arrives as its raw UTF-8 bytes, and a 0x9E among them
				-- is a C1 control - which `is_forbidden_in_name' rightly
				-- refuses. The escapes say what is meant; the same convention
				-- CHAT_EVENT_KINDS.Bot_marker already uses.
			assert ("Hebrew passes", l_app.is_acceptable_display_name ({STRING_32} "%/1502/%/1513/%/1492/"))
			assert ("Greek passes", l_app.is_acceptable_display_name ({STRING_32} "%/935/%/961/%/953/%/963/%/964/%/972/%/962/"))

				-- Empty is refused; `create_member' substitutes the username
				-- before it ever reaches here.
			assert ("empty refused", not l_app.is_acceptable_display_name ({STRING_32} ""))

				-- The bot marker authenticates bots and is theirs alone (NEW-4):
				-- no human account may carry it, wherever it sits in the name.
			assert ("leading bot marker refused", not l_app.is_acceptable_display_name ({CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Claude"))
			assert ("embedded bot marker refused", not l_app.is_acceptable_display_name ({STRING_32} "Nick " + {CHAT_EVENT_KINDS}.Bot_marker))

				-- Control and bidi-override characters are refused: a display
				-- name is shown next to other people's, and an override would
				-- let one account paint itself as another (U+202E, 8238).
			assert ("a control character refused", not l_app.is_acceptable_display_name ({STRING_32} "Ni%/1/ck"))
			assert ("a bidi override refused", not l_app.is_acceptable_display_name ({STRING_32} "Nick%/8238/"))

				-- The query answers its own definition, so the application's
				-- gate and the service's precondition cannot drift apart.
			assert ("gate equals the rule", l_app.is_acceptable_display_name ({STRING_32} "Nick")
				= (create {CHAT_USER_RULES}).is_valid_human_display_name ({STRING_32} "Nick"))
		end

	test_server_app_decodes_utf8_console_bytes
			-- The READING PATH, fed real UTF-8 BYTES - not decimal escapes of
			-- the finished code points, which would prove nothing about
			-- decoding.
			--
			-- This is the defect the orchestrator found against the installed
			-- binary: with stdin redirected from a BOM-less UTF-8 file holding
			-- a four-letter Hebrew display name, --create-admin refused it as
			-- carrying control characters. The bytes D7 9C D7 90 D7 A8 D7 99
			-- were being taken one character per byte, and 0x9C is a C1
			-- control, so the naming rule refused them - correctly. The rule
			-- was right; the decoding never happened.
			--
			-- `decoded_text' is exactly what `line_read_text' applies to
			-- whatever `io.read_line' last read, so feeding it here drives the
			-- same path a redirected stdin and a code-page-65001 console both
			-- take. The console itself cannot be driven from a test.
		local
			l_app: SERVER_APP
			l_utf8: STRING_8
			l_text: STRING_32
		do
			create l_app.make_idle

				-- The Hebrew name as the eight UTF-8 bytes stdin delivers:
				-- D7 9C  D7 90  D7 A8  D7 99  (215/156, 215/144, 215/168, 215/153).
			create l_utf8.make (8)
			l_utf8.append_code (215); l_utf8.append_code (156)
			l_utf8.append_code (215); l_utf8.append_code (144)
			l_utf8.append_code (215); l_utf8.append_code (168)
			l_utf8.append_code (215); l_utf8.append_code (153)

			l_text := l_app.decoded_text (l_utf8)
			assert ("four code points, not eight bytes", l_text.count = 4)
			assert ("U+05DC lamed", l_text.code (1) = 1500)
			assert ("U+05D0 alef", l_text.code (2) = 1488)
			assert ("U+05E8 resh", l_text.code (3) = 1512)
			assert ("U+05D9 yod", l_text.code (4) = 1497)

				-- The whole point: the decoded name must now be ACCEPTED.
			assert ("the Hebrew name is accepted", l_app.is_acceptable_display_name (l_text))

				-- Greek too (Christos) = CE A7 CF 81 CE B9 CF 83 CF 84 CF 8C CF 82.
			create l_utf8.make (14)
			l_utf8.append_code (206); l_utf8.append_code (167)
			l_utf8.append_code (207); l_utf8.append_code (129)
			l_utf8.append_code (206); l_utf8.append_code (185)
			l_utf8.append_code (207); l_utf8.append_code (131)
			l_utf8.append_code (207); l_utf8.append_code (132)
			l_utf8.append_code (207); l_utf8.append_code (140)
			l_utf8.append_code (207); l_utf8.append_code (130)
			l_text := l_app.decoded_text (l_utf8)
			assert ("seven Greek code points", l_text.count = 7)
			assert ("keeps the tonos", l_text.code (6) = 972)
			assert ("the Greek name is accepted", l_app.is_acceptable_display_name (l_text))

				-- Plain ASCII is valid UTF-8 and must come back untouched.
			assert ("ASCII survives", l_app.decoded_text ({STRING_8} "Larry Rix").same_string ({STRING_32} "Larry Rix"))

				-- A trailing CR from a CRLF stream is dropped: `io.read_line'
				-- strips the newline but leaves the CR, and a name ending in
				-- one would be refused by the naming rule.
			assert ("trailing CR dropped", l_app.decoded_text ({STRING_8} "Nick%R").same_string ({STRING_32} "Nick"))

				-- Bytes that are NOT valid UTF-8 (Latin-1 "Jos%/233/") must not
				-- be mangled into nothing: the old byte-for-byte widening is
				-- exactly right there, and this is what a console left at a
				-- legacy code page delivers.
			create l_utf8.make (4)
			l_utf8.append_code (74); l_utf8.append_code (111)
			l_utf8.append_code (115); l_utf8.append_code (233)
			l_text := l_app.decoded_text (l_utf8)
			assert ("invalid UTF-8 widened byte-for-byte", l_text.count = 4 and l_text.code (4) = 233)

				-- REAL control characters must still be refused after decoding:
				-- decoding is not permission. U+0007 is a C0 control.
			assert ("a decoded control character is still refused",
				not l_app.is_acceptable_display_name (l_app.decoded_text ({STRING_8} "Ni%/7/ck")))

				-- Text that arrives ALREADY decoded (code points above 255) is
				-- returned unchanged rather than mistaken for bytes.
			l_text := l_app.decoded_text ({STRING_32} "%/1500/%/1488/")
			assert ("already-decoded text is left alone", l_text.count = 2 and l_text.code (1) = 1500)
		end

feature {NONE} -- Assertion support

	assert_defaults_stand (a_config: SERVER_CONFIG)
			-- Every default value stands untouched.
		do
			assert ("default port", a_config.port = 8080)
			assert ("localhost", a_config.bind_address.same_string ("127.0.0.1"))
			assert ("no door", a_config.front_door_kind.same_string ({SERVER_CONFIG}.Door_none)
				and not a_config.is_public and a_config.public_name.is_empty)
			assert ("default data dir", a_config.data_dir.same_string ({STRING_32} "data"))
			assert ("default limits", a_config.message_characters = 4000 and a_config.upload_bytes = 8388608
				and a_config.ai_requests_per_hour = 5 and a_config.posts_per_minute = 30
				and a_config.login_failures_per_10_minutes = 10 and a_config.session_days = 90
				and a_config.password_minimum = 8)
			assert ("no ddns", not a_config.ddns_enabled and a_config.ddns_interval_seconds = 300)
			assert ("no participants", a_config.participant_count = 0)
		end

	has_error_naming (a_config: SERVER_CONFIG; a_field: STRING_8): BOOLEAN
			-- Does some validation error begin "`a_field': "?
		local
			l_prefix: STRING_32
		do
			create l_prefix.make (a_field.count + 1)
			l_prefix.append_string_general (a_field)
			l_prefix.append_string_general (":")
			Result := across a_config.validation_errors as e some e.starts_with (l_prefix) end
		end

	first_error_text (a_config: SERVER_CONFIG): STRING_8
			-- The first error, for a failing assertion's tag.
		do
			if a_config.error_count > 0 then
				Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_config.validation_errors.first)
			else
				Result := "no error recorded"
			end
		end

feature {NONE} -- Scratch files

	Scratch_directory: STRING_8 = "testing/config_scratch"

	scratch_path (a_tag: STRING_8): STRING_32
			-- testing/config_scratch/<tag>.toml, wiped of any leftover.
		local
			l_directory: DIRECTORY
		do
			create l_directory.make (Scratch_directory)
			if not l_directory.exists then
				l_directory.recursive_create_dir
			end
			create Result.make (Scratch_directory.count + a_tag.count + 6)
			Result.append_string_general (Scratch_directory)
			Result.append_string_general ("/")
			Result.append_string_general (a_tag)
			Result.append_string_general (".toml")
			delete_file (Result)
		ensure
			named: Result.ends_with ({STRING_32} ".toml")
		end

	write_config (a_tag: STRING_8; a_text: STRING_8): STRING_32
			-- Write `a_text' to a fresh scratch file; its path.
		local
			l_file: PLAIN_TEXT_FILE
		do
			Result := scratch_path (a_tag)
			create l_file.make_create_read_write (Result)
			l_file.put_string (a_text)
			l_file.close
		end

	delete_file (a_path: READABLE_STRING_GENERAL)
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.delete
			end
		end

end
