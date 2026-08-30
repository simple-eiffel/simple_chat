note
	description: "[
		CHAT_VIEW that remembers what it was told: the presenter's test
		double. `set_flips_on_show' makes every shown event toggle
		`is_foreground' - the assault's way of bringing the window to the
		front, or sending it back, in the middle of a pump.
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
			create status.make_empty
			is_foreground := True
		ensure
			nothing_shown: shown_count = 0
			in_front: is_foreground
			steady: not flips_on_show
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
	status: STRING_32
	mine_count: INTEGER
	connected: BOOLEAN
	endpoint: detachable CHAT_ENDPOINT

feature -- Status report

	is_foreground: BOOLEAN

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
			connected := a_connected
		end

invariant
	model_consistent: shown_model.count = shown_ids.count

end
