note
	description: "[
		`@claude' (aliases "Claude:" / "ROBOT:"): answers through
		CLAUDE_CODE_CLIENT - claude -p on Larry's subscription - with a
		persona that keeps the chat register and never fabricates specifics
		about people, and a hard timeout (intent-v2 Q7).

		Sandboxed (decision D3, Issue 33): the working directory is the
		participant's own - <data_dir>/participants/<handle> - never the
		vault, so no skill, memory or private note loads for whoever can
		type "@claude"; its tools stay disabled (`tools_disabled'); the
		client is pinned to that directory. Any image it names is judged
		by PARTICIPANT_ANSWER.is_safe_image_path before the dispatcher
		reads it. Sessions are kept per room (`sessions_model'), so a
		conversation in one room never continues another's.
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
			a_working_directory: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			directory_given: not a_working_directory.is_empty
			sandboxed: is_sandbox_directory_for (a_working_directory, a_handle)
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			create handle.make_from_string_general (a_handle)
			bot_user := a_bot_user
			client := a_client
			create working_directory.make_from_string_general (a_working_directory)
			a_client.set_working_directory (working_directory.twin)
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
			max_concurrent := 1
			tools_disabled := True
			create sessions.make (4)
		ensure
			handle_set: handle.same_string_general (a_handle)
			directory_set: working_directory.same_string_general (a_working_directory)
			timeout_set: timeout_seconds = a_timeout_seconds
			one_at_a_time: max_concurrent = 1
			no_tools: tools_disabled
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

	tools_disabled: BOOLEAN
			-- The CLI runs with no tools: chat text drives a model, never an agent.

	session_of (a_room_id: INTEGER_64): detachable STRING_32
			-- The session to resume in `a_room_id', or Void.
		do
			Result := sessions.item (a_room_id)
		ensure
			consistent: (Result /= Void) = sessions_model.domain.has (a_room_id)
			from_model: attached Result as s implies s.same_string (sessions_model [a_room_id])
		end

feature -- Status report

	is_sandbox_directory (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_path' this participant's own directory?
		do
			Result := is_sandbox_directory_for (a_path, handle)
		ensure
			definition: Result = is_sandbox_directory_for (a_path, handle)
		end

	is_sandbox_directory_for (a_path, a_handle: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_path' the dedicated directory of `a_handle': its last two
			-- segments "participants" and the handle without its "@", and nothing
			-- called "obsidian" or "vault" anywhere in it (case-insensitively)?
		local
			l_lower: STRING_32
			l_segments: ARRAYED_LIST [STRING_32]
		do
			l_lower := a_path.to_string_32.as_lower
			l_segments := segments_of (l_lower)
			Result := a_handle.count >= 2 and l_segments.count >= 2
				and then l_segments [l_segments.count - 1].same_string_general ("participants")
				and then l_segments [l_segments.count].same_string_general (a_handle.as_lower.substring (2, a_handle.count))
				and then not l_lower.has_substring ("obsidian") and then not l_lower.has_substring ("vault")
		ensure
			never_the_vault: Result implies (not a_path.as_lower.has_substring ("obsidian") and not a_path.as_lower.has_substring ("vault"))
			under_participants: Result implies a_path.as_lower.has_substring ("participants")
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

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		do
			calls := calls + 1
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4: persona system prompt; client in working_directory with tools disabled;
			-- --resume session_of (a_request.room_id); --json-schema {text, image_path}; record_run; kill at timeout
		ensure then
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
			image_safe: (Result.is_success and then attached Result.image_path as p) implies Result.is_safe_image_path (p)
		end

feature {NONE} -- Implementation

	client: CLAUDE_CODE_CLIENT

	sessions: HASH_TABLE [STRING_32, INTEGER_64]

invariant
	sandboxed: is_sandbox_directory (working_directory)
	client_sandboxed: client.working_directory.same_string (working_directory)
	no_tools: tools_disabled
	one_at_a_time: max_concurrent = 1
	sessions_consistent: sessions_model.count = sessions.count

end
