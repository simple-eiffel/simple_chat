note
	description: "[
		The participants cluster under assault (Phase 1b): the handle and
		alias rules, the parser's boundary and `via' laws, the tool
		template's two gates and its disclosure law, the sandbox rules,
		the engines' timing contracts, the configuration's completeness,
		and the dispatcher's idempotence, cursors, restart and population -
		all on one processor, against a CHAT_API over the memory store.
		The Phase 4 engines run for real against stand-ins: ping.exe as
		the child (needs no shell and no stdin, and "127.0.0.1" passes
		bible's own reference gate), a scratch shape database bearing the
		real schema, and an Ollama client pointed at an unroutable
		loopback port - the suite never touches a live AI engine or the
		network, and the Claude engines are exercised up to (never
		through) the CLI call. Phase 4 adds the mention-anywhere rule and
		the memory window: a room built in the memory store, real messages
		posted through the service, and the dispatcher woken over them, so
		the window a participant is handed is the room's own history.
	]"
	author: "Larry Rix"

class
	PARTICIPANTS_ASSAULT

inherit
	TEST_SET_BASE

	CHAT_SHARED
		undefine
			default_create
		end

feature -- Rules and parsing

	test_handle_rules
		local
			r: PARTICIPANT_RULES
		do
			create r
			assert ("plain handle", r.is_valid_handle ({STRING_32} "@claude"))
			assert ("hyphen and digits", r.is_valid_handle ({STRING_32} "@tools-larry2"))
			assert ("underscore", r.is_valid_handle ({STRING_32} "@shape_tool"))
			assert ("mixed case refused", not r.is_valid_handle ({STRING_32} "@Claude"))
			assert ("no at sign refused", not r.is_valid_handle ({STRING_32} "claude"))
			assert ("bare at refused", not r.is_valid_handle ({STRING_32} "@"))
			assert ("blank refused", not r.is_valid_handle ({STRING_32} "@claude bot"))
			assert ("32 accepted", r.is_valid_handle ({STRING_32} "@abcdefghijabcdefghijabcdefghijab"))
			assert ("33 refused", not r.is_valid_handle ({STRING_32} "@abcdefghijabcdefghijabcdefghijabc"))
			assert ("non-ascii refused", not r.is_valid_handle ({STRING_32} "@%/1513/%/1500/"))
			assert ("colon alias", r.is_valid_alias ({STRING_32} "Claude:"))
			assert ("at alias", r.is_valid_alias ({STRING_32} "@robot"))
			assert ("one character refused", not r.is_valid_alias ({STRING_32} ":"))
			assert ("plain via", r.is_via_choice ({STRING_32} "plain"))
			assert ("handle via", r.is_via_choice ({STRING_32} "@qwen"))
			assert ("word via refused", not r.is_via_choice ({STRING_32} "train"))
		end

	test_prefix_spoof_and_boundary
		local
			p: ADDRESS_PARSER
		do
			create p.make (registry_with ({STRING_32} "@claude"))
			assert ("leading token is whole", p.leading_handle ({STRING_32} "@claudette hi").same_string ({STRING_32} "@claudette"))
			assert ("spoof not addressed", not p.is_addressed ({STRING_32} "@claudette hi"))
			assert ("case folded", p.is_addressed ({STRING_32} "@Claude hi"))
			assert ("comma boundary", attached p.parse ({STRING_32} "@Claude, what time is it") as q and then (q.text.same_string ({STRING_32} "what time is it") and q.handle.same_string ({STRING_32} "@claude")))
			assert ("colon boundary", attached p.parse ({STRING_32} "@claude: hi") as q2 and then q2.text.same_string ({STRING_32} "hi"))
			assert ("dot is no boundary", not p.is_addressed ({STRING_32} "@claude.hi"))
			assert ("mid-text handle is not an address", not p.is_addressed ({STRING_32} "ask @claude"))
			assert ("unknown handle", not p.is_addressed ({STRING_32} "@nobody hi"))
			assert ("empty is plain", not p.is_addressed ({STRING_32} "") and p.leading_handle ({STRING_32} "").is_empty)
			assert ("address of", p.address_of ({STRING_32} "@CLAUDE hi").same_string ({STRING_32} "@claude") and p.address_of ({STRING_32} "hi").is_empty)
		end

	test_handle_only_body_is_not_a_request
		local
			p: ADDRESS_PARSER
		do
			create p.make (registry_with ({STRING_32} "@claude"))
			assert ("bare handle is addressed", p.is_addressed ({STRING_32} "@claude"))
			assert ("but asks nothing", p.parse ({STRING_32} "@claude") = Void)
			assert ("blanks ask nothing", p.parse ({STRING_32} "@claude   ") = Void)
			assert ("comma asks nothing", p.parse ({STRING_32} "@claude,") = Void)
			assert ("only a via asks nothing", p.parse ({STRING_32} "@claude via plain") = Void)
			assert ("a word asks", attached p.parse ({STRING_32} "@claude hi") as q and then q.text.same_string ({STRING_32} "hi"))
		end

	test_via_parsing
		local
			p: ADDRESS_PARSER
		do
			create p.make (registry_with ({STRING_32} "@claude"))
			assert ("via train stays text", attached p.parse ({STRING_32} "@claude tell me about travelling via train") as q and then (q.via = Void and q.text.same_string ({STRING_32} "tell me about travelling via train")))
			assert ("via shaper", attached p.parse ({STRING_32} "@claude sum it up via @qwen") as q2 and then (attached q2.via as v and then v.same_string ({STRING_32} "@qwen")) and then q2.text.same_string ({STRING_32} "sum it up"))
			assert ("via plain, any case", attached p.parse ({STRING_32} "@claude Gen 1:1 VIA Plain") as q3 and then (attached q3.via as v3 and then v3.same_string ({STRING_32} "plain")) and then q3.text.same_string ({STRING_32} "Gen 1:1"))
			assert ("via alone is Void", p.via_of ({STRING_32} "hello") = Void and p.via_of ({STRING_32} "via") = Void)
			assert ("without via", p.without_via ({STRING_32} "sum it up  via  @qwen ").same_string ({STRING_32} "sum it up"))
		end

	test_registry_alias_resolution
		local
			r: PARTICIPANT_REGISTRY
			p: ADDRESS_PARSER
		do
			r := registry_with ({STRING_32} "@claude")
			r.register_alias ({STRING_32} "Claude:", {STRING_32} "@claude")
			r.register_alias ({STRING_32} "@robot", {STRING_32} "@claude")
			assert ("two aliases", r.alias_count = 2 and r.aliases_model.count = 2 and r.alias_names.count = 2)
			assert ("case folded", r.has_alias ({STRING_32} "CLAUDE:") and r.handle_of_alias ({STRING_32} "claude:").same_string ({STRING_32} "@claude"))
			assert ("alias is not a handle", r.find ({STRING_32} "@robot") = Void and not r.has ({STRING_32} "@robot"))
			create p.make (r)
			assert ("colon alias addresses", attached p.parse ({STRING_32} "Claude: what time is it") as q and then (q.handle.same_string ({STRING_32} "@claude") and q.text.same_string ({STRING_32} "what time is it")))
			assert ("at alias addresses", attached p.parse ({STRING_32} "@Robot, hi") as q2 and then (q2.handle.same_string ({STRING_32} "@claude") and q2.text.same_string ({STRING_32} "hi")))
			assert ("alias needs its colon", not p.is_addressed ({STRING_32} "Claude what time"))
			assert ("alias case folded in text", p.is_addressed ({STRING_32} "CLAUDE: hi"))
		end

	test_participant_config_completeness
		local
			c: PARTICIPANT_CONFIG
		do
			create c.make ({STRING_32} "@claude", {PARTICIPANT_CONFIG}.Kind_claude_code, "claude", {STRING_32} "Claude", {STRING_32} "data\participants\claude")
			assert ("complete", c.is_complete_for_kind and c.working_directory.same_string ({STRING_32} "data\participants\claude"))
			assert ("marked", c.marked_display_name.starts_with ({CHAT_EVENT_KINDS}.Bot_marker) and c.marked_display_name.ends_with ({STRING_32} "Claude"))
			assert ("defaults", c.requests_per_hour = 5 and c.max_characters = 1200 and c.timeout_seconds = 120)
			assert ("ollama needs a model", not c.is_complete ({PARTICIPANT_CONFIG}.Kind_ollama, "", "", "", "x"))
			assert ("ollama with a model", c.is_complete ({PARTICIPANT_CONFIG}.Kind_ollama, "", "", "qwen", ""))
			assert ("none needs nothing", c.is_complete ({PARTICIPANT_CONFIG}.Kind_none, "", "", "", ""))
			assert ("tools need their engine", not c.is_complete ({PARTICIPANT_CONFIG}.Kind_bible_tool, "", "", "", "") and not c.is_complete ({PARTICIPANT_CONFIG}.Kind_shape_tool, "", "", "", ""))
			c.add_alias ({STRING_32} "Claude:")
			assert ("alias folded", c.has_alias ({STRING_32} "CLAUDE:") and c.aliases_model.count = 1 and c.aliases_model.has ({STRING_32} "claude:"))
			c.add_allow_via ({STRING_32} "@Qwen")
			assert ("via folded", c.allows_via ({STRING_32} "@qwen") and c.allow_via_model.has ({STRING_32} "@qwen") and c.allow_via_count = 1)
			assert ("shaper names", c.is_known_shaper_name ({STRING_32} "none") and c.is_known_shaper_name ({STRING_32} "@qwen") and not c.is_known_shaper_name ({STRING_32} "qwen"))
			c.set_limits (3, 800, 60)
			assert ("limits", c.requests_per_hour = 3 and c.max_characters = 800 and c.timeout_seconds = 60)
			c.set_shapers ({STRING_32} "@qwen", {STRING_32} "none")
			assert ("shapers", c.query_shaper.same_string ({STRING_32} "@qwen") and c.is_complete_for_kind)
		end

