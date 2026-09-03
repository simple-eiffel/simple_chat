note
	description: "[
		`@qwen' and friends: a local model through OLLAMA_CLIENT as a room
		member - the cheapest AI in the room. Bounded in time like every
		engine (TIMED_ENGINE, Issue 26): the bound is advisory pending an
		OLLAMA_CLIENT timeout API in simple_ai_client (its chat request
		carries no curl --max-time today), so `last_timed_out' derives from
		`elapsed_seconds', an overrun is an error, and `elapsed_seconds' is
		never clamped.

		MEMORY (Phase 4): the local models keep no session, so the room's
		recent messages (`context_block_of' over the request's
		`context_lines') go in front of every question. With
		`context_messages = 0' the prompt is exactly what it always was.
	]"
	author: "Larry Rix"

class
	OLLAMA_PARTICIPANT

inherit
	PARTICIPANT

	TIMED_ENGINE

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_client: OLLAMA_CLIENT; a_model: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			model_given: not a_model.is_empty
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			create handle.make_from_string_general (a_handle)
			bot_user := a_bot_user
			client := a_client
			create model.make_from_string_general (a_model)
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
			max_concurrent := 1
		ensure
			handle_set: handle.same_string_general (a_handle)
			model_set: model.same_string_general (a_model)
			timeout_set: timeout_seconds = a_timeout_seconds
			one_at_a_time: max_concurrent = 1
		end

feature -- Access

	model: STRING_32

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
			-- <Precursor>: one chat completion on the local model, with a
			-- persona that keeps the chat register. A dead or absent
			-- Ollama is an error result (the client answers an error; a
			-- raising engine is caught), never an exception. The bound is
			-- advisory (OLLAMA_CLIENT has no timeout API): an overrun is
			-- recorded and reported as a timeout error.
		local
			l_started, l_now: SIMPLE_DATE_TIME
			l_system, l_prompt: STRING_32
			l_response: detachable AI_RESPONSE
			l_failed: BOOLEAN
		do
			create l_started.make_now
			if not l_failed then
				calls := calls + 1
				client.set_model (model)
				create l_system.make (160)
				l_system.append ({STRING_32} "You are ")
				l_system.append (handle)
				l_system.append ({STRING_32} " in the chat room %"")
				l_system.append (a_request.room_name)
				l_system.append ({STRING_32} "%". Reply in plain text for a chat: brief and direct, at most ")
				l_system.append_string_general (a_request.max_characters.out)
				l_system.append ({STRING_32} " characters. Never invent facts about the people in the room.")
				create l_prompt.make (a_request.text.count + a_request.asker_display_name.count + 8)
				l_prompt.append (context_block_of (a_request))
				l_prompt.append (a_request.asker_display_name)
				l_prompt.append ({STRING_32} " asks: ")
				l_prompt.append (a_request.text)
				l_response := client.ask_with_system (l_system, l_prompt)
			end
			create l_now.make_now
			record_run ((l_now.to_timestamp - l_started.to_timestamp).to_integer_32.max (0))
			if l_failed or l_response = Void then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "the engine raised instead of answering", 503))
			elseif last_timed_out then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "no answer within " + timeout_seconds.out + " seconds", 503))
			elseif attached l_response as l_r and then l_r.is_success and then not l_r.text.is_empty then
				create Result.make_success (l_r.text.head (a_request.max_characters), Void)
			else
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, {STRING_32} "the local model " + model + {STRING_32} " could not answer", 503))
			end
		ensure then
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
		rescue
				-- One retry only: the retried body skips the engine and
				-- answers an error; a second exception (it would have to
				-- come from the recovery path itself) propagates instead of
				-- looping the rescue forever.
			if not l_failed then
				l_failed := True
				retry
			end
		end

feature {NONE} -- Implementation

	client: OLLAMA_CLIENT

invariant
	model_given: not model.is_empty
	one_at_a_time: max_concurrent = 1

end
