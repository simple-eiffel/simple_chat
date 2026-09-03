note
	description: "[
		Something in the room that answers when addressed by its handle:
		an AI, a tool with no AI, or a tool whose output a model phrases.
		Every participant is an ordinary member with a bot identity - a
		stored, active bot user whose display name carries the marker - and
		its own rate limit per asker (addendum 09). Its handle obeys
		PARTICIPANT_RULES, so the limiter key is always ASCII (M1).

		MEMORY (Phase 4). `context_messages' is how many of the room's most
		recent messages the dispatcher attaches to a request, so a follow-up
		("and its cube root?") reaches the engine with the turns it answers.
		Zero - the default for a hand-built participant - means no window at
		all; the [[participants]] configuration sets it, and
		`context_block_of' is the one place a window becomes prompt text, so
		every engine renders it the same way.

		`answer' is a state-changing function by design (`calls', the
		engine): recorded for the Phase 4.5 CQS audit. `in_flight' is what
		a concurrent dispatcher checks before asking (M5); on the one
		dispatcher processor of D1 it is 0 between calls.
	]"
	author: "Larry Rix"

deferred class
	PARTICIPANT

feature -- Access

	handle: STRING_32
			-- "@tools-larry"; lowercase; what a message starts with to address this.

	bot_user: CHAT_USER
			-- The member the answers are posted as.

	calls: INTEGER
			-- Answers attempted so far.

	in_flight: INTEGER
			-- Requests being answered right now; never above `max_concurrent'.

	max_concurrent: INTEGER
			-- How many requests may be in flight at once (1 for Claude).

	max_characters: INTEGER
			-- The longest answer this participant may give.

	context_messages: INTEGER
			-- How many recent room messages come with a request; 0 for a
			-- participant that is told nothing but the question.

	limit_key (a_asker_id: INTEGER_64): STRING_8
			-- The rate-limit key for `a_asker_id' asking this participant.
		require
			positive: a_asker_id > 0
		do
			Result := "p:" + handle.to_string_8 + ":" + a_asker_id.out
		ensure
			prefixed: Result.starts_with ("p:")
			definition: Result.same_string ("p:" + handle.to_string_8 + ":" + a_asker_id.out)
		end

feature -- Element change

	set_context_messages (a_count: INTEGER)
			-- Give this participant a window of `a_count' recent room
			-- messages with every request; 0 takes the window away.
		require
			in_range: a_count >= 0 and a_count <= {PARTICIPANT_RULES}.Context_maximum
		do
			context_messages := a_count
		ensure
			set: context_messages = a_count
		end

feature -- Conversion (contract support)

	context_block_of (a_request: PARTICIPANT_REQUEST): STRING_32
			-- The room's recent conversation as prompt text: a heading, one
			-- line per message oldest first, and a blank line before the
			-- question. Empty when the request carries no window, so an
			-- engine may always prepend it.
		do
			create Result.make (128)
			if not a_request.context_lines.is_empty then
				Result.append ({STRING_32} "Recent messages in this room, oldest first:%N")
				across a_request.context_lines as l loop
					Result.append (l)
					Result.append_character ('%N')
				end
				Result.append ({STRING_32} "%NAnswer the message below, using the conversation above when it is what the message refers to.%N%N")
			end
		ensure
			empty_when_no_window: a_request.context_lines.is_empty implies Result.is_empty
			carries_each: across a_request.context_lines as l all Result.has_substring (l) end
			given_when_window: not a_request.context_lines.is_empty implies not Result.is_empty
		end

feature -- Status report

	permits_via (a_choice: READABLE_STRING_GENERAL): BOOLEAN
			-- May a member steer this participant with "via a_choice"?
			-- False here: a plain participant has no via edge, and the
			-- dispatcher refuses such a request explicitly rather than
			-- dropping the choice silently (NEW-10). Tools redefine this
			-- to their configured shaper choices (`allows_via').
		do
			Result := False
		end

	has_capacity: BOOLEAN
			-- May one more request be answered now?
		do
			Result := in_flight < max_concurrent
		ensure
			definition: Result = (in_flight < max_concurrent)
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
			-- The reply to `a_request', or why there is none. Never raises.
		require
			capacity: has_capacity
		deferred
		ensure
			counted: calls = old calls + 1
			outcome: Result.is_success xor (Result.error /= Void)
			bounded: Result.is_success implies Result.text.count <= a_request.max_characters
			settled: in_flight = old in_flight
		end

feature -- Constants

	Default_max_characters: INTEGER = 1200
			-- The configuration's default answer limit.

invariant
	handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (handle)
	bot_is_bot: bot_user.is_bot
	bot_stored: bot_user.is_stored
	bot_active: bot_user.is_active
	bot_marked: bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
	calls_non_negative: calls >= 0
	concurrency_positive: max_concurrent >= 1
	within_concurrency: in_flight >= 0 and in_flight <= max_concurrent
	max_positive: max_characters > 0
	context_in_range: context_messages >= 0 and context_messages <= {PARTICIPANT_RULES}.Context_maximum

end