feature -- Tools

	test_tool_gates_raw_and_shaped
		local
			t: MOCK_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
			evil, good: MOCK_SHAPER
		do
			t := mock_tool ({STRING_32} "@tool", {STRING_32} "In the beginning God created the heavens and the earth.")
			a := t.answer (request ({STRING_32} "Gen 1:1 | dir", Void))
			assert ("unsafe refused on the raw path", not a.is_success and t.runs = 0 and t.executed_model.is_empty)
			a := t.answer (request ({STRING_32} "  Gen 1:1 ", Void))
			assert ("safe text ran once", a.is_success and t.runs = 1 and t.executed_query.same_string ({STRING_32} "Gen 1:1") and t.executed_model.count = 2)
			assert ("reply echoes what ran", a.text.has_substring ({STRING_32} "Gen 1:1") and a.text.has_substring ({STRING_32} "In the beginning"))
			assert ("no false footer", not a.text.has_substring ({TOOL_PARTICIPANT}.Phrased_by_prefix) and not t.last_response_shaped)
			create evil.make ({STRING_32} "@evil", {STRING_32} "Gen 1:1 | dir")
			t.add_shaper (evil)
			t.set_query_shaper (evil)
			a := t.answer (request ({STRING_32} "what does genesis open with", Void))
			assert ("unsafe shaped output refused", not a.is_success and t.runs = 1 and t.last_shaped_query.same_string ({STRING_32} "Gen 1:1 | dir"))
			assert ("last run still the safe one", t.executed_query.same_string ({STRING_32} "Gen 1:1"))
			create good.make ({STRING_32} "@good", {STRING_32} "Gen 1:1")
			t.add_shaper (good)
			a := t.answer (request ({STRING_32} "what does genesis open with", {STRING_32} "@good"))
			assert ("via chooses the query shaper too", a.is_success and t.runs = 2 and t.executed_query.same_string ({STRING_32} "Gen 1:1"))
			assert ("via shaper phrases and is named", t.last_response_shaped and a.text.has_substring ({STRING_32} "phrased by @good"))
			a := t.answer (request ({STRING_32} "Gen 1:1", {STRING_32} "@nobody"))
			assert ("unknown via refused", not a.is_success and t.runs = 2)
			assert ("choices", t.allows_via ({STRING_32} "plain") and t.allows_via ({STRING_32} "@GOOD") and not t.allows_via ({STRING_32} "@nobody") and t.shapers_model.count = 3)
		end

	test_via_plain_disclosure_law
		local
			t: MOCK_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
			m: MOCK_SHAPER
		do
			t := mock_tool ({STRING_32} "@tool", {STRING_32} "In the beginning God created the heavens and the earth.")
			create m.make ({STRING_32} "@mock", {STRING_32} "It opens with God creating everything.")
			t.add_shaper (m)
			t.set_response_shaper (m)
			a := t.answer (request ({STRING_32} "Gen 1:1", Void))
			assert ("phrased and disclosed", a.is_success and t.last_response_shaped and a.text.has_substring ({STRING_32} "phrased by @mock") and a.text.has_substring ({STRING_32} "It opens with"))
			a := t.answer (request ({STRING_32} "Gen 1:1", {STRING_32} "plain"))
			assert ("via plain: raw and undisclosed", a.is_success and not t.last_response_shaped and not a.text.has_substring ({TOOL_PARTICIPANT}.Phrased_by_prefix) and a.text.has_substring ({STRING_32} "In the beginning"))
			a := t.answer (request ({STRING_32} "Gen 1:1", {STRING_32} "@mock"))
			assert ("via the shaper", a.is_success and t.last_response_shaped)
			m.set_should_fail (True)
			a := t.answer (request ({STRING_32} "Gen 1:1", Void))
			assert ("shaper failure is the answer's error", not a.is_success and attached t.last_shaper_error as e and then a.error = e)
			assert ("effective shapers", t.effective_response_shaper (request ({STRING_32} "x", {STRING_32} "plain")).cost_tier = {SHAPER}.Tier_none and t.effective_response_shaper (request ({STRING_32} "x", Void)) = m)
		end

	test_tool_reply_limits
		local
			t: MOCK_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
			l_long: STRING_32
			l_args: ARRAYED_LIST [STRING_32]
			l_output: STRING_32
		do
			t := mock_tool ({STRING_32} "@tool", {STRING_32} "short")
			a := t.answer (create {PARTICIPANT_REQUEST}.make_addressed (7, {STRING_32} "Nick", {STRING_32} "Gen 1:1", 1, {STRING_32} "main", 100, Void))
			assert ("limit under the minimum refused", not a.is_success and t.runs = 0)
			create l_long.make_filled ('a', 180)
			a := t.answer (create {PARTICIPANT_REQUEST}.make_addressed (7, {STRING_32} "Nick", l_long, 1, {STRING_32} "main", 200, Void))
			assert ("echo that cannot fit refused", not a.is_success and t.runs = 0)
			create l_long.make_filled ('b', 70000)
			t := mock_tool ({STRING_32} "@tool", l_long)
			create l_args.make (2)
			l_args.extend ({STRING_32} "Gen")
			l_args.extend ({STRING_32} "1:1")
			l_output := t.run_tool (l_args)
			assert ("output cut at the maximum", l_output.count = {TOOL_PARTICIPANT}.Output_maximum and t.runs = 1 and t.executed_model.count = 2)
			a := t.answer (request ({STRING_32} "Gen 1:1", Void))
			assert ("reply cut to the room's limit", a.is_success and a.text.count <= 400 and a.text.starts_with ({STRING_32} "> Gen 1:1"))
		end

	test_bible_and_shape_allowlists
		local
			b: BIBLE_TOOL_PARTICIPANT
			s: SHAPE_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
		do
				-- A name certainly absent: a bare "bible.exe" is found through
				-- the PATH search on a machine that has simple_scholar
				-- installed, and then the child ANSWERS - this assault pins
				-- the missing-engine path, so the name must miss everywhere.
			create b.make ({STRING_32} "@tools-larry", bot ("tools", {STRING_32} "Tools"), {STRING_32} "no_such_bible_probe.exe", 1200, 30)
			assert ("verse", b.accepts ({STRING_32} "Gen 1:1") and b.arguments_of ({STRING_32} "Gen 1:1").count = 2)
			assert ("range with a book number", b.accepts ({STRING_32} "1 John 3:16-18"))
			assert ("version prefix", b.accepts ({STRING_32} "kjv Ps 23"))
			assert ("allowed commands", b.accepts ({STRING_32} "/define H1254") and b.accepts ({STRING_32} "/versions") and b.accepts ({STRING_32} "/search bara"))
			assert ("closed set is closed", b.Allowed_commands.count = 18)
			assert ("state changers refused", not b.accepts ({STRING_32} "/reload") and not b.accepts ({STRING_32} "/cache clear")
				and not b.accepts ({STRING_32} "/quit") and not b.accepts ({STRING_32} "/default kjv")
				and not b.accepts ({STRING_32} "/load kjv") and not b.accepts ({STRING_32} "/repl") and not b.accepts ({STRING_32} "/exit"))
			assert ("unknown command refused", not b.accepts ({STRING_32} "/lex H7225") and not b.accepts ({STRING_32} "/research why"))
			assert ("pipe refused", not b.accepts ({STRING_32} "Gen 1:1 | dir"))
			assert ("option refused", not b.accepts ({STRING_32} "-rf"))
			assert ("empty refused", not b.accepts ({STRING_32} ""))
			assert ("two words after a command refused", not b.accepts ({STRING_32} "/define a b"))
			assert ("no digit is no reference", not b.accepts ({STRING_32} "Genesis"))
			assert ("command line shape", b.command_line_of (b.arguments_of ({STRING_32} "Gen 1:1")).same_string ("no_such_bible_probe.exe Gen 1:1"))
			a := b.answer (request ({STRING_32} "Gen 1:1", Void))
			assert ("missing engine says nothing, honestly", not a.is_success and b.runs = 1 and b.executed_query.same_string ({STRING_32} "Gen 1:1"))
			create s.make ({STRING_32} "@shape-larry", bot ("shape", {STRING_32} "Shape"), {STRING_32} "shape.db", 1200, 30)
			assert ("slug", s.accepts ({STRING_32} "beachhead_that_moves") and s.is_slug ({STRING_32} "a1"))
			assert ("not a slug", not s.accepts ({STRING_32} "Beachhead") and not s.accepts ({STRING_32} "a b") and not s.accepts ({STRING_32} ""))
			a := s.answer (request ({STRING_32} "beachhead_that_moves", Void))
			assert ("missing database is an error", not a.is_success and s.runs = 1)
		end

	test_metacharacter_law
			-- NEW-2: the base law of every tool refuses each shell
			-- metacharacter, whitespace, controls and options in any single
			-- argument, and the sanctioned joining is program + words with
			-- single spaces.
		local
			t: MOCK_TOOL_PARTICIPANT
			l_bad: STRING_32
			i: INTEGER
			c: CHARACTER_8
		do
			t := mock_tool ({STRING_32} "@tool", {STRING_32} "out")
			from i := 1 until i > {TOOL_PARTICIPANT}.Forbidden_argument_characters.count loop
				c := {TOOL_PARTICIPANT}.Forbidden_argument_characters [i]
				l_bad := {STRING_32} "a"
				l_bad.append_character (c.to_character_32)
				l_bad.append ({STRING_32} "b")
				assert ("metacharacter refused: " + c.out, not t.is_safe_argument (l_bad))
				i := i + 1
			end
			assert ("all seventeen probed", {TOOL_PARTICIPANT}.Forbidden_argument_characters.count = 17)
			assert ("blank refused", not t.is_safe_argument ({STRING_32} "a b"))
			assert ("control refused", not t.is_safe_argument ({STRING_32} "a%Tb"))
			assert ("option refused", not t.is_safe_argument ({STRING_32} "-x"))
			assert ("empty refused", not t.is_safe_argument ({STRING_32} ""))
			assert ("plain words accepted", t.is_safe_argument ({STRING_32} "Gen") and t.is_safe_argument ({STRING_32} "1:1") and t.is_safe_argument ({STRING_32} "/define"))
			assert ("request splits to words", t.arguments_of ({STRING_32} "  Gen 1:1  ").count = 2 and t.accepts ({STRING_32} "Gen 1:1"))
			assert ("one bad word gates all", t.arguments_of ({STRING_32} "Gen 1:1 | dir").is_empty and t.arguments_of ({STRING_32} "Gen 1:1 $x").is_empty)
			assert ("command line is program plus words", t.command_line_of (t.arguments_of ({STRING_32} "Gen 1:1")).same_string ("mock.exe Gen 1:1"))
		end

