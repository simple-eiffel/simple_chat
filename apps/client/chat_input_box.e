note
	description: "[
		The room's one-line composer: SW_TEXT_BOX with a SUBMIT.

		SW_TEXT_BOX drops Return in single-line mode (a single line has
		nowhere to put a newline) and offers the host no hook for it, so
		Enter-to-send - the gesture every chat client in the world has -
		has nowhere to live. This descendant gives it one: Return fires
		`on_submit' and nothing else changes. Every other key, the whole
		selection model, the undo stack and the clipboard rules are the
		parent's, untouched.

		The widget still owns only what an edit IS. What a submit MEANS -
		posting to the room, refusing an empty line - belongs to the host,
		which is why `on_submit' is an agent and not a call to a client.
	]"
	author: "Larry Rix"

class
	CHAT_INPUT_BOX

inherit
	SW_TEXT_BOX
		redefine
			handle_char
		end

create
	make_single_line

feature -- Access

	on_submit: detachable PROCEDURE
			-- Fired when Return is pressed on a single line.

feature -- Element change

	set_on_submit (a_action: PROCEDURE)
		do
			on_submit := a_action
		ensure
			set: on_submit = a_action
		end

feature -- Input

	handle_char (a_code: INTEGER)
			-- Return submits on a single line; everything else is the parent's.
		do
			if a_code = Return_code and then is_single_line then
				if attached on_submit as a then
					a.call
				end
			else
				Precursor (a_code)
			end
		end

feature -- Constants

	Return_code: INTEGER = 13
			-- The character SW_TEXT_BOX's own `handle_char' tests for a new line.

end
