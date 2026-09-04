note
	description: "[
		CHAT_VIEW that remembers what it was told: the presenter's test
		double. `set_flips_on_show' makes every shown event toggle
		`is_foreground' - the assault's way of bringing the window to the
		front, or sending it back, in the middle of a pump.
		`connection_count' counts the `show_connection' calls, so the
		assault can prove the presenter revises the connection state only
		when it changes.
	]"
	author: "Larry Rix"

class
	MEMORY_CHAT_VIEW

inherit
	CHAT_VIEW

create
	make

feature {NONE} -- Initialization

	make
		do
			create shown_ids.make (16)
			create errors.make (4)
			create hints.make (4)
			create status.make_empty
			is_foreground := True
		ensure
			nothing_shown: shown_count = 0
			in_front: is_foreground
			steady: not flips_on_show
			nothing_said_of_the_server: not is_connected and connection_count = 0
		end

feature -- Model Queries (for MML postconditions)

	shown_model: MML_SEQUENCE [INTEGER_64]
		do
			create Result
			across shown_ids as ic loop
				Result := Result & ic
			end
		end

feature -- Access

	shown_count: INTEGER
		do
			Result := shown_ids.count
		end

	shown_ids: ARRAYED_LIST [INTEGER_64]
	errors: ARRAYED_LIST [STRING_32]
	hints: ARRAYED_LIST [STRING_32]
			-- Every `show_hint' text, in order - the assault's window onto them.
	status: STRING_32
	mine_count: INTEGER
	endpoint: detachable CHAT_ENDPOINT

	connection_count: INTEGER
			-- `show_connection' calls so far.

feature -- Status report

	is_foreground: BOOLEAN

	is_connected: BOOLEAN
			-- What the last `show_connection' said; False until one.

	hint_count: INTEGER
			-- How many `show_hint' calls have landed.
		do
			Result := hints.count
		end

	flips_on_show: BOOLEAN
			-- Does each `show_event' toggle `is_foreground'?

feature -- Element change

	set_foreground (a_value: BOOLEAN)
		do
			is_foreground := a_value
		ensure
			set: is_foreground = a_value
		end

	set_flips_on_show (a_value: BOOLEAN)
		do
			flips_on_show := a_value
		ensure
			set: flips_on_show = a_value
		end

feature -- Basic operations

	show_event (a_event: CHAT_EVENT; a_sender_name: READABLE_STRING_GENERAL; a_mine: BOOLEAN)
		do
			shown_ids.extend (a_event.id)
			if a_mine then
				mine_count := mine_count + 1
			end
			if flips_on_show then
				is_foreground := not is_foreground
			end
		ensure then
			flipped: flips_on_show implies is_foreground = not old is_foreground
			steady: not flips_on_show implies is_foreground = old is_foreground
		end

	apply_edit (a_event_id: INTEGER_64; a_text: READABLE_STRING_GENERAL)
			-- Recorded, and only for a message this view actually showed and
			-- has not tombstoned - the same two guards the real view applies,
			-- so an assault against this one is an assault against that one.
		do
			if shown_ids.has (a_event_id) and then not deleted_ids.has (a_event_id) then
				edited_text.force (a_text.to_string_32, a_event_id)
			end
		end

	apply_delete (a_event_id: INTEGER_64)
		do
			if shown_ids.has (a_event_id) then
				deleted_ids.extend (a_event_id)
			end
		end

	apply_reactions (a_event_id: INTEGER_64; a_list: LIST [TUPLE [emoji: STRING_32; tally: INTEGER; mine: BOOLEAN]])
		local
			l_copy: ARRAYED_LIST [TUPLE [emoji: STRING_32; tally: INTEGER; mine: BOOLEAN]]
		do
			if shown_ids.has (a_event_id) and then not deleted_ids.has (a_event_id) then
				create l_copy.make (a_list.count)
				across a_list as r loop
					l_copy.extend ([r.emoji.twin, r.tally, r.mine])
				end
				reaction_rows.force (l_copy, a_event_id)
			end
		end

	apply_reply_quote (a_event_id: INTEGER_64; a_author, a_text: READABLE_STRING_GENERAL)
		do
			if shown_ids.has (a_event_id) and then not deleted_ids.has (a_event_id) then
				quotes.force (a_author.to_string_32 + {STRING_32} ": " + a_text.to_string_32, a_event_id)
			end
		end

feature -- What the fold did (for the assaults)

	edited_text: HASH_TABLE [STRING_32, INTEGER_64]
		attribute
			create Result.make (4)
		end

	deleted_ids: ARRAYED_LIST [INTEGER_64]
		attribute
			create Result.make (4)
		end

	reaction_rows: HASH_TABLE [ARRAYED_LIST [TUPLE [emoji: STRING_32; tally: INTEGER; mine: BOOLEAN]], INTEGER_64]
		attribute
			create Result.make (4)
		end

	quotes: HASH_TABLE [STRING_32, INTEGER_64]
		attribute
			create Result.make (4)
		end

	is_tombstoned (a_event_id: INTEGER_64): BOOLEAN
		do
			Result := deleted_ids.has (a_event_id)
		end

feature -- Showing

	show_status (a_text: READABLE_STRING_GENERAL)
		do
			status := a_text.to_string_32
		end

	show_error (a_message: READABLE_STRING_GENERAL)
		do
			errors.extend (a_message.to_string_32)
		ensure then
			kept: errors.count = old errors.count + 1
		end

	show_connection (a_endpoint: CHAT_ENDPOINT; a_connected: BOOLEAN)
		do
			endpoint := a_endpoint
			is_connected := a_connected
			connection_count := connection_count + 1
		ensure then
			counted: connection_count = old connection_count + 1
			endpoint_kept: endpoint = a_endpoint
		end

	show_hint (a_text: READABLE_STRING_GENERAL)
		do
			hints.extend (a_text.to_string_32)
		ensure then
			kept: hints.count = old hints.count + 1 and hints.last.same_string_general (a_text)
		end

invariant
	model_consistent: shown_model.count = shown_ids.count
	connections_non_negative: connection_count >= 0
	hint_count_matches: hint_count = hints.count

end