feature -- Sandboxes

	test_image_path_rules
		local
			a: PARTICIPANT_ANSWER
		do
			create a.make_success ({STRING_32} "here", {STRING_32} "shots/2026/x.jpg")
			assert ("relative image kept", attached a.image_path as p and then p.same_string ({STRING_32} "shots/2026/x.jpg"))
			assert ("simple name", a.is_safe_image_path ({STRING_32} "out.png") and a.is_safe_image_path ({STRING_32} "OUT.PNG"))
			assert ("drive refused", not a.is_safe_image_path ({STRING_32} "C:\Users\x\Pictures\x.png"))
			assert ("parent refused", not a.is_safe_image_path ({STRING_32} "../x.png"))
			assert ("unc refused", not a.is_safe_image_path ({STRING_32} "\\server\share\x.png"))
			assert ("root refused", not a.is_safe_image_path ({STRING_32} "/etc/x.png"))
			assert ("not an image refused", not a.is_safe_image_path ({STRING_32} "x.exe") and not a.is_safe_image_path ({STRING_32} "x.png.exe"))
			assert ("empty refused", not a.is_safe_image_path ({STRING_32} ""))
			assert ("too long refused", not a.is_safe_image_path (create {STRING_32}.make_filled ('a', 197) + {STRING_32} ".png"))
			assert ("200 accepted", a.is_safe_image_path (create {STRING_32}.make_filled ('a', 196) + {STRING_32} ".png"))
			assert ("device names refused", not a.is_safe_image_path ({STRING_32} "CON.png") and not a.is_safe_image_path ({STRING_32} "nul.jpg")
				and not a.is_safe_image_path ({STRING_32} "COM1.png") and not a.is_safe_image_path ({STRING_32} "shots/PRN.png")
				and not a.is_safe_image_path ({STRING_32} "aux.tar.png") and not a.is_safe_image_path ({STRING_32} "lpt9.PNG"))
			assert ("device lookalikes kept", a.is_safe_image_path ({STRING_32} "CONX.png") and a.is_safe_image_path ({STRING_32} "null.png")
				and a.is_safe_image_path ({STRING_32} "com10.png") and a.is_safe_image_path ({STRING_32} "lpt0.png"))
		end

	test_image_path_outside_sandbox_refused
		local
			a: PARTICIPANT_ANSWER
			l_tried, l_created: BOOLEAN
		do
			if not l_tried then
				l_tried := True
				create a.make_success ({STRING_32} "here", {STRING_32} "C:\Users\x\Pictures\x.png")
				l_created := True
			end
			assert ("an image path outside the sandbox is refused by the precondition", not l_created)
		rescue
			if l_tried and not l_created then
				retry
			end
		end

	test_claude_sandbox_rule
		local
			c: CLAUDE_CODE_CLIENT
			p: CLAUDE_CODE_PARTICIPANT
			l_data: STRING_32
		do
			create c.make
			l_data := {STRING_32} "C:\Users\Public\sc_chat_probe_ok\data"
			create p.make ({STRING_32} "@claude", bot ("claude", {STRING_32} "Claude"), c,
				l_data, l_data + {STRING_32} "\participants\claude", 1200, 120)
			assert ("sandboxed", p.tools_disabled and p.is_sandbox_directory (p.working_directory))
			assert ("client pinned", c.working_directory.same_string (p.working_directory))
			assert ("client stripped", c.tools_disabled and c.strict_mcp_config and attached c.setting_sources as ss and then ss.is_empty)
			assert ("client timed", c.timeout_seconds = 120)
			assert ("vault refused", not p.is_sandbox_directory_for ({STRING_32} "C:\Users\LJR19\OneDrive\Documents\Obsidian Vault\Scholars\participants\claude",
				{STRING_32} "C:\Users\LJR19\OneDrive\Documents\Obsidian Vault\Scholars", {STRING_32} "@claude"))
			assert ("relative refused", not p.is_sandbox_directory_for ({STRING_32} "data\participants\claude", {STRING_32} "data", {STRING_32} "@claude"))
			assert ("dot dot segment refused", not p.is_sandbox_directory_for (l_data + {STRING_32} "\participants\x\..\claude", l_data, {STRING_32} "@claude"))
			assert ("another handle's directory refused", not p.is_sandbox_directory_for (l_data + {STRING_32} "\participants\qwen", l_data, {STRING_32} "@claude"))
			assert ("no participants segment refused", not p.is_sandbox_directory_for (l_data + {STRING_32} "\members\claude", l_data, {STRING_32} "@claude"))
			assert ("outside the data dir refused", not p.is_sandbox_directory_for ({STRING_32} "C:\Users\Public\sc_chat_probe_other\data\participants\claude", l_data, {STRING_32} "@claude"))
			assert ("forward slashes and a trailing separator", p.is_sandbox_directory_for ({STRING_32} "C:/Users/Public/sc_chat_probe_ok/data/participants/claude/", l_data, {STRING_32} "@claude"))
			assert ("no sessions yet", p.sessions_model.is_empty and p.session_of (1) = Void)
			p.remember_session (1, {STRING_32} "sess-1")
			p.remember_session (2, {STRING_32} "sess-2")
			p.remember_session (1, {STRING_32} "sess-1b")
			assert ("per room", attached p.session_of (1) as s1 and then s1.same_string ({STRING_32} "sess-1b"))
			assert ("other room kept", attached p.session_of (2) as s2 and then s2.same_string ({STRING_32} "sess-2"))
			assert ("two rooms", p.sessions_model.count = 2)
		end

	test_claude_sandbox_memory_files
			-- The ancestor walk (Issue 33): a clean temp tree is a sandbox;
			-- the same tree with a CLAUDE.md planted two levels above the
			-- sandbox is not. Planted under the public scratch area, deleted
			-- after.
		local
			c: CLAUDE_CODE_CLIENT
			p: CLAUDE_CODE_PARTICIPANT
			l_data, l_sandbox: STRING_32
			l_dir: DIRECTORY
			l_file: RAW_FILE
		do
			create c.make
			create p.make ({STRING_32} "@claude", bot ("claude", {STRING_32} "Claude"), c,
				{STRING_32} "C:\Users\Public\sc_chat_probe_ok\data",
				{STRING_32} "C:\Users\Public\sc_chat_probe_ok\data\participants\claude", 1200, 120)
			l_data := {STRING_32} "C:\Users\Public\sc_chat_probe_bad\data"
			l_sandbox := l_data + {STRING_32} "\participants\claude"
			assert ("clean tree accepted", p.is_sandbox_directory_for (l_sandbox, l_data, {STRING_32} "@claude") and not p.has_memory_files_above (l_sandbox))
			create l_dir.make (l_data)
			l_dir.recursive_create_dir
			create l_file.make_with_name (l_data + {STRING_32} "\CLAUDE.md")
			l_file.create_read_write
			l_file.put_string ("planted")
			l_file.close
			assert ("planted memory two levels up refused", p.has_memory_files_above (l_sandbox)
				and not p.is_sandbox_directory_for (l_sandbox, l_data, {STRING_32} "@claude"))
			l_file.delete
			assert ("clean again once removed", not p.has_memory_files_above (l_sandbox))
			create l_dir.make ({STRING_32} "C:\Users\Public\sc_chat_probe_bad")
			if l_dir.exists then
				l_dir.recursive_delete
			end
		end

	test_claude_vault_directory_refused
		local
			c: CLAUDE_CODE_CLIENT
			p: CLAUDE_CODE_PARTICIPANT
			l_tried, l_created: BOOLEAN
		do
			if not l_tried then
				l_tried := True
				create c.make
				create p.make ({STRING_32} "@claude", bot ("claude", {STRING_32} "Claude"), c,
					{STRING_32} "C:\Users\LJR19\OneDrive\Documents\Obsidian Vault",
					{STRING_32} "C:\Users\LJR19\OneDrive\Documents\Obsidian Vault\participants\claude", 1200, 120)
				l_created := True
			end
			assert ("the vault is refused as a working directory", not l_created)
		rescue
			if l_tried and not l_created then
				retry
			end
		end

