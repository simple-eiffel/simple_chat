note
	description: "[
		The participants cluster under assault (Phase 1b): the handle and
		alias rules, the parser's boundary and `via' laws, the tool
		template's two gates and its disclosure law, the sandbox rules,
		the engines' timing contracts, the configuration's completeness,
		and the dispatcher's idempotence, cursors and restart - all on one
		processor, against a CHAT_API over the memory store whose Phase 4
		bodies are stubs: what is asserted is what the code does today.
	]"
	author: "Larry Rix"

class
	PARTICIPANTS_ASSAULT

inherit
	TEST_SET_BASE

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
			assert ("safe text ran once", a.is_success and t.runs = 1 and t.executed_query.same_string ({STRING_32} "Gen 1:1") and t.executed_model.count = 1)
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
			create l_args.make (1)
			l_args.extend ({STRING_32} "Gen 1:1")
			l_output := t.run_tool (l_args)
			assert ("output cut at the maximum", l_output.count = {TOOL_PARTICIPANT}.Output_maximum and t.runs = 1 and t.executed_model.count = 1)
			a := t.answer (request ({STRING_32} "Gen 1:1", Void))
			assert ("reply cut to the room's limit", a.is_success and a.text.count <= 400 and a.text.starts_with ({STRING_32} "> Gen 1:1"))
		end

	test_bible_and_shape_allowlists
		local
			b: BIBLE_TOOL_PARTICIPANT
			s: SHAPE_TOOL_PARTICIPANT
			a: PARTICIPANT_ANSWER
		do
			create b.make ({STRING_32} "@tools-larry", bot ("tools", {STRING_32} "Tools"), {STRING_32} "bible.exe", 1200, 30)
			assert ("verse", b.is_safe_argument ({STRING_32} "Gen 1:1"))
			assert ("range with a book number", b.is_safe_argument ({STRING_32} "1 John 3:16-18"))
			assert ("version prefix", b.is_safe_argument ({STRING_32} "kjv Ps 23"))
			assert ("slash command with one word", b.is_safe_argument ({STRING_32} "/lex H7225"))
			assert ("pipe refused", not b.is_safe_argument ({STRING_32} "Gen 1:1 | dir"))
			assert ("option refused", not b.is_safe_argument ({STRING_32} "-rf"))
			assert ("empty refused", not b.is_safe_argument ({STRING_32} ""))
			assert ("two words after a command refused", not b.is_safe_argument ({STRING_32} "/lex a b"))
			assert ("no digit is no reference", not b.is_safe_argument ({STRING_32} "Genesis"))
			a := b.answer (request ({STRING_32} "Gen 1:1", Void))
			assert ("stub engine says nothing, honestly", not a.is_success and b.runs = 1 and b.executed_query.same_string ({STRING_32} "Gen 1:1"))
			create s.make ({STRING_32} "@shape-larry", bot ("shape", {STRING_32} "Shape"), {STRING_32} "shape.db", 1200, 30)
			assert ("slug", s.is_safe_argument ({STRING_32} "beachhead_that_moves") and s.is_slug ({STRING_32} "a1"))
			assert ("not a slug", not s.is_safe_argument ({STRING_32} "Beachhead") and not s.is_safe_argument ({STRING_32} "a b") and not s.is_safe_argument ({STRING_32} ""))
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
		do
			create c.make
			create p.make ({STRING_32} "@claude", bot ("claude", {STRING_32} "Claude"), c, {STRING_32} "D:\prod\simple_chat\data\participants\claude", 1200, 120)
			assert ("sandboxed", p.tools_disabled and p.is_sandbox_directory (p.working_directory))
			assert ("client pinned", c.working_directory.same_string (p.working_directory))
			assert ("vault refused", not p.is_sandbox_directory_for ({STRING_32} "C:\Users\LJR19\OneDrive\Documents\Obsidian Vault\Scholars\participants\claude", {STRING_32} "@claude"))
			assert ("another handle's directory refused", not p.is_sandbox_directory_for ({STRING_32} "data\participants\qwen", {STRING_32} "@claude"))
			assert ("no participants segment refused", not p.is_sandbox_directory_for ({STRING_32} "data\claude", {STRING_32} "@claude"))
			assert ("forward slashes and a trailing separator", p.is_sandbox_directory_for ({STRING_32} "data/participants/claude/", {STRING_32} "@claude"))
			assert ("no sessions yet", p.sessions_model.is_empty and p.session_of (1) = Void)
			p.remember_session (1, {STRING_32} "sess-1")
			p.remember_session (2, {STRING_32} "sess-2")
			p.remember_session (1, {STRING_32} "sess-1b")
			assert ("per room", attached p.session_of (1) as s1 and then s1.same_string ({STRING_32} "sess-1b"))
			assert ("other room kept", attached p.session_of (2) as s2 and then s2.same_string ({STRING_32} "sess-2"))
			assert ("two rooms", p.sessions_model.count = 2)
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
				create p.make ({STRING_32} "@claude", bot ("claude", {STRING_32} "Claude"), c, {STRING_32} "C:\Users\LJR19\OneDrive\Documents\Obsidian Vault\Scholars", 1200, 120)
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
			create oc.make
			create op.make ({STRING_32} "@qwen", bot ("qwen", {STRING_32} "Qwen"), oc, {STRING_32} "qwen2.5", 1200, 30)
			a := op.answer (request ({STRING_32} "hello", Void))
			assert ("stub engine fails honestly", not a.is_success and op.calls = 1 and op.elapsed_seconds = 0 and not op.last_timed_out and op.timeout_seconds = 30)
			create os.make ({STRING_32} "@qwen", oc, {STRING_32} "qwen2.5", 30)
			create brief.make ({SHAPING_BRIEF}.Purpose_response, {STRING_32} "test", 100)
			st := os.shape ({STRING_32} "hello", brief)
			assert ("stub shaper fails honestly", not st.is_success and os.elapsed_seconds = 0 and os.cost_tier = {SHAPER}.Tier_local)
			create cc.make
			create cs.make ({STRING_32} "@claude", cc, 60)
			st := cs.shape ({STRING_32} "hello", brief)
			assert ("claude shaper stub", not st.is_success and cs.cost_tier = {SHAPER}.Tier_subscription and cs.timeout_seconds = 60)
			brief.add_example ({STRING_32} "Gen 1:1")
			assert ("brief keeps its description", brief.example_count = 1 and brief.example (1).same_string ({STRING_32} "Gen 1:1") and brief.description.same_string ({STRING_32} "test"))
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
			assert ("two wakes, one pending room", d.pending_count = 1 and d.is_pending (1) and d.wake_count = 2)
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
			assert ("two rooms pending", d.pending_count = 2 and d.wake_count = 3)
			d.dispatch_pending
			assert ("both drained, cursors kept", not d.has_pending and d.cursor_of (1) = 3 and d.cursor_of (2) = 7)
		end

feature {NONE} -- Fixtures

	last_mock: detachable MOCK_PARTICIPANT
			-- The "@mock" participant of the latest `dispatcher'.

	dispatcher (a_start_after: INTEGER_64): PARTICIPANT_DISPATCHER
			-- A dispatcher over a CHAT_API on the memory store, with "@mock" registered.
		local
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_service: CHAT_SERVICE
			l_api: CHAT_API
			l_registry: PARTICIPANT_REGISTRY
			l_parser: ADDRESS_PARSER
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
			create l_registry.make
			create l_mock.make ({STRING_32} "@mock", bot ("mock", {STRING_32} "Mock"), {STRING_32} "In the beginning God created")
			l_registry.register (l_mock)
			last_mock := l_mock
			create l_parser.make (l_registry)
			create Result.make (l_api, l_parser, l_log, a_start_after)
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

end
