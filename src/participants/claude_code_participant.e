note
	description: "[
		`@claude' (aliases "Claude:" / "ROBOT:"): answers through
		CLAUDE_CODE_CLIENT - claude -p on Larry's subscription - with a
		persona that keeps the chat register and never fabricates specifics
		about people, and a hard timeout (intent-v2 Q7).

		Sandboxed (decision D3, Issue 33), anchored to the server:
		`working_directory' must be exactly <data_dir>\participants\<handle
		without its "@"> - both paths absolute, compared canonically
		(EiffelBase PATH), never by substring; "." and ".." segments and
		relative paths are refused; and no directory above the sandbox, up
		to the drive root, may contain CLAUDE.md, .claude or MEMORY.md
		(`has_memory_files_above', a real filesystem walk): Claude Code
		loads CLAUDE.md memory from every ancestor of its working
		directory, so D:\prod\CLAUDE.md would load into the child from any
		sandbox under D:\prod. What the directory rule cannot fence, the
		command does: `make' pins the client with --tools "" (no built-in
		tool), --setting-sources "" (no user, project or local settings
		file - no permissions, no hooks; managed policy settings still
		apply) and --strict-mcp-config (no MCP server), all verifiable
		through the client's `extra_arguments'; `tools_disabled' reads the
		client, so `no_tools' is true by construction. Any image it names
		is judged by PARTICIPANT_ANSWER.is_safe_image_path before the
		dispatcher reads it. Sessions are kept per room (`sessions_model'),
		so a conversation in one room never continues another's.

		MEMORY (Phase 4) is carried BOTH ways, and neither alone is trusted.
		The CLI's own `--resume <session id>' continues the room's session
		(`session_of', `remember_session'); a turn that produced no answer
		drops it (`forget_session'), so a session the CLI will not resume is
		never asked for twice and the next turn starts fresh. Under that, and
		on every turn, `contextual_prompt_of' puts the room's last messages
		(PARTICIPANT_REQUEST's `context_lines', filled by the dispatcher from
		the room itself) in front of the question, so a follow-up is
		answerable even on a fresh session, after a restart, or when a resume
		fails.

		A PRIVATE ASK CARRIES NO SESSION AT ALL. A summary is one member's
		own: the dispatcher marks its request `is_private' and hands it the
		room transcript it is to summarise. `session_to_resume_for' returns
		Void for it - the CLI is given no --resume, so the only conversation
		it can see is the transcript in the prompt - and `note_session_from'
		keeps nothing from it, so a private catch-up never becomes what the
		room's next question continues from. Without both halves the engine
		holds two candidate transcripts and answers out of its own: that is
		"@claude sum" coming back with a summary of the CLI session instead
		of the room.
	]"
	author: "Larry Rix"

class
	CLAUDE_CODE_PARTICIPANT

inherit
	PARTICIPANT

	TIMED_ENGINE

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_client: CLAUDE_CODE_CLIENT;
			a_data_dir, a_working_directory: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
			-- A sandboxed Claude in `a_working_directory' - exactly
			-- `a_data_dir'\participants\<handle without "@">, the server's
			-- absolute data directory anchoring it - over `a_client', which
			-- is pinned to the directory, stripped of tools, settings
			-- sources and MCP servers, and given the same timeout.
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			data_dir_given: not a_data_dir.is_empty
			directory_given: not a_working_directory.is_empty
			sandboxed: is_sandbox_directory_for (a_working_directory, a_data_dir, a_handle)
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			create handle.make_from_string_general (a_handle)
			bot_user := a_bot_user
			client := a_client
			create data_dir.make_from_string_general (a_data_dir)
			create working_directory.make_from_string_general (a_working_directory)
			a_client.set_working_directory (working_directory.twin)
			a_client.set_tools_disabled
			a_client.set_setting_sources (No_setting_sources)
			a_client.set_strict_mcp_config
			a_client.set_timeout_seconds (a_timeout_seconds)
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
			max_concurrent := 1
			create sessions.make (4)
		ensure
			handle_set: handle.same_string_general (a_handle)
			data_dir_set: data_dir.same_string_general (a_data_dir)
			directory_set: working_directory.same_string_general (a_working_directory)
			timeout_set: timeout_seconds = a_timeout_seconds
			one_at_a_time: max_concurrent = 1
			no_tools: tools_disabled
			sources_pinned: attached client.setting_sources as s and then s.same_string (No_setting_sources)
			strict_mcp: client.strict_mcp_config
			client_timed: client.timeout_seconds = timeout_seconds
			no_sessions: sessions_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	sessions_model: MML_MAP [INTEGER_64, STRING_32]
			-- Room id -> the session to resume there (I-006).
		do
			create Result
			across sessions as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = sessions.count
		end

feature -- Access

	working_directory: STRING_32
			-- The sandbox the CLI runs in.

	data_dir: STRING_32
			-- The server's absolute data directory the sandbox is anchored under.

	tools_disabled: BOOLEAN
			-- Does the client run the CLI with every built-in tool disabled
			-- (--tools "")? Read from the client, so `no_tools' is true by
			-- construction: `make' sets the flag and nothing unsets it
			-- (Issue 33 - the flag is the command's, not a free boolean).
		do
			Result := client.tools_disabled
		ensure
			definition: Result = client.tools_disabled
		end

	session_of (a_room_id: INTEGER_64): detachable STRING_32
			-- The session to resume in `a_room_id', or Void.
		do
			Result := sessions.item (a_room_id)
		ensure
			consistent: (Result /= Void) = sessions_model.domain.has (a_room_id)
			from_model: attached Result as s implies s.same_string (sessions_model [a_room_id])
		end

	session_to_resume_for (a_request: PARTICIPANT_REQUEST): detachable STRING_32
			-- The CLI session `a_request' may continue with --resume: the
			-- one kept for its room, when that room has a valid one.
			--
			-- VOID FOR A PRIVATE ASK, always. A summary is answered to one
			-- member and posted nowhere, and the conversation it is to
			-- summarise travels in the request as `context_lines'. Resumed
			-- into the room's session, the CLI would hold a second
			-- transcript - its own - nearer to hand than the one in the
			-- prompt, and that is the one it answered out of when Larry
			-- typed "@claude sum".
		require
			positive_room: a_request.room_id > 0
		do
			if not a_request.is_private and then attached session_of (a_request.room_id) as l_session
				and then client.is_valid_session_id (l_session)
			then
				Result := l_session
			end
		ensure
			never_for_a_private_ask: a_request.is_private implies Result = Void
			the_rooms_own: attached Result as r implies (attached session_of (a_request.room_id) as k and then r.same_string (k))
			resumable: attached Result as r implies client.is_valid_session_id (r)
		end

feature -- Status report

	is_sandbox_directory (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_path' this participant's own anchored directory?
		do
			Result := is_sandbox_directory_for (a_path, data_dir, handle)
		ensure
			definition: Result = is_sandbox_directory_for (a_path, data_dir, handle)
		end

	is_sandbox_directory_for (a_path, a_data_dir, a_handle: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_path' exactly `a_data_dir'\participants\<`a_handle'
			-- without its "@">? Both must be absolute; the comparison is
			-- between canonical absolute paths (EiffelBase PATH), never a
			-- substring test; "." and ".." segments are refused outright;
			-- nothing called "obsidian" or "vault" may appear anywhere in
			-- the path; and no directory above the sandbox may contain
			-- CLAUDE.md, .claude or MEMORY.md (`has_memory_files_above').
		local
			l_path, l_data: PATH
		do
			if not a_path.is_empty and not a_data_dir.is_empty and a_handle.count >= 2 and then a_handle.code (1) = 64 then
				create l_path.make_from_string (a_path)
				create l_data.make_from_string (a_data_dir)
				Result := l_path.is_absolute and then l_data.is_absolute
					and then not has_dot_segment (a_path) and then not has_dot_segment (a_data_dir)
					and then canonical_lower (a_path).same_string (canonical_lower (a_data_dir) + {STRING_32} "\participants\" + a_handle.to_string_32.as_lower.substring (2, a_handle.count))
					and then not a_path.to_string_32.as_lower.has_substring ({STRING_32} "obsidian")
					and then not a_path.to_string_32.as_lower.has_substring ({STRING_32} "vault")
					and then not has_memory_files_above (a_path)
			end
		ensure
			absolute: Result implies (create {PATH}.make_from_string (a_path)).is_absolute
			no_dot_segments: Result implies not has_dot_segment (a_path)
			anchored: Result implies canonical_lower (a_path).same_string (canonical_lower (a_data_dir) + {STRING_32} "\participants\" + a_handle.to_string_32.as_lower.substring (2, a_handle.count))
			never_the_vault: Result implies (not a_path.as_lower.has_substring ("obsidian") and not a_path.as_lower.has_substring ("vault"))
			clean_ancestry: Result implies not has_memory_files_above (a_path)
		end

	has_memory_files_above (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Does any directory strictly above `a_path' - its parent, up to
			-- and including the drive root - contain "CLAUDE.md", ".claude"
			-- or "MEMORY.md"? A real filesystem walk, not a name test:
			-- Claude Code loads CLAUDE.md memory from every ancestor of its
			-- working directory, so a sandbox with any of them above it is
			-- no sandbox (Issue 33; D:\prod\CLAUDE.md exists and would load
			-- into `@claude' from any sandbox under D:\prod).
		local
			l_dir: STRING_32
		do
			if not a_path.is_empty then
				from
					l_dir := parent_directory (canonical_of (a_path))
				until
					Result or l_dir.is_empty
				loop
					Result := directory_has_memory_files (l_dir)
					l_dir := parent_directory (l_dir)
				end
			end
		end

	has_dot_segment (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_path' contain a "." or ".." segment?
		do
			across segments_of (a_path.to_string_32) as s loop
				Result := Result or s.same_string ({STRING_32} ".") or s.same_string ({STRING_32} "..")
			end
		end

	segments_of (a_path: READABLE_STRING_32): ARRAYED_LIST [STRING_32]
			-- The non-empty parts of `a_path' between "\" and "/" separators.
		local
			i: INTEGER
			l_part: STRING_32
		do
			create Result.make (8)
			create l_part.make_empty
			from i := 1 until i > a_path.count loop
				if a_path.code (i) = 92 or a_path.code (i) = 47 then
					if not l_part.is_empty then
						Result.extend (l_part)
						create l_part.make_empty
					end
				else
					l_part.append_code (a_path.code (i))
				end
				i := i + 1
			end
			if not l_part.is_empty then
				Result.extend (l_part)
			end
		ensure
			no_empty_parts: across Result as s all not s.is_empty end
		end

feature -- Element change

	remember_session (a_room_id: INTEGER_64; a_session_id: READABLE_STRING_GENERAL)
			-- Continue the conversation of `a_room_id' from `a_session_id' next time.
		require
			positive_room: a_room_id > 0
			session_given: not a_session_id.is_empty
		do
			sessions.force (a_session_id.to_string_32, a_room_id)
		ensure
			mapped: sessions_model |=| (old sessions_model).updated (a_room_id, a_session_id.to_string_32)
			findable: attached session_of (a_room_id) as s and then s.same_string_general (a_session_id)
		end

	forget_session (a_room_id: INTEGER_64)
			-- Start `a_room_id' fresh next time: the session kept for it
			-- could not be resumed, and asking for it again would fail again.
		require
			positive_room: a_room_id > 0
		do
			sessions.remove (a_room_id)
		ensure
			gone: not sessions_model.domain.has (a_room_id)
			others_kept: sessions_model |=| (old sessions_model).removed (a_room_id)
		end

	note_session_from (a_request: PARTICIPANT_REQUEST; a_session_id: detachable READABLE_STRING_GENERAL; a_resumed: BOOLEAN)
			-- Keep, or drop, the session of `a_request''s room now that the
			-- turn is over: `a_session_id' is what the CLI reported, Void
			-- when it reported nothing. A turn that answered nothing after
			-- resuming drops the kept session, so a session the CLI will
			-- not resume is never asked for twice.
			--
			-- A PRIVATE ASK CHANGES NOTHING. A summary is not the room's
			-- conversation, so it may neither become it nor end it: kept,
			-- it would be what the next member's question continues from.
		require
			positive_room: a_request.room_id > 0
		do
			if a_request.is_private then
					-- Nothing: the room's session is not a summary's to set or clear.
			elseif attached a_session_id as l_id and then client.is_valid_session_id (l_id) then
				remember_session (a_request.room_id, l_id)
			elseif a_resumed and then sessions.has (a_request.room_id) then
				forget_session (a_request.room_id)
			end
		ensure
			private_changes_nothing: a_request.is_private implies sessions_model |=| old sessions_model
			kept: (not a_request.is_private and then attached a_session_id as l_id and then client.is_valid_session_id (l_id)) implies
				sessions_model |=| (old sessions_model).updated (a_request.room_id, l_id.to_string_32)
			dropped_only_after_a_resume: (not a_request.is_private and a_resumed
				and then not (attached a_session_id as l_bad and then client.is_valid_session_id (l_bad))) implies
				sessions_model |=| (old sessions_model).removed (a_request.room_id)
			untouched_when_there_was_nothing_to_note: (not a_request.is_private and not a_resumed
				and then not (attached a_session_id as l_none and then client.is_valid_session_id (l_none))) implies
				sessions_model |=| old sessions_model
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
			-- <Precursor>: one `claude -p' call in the sandbox - the client
			-- is already pinned (working directory, --tools "",
			-- --setting-sources "", --strict-mcp-config, this timeout) and
			-- clears ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN in the child,
			-- so the call draws on the login, never on API credit. The
			-- persona is `persona_of' (--append-system-prompt-file), the
			-- prompt `contextual_prompt_of' - the room's recent messages, then
			-- the question; the room's conversation continues through
			-- --resume with `session_to_resume_for', and `note_session_from'
			-- keeps a successful reply's session id per room while a turn
			-- that answered nothing drops the kept session, so the next one
			-- starts fresh on the context window alone. A PRIVATE request
			-- (a summary) resumes nothing and is remembered nowhere: the
			-- conversation it is to work from is in the request itself. The
			-- installed CLI does offer --json-schema for structured output;
			-- v1 deliberately sends no schema and takes the whole result
			-- text as the answer - `image_path' stays Void, so nothing is
			-- invented around a structure that is not needed yet. The bound
			-- is advisory (the client cannot kill the CLI - Issue 26): an
			-- overrun is recorded and reported as a timeout error, and a
			-- raising engine is an error result, never an exception.
		local
			l_started, l_now: SIMPLE_DATE_TIME
			l_response: detachable AI_RESPONSE
			l_failed, l_resumed: BOOLEAN
		do
			create l_started.make_now
			if not l_failed then
				calls := calls + 1
				if attached session_to_resume_for (a_request) as l_session then
					client.set_resume_session (l_session)
					l_resumed := True
				else
					client.clear_resume_session
				end
				l_response := client.ask_with_system (persona_of (a_request), contextual_prompt_of (a_request))
			end
			create l_now.make_now
			record_run ((l_now.to_timestamp - l_started.to_timestamp).to_integer_32.max (0))
			if attached l_response as l_ok and then l_ok.is_success then
				note_session_from (a_request, client.last_session_id, l_resumed)
			else
					-- The turn answered nothing. Had it resumed, the session
					-- may be gone or the CLI refused it: never ask for it
					-- again - the next turn starts fresh on the window alone.
				note_session_from (a_request, Void, l_resumed)
			end
			if l_failed or l_response = Void then
				create Result.make_error (unavailable_error ("the engine raised instead of answering"))
			elseif last_timed_out then
				create Result.make_error (unavailable_error ("no answer within " + timeout_seconds.out + " seconds"))
			elseif attached l_response as l_r and then l_r.is_success and then not l_r.text.is_empty then
				create Result.make_success (scrubbed (l_r.text).head (a_request.max_characters), Void)
			elseif attached l_response as l_e and then attached l_e.error_message as l_message and then not l_message.is_empty then
				create Result.make_error (unavailable_error ({STRING_32} "Claude could not answer: " + l_message.head (200)))
			else
				create Result.make_error (unavailable_error ("Claude answered nothing"))
			end
		ensure then
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
			image_safe: (Result.is_success and then attached Result.image_path as p) implies Result.is_safe_image_path (p)
		rescue
				-- One retry only: the retried body skips the engine and
				-- answers an error; a second exception propagates instead
				-- of looping the rescue forever.
			if not l_failed then
				l_failed := True
				retry
			end
		end

feature -- Conversion (contract support)

	persona_of (a_request: PARTICIPANT_REQUEST): STRING_32
			-- The system prompt: who this participant is, where it speaks,
			-- and the register it must keep - chat length, plain text, no
			-- fabricated specifics about people (intent-v2 Q7).
		do
			create Result.make (256)
			Result.append ({STRING_32} "You are ")
			Result.append (handle)
			Result.append ({STRING_32} ", a participant in the chat room %"")
			Result.append (a_request.room_name)
			Result.append ({STRING_32} "%". Answer the member who addressed you, in plain text for a chat: brief and direct, at most ")
			Result.append_string_general (a_request.max_characters.out)
			Result.append ({STRING_32} " characters. Never invent facts about the people in the room.")
			Result.append (No_tools_clause)
		ensure
			named: Result.has_substring (handle)
			room_named: Result.has_substring (a_request.room_name)
			register_kept: Result.has_substring ({STRING_32} "Never invent facts")
		end

	contextual_prompt_of (a_request: PARTICIPANT_REQUEST): STRING_32
			-- The user prompt with memory: the room's recent messages
			-- (`context_block_of'), then `prompt_of'. Identical to
			-- `prompt_of' when the request carries no window, so a
			-- participant configured with `context_messages = 0' sends
			-- exactly what it always sent.
		do
			Result := context_block_of (a_request) + prompt_of (a_request)
		ensure
			carries_request: Result.ends_with (prompt_of (a_request))
			plain_when_no_window: a_request.context_lines.is_empty implies Result.same_string (prompt_of (a_request))
			window_first: not a_request.context_lines.is_empty implies Result.starts_with (context_block_of (a_request))
		end

	No_tools_clause: STRING_32 = " You are running with NO TOOLS: you cannot read files, list directories, run commands, browse, or reach anything on this computer, and you remember nothing between turns except the room messages you are shown. If you are asked whether you can see a drive, a folder or a file, say plainly that you cannot. NEVER write tool-call markup of any kind and never describe a command you did not run."
			-- The participant is started with --tools "", so it HAS no tools; the
			-- model was not told, and when Larry asked whether it could see his
			-- drive it answered with a tool-call transcript and a directory
			-- listing that was pure invention - the folders it named do not
			-- exist. The sandbox held; the honesty did not. So the persona says
			-- what it is, and `scrubbed' catches it if it says otherwise.

	scrubbed (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' unless it carries TOOL-CALL MARKUP, in which case one
			-- honest sentence instead of the whole of it.
			--
			-- This participant runs with --tools "" and has none. Asked whether
			-- it could see Larry's drive, it answered with an <invoke> block and
			-- a directory listing - and the listing was INVENTED: not one of the
			-- folders it named exists. Nothing was read and nothing escaped the
			-- sandbox, but the room was shown a transcript of work that never
			-- happened, which is worse than a refusal. A reply that contains the
			-- markup of a tool call is, on its face, not an answer this
			-- participant could have produced honestly, so it does not go to
			-- the room.
		do
			if has_tool_markup (a_text) then
				create Result.make_from_string (No_tools_reply)
			else
				create Result.make_from_string (a_text)
			end
		ensure
			never_markup: not has_tool_markup (Result)
			kept_when_clean: not has_tool_markup (a_text) implies Result.same_string (a_text)
			said_something: not Result.is_empty
		end

	has_tool_markup (a_text: READABLE_STRING_32): BOOLEAN
			-- Does `a_text' carry the opening of a tool call in any of the forms
			-- the model writes them? Matched case-insensitively and on the
			-- OPENING only, so a closing tag or a stray word cannot hide one.
		local
			l_low: STRING_32
		do
			l_low := a_text.as_lower
			Result := l_low.has_substring ({STRING_32} "<invoke")
				or l_low.has_substring ({STRING_32} "<parameter")
				or l_low.has_substring ({STRING_32} "<function_calls")
				or l_low.has_substring ({STRING_32} "</invoke")
				or l_low.has_substring ({STRING_32} "</function_calls")
		end

	No_tools_reply: STRING_32 = "I have no tools and no file access in this room - I can only read the messages here, so I cannot look at your drive or your folders."
			-- What the room gets instead of invented work.

	prompt_of (a_request: PARTICIPANT_REQUEST): STRING_32
			-- The user prompt: the asker by display name, then the request.
		do
			create Result.make (a_request.text.count + a_request.asker_display_name.count + 8)
			Result.append (a_request.asker_display_name)
			Result.append ({STRING_32} " asks: ")
			Result.append (a_request.text)
		ensure
			asker_named: Result.starts_with (a_request.asker_display_name)
			carries_request: Result.ends_with (a_request.text)
		end

feature {NONE} -- Implementation

	client: CLAUDE_CODE_CLIENT

	sessions: HASH_TABLE [STRING_32, INTEGER_64]

	unavailable_error (a_message: READABLE_STRING_GENERAL): CHAT_ERROR
		require
			explained: not a_message.is_empty
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, a_message, 503)
		end

	canonical_of (a_path: READABLE_STRING_GENERAL): STRING_32
			-- `a_path' resolved to its canonical form when absolute (no "."
			-- or ".." segment, lexically - EiffelBase PATH); `a_path' itself
			-- otherwise.
		local
			l_p: PATH
		do
			create l_p.make_from_string (a_path)
			if l_p.is_absolute then
				create Result.make_from_string (l_p.canonical_path.name)
			else
				create Result.make_from_string_general (a_path)
			end
		end

	canonical_lower (a_path: READABLE_STRING_GENERAL): STRING_32
			-- The canonical form of `a_path', lowercased (Windows paths
			-- compare case-insensitively).
		do
			Result := canonical_of (a_path)
			Result.to_lower
		end

	parent_directory (a_path: READABLE_STRING_32): STRING_32
			-- The directory above `a_path': "c:\users" above "c:\users\x",
			-- "c:\" above "c:\users", empty above a root or a
			-- separator-free name.
		local
			l_trim: STRING_32
			i: INTEGER
		do
			create l_trim.make_from_string (a_path)
			from
			until
				l_trim.count <= 1 or else (l_trim.code (l_trim.count) /= 92 and l_trim.code (l_trim.count) /= 47)
			loop
				l_trim.remove_tail (1)
			end
			i := l_trim.count
			from until i < 1 or else (l_trim.code (i) = 92 or l_trim.code (i) = 47) loop
				i := i - 1
			end
			if i >= 2 then
				Result := l_trim.substring (1, i)
				if not (Result.count = 3 and then Result.code (2) = 58) then
					Result.remove_tail (1)
				end
			else
				create Result.make_empty
			end
		ensure
			shorter: Result.count < a_path.count or a_path.is_empty
		end

	directory_has_memory_files (a_dir: READABLE_STRING_32): BOOLEAN
			-- Does `a_dir' contain CLAUDE.md, .claude or MEMORY.md (file or directory)?
		local
			l_base: STRING_32
		do
			create l_base.make_from_string (a_dir)
			if l_base.is_empty or else (l_base.code (l_base.count) /= 92 and l_base.code (l_base.count) /= 47) then
				l_base.append_character ('\')
			end
			Result := path_exists (l_base + {STRING_32} "CLAUDE.md")
				or else path_exists (l_base + {STRING_32} ".claude")
				or else path_exists (l_base + {STRING_32} "MEMORY.md")
		end

	path_exists (a_path: READABLE_STRING_32): BOOLEAN
			-- Is there a file or a directory at `a_path'?
		local
			l_file: RAW_FILE
			l_dir: DIRECTORY
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists
			if not Result then
				create l_dir.make (a_path)
				Result := l_dir.exists
			end
		end

feature -- Constants

	No_setting_sources: STRING_8 = ""
			-- The safe minimal `--setting-sources' value: load no user,
			-- project or local settings file (managed policy settings still
			-- apply - the CLI offers no flag past those).

invariant
	sandboxed: is_sandbox_directory (working_directory)
	client_sandboxed: client.working_directory.same_string (working_directory)
	no_tools: tools_disabled
	settings_pinned: attached client.setting_sources as s and then s.is_empty
	strict_mcp: client.strict_mcp_config
	client_timed: client.timeout_seconds = timeout_seconds
	one_at_a_time: max_concurrent = 1
	sessions_consistent: sessions_model.count = sessions.count
	data_dir_given: not data_dir.is_empty

end