feature -- Engines

	test_engine_timing_contracts
			-- Phase 4 engines fail honestly against a dead endpoint: the
			-- Ollama client points at an unroutable loopback port (the
			-- ops-assault pattern - the refusal is immediate, no live
			-- engine, no network), and no exception escapes. The Claude
			-- shaper is construction-only here: its `shape' would invoke
			-- the installed CLI and spend the subscription, so the suite
			-- pins its wiring and tier instead.
		local
			oc: OLLAMA_CLIENT
			cc: CLAUDE_CODE_CLIENT
			op: OLLAMA_PARTICIPANT
			os: OLLAMA_SHAPER
			cs: CLAUDE_SHAPER
			a: PARTICIPANT_ANSWER
			st: SHAPED_TEXT
			brief: SHAPING_BRIEF
		do
			create oc.make_with_base_url ({STRING_32} "http://127.0.0.1:9")
			create op.make ({STRING_32} "@qwen", bot ("qwen", {STRING_32} "Qwen"), oc, {STRING_32} "qwen2.5", 1200, 30)
			a := op.answer (request ({STRING_32} "hello", Void))
			assert ("dead ollama is an error, not an exception", not a.is_success and op.calls = 1 and not op.last_timed_out and op.timeout_seconds = 30)
			assert ("timing recorded within the bound", op.elapsed_seconds >= 0 and op.elapsed_seconds <= 30)
			create os.make ({STRING_32} "@qwen", oc, {STRING_32} "qwen2.5", 30)
			create brief.make ({SHAPING_BRIEF}.Purpose_response, {STRING_32} "test", 100)
			st := os.shape ({STRING_32} "hello", brief)
			assert ("dead ollama shaper fails honestly", not st.is_success and not os.last_timed_out and os.cost_tier = {SHAPER}.Tier_local)
			create cc.make
			create cs.make ({STRING_32} "@claude", cc, 60)
			assert ("claude shaper wired", cs.cost_tier = {SHAPER}.Tier_subscription and cs.timeout_seconds = 60 and cs.name.same_string ({STRING_32} "@claude"))
			brief.add_example ({STRING_32} "Gen 1:1")
			assert ("brief keeps its description", brief.example_count = 1 and brief.example (1).same_string ({STRING_32} "Gen 1:1") and brief.description.same_string ({STRING_32} "test"))
		end

feature -- Tool engines (Task 7)

	test_bible_tool_runs_a_real_child
			-- The child engine end to end on a stand-in: ping.exe answers
			-- four echoes to 127.0.0.1 in about three seconds, well inside
			-- a ten-second bound, and its output reaches the reply through
			-- the same gates as any tool run. The stand-in needs no shell
			-- and no stdin, and "127.0.0.1" passes bible's own reference
			-- gate (digits and dots), so no test-only hook is needed.
		local
			b: BIBLE_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
		do
			create b.make ({STRING_32} "@tools-larry", bot ("tools", {STRING_32} "Tools"), {STRING_32} "C:\Windows\System32\ping.exe", 4000, 10)
			a := b.answer (request_wide ({STRING_32} "127.0.0.1", 4000))
			assert ("child ran and answered", a.is_success and b.runs = 1)
			assert ("within the bound", not b.last_timed_out and b.elapsed_seconds <= 10)
			assert ("echoes what ran", a.text.has_substring ({STRING_32} "> 127.0.0.1"))
			assert ("carries the child's output", a.text.count > 40)
			assert ("undisclosed: no shaper ran", not b.last_response_shaped)
		end

	test_tool_child_killed_at_timeout
			-- Task 7 acceptance: a child alive past the bound is killed,
			-- confirmed dead and reported as one timeout failure. Ping's
			-- four echoes need about three seconds and the bound is one,
			-- so the answer coming back in about a second IS the kill
			-- working - the child alone would hold the call for three.
		local
			b: BIBLE_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
			l_before, l_after: SIMPLE_DATE_TIME
		do
			create b.make ({STRING_32} "@tools-larry", bot ("tools", {STRING_32} "Tools"), {STRING_32} "C:\Windows\System32\ping.exe", 4000, 1)
			create l_before.make_now
			a := b.answer (request_wide ({STRING_32} "127.0.0.1", 4000))
			create l_after.make_now
			assert ("timed out and failed", not a.is_success and b.last_timed_out and b.runs = 1)
			assert ("overrun never clamped", b.elapsed_seconds > b.timeout_seconds)
			assert ("counted once", b.calls = 1)
			assert ("killed, not waited out", (l_after.to_timestamp - l_before.to_timestamp) <= 2)
			assert ("timeout is the error", attached a.error as e and then e.code.same_string ({CHAT_ERROR}.Code_unavailable))
		end

	test_shape_tool_answers_from_a_scratch_database
			-- The query engine against a scratch shape.db bearing the real
			-- schema (shape + shape_instance): the census always names all
			-- four verdicts together - the store's own rule - and the
			-- instances follow; an unknown slug is an honest error.
		local
			s: SHAPE_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
		do
			create s.make ({STRING_32} "@shape-larry", bot ("shape", {STRING_32} "Shape"), scratch_shape_database, 4000, 10)
			a := s.answer (request_wide ({STRING_32} "beachhead_that_moves", 4000))
			assert ("answered from the database", a.is_success and s.runs = 1)
			assert ("all four verdicts together", a.text.has_substring ({STRING_32} "FITS 2") and a.text.has_substring ({STRING_32} "PARTIAL 0")
				and a.text.has_substring ({STRING_32} "FAILS 1") and a.text.has_substring ({STRING_32} "NO_DATA 0"))
			assert ("an instance is named", a.text.has_substring ({STRING_32} "JHN 5:19!17"))
			a := s.answer (request_wide ({STRING_32} "no_such_slug", 4000))
			assert ("unknown slug is an error", not a.is_success and s.runs = 2)
		end

feature -- Dispatcher

	test_dispatcher_ignores_bots_and_answers_once
		local
			d: PARTICIPANT_DISPATCHER
			e_bot, e, e_sys, e_plain: CHAT_EVENT
			l_page: STRING_8
		do
			d := dispatcher (0)
			assert ("fresh", d.requests_seen = 0 and d.answered_model.is_empty and d.cursor_of (1) = 0 and not d.has_pending and d.start_after = 0)
			e_bot := message (5, 1, 99, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " @mock hi", True)
			d.handle_event (e_bot)
			assert ("bot ignored", d.requests_seen = 0 and d.target_of (e_bot) = Void)
			e := message (6, 1, 7, {STRING_32} "@mock hi", False)
			assert ("target found", d.target_of (e) = last_mock)
			d.handle_event (e)
			assert ("taken once", d.requests_seen = 1 and d.answered_model.has (6) and d.has_answered (6) and d.answered_model.count = 1)
			assert ("room cannot take it today: a failure, no ask", d.answer_failures = 1 and d.answers_posted = 0 and d.asks = 0 and not d.last_can_post and not d.last_ask_granted)
			assert ("mock not asked", attached last_mock as m and then m.calls = 0)
			d.handle_event (e)
			assert ("second delivery skipped", d.requests_seen = 1 and d.answer_failures = 1 and d.answered_model.count = 1)
			e_sys := system_event (7, 1, {STRING_32} "@mock hi")
			d.handle_event (e_sys)
			assert ("system event ignored", d.requests_seen = 1 and d.target_of (e_sys) = Void)
			e_plain := message (8, 1, 7, {STRING_32} "hello everyone", False)
			d.handle_event (e_plain)
			assert ("unaddressed ignored", d.requests_seen = 1)
			d.wake (1)
			d.wake (1)
			assert ("wakes drain themselves", d.pending_count = 0 and not d.is_pending (1) and d.wake_count = 2)
			d.dispatch_pending
			assert ("drained against an empty store", not d.has_pending and d.requests_seen = 1 and d.cursor_of (1) = 0)
			l_page := page_bytes (<<message (9, 1, 7, {STRING_32} "@mock again", False)>>)
			d.handle_page (1, l_page)
			d.handle_page (1, l_page)
			assert ("the same page twice is taken once", d.requests_seen = 2 and d.cursor_of (1) = 9 and d.answered_model.count = 2 and d.last_page_count = 1)
		end

	test_dispatcher_restart_cursor_honoured
		local
			d: PARTICIPANT_DISPATCHER
		do
			d := dispatcher (42)
			assert ("starts where told", d.start_after = 42 and d.cursor_of (1) = 42 and d.cursor_of (9) = 42 and d.cursors_model.is_empty)
			d.handle_page (1, page_bytes (<<message (41, 1, 7, {STRING_32} "@mock old", False), message (43, 1, 7, {STRING_32} "@mock new", False)>>))
			assert ("history not re-answered", d.requests_seen = 1 and d.answered_model.has (43) and not d.answered_model.has (41) and d.cursor_of (1) = 43)
			d.wake (1)
			d.dispatch_pending
			assert ("cursor kept across a drain", d.cursor_of (1) = 43 and not d.has_pending)
		end

	test_dispatcher_per_room_cursors
		local
			d: PARTICIPANT_DISPATCHER
		do
			d := dispatcher (0)
			d.handle_page (1, page_bytes (<<message (3, 1, 7, {STRING_32} "hello", False)>>))
			assert ("room 1 cursor", d.cursor_of (1) = 3 and d.cursor_of (2) = 0 and d.cursors_model.count = 1)
			d.handle_page (2, page_bytes (<<message (7, 2, 7, {STRING_32} "@mock hi", False)>>))
			assert ("room 2 cursor", d.cursor_of (2) = 7 and d.cursor_of (1) = 3 and d.cursors_model.count = 2 and d.requests_seen = 1)
			d.handle_page (1, page_bytes (<<message (9, 2, 7, {STRING_32} "foreign", False)>>))
			assert ("foreign event skipped", d.cursor_of (1) = 3 and d.cursor_of (2) = 7)
			d.handle_page (1, "not json")
			assert ("undecodable page changes nothing", d.cursor_of (1) = 3 and d.last_page_count = 0)
			d.wake (1)
			d.wake (2)
			d.wake (1)
			assert ("wakes drain, three counted", d.pending_count = 0 and d.wake_count = 3)
			d.dispatch_pending
			assert ("both drained, cursors kept", not d.has_pending and d.cursor_of (1) = 3 and d.cursor_of (2) = 7)
		end

	test_dispatcher_grants_and_charges_via
			-- The granted path (NEW-11): a stored bot member, a real ask, a
			-- posted answer; a `via' naming a participant is charged under
			-- both keys (Issue 15, `via_charged'); a via-key refusal after
			-- the target grant refuses the request; an unpermitted `via' is
			-- an explicit refusal with no ask (NEW-10).
		local
			d: PARTICIPANT_DISPATCHER
		do
			d := posting_dispatcher (0)
			d.handle_event (message (11, 1, 7, {STRING_32} "@mock hi", False))
				-- The service's post_message body is a Phase 4 stub (501), so a
				-- posted answer lands in the accounting sum, not in answers_posted;
				-- what this test pins is the GRANTED path: ask, engine, account.
			assert ("granted, asked, accounted", d.last_can_post and d.last_ask_granted and d.asks = 1 and d.answers_posted + d.answer_failures = 1)
			assert ("asked the engine", attached last_mock as m1 and then m1.calls = 1)
			assert ("charged the asker", d.last_ask_key.same_string ("p:@mock:7") and d.last_via_key.is_empty)
			d.handle_event (message (12, 1, 7, {STRING_32} "@tool Gen 1:1 via @mock", False))
			assert ("via charged under both keys", d.last_ask_granted and d.last_ask_key.same_string ("p:@tool:7")
				and d.last_via_key.same_string ("p:@mock:7") and d.asks = 2 and d.answers_posted + d.answer_failures = 2)
			assert ("tool ran", attached last_tool as t1 and then t1.runs = 1)
			if attached last_limits as ll then
				ll.set_limit ("p:@mock:", 1, 3600)
			end
			d.handle_event (message (13, 1, 7, {STRING_32} "@tool Gen 1:1 via @mock", False))
			assert ("via key exhausted refuses after the target grant", not d.last_ask_granted and d.asks = 2 and d.answers_posted + d.answer_failures = 3)
			assert ("tool not run again", attached last_tool as t2 and then t2.runs = 1)
			d.handle_event (message (14, 1, 7, {STRING_32} "@mock hi via plain", False))
			assert ("unpermitted via refused explicitly", d.answers_posted + d.answer_failures = 4 and d.asks = 2)
			assert ("engine untouched by the refusal", attached last_mock as m2 and then m2.calls = 1)
		end

	test_dispatcher_survives_raising_engine
			-- NEW-7: an engine that raises is one answer_failure with the
			-- queue slot released; the dispatcher lives on and answers the
			-- next request.
		local
			d: PARTICIPANT_DISPATCHER
		do
			d := posting_dispatcher (0)
			if attached last_mock as m then
				m.set_should_raise (True)
			end
			d.handle_event (message (21, 1, 7, {STRING_32} "@mock boom", False))
			assert ("raise became a failure", d.answer_failures = 1 and d.answers_posted = 0 and d.last_answer_raised and d.requests_seen = 1)
			assert ("slot released", attached last_mock as m3 and then d.queue_depth_of (m3) = 0)
			if attached last_mock as m then
				m.set_should_raise (False)
			end
			d.handle_event (message (22, 1, 7, {STRING_32} "@mock again", False))
			assert ("dispatcher alive and answering", d.answers_posted + d.answer_failures = 2 and d.asks = 1
				and not d.last_answer_raised and d.requests_seen = 2)
			assert ("engine asked again", attached last_mock as m4 and then m4.calls = 1)
		end

	test_dispatcher_post_does_not_ring_the_dispatcher_back
			-- THE SECOND-CALL FREEZE (phase4/second-call-freeze), at the seam
			-- where it was made. A member's post rings the bus and wakes the
			-- dispatcher, which is the whole point of the doorbell. The
			-- dispatcher's OWN post must ring the room and wake everybody else
			-- and NOT wake the dispatcher - because that call carries the
			-- dispatcher's own lock (`a_text' is its string), so in the server
			-- the wake did not queue for the dispatcher's turn: it ran there and
			-- then, on the API's thread, by SCOOP impersonation, inside
			-- `handle_page', inside the drain. It queued a room and counted a
			-- wake under a frame that promises neither, the postcondition
			-- raised, `dispatch_pending' unwound with `is_dispatching' left
			-- True, and the bot never answered again - no child, no log line,
			-- the rest of the server serving normally. Measured in
			-- .eiffel-workflow/evidence/phase4-second-call-freeze.txt.
		local
			d: PARTICIPANT_DISPATCHER
			l_wakes, l_rings: INTEGER
			l_posted: CHAT_RESULT [CHAT_EVENT]
		do
			d := posting_dispatcher (0)
			if attached last_bus as b then
				b.subscribe (d)
				assert ("the bus knows the dispatcher by the name it gives", b.dispatcher_ticket = b.last_ticket)
			end
				-- A member's post: rings, and wakes the dispatcher.
			if attached last_bus as b and attached last_service as sv and attached last_room as r and attached last_nick as n then
				l_wakes := d.wake_count
				l_rings := b.ring_count
				l_posted := sv.post_message (n, r, {STRING_32} "just talking, nobody addressed")
				assert ("the member's message landed", l_posted.is_success)
				assert ("it rang the room", b.ring_count = l_rings + 1)
				assert ("and it woke the dispatcher - the doorbell works", d.wake_count = l_wakes + 1)
			end
				-- The dispatcher's own post: rings, and wakes everybody but it.
				-- Driven through `handle_event' rather than a drain, so the only
				-- ring on the stack is the answer's own - which is the one under
				-- test. (On ONE processor a bus wake is a plain call, so a drain
				-- started BY a ring would post from inside that ring's own frame,
				-- something the server never does: there the wake is asynchronous
				-- and `ring' returns long before the dispatcher moves.)
			if attached last_bus as b then
				l_wakes := d.wake_count
				l_rings := b.ring_count
				d.handle_event (message (500, 1, 7, {STRING_32} "@mock answer me", False))
				assert ("the request was asked and answered", d.asks = 1 and d.answers_posted = 1)
				assert ("the answer rang the room, as every post does", b.ring_count = l_rings + 1)
				assert ("but it did NOT wake the dispatcher: this is the freeze", d.wake_count = l_wakes)
				assert ("and the mute did not outlive the post", b.muted_ticket = 0 and not b.is_muted (b.dispatcher_ticket))
			end
				-- And the bell comes straight back for the next member's message.
			if attached last_service as sv and attached last_room as r and attached last_nick as n then
				l_wakes := d.wake_count
				l_posted := sv.post_message (n, r, {STRING_32} "and one more, still nobody addressed")
				assert ("the doorbell is not left switched off", d.wake_count = l_wakes + 1)
			end
		end

	test_dispatcher_answers_the_second_and_third_request_of_a_run
			-- What the freeze actually cost: the FIRST request of a server run
			-- was answered and every one after it was not, for the life of the
			-- process - reproduced on main's own binary with two `@claude'
			-- turns four seconds apart, so it was never a race. Three
			-- requests, three answers, one dispatcher.
		local
			d: PARTICIPANT_DISPATCHER
			l_reason: STRING_32
		do
			d := posting_dispatcher (0)
			l_reason := say_reason (d, {STRING_32} "@mock one")
			assert ("the first turn was clean - " + l_reason.to_string_8, l_reason.is_empty)
			assert ("first request answered", d.asks = 1)
			l_reason := say_reason (d, {STRING_32} "@mock two")
			assert ("the second turn was clean - " + l_reason.to_string_8, l_reason.is_empty)
			assert ("SECOND request answered - the one the freeze took", d.asks = 2 and d.requests_seen = 2)
			l_reason := say_reason (d, {STRING_32} "@mock three")
			assert ("the third turn was clean - " + l_reason.to_string_8, l_reason.is_empty)
			assert ("third request answered", d.asks = 3 and d.requests_seen = 3)
			assert ("the engine was asked three times", attached last_mock as m and then m.calls = 3)
			assert ("every one accounted, none lost", d.answers_posted + d.answer_failures = 3)
			assert ("the cursor walked past all six events", d.cursor_of (1) >= 3)
		end

	test_dispatcher_answers_two_requests_that_arrive_together
			-- Back to back, on ONE page: the first answer's post lands while
			-- the page holding the second request is still being handled. That
			-- is the shape Larry hit - a request arriving while the previous
			-- answer is being written - and both must be answered.
		local
			d: PARTICIPANT_DISPATCHER
			l_reason: STRING_32
		do
			d := posting_dispatcher (0)
			append_ask ({STRING_32} "@mock one")
			append_ask ({STRING_32} "@mock two")
			l_reason := drain_reason (d, 1)
			assert ("the drain was clean - " + l_reason.to_string_8, l_reason.is_empty)
			assert ("both requests of one page answered", d.requests_seen = 2 and d.asks = 2)
			assert ("the engine was asked twice", attached last_mock as m and then m.calls = 2)
			assert ("nothing left pending", not d.has_pending)
		end

	test_dispatcher_two_bots_answer_the_same_room
			-- Two participants, one room, one run: "@mock" answers, then
			-- "@tool" answers. The freeze took the second bot's FIRST call as
			-- surely as it took one bot's second, because it was never about
			-- the participant.
		local
			d: PARTICIPANT_DISPATCHER
			l_reason: STRING_32
		do
			d := posting_dispatcher (0)
			l_reason := say_reason (d, {STRING_32} "@mock hello")
			assert ("the first bot's turn was clean - " + l_reason.to_string_8, l_reason.is_empty)
			assert ("the first bot answered", attached last_mock as m and then m.calls = 1)
			l_reason := say_reason (d, {STRING_32} "@tool Gen 1:1")
			assert ("the second bot's FIRST call was reached - " + l_reason.to_string_8, l_reason.is_empty)
			assert ("the second bot ran", attached last_tool as t and then t.runs = 1)
			assert ("both accounted", d.requests_seen = 2 and d.asks = 2 and d.answers_posted + d.answer_failures = 2)
		end

	test_bus_mutes_one_ticket_and_only_for_that_post
			-- The mute is one subscriber wide and one post long: everybody
			-- else is rung through it, the ring is still counted, and
			-- `unmute' gives the muted one its bell back.
		local
			l_bus: EVENT_BUS
			l_waiter: POLL_WAITER
			d: PARTICIPANT_DISPATCHER
			l_ticket_d, l_ticket_w: INTEGER
		do
			create l_bus.make
			d := dispatcher (0)
			create l_waiter.make (1)
			assert ("the bus knows no dispatcher yet", l_bus.dispatcher_ticket = 0)
			l_bus.subscribe (l_waiter)
			l_ticket_w := l_bus.last_ticket
			assert ("a long-poll is not the dispatcher", l_bus.dispatcher_ticket = 0)
			l_bus.subscribe (d)
			l_ticket_d := l_bus.last_ticket
			assert ("the name is the pin: PARTICIPANT_DISPATCHER gives it", d.subscriber_name.same_string ({EVENT_BUS}.Dispatcher_subscriber_name))
			assert ("and the bus noted its ticket", l_bus.dispatcher_ticket = l_ticket_d)
			assert ("nobody muted to begin with", l_bus.muted_ticket = 0 and not l_bus.is_muted (l_ticket_d))
			l_bus.ring (1)
			assert ("both woken", l_waiter.wake_count = 1 and d.wake_count = 1 and l_bus.ring_count = 1)
			l_bus.mute_dispatcher
			assert ("the dispatcher, and only it, is muted", l_bus.is_muted (l_ticket_d) and not l_bus.is_muted (l_ticket_w))
			l_bus.ring (1)
			assert ("the muted one was passed over", d.wake_count = 1)
			assert ("everybody else was rung as ever", l_waiter.wake_count = 2)
			assert ("the ring was still counted", l_bus.ring_count = 2)
			l_bus.unmute
			assert ("nobody muted again", l_bus.muted_ticket = 0 and not l_bus.is_muted (l_ticket_d))
			l_bus.ring (1)
			assert ("the bell came back", d.wake_count = 2 and l_waiter.wake_count = 3 and l_bus.ring_count = 3)
		end

	test_summary_is_never_a_room_event
			-- THE LAW A SUMMARY LIVES UNDER. It is an engine reply to the one
			-- member who asked, drawn in their own window - so it leaves no
			-- trace whatever in the room: nothing posted, nothing rung, no
			-- cursor moved, no id marked answered, no queue slot taken. Events
			-- are never per-person, which is exactly why a summary must not be
			-- one.
		local
			d: PARTICIPANT_DISPATCHER
			l_text: STRING_32
			l_before: INTEGER_64
		do
			d := posting_dispatcher (0)
			append_ask ({STRING_32} "the roof is finished")
			append_ask ({STRING_32} "and the gutters go on Friday")
			if attached last_service as sv then
				l_before := sv.store.last_event_id
			end
			l_text := d.summary_of (1, 0, 0, last_nick_id, 0)
			assert ("the engine answered", d.last_summary_status = {PARTICIPANT_DISPATCHER}.Summary_ok and not l_text.is_empty)
			assert ("asked and given, on the summary account", d.summaries_asked = 1 and d.summaries_given = 1)
			assert ("NOTHING WAS POSTED", attached last_service as sv2 and then sv2.store.last_event_id = l_before)
			assert ("the room was never rung", attached last_bus as b and then b.ring_count = 0)
			assert ("no request taken, no answer accounted", d.requests_seen = 0 and d.asks = 0 and d.answers_posted = 0 and d.answer_failures = 0)
			assert ("no cursor moved, nothing marked answered", d.cursors_model.is_empty and d.answered_model.is_empty)
			assert ("the dispatcher was not woken", d.wake_count = 0 and not d.has_pending)
		end

	test_summary_spends_its_own_budget
			-- A summary is charged under "s:", an answer under "p:". Catching up
			-- on what was missed must never cost a member the right to ask a
			-- question - which is the whole reason the budgets are two.
		local
			d: PARTICIPANT_DISPATCHER
			l_text: STRING_32
		do
			d := posting_dispatcher (0)
			append_ask ({STRING_32} "something was said")
			if attached last_limits as ll then
				ll.set_limit ("s:@mock:", 1, 3600)
			end
			l_text := d.summary_of (1, 0, 0, last_nick_id, 0)
			assert ("the first summary is given", d.last_summary_status = {PARTICIPANT_DISPATCHER}.Summary_ok and not l_text.is_empty)
			assert ("charged to the summary key", d.last_summary_key.same_string ("s:@mock:" + last_nick_id.out))
			l_text := d.summary_of (1, 0, 0, last_nick_id, 0)
			assert ("the second is refused by the SUMMARY budget", d.last_summary_status = {PARTICIPANT_DISPATCHER}.Summary_budget_spent and l_text.is_empty)
			assert ("and the engine was asked only once", d.summaries_asked = 1)
			d.handle_event (message (900, 1, last_nick_id, {STRING_32} "@mock and a question", False))
			assert ("the ANSWER budget was never spent by a summary", d.last_ask_granted and d.asks = 1)
			assert ("two different keys entirely", not d.last_ask_key.same_string (d.last_summary_key))
		end

	test_summary_says_when_there_is_nothing_to_say
			-- An empty gap is not an engine call. Nothing to summarise costs
			-- nothing and spends no budget.
		local
			d: PARTICIPANT_DISPATCHER
			l_text: STRING_32
		do
			d := posting_dispatcher (0)
			l_text := d.summary_of (1, 0, 0, last_nick_id, 0)
			assert ("nothing to say, and said so", d.last_summary_status = {PARTICIPANT_DISPATCHER}.Summary_nothing_to_say and l_text.is_empty)
			assert ("the engine was never asked", d.summaries_asked = 0 and attached last_mock as m and then m.calls = 0)
		end

	test_summary_gate_refuses_a_stranger
			-- The gate answers 0 for a token that names nobody, and says nothing
			-- about which rooms exist while it does.
		local
			d: PARTICIPANT_DISPATCHER
		do
			d := posting_dispatcher (0)
			assert ("a stranger is refused", attached last_api as a and then a.summary_gate ("not-a-token", 1) = 0)
			assert ("an unknown room is refused the same way", attached last_api as a2 and then a2.summary_gate ("not-a-token", 9999) = 0)
		end

	test_a_reply_carrying_tool_markup_never_reaches_the_room
			-- Asked whether it could see Larry's drive, the participant answered
			-- with an <invoke> block and a directory listing - and the listing
			-- was INVENTED: not one of the folders it named exists. The sandbox
			-- held and nothing was read, but the room was shown a transcript of
			-- work that never happened, which is worse than a refusal. A reply
			-- carrying tool-call markup is not an answer this participant could
			-- have produced honestly, so it never reaches the room.
		local
			p: CLAUDE_CODE_PARTICIPANT
		do
			p := claude_participant
			assert ("an invoke block is refused", p.has_tool_markup ({STRING_32} "sure<invoke name=Bash>ls /c/Users</invoke>"))
			assert ("a parameter block is refused", p.has_tool_markup ({STRING_32} "<parameter name=command>ls</parameter>"))
			assert ("a function_calls block is refused", p.has_tool_markup ({STRING_32} "<function_calls>x</function_calls>"))
			assert ("the case does not matter", p.has_tool_markup ({STRING_32} "<INVOKE NAME=Bash>"))
			assert ("ordinary prose is untouched", not p.has_tool_markup ({STRING_32} "I cannot see your drive from here."))
			assert ("arithmetic is not markup: 5 < 10 stays", not p.has_tool_markup ({STRING_32} "5 < 10 and 10 > 5"))
			assert ("what the room gets instead tells the truth",
				p.scrubbed ({STRING_32} "<invoke name=Bash>ls</invoke>").has_substring ({STRING_32} "no tools"))
			assert ("a clean answer passes through unchanged",
				p.scrubbed ({STRING_32} "Gen 1:1 in the beginning").same_string ({STRING_32} "Gen 1:1 in the beginning"))
			assert ("the persona tells the model it has no tools",
				p.persona_of (request_wide ({STRING_32} "hello", 400)).has_substring ({STRING_32} "NO TOOLS"))
			assert ("and tells it to say so when asked",
				p.persona_of (request_wide ({STRING_32} "hello", 400)).has_substring ({STRING_32} "say plainly that you cannot"))
		end

	test_dispatcher_prunes_answered
			-- NEW-6: taken ids at or below the lowest room cursor are pruned
			-- after a drain, and ids at or below the floor are never retaken.
		local
			d: PARTICIPANT_DISPATCHER
		do
			d := dispatcher (0)
			d.handle_page (1, page_bytes (<<message (5, 1, 7, {STRING_32} "@mock hi", False)>>))
			assert ("taken", d.has_answered (5) and d.cursor_of (1) = 5 and d.requests_seen = 1)
			d.wake (1)
			assert ("pruned at the cursor", not d.has_answered (5) and d.pruned_floor = 5)
			d.handle_page (1, page_bytes (<<message (5, 1, 7, {STRING_32} "@mock hi", False)>>))
			assert ("replayed page not retaken", d.requests_seen = 1)
			d.handle_event (message (4, 1, 7, {STRING_32} "@mock old", False))
			assert ("ancient id skipped", d.requests_seen = 1 and not d.has_answered (4))
		end

	test_dispatcher_population_from_configuration
			-- Task 7 item 5: with a configuration path in the per-process
			-- shared settings (the same key the facade fills), `make'
			-- brings every buildable [[participants]] entry to life - bot
			-- users created on first sight through the API (the
			-- configuration drives the store), aliases and via choices
			-- wired, the claude sandbox directory created - and an entry
			-- whose engine is missing is skipped while the rest come up
			-- (D6). The key is blanked again at the end, so later
			-- fixtures populate nothing.
		local
			d: PARTICIPANT_DISPATCHER
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_service: CHAT_SERVICE
			l_api: CHAT_API
			l_dir: DIRECTORY
		do
			shared_put ({CHAT_SHARED}.Config_path_key, population_config_path)
				-- The API's own configuration is the SAME file the dispatcher
				-- loads (as in production, where make_from_shared reads the
				-- shared path): dispatcher_bot_id_of resolves entries by index
				-- against the API's copy, so a defaults-built API would answer
				-- 0 for every entry and nothing would register.
			create l_config.make_from_file (population_config_path)
			create l_store.make
			l_store.open
			create l_bus.make
			create l_limits.make (3600)
			create l_logger
			create l_log.make (l_logger)
			create l_service.make (l_store, l_bus, l_limits, l_config, l_log)
			create l_api.make (l_service, l_config)
			create d.make (l_api, 0)
			d.populate
			assert ("four registered, one skipped", d.participants_registered = 4 and d.participants_skipped = 1 and d.registry.count = 4)
			assert ("every kind found", d.registry.has ({STRING_32} "@pop-null") and d.registry.has ({STRING_32} "@pop-bible")
				and d.registry.has ({STRING_32} "@pop-qwen") and d.registry.has ({STRING_32} "@pop-claude"))
			assert ("missing engine skipped", not d.registry.has ({STRING_32} "@pop-miss"))
			assert ("bots created on first sight", l_store.has_username ("pop_bible_bot") and l_store.has_username ("pop_qwen_bot")
				and l_store.has_username ("pop_claude_bot") and l_store.has_username ("pop_null_bot") and not l_store.has_username ("pop_miss_bot"))
			assert ("a stored active bot", attached l_store.user_by_username ("pop_bible_bot") as u and then (u.is_bot and u.is_active and u.is_stored))
			assert ("alias wired", d.registry.has_alias ({STRING_32} "Pop:") and d.registry.handle_of_alias ({STRING_32} "Pop:").same_string ({STRING_32} "@pop-bible"))
			assert ("via choice wired to the ollama entry", attached d.registry.find ({STRING_32} "@pop-bible") as t
				and then (t.permits_via ({STRING_32} "@pop-qwen") and t.permits_via ({STRING_32} "plain")))
			assert ("resolved bot user carried", attached d.registry.find ({STRING_32} "@pop-bible") as t2 and then t2.bot_user.is_stored)
			create l_dir.make ({STRING_32} "C:\Users\Public\sc_chat_pop\data\participants\pop-claude")
			assert ("claude sandbox directory created", l_dir.exists)
			shared_put ({CHAT_SHARED}.Config_path_key, "")
			create d.make (l_api, 0)
			d.populate
			assert ("a blank key populates nothing", d.participants_registered = 0 and d.registry.count = 0)
			create l_dir.make ({STRING_32} "C:\Users\Public\sc_chat_pop")
			if l_dir.exists then
				l_dir.recursive_delete
			end
		end

