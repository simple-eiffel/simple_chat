note
	description: "[
		What the client's window must be able to show; nothing about how.
		SW_CHAT_VIEW (apps/client, simple_widgets) draws it once
		simple_shaping renders Hebrew; MEMORY_CHAT_VIEW records it for the
		assault. The presenter talks only to this. `shown_model' - the ids
		shown, in order - is part of the contract so that a presenter's
		pump can be proved to show each event once and in order without
		reaching into a poller.
	]"
	author: "Larry Rix"

deferred class
	CHAT_VIEW

feature -- Model Queries (for MML postconditions)

	shown_model: MML_SEQUENCE [INTEGER_64]
			-- Ids shown, in order.
		deferred
		ensure
			same_count: Result.count = shown_count
		end

feature -- Access

	shown_count: INTEGER
			-- Events shown so far.
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Status report

	is_foreground: BOOLEAN
			-- Is the room window in front of the member right now?
		deferred
		end

feature -- Basic operations

	show_event (a_event: CHAT_EVENT; a_sender_name: READABLE_STRING_GENERAL; a_mine: BOOLEAN)
			-- One event, attributed; `a_mine' places it as the member's own.
		require
			named: not a_sender_name.is_empty
		deferred
		ensure
			counted: shown_count = old shown_count + 1
			appended: shown_model |=| ((old shown_model) & a_event.id)
		end

	show_status (a_text: READABLE_STRING_GENERAL)
			-- An ephemeral line ("🤖 Claude is thinking…"); replaces the previous one.
		deferred
		ensure
			events_unchanged: shown_model |=| old shown_model
		end

	show_error (a_message: READABLE_STRING_GENERAL)
		require
			explained: not a_message.is_empty
		deferred
		ensure
			events_unchanged: shown_model |=| old shown_model
		end

	show_connection (a_endpoint: CHAT_ENDPOINT; a_connected: BOOLEAN)
			-- Which server, and whether it answers.
		deferred
		ensure
			events_unchanged: shown_model |=| old shown_model
		end

end
