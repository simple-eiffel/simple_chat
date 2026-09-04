note
	description: "[
		SUMMARY_HOST's shape with the wire replaced by a sleep: a
		processor of its own that takes `delay_milliseconds' to produce an
		answer and then leaves it in the REAL SUMMARY_SLOT, exactly as the
		shipped host does after a `claude -p' run.

		It exists to time the GUI. The whole point of the summary design
		is that the window keeps its 250 ms heartbeat while the engine
		takes seconds, so the assault needs a summary that is reliably
		slow and needs no server, no network and no subscription.
	]"
	author: "Larry Rix"

class
	SLOW_SUMMARY_HOST

create
	make

feature {NONE} -- Initialization

	make (a_delay_milliseconds: INTEGER)
		require
			non_negative: a_delay_milliseconds >= 0
		do
			delay_milliseconds := a_delay_milliseconds
		ensure
			set: delay_milliseconds = a_delay_milliseconds
			no_slot: slot = Void
		end

feature -- Access

	delay_milliseconds: INTEGER

	has_slot: BOOLEAN
			-- Has the slot been handed in?
		do
			Result := slot /= Void
		end

feature -- Basic operations

	set_slot (a_slot: separate SUMMARY_SLOT)
		do
			slot := a_slot
		ensure
			set: slot = a_slot
		end

	fetch (a_room_id: INTEGER_64)
			-- Sleep, then answer - an engine that takes its time. Asynchronous
			-- from the caller's side: nothing but a scalar crosses.
		require
			has_slot: has_slot
			positive_room: a_room_id > 0
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			if delay_milliseconds > 0 then
				create l_env
				l_env.sleep (delay_milliseconds.to_integer_64 * 1_000_000)
			end
			if attached slot as s then
				deliver (s)
			end
		end

feature {NONE} -- Implementation

	slot: detachable separate SUMMARY_SLOT

	deliver (a_slot: separate SUMMARY_SLOT)
		do
			a_slot.put_text (Answer)
		end

	Answer: STRING_32 = "Decided: the roof job starts Monday. Still open: the skip hire."

end
