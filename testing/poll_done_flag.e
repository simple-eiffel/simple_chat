note
	description: "[
		A one-bit rendezvous for an assault that must ask "has that
		processor's loop returned?" WITHOUT joining it.

		Asking the looping processor itself is not an option. A separate
		QUERY is synchronous: it is not answered until the processor is
		free, so an assault that asked SLOW_POLL_HOST whether its loop had
		ended would simply wait for the loop to end - and against a loop
		that never ends it would hang, which is the very defect under
		assault wearing another name.

		This object lives on a processor that does nothing but assign one
		boolean, so it answers at once. An assault can therefore wait with
		a DEADLINE and FAIL when the deadline passes, which is what a test
		is for.
	]"
	author: "Larry Rix"

class
	POLL_DONE_FLAG

create
	make

feature {NONE} -- Initialization

	make
			-- A flag nobody has raised.
		do
		ensure
			down: not is_done
		end

feature -- Status report

	is_done: BOOLEAN
			-- Has the loop this flag watches returned?

feature -- Element change

	note_done
			-- The loop has returned.
		do
			is_done := True
		ensure
			raised: is_done
		end

end