feature -- Mention anywhere (Phase 4)

	test_mention_boundary_rule_anywhere_in_the_text
			-- ADDRESS_PARSER's rule, whole: start, middle, end, punctuation,
			-- case, a longer word, an "@" that follows a handle character,
			-- an "@"-shaped alias, and the same handle named twice.
		local
			p: ADDRESS_PARSER
			r: PARTICIPANT_REGISTRY
		do
			create r.make
			r.register (create {NULL_PARTICIPANT}.make ({STRING_32} "@claude", bot ("c", {STRING_32} "C")))
			r.register (create {NULL_PARTICIPANT}.make ({STRING_32} "@qwen", bot ("q", {STRING_32} "Q")))
			r.register_alias ({STRING_32} "@robot", {STRING_32} "@claude")
			create p.make (r)
			assert ("at the start", p.mentions_handle ({STRING_32} "@Claude hello", {STRING_32} "@claude"))
			assert ("in the middle", p.mentions_handle ({STRING_32} "hello @Claude what is 2+2", {STRING_32} "@claude"))
			assert ("at the end", p.mentions_handle ({STRING_32} "and times 3 @claude", {STRING_32} "@claude"))
			assert ("with a question mark", p.mentions_handle ({STRING_32} "so what @claude?", {STRING_32} "@claude"))
			assert ("with a colon", p.mentions_handle ({STRING_32} "@claude: are you still getting this?", {STRING_32} "@claude"))
			assert ("with a comma", p.mentions_handle ({STRING_32} "well @Claude, tell me", {STRING_32} "@claude"))
			assert ("in brackets", p.mentions_handle ({STRING_32} "ask the bot (@CLAUDE) about it", {STRING_32} "@claude"))
			assert ("a longer word is not the handle", not p.mentions_handle ({STRING_32} "hi @claudette there", {STRING_32} "@claude"))
			assert ("an underscored handle is not the handle", not p.mentions_handle ({STRING_32} "hi @claude_bot there", {STRING_32} "@claude"))
			assert ("an address inside a word is nobody", not p.mentions_handle ({STRING_32} "write to bob@claude now", {STRING_32} "@claude"))
			assert ("an unregistered mention is nobody", p.mentioned_handles ({STRING_32} "hello @nobody there").is_empty)
			assert ("blank text mentions nobody", p.mentioned_handles ({STRING_32} "").is_empty)
			assert ("an %"@%" alias mentions its handle", p.mentioned_handles ({STRING_32} "please look @ROBOT at this").count = 1
				and then p.mentioned_handles ({STRING_32} "please look @ROBOT at this").first.same_string ({STRING_32} "@claude"))
			assert ("twice named, once listed", p.mentioned_handles ({STRING_32} "@claude and again @claude").count = 1)
			assert ("two bots, both listed, in order", p.mentioned_handles ({STRING_32} "hi @qwen and @claude").count = 2
				and then p.mentioned_handles ({STRING_32} "hi @qwen and @claude").first.same_string ({STRING_32} "@qwen"))
			assert ("a colon alias stays a start-of-text address", p.mentioned_handles ({STRING_32} "well claude: hello").is_empty)
		end

	test_mention_rewritten_into_the_leading_address
			-- `addressed_body': one addressed-request path serves a middle
			-- mention, the question keeps its words, the "via" survives, and
			-- a bare mention still asks nothing.
		local
			p: ADDRESS_PARSER
			r: PARTICIPANT_REGISTRY
		do
			create r.make
			r.register (create {NULL_PARTICIPANT}.make ({STRING_32} "@claude", bot ("c", {STRING_32} "C")))
			create p.make (r)
			assert ("middle mention leads now",
				p.addressed_body ({STRING_32} "hello @Claude what is 2+2", {STRING_32} "@claude").same_string ({STRING_32} "@claude hello what is 2+2"))
			assert ("a trailing mention keeps its punctuation",
				p.addressed_body ({STRING_32} "so what @claude?", {STRING_32} "@claude").same_string ({STRING_32} "@claude so what?"))
			assert ("both mentions go",
				p.addressed_body ({STRING_32} "@claude hi and @claude again", {STRING_32} "@claude").same_string ({STRING_32} "@claude hi and again"))
			assert ("a leading colon form is unchanged in meaning",
				p.addressed_body ({STRING_32} "@claude: are you still getting this?", {STRING_32} "@claude").same_string ({STRING_32} "@claude are you still getting this?"))
			assert ("the rewrite is addressed", p.is_addressed (p.addressed_body ({STRING_32} "hello @Claude what", {STRING_32} "@claude")))
			assert ("the via survives the rewrite",
				attached p.parse (p.addressed_body ({STRING_32} "look this up @claude via plain", {STRING_32} "@claude")) as l_r
				and then (attached l_r.via as v and then v.same_string ({STRING_32} "plain")) and then l_r.text.same_string ({STRING_32} "look this up"))
			assert ("a bare mention asks nothing", p.parse (p.addressed_body ({STRING_32} "@claude", {STRING_32} "@claude")) = Void)
		end

	test_dispatcher_answers_a_mention_in_the_middle
			-- Larry's case: "@Claude" in the middle of a sentence is a
			-- request, taken once, with the handle out of the question.
		local
			d: PARTICIPANT_DISPATCHER
			e: CHAT_EVENT
		do
			d := posting_dispatcher (0)
			e := message (11, 1, 7, {STRING_32} "hello @Mock what is 2+2", False)
			assert ("the old start-of-text rule does not see it", d.target_of (e) = Void)
			assert ("the mention rule does", d.addressed_targets (e).count = 1 and then d.addressed_targets (e).first = last_mock)
			d.handle_mentions (e)
			assert ("taken once, asked once", d.requests_seen = 1 and d.asks = 1 and d.answers_posted + d.answer_failures = 1)
			assert ("the handle is out of the question",
				attached last_mock as m and then attached m.last_request as q and then q.text.same_string ({STRING_32} "hello what is 2+2"))
			d.handle_mentions (e)
			assert ("a second delivery is skipped", d.requests_seen = 1 and d.asks = 1)
			d.handle_mentions (message (12, 1, 7, {STRING_32} "and times 3? @mock", False))
			assert ("a trailing mention is a request too", d.requests_seen = 2 and d.asks = 2
				and attached last_mock as m2 and then attached m2.last_request as q2 and then q2.text.same_string ({STRING_32} "and times 3?"))
		end

	test_a_bots_own_mention_never_triggers_it
			-- No echo loop: a bot-authored message, a system event and a
			-- longer word are all nobody's request, however they read.
		local
			d: PARTICIPANT_DISPATCHER
			e_bot, e_word, e_sys: CHAT_EVENT
		do
			d := posting_dispatcher (0)
			e_bot := message (21, 1, 99, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " thanks @mock, that helps", True)
			d.handle_mentions (e_bot)
			assert ("a bot's own mention is nobody's request", d.addressed_targets (e_bot).is_empty and d.requests_seen = 0 and d.mentions_seen = 0 and d.asks = 0)
			e_word := message (22, 1, 7, {STRING_32} "have you met @mockingbird yet", False)
			d.handle_mentions (e_word)
			assert ("a longer word is not the handle", d.addressed_targets (e_word).is_empty and d.requests_seen = 0 and d.asks = 0)
			e_sys := system_event (23, 1, {STRING_32} "nick joined, say hi @mock")
			d.handle_mentions (e_sys)
			assert ("a system event is nobody's request", d.addressed_targets (e_sys).is_empty and d.requests_seen = 0 and d.asks = 0)
		end

	test_two_bots_in_one_message_each_reply_once
			-- Both named participants answer, each exactly once, and a page
			-- delivered twice does not double either of them.
		local
			d: PARTICIPANT_DISPATCHER
			l_page: STRING_8
		do
			d := posting_dispatcher (0)
			l_page := page_bytes (<<message (31, 1, 7, {STRING_32} "morning @mock and @tool please", False)>>)
			d.handle_page (1, l_page)
			assert ("both taken, the second as a mention", d.requests_seen = 2 and d.mentions_seen = 1 and d.asks = 2)
			assert ("each engine asked once", attached last_mock as m and then m.calls = 1
				and attached last_tool as l_t and then l_t.calls = 1)
			assert ("both accounted", d.answers_posted + d.answer_failures = 2)
			d.handle_page (1, l_page)
			assert ("the same page twice is taken once", d.requests_seen = 2 and d.mentions_seen = 1 and d.asks = 2)
			assert ("the extra mention is remembered by (event, handle)",
				d.has_answered_mention (31, {STRING_32} "@tool") and not d.has_answered_mention (31, {STRING_32} "@nobody")
				and d.answered_mention_count = 1)
			d.wake (1)
			assert ("the floor prunes both books", d.answered_mention_count = 0 and d.answered_model.is_empty)
		end

	test_mention_keeps_the_rate_limit
			-- The limiter is charged and obeyed for a middle mention exactly
			-- as for a leading one: the second ask in the hour is refused
			-- and the engine is never called.
		local
			d: PARTICIPANT_DISPATCHER
		do
			d := posting_dispatcher (0)
			if attached last_limits as l_lim then
				l_lim.set_limit ("p:@mock:", 1, 3600)
			end
			d.handle_mentions (message (41, 1, 7, {STRING_32} "hello @mock what is 2+2", False))
			assert ("the first is granted", d.last_ask_granted and d.asks = 1 and d.last_ask_key.same_string ("p:@mock:7"))
			d.handle_mentions (message (42, 1, 7, {STRING_32} "and again @mock", False))
			assert ("the second is refused", not d.last_ask_granted and d.asks = 1
				and attached last_mock as m and then m.calls = 1)
			assert ("the refusal is told, not dropped", d.answers_posted + d.answer_failures = 2)
		end

feature -- Memory (Phase 4)

	test_context_window_carries_the_conversation
			-- Three turns in a real room: the third request reaches the
			-- engine with the first two and the bot's own reply, oldest
			-- first, each line prefixed by its sender's display name, and
			-- the question itself is untouched.
		local
			d: PARTICIPANT_DISPATCHER
			l_lines: ARRAYED_LIST [STRING_32]
		do
			d := posting_dispatcher (0)
			if attached last_mock as m then
				m.set_context_messages (12)
			end
			say (d, {STRING_32} "hello @mock what is 2+2")
			say (d, {STRING_32} "thanks")
			say (d, {STRING_32} "and times 3? @mock")
			assert ("both mentions answered", d.requests_seen = 2 and d.asks = 2)
			assert ("a window came with the third turn",
				attached last_mock as m2 and then attached m2.last_request as q and then not q.context_lines.is_empty)
			if attached last_mock as m3 and then attached m3.last_request as q2 then
				l_lines := q2.context_lines
				assert ("the question is the question, not the window", q2.text.same_string ({STRING_32} "and times 3?"))
				assert ("three lines before it: the first ask, the bot's reply, the aside", l_lines.count = 3)
				assert ("oldest first, the asker named", l_lines [1].same_string ({STRING_32} "Nick: hello @mock what is 2+2"))
				assert ("the bot's own reply is in the window, marker not doubled",
					l_lines [2].same_string ({CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Mock: In the beginning God created"))
				assert ("the aside is there too", l_lines [3].same_string ({STRING_32} "Nick: thanks"))
				assert ("the addressing message itself is not repeated in the window",
					across l_lines as l all not l.has_substring ({STRING_32} "and times 3") end)
			end
		end

	test_context_window_is_capped_and_optional
			-- The window is `context_messages' long, no longer; zero takes
			-- it away altogether and the prompt is what it always was.
		local
			d: PARTICIPANT_DISPATCHER
			c: CLAUDE_CODE_PARTICIPANT
			q: PARTICIPANT_REQUEST
			l_lines: ARRAYED_LIST [STRING_32]
		do
			d := posting_dispatcher (0)
			if attached last_mock as m then
				m.set_context_messages (2)
			end
			say (d, {STRING_32} "one @mock")
			say (d, {STRING_32} "two")
			say (d, {STRING_32} "three")
			say (d, {STRING_32} "four @mock")
			assert ("capped at two", attached last_mock as m2 and then attached m2.last_request as q1 and then q1.context_lines.count = 2)
			if attached last_mock as m3 and then attached m3.last_request as q2 then
				assert ("and they are the newest two", q2.context_lines [1].same_string ({STRING_32} "Nick: two")
					and q2.context_lines [2].same_string ({STRING_32} "Nick: three"))
			end
			if attached last_mock as m4 then
				m4.set_context_messages (0)
			end
			say (d, {STRING_32} "five @mock")
			assert ("zero means no window", attached last_mock as m5 and then attached m5.last_request as q3 and then q3.context_lines.is_empty)
			create l_lines.make (2)
			l_lines.extend ({STRING_32} "Nick: what is 2+2")
			l_lines.extend ({STRING_32} "Bot: four")
			q := request ({STRING_32} "and its cube root?", Void)
			assert ("a request starts with no window", q.context_lines.is_empty)
			c := claude_participant
			assert ("no window, no change to the prompt", c.contextual_prompt_of (q).same_string (c.prompt_of (q)))
			q.set_context (l_lines)
			assert ("the window comes first and the question last",
				c.contextual_prompt_of (q).ends_with (c.prompt_of (q))
				and c.contextual_prompt_of (q).has_substring ({STRING_32} "Nick: what is 2+2")
				and c.contextual_prompt_of (q).has_substring ({STRING_32} "Bot: four"))
			assert ("the window is not the question", q.text.same_string ({STRING_32} "and its cube root?"))
		end

	test_claude_session_is_kept_per_room_and_dropped_on_failure
			-- The resume path: a session id is kept per room and reused, a
			-- room never borrows another's, and a session that could not
			-- answer is forgotten so the next turn starts fresh.
		local
			c: CLAUDE_CODE_PARTICIPANT
		do
			c := claude_participant
			assert ("no session at the start", c.sessions_model.is_empty and c.session_of (1) = Void)
			c.remember_session (1, {STRING_32} "11111111-2222-3333-4444-555555555555")
			c.remember_session (2, {STRING_32} "66666666-7777-8888-9999-aaaaaaaaaaaa")
			assert ("kept per room", attached c.session_of (1) as s1 and then s1.same_string ({STRING_32} "11111111-2222-3333-4444-555555555555")
				and attached c.session_of (2) as s2 and then s2.same_string ({STRING_32} "66666666-7777-8888-9999-aaaaaaaaaaaa"))
			c.forget_session (1)
			assert ("the failed room starts fresh, the other is untouched",
				c.session_of (1) = Void and c.sessions_model.count = 1 and c.session_of (2) /= Void)
		end

	test_participant_config_carries_the_context_setting
			-- The [[participants]] setting: a default, a value, zero, and a
			-- number past the cap refused with the default kept.
		local
			e: PARTICIPANT_CONFIG
		do
			create e.make ({STRING_32} "@claude", {PARTICIPANT_CONFIG}.Kind_claude_code, "claude_bot", {STRING_32} "Claude", {STRING_32} "C:\sandbox")
			assert ("a default window", e.context_messages = {PARTICIPANT_RULES}.Default_context_messages and e.context_messages = 12)
			e.set_context_messages (4)
			assert ("set", e.context_messages = 4)
			e.set_context_messages (0)
			assert ("zero is lawful", e.context_messages = 0)
			e.set_context_messages ({PARTICIPANT_RULES}.Context_maximum)
			assert ("the cap is lawful", e.context_messages = 50)
			assert ("the limits are untouched", e.requests_per_hour = 5 and e.max_characters = 1200 and e.timeout_seconds = 120)
		end

feature {NONE} -- Fixtures

	last_bus: detachable EVENT_BUS
			-- The latest `posting_dispatcher''s bus - the one its API rings.
			-- Nothing subscribes to it unless a test asks: on ONE processor a
			-- bus wake is a plain call, so a subscribed dispatcher would answer
			-- and post from inside `EVENT_BUS.ring', ringing it again under its
			-- own frame. The server never does that - there the wake is
			-- asynchronous and `ring' returns long before the dispatcher moves.

	last_nick_id: INTEGER_64
			-- The fixture's human member, whose id the store assigned.
		do
			if attached last_nick as n then
				Result := n.id
			end
		end

	last_api: detachable CHAT_API
			-- That fixture's API, so a test can call `dispatcher_post' itself.

	append_ask (a_body: STRING_32)
			-- Put `a_body' in the store as Nick WITHOUT ringing anybody, so two
			-- requests can be sitting on one page before any drain begins.
			-- `say_reason' is the ordinary path; this one exists to build the
			-- shape Larry hit - a request already waiting while the previous
			-- answer is being written.
		require
			room_built: last_service /= Void and last_nick /= Void
			given: not a_body.is_empty
		local
			l_payload: SIMPLE_JSON_OBJECT
		do
			if attached last_service as s and attached last_nick as n then
				create l_payload.make
				if attached s.store.append_event (create {CHAT_EVENT_DRAFT}.make (1, n.id, {CHAT_EVENT_KINDS}.Kind_message, a_body, Void, l_payload, False)) as e then
					check appended: e.id > 0 and e.room_id = 1 end
				end
			end
		end

	drain_reason (a_dispatcher: PARTICIPANT_DISPATCHER; a_room_id: INTEGER_64): STRING_32
			-- Empty when `wake' drained `a_room_id' without raising; the
			-- exception's type and description otherwise. `wake' is what the
			-- bus calls, so this is the production entry point, and a raise
			-- inside it is exactly what the server swallowed in silence.
		require
			positive_room: a_room_id > 0
		local
			l_failed: BOOLEAN
		do
			create Result.make_empty
			if not l_failed then
				a_dispatcher.wake (a_room_id)
			else
				Result.append ({STRING_32} "the drain RAISED")
				if attached (create {EXCEPTION_MANAGER}).last_exception as l_x then
					if attached l_x.original as l_o then
						Result.append ({STRING_32} " ")
						Result.append (l_o.generating_type.name_32)
						if attached l_o.description as l_d then
							Result.append ({STRING_32} ": ")
							Result.append (l_d.to_string_32)
						end
					end
				end
			end
		rescue
			if not l_failed then
				l_failed := True
				retry
			end
		end

	say_reason (a_dispatcher: PARTICIPANT_DISPATCHER; a_body: STRING_32): STRING_32
			-- Empty when Nick could say `a_body' into the fixture's room and
			-- everything it set off came back without raising; the exception's
			-- type and description otherwise.
			--
			-- Post as a member, then drain - which is what the bus's wake does
			-- in the server - with the raise caught and named, so a test can say
			-- WHICH clause broke instead of dying at its first line.
		require
			room_built: last_service /= Void and last_room /= Void and last_nick /= Void
			given: not a_body.is_empty
		local
			l_failed: BOOLEAN
			l_posted: CHAT_RESULT [CHAT_EVENT]
		do
			create Result.make_empty
			if not l_failed then
				if attached last_service as s and attached last_room as r and attached last_nick as n then
					l_posted := s.post_message (n, r, a_body)
					if l_posted.is_success then
						a_dispatcher.wake (r.id)
					else
						Result.append ({STRING_32} "the room refused the message")
					end
				end
			else
				Result.append ({STRING_32} "it RAISED")
				if attached (create {EXCEPTION_MANAGER}).last_exception as l_x then
					if attached l_x.original as l_o then
						Result.append ({STRING_32} " ")
						Result.append (l_o.generating_type.name_32)
						if attached l_o.description as l_d then
							Result.append ({STRING_32} ": ")
							Result.append (l_d.to_string_32)
						end
					end
				end
			end
		rescue
			if not l_failed then
				l_failed := True
				retry
			end
		end

	last_mock: detachable MOCK_PARTICIPANT
			-- The "@mock" participant of the latest `dispatcher' / `posting_dispatcher'.

	last_tool: detachable MOCK_TOOL_PARTICIPANT
			-- The "@tool" participant of the latest `posting_dispatcher'.

	last_limits: detachable RATE_LIMITER
			-- The limiter behind the latest fixture's API.

	last_service: detachable CHAT_SERVICE
			-- The service behind the latest `posting_dispatcher', so a test
			-- may post real messages into the room the dispatcher reads.

	last_room: detachable CHAT_ROOM
			-- The room `posting_dispatcher' built.

	last_nick: detachable CHAT_USER
			-- The stored human member of `last_room' - "Nick", who asks.

	say (a_dispatcher: PARTICIPANT_DISPATCHER; a_body: STRING_32)
			-- Post `a_body' as Nick into the fixture's room and let
			-- `a_dispatcher' drain the room from the store, exactly as the
			-- bus's wake does in the server.
		require
			room_built: last_service /= Void and last_room /= Void and last_nick /= Void
		do
			if attached last_service as s and attached last_room as r and attached last_nick as n then
				if s.post_message (n, r, a_body).is_success then
					a_dispatcher.wake (r.id)
				end
			end
		end

	claude_participant: CLAUDE_CODE_PARTICIPANT
			-- A sandboxed Claude under C:\Users\Public\sc_mention_ctx, built
			-- for the prompt and session laws only - the CLI is never called.
		local
			l_client: CLAUDE_CODE_CLIENT
			l_dir: DIRECTORY
		do
			create l_dir.make ({STRING_32} "C:\Users\Public\sc_mention_ctx\participants\claude")
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
			create l_client.make
			create Result.make ({STRING_32} "@claude", bot ("claude", {STRING_32} "Claude"), l_client,
				{STRING_32} "C:\Users\Public\sc_mention_ctx", {STRING_32} "C:\Users\Public\sc_mention_ctx\participants\claude", 400, 5)
		end

	dispatcher (a_start_after: INTEGER_64): PARTICIPANT_DISPATCHER
			-- A dispatcher over a CHAT_API on the memory store, with "@mock"
			-- registered through the dispatcher's own registry (NEW-1: `make'
			-- builds registry, parser and log itself).
		local
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_service: CHAT_SERVICE
			l_api: CHAT_API
			l_mock: MOCK_PARTICIPANT
		do
			create l_config.make_defaults
			create l_store.make
			l_store.open
			create l_bus.make
			create l_limits.make (3600)
			create l_logger
			create l_log.make (l_logger)
			create l_service.make (l_store, l_bus, l_limits, l_config, l_log)
			create l_api.make (l_service, l_config)
			create l_mock.make ({STRING_32} "@mock", bot ("mock", {STRING_32} "Mock"), {STRING_32} "In the beginning God created")
			last_mock := l_mock
			last_limits := l_limits
			create Result.make (l_api, a_start_after)
			Result.registry.register (l_mock)
		end

	posting_dispatcher (a_start_after: INTEGER_64): PARTICIPANT_DISPATCHER
			-- Like `dispatcher', but the bot user is stored, active and a
			-- member of room 1, so the granted path runs; "@tool" (a mock
			-- tool offering the "@mock" via choice) is registered beside
			-- "@mock", both posting as the same stored bot.
		local
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_service: CHAT_SERVICE
			l_api: CHAT_API
			l_mock: MOCK_PARTICIPANT
			l_tool: MOCK_TOOL_PARTICIPANT
			l_bot, l_nick: CHAT_USER
			l_now: SIMPLE_DATE_TIME
		do
			create l_config.make_defaults
			create l_store.make
			l_store.open
			create l_now.make_now
			create l_bot.make (0, "mock", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Mock", "", False, True, l_now)
			l_store.add_user (l_bot)
			create l_nick.make (0, "nick", {STRING_32} "Nick",
				"0123456789abcdef0123456789abcdef$600000$0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", False, False, l_now)
			l_store.add_user (l_nick)
			l_store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", l_now))
			l_store.add_membership (create {CHAT_MEMBERSHIP}.make (l_store.default_room_id, l_bot.id, {CHAT_MEMBERSHIP}.Role_member, l_now))
			l_store.add_membership (create {CHAT_MEMBERSHIP}.make (l_store.default_room_id, l_nick.id, {CHAT_MEMBERSHIP}.Role_member, l_now))
			create l_bus.make
			create l_limits.make (3600)
			create l_logger
			create l_log.make (l_logger)
			create l_service.make (l_store, l_bus, l_limits, l_config, l_log)
			create l_api.make (l_service, l_config)
			create l_mock.make ({STRING_32} "@mock", l_bot, {STRING_32} "In the beginning God created")
			create l_tool.make ({STRING_32} "@tool", l_bot, {STRING_32} "In the beginning God created the heavens and the earth.")
			l_tool.add_shaper (create {MOCK_SHAPER}.make ({STRING_32} "@mock", {STRING_32} "Gen 1:1"))
			last_mock := l_mock
			last_tool := l_tool
			last_limits := l_limits
			last_service := l_service
			last_room := l_store.room (l_store.default_room_id)
			last_nick := l_nick
			last_bus := l_bus
			last_api := l_api
			create Result.make (l_api, a_start_after)
			Result.registry.register (l_mock)
			Result.registry.register (l_tool)
		end

	registry_with (a_handle: STRING_32): PARTICIPANT_REGISTRY
			-- A registry holding a switched-off participant under `a_handle'.
		do
			create Result.make
			Result.register (create {NULL_PARTICIPANT}.make (a_handle, bot ("off", {STRING_32} "Off")))
		end

	mock_tool (a_handle, a_output: STRING_32): MOCK_TOOL_PARTICIPANT
		do
			create Result.make (a_handle, bot ("tool", {STRING_32} "Tool"), a_output)
		end

	request (a_text: STRING_32; a_via: detachable STRING_32): PARTICIPANT_REQUEST
			-- Member 7 asking `a_text' in room 1 with a 400-character limit.
		do
			create Result.make_addressed (7, {STRING_32} "Nick", a_text, 1, {STRING_32} "main", 400, a_via)
		end

	message (a_id, a_room_id, a_sender_id: INTEGER_64; a_body: STRING_32; a_bot: BOOLEAN): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_now.make (2026, 8, 29, 12, 0, 0)
			create l_payload.make
			create Result.make (a_id, a_room_id, a_sender_id, {CHAT_EVENT_KINDS}.Kind_message, l_now, a_body, Void, l_payload, a_bot)
		end

	system_event (a_id, a_room_id: INTEGER_64; a_body: STRING_32): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_now.make (2026, 8, 29, 12, 0, 0)
			create l_payload.make
			create Result.make (a_id, a_room_id, 0, {CHAT_EVENT_KINDS}.Kind_system, l_now, a_body, Void, l_payload, False)
		end

	page_bytes (a_events: ARRAY [CHAT_EVENT]): STRING_8
			-- `a_events' as the wire page the API would answer.
		local
			l_list: ARRAYED_LIST [CHAT_EVENT]
			l_codec: CHAT_JSON
		do
			create l_list.make (a_events.count)
			across a_events as e loop
				l_list.extend (e)
			end
			create l_codec.make
			Result := l_codec.bytes_of (l_codec.page_to_json (l_list, create {ARRAYED_LIST [CHAT_STATUS]}.make (0)))
		end

	bot (a_username: STRING_8; a_display: STRING_32): CHAT_USER
			-- A stored, active bot whose display name carries the marker.
		local
			l_now: SIMPLE_DATE_TIME
		do
			create l_now.make_now
			create Result.make (0, a_username, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " " + a_display, "", False, True, l_now)
			Result.set_id (99)
		end

	request_wide (a_text: STRING_32; a_max: INTEGER): PARTICIPANT_REQUEST
			-- Member 7 asking `a_text' in room 1 with a chosen reply limit.
		require
			max_positive: a_max > 0
		do
			create Result.make_addressed (7, {STRING_32} "Nick", a_text, 1, {STRING_32} "main", a_max, Void)
		end

	scratch_shape_database: STRING_32
			-- testing/participants_scratch/shape_probe.db bearing the real
			-- shape.db shape (shape + shape_instance, joined on shape_id),
			-- rebuilt each run: two FITS and one FAILS instance of one shape.
		local
			l_dir: DIRECTORY
			l_file: RAW_FILE
			l_db: SIMPLE_SQL_DATABASE
		do
			create l_dir.make (Scratch_directory)
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
			Result := Scratch_directory + {STRING_32} "/shape_probe.db"
			create l_file.make_with_name (Result)
			if l_file.exists then
				l_file.delete
			end
			create l_db.make (Result)
			l_db.perform ("CREATE TABLE shape (shape_id INTEGER PRIMARY KEY, slug TEXT UNIQUE NOT NULL, name TEXT NOT NULL)")
			l_db.perform ("CREATE TABLE shape_instance (instance_id INTEGER PRIMARY KEY, shape_id INTEGER NOT NULL, ref TEXT NOT NULL, verdict TEXT NOT NULL, tier TEXT, grounds TEXT)")
			l_db.perform ("INSERT INTO shape VALUES (1, 'beachhead_that_moves', 'A beachhead that moves')")
			l_db.perform ("INSERT INTO shape_instance VALUES (1, 1, 'JHN 5:19!17', 'FITS', 'T1', 'probe')")
			l_db.perform ("INSERT INTO shape_instance VALUES (2, 1, 'MRK 1:1!1', 'FITS', 'T1', 'probe')")
			l_db.perform ("INSERT INTO shape_instance VALUES (3, 1, 'ACT 16:19!4', 'FAILS', 'T1', 'probe')")
			l_db.close
		end

	population_config_path: STRING_8
			-- A [[participants]] configuration written into the scratch
			-- directory: four buildable entries (one per kind, none
			-- included) and one whose executable does not exist. STRING_8,
			-- because it goes into the shared settings as the config path.
		local
			l_dir: DIRECTORY
			l_file: PLAIN_TEXT_FILE
		do
			create l_dir.make (Scratch_directory)
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
			Result := Scratch_directory.to_string_8 + "/population.toml"
			create l_file.make_with_name (Result)
			l_file.create_read_write
			l_file.put_string ("[
data_dir = "C:/Users/Public/sc_chat_pop/data"

[[participants]]
handle = "@pop-null"
kind = "none"
bot_username = "pop_null_bot"
display_name = "Pop Null"

[[participants]]
handle = "@pop-bible"
kind = "bible_tool"
engine = "C:/Windows/System32/ping.exe"
bot_username = "pop_bible_bot"
display_name = "Pop Bible"
aliases = ["Pop:"]
allow_via = ["plain", "@pop-qwen"]

[[participants]]
handle = "@pop-miss"
kind = "bible_tool"
engine = "C:/Windows/System32/no_such_probe_tool.exe"
bot_username = "pop_miss_bot"
display_name = "Pop Miss"

[[participants]]
handle = "@pop-qwen"
kind = "ollama"
engine = "qwen2.5"
bot_username = "pop_qwen_bot"
display_name = "Pop Qwen"

[[participants]]
handle = "@pop-claude"
kind = "claude_code"
engine = "C:/Users/Public/sc_chat_pop/data/participants/pop-claude"
bot_username = "pop_claude_bot"
display_name = "Pop Claude"
]")
			l_file.close
		end

	Scratch_directory: STRING_32 = "testing/participants_scratch"
			-- Where this class writes its scratch files (the
			-- config-assault pattern; rebuilt by each test that uses it).

end
