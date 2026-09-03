note
	description: "[
		The door: server, name, password, "remember me" - and one line
		that says why the last attempt was refused.

		IT DOES NOT LOG ANYBODY IN. `attempt' is an agent the host
		supplies; it answers Void when the session was opened and the
		message to show when it was not. That is what keeps this class
		assaultable with no server anywhere: the assault scripts the
		agent and drives `try_login' exactly as the button does.

		VALIDATION IS THIS CLASS'S, THE VERDICT IS THE SERVER'S. Three
		things are refused here because CHAT_CLIENT's own preconditions
		would otherwise be violated rather than reported: an address that
		is not https and not this machine's loopback (CHAT_URL_RULES, the
		same rule CHAT_ENDPOINT is built on), a name that is empty or not
		plain ASCII (`CHAT_CLIENT.login' takes a READABLE_STRING_8), and
		an empty password. Everything else - a wrong password, a locked
		account, a server that is not answering - comes back from the
		host's agent as a message, because only the server knows.

		THE ORDER OF WINDOWS. simple_shell owns ONE native window at a
		time, so this one runs and closes BEFORE the room pane is shown;
		it is not a modal dialog over the chat window and must never try
		to be.
	]"
	author: "Larry Rix"

class
	LOGIN_WINDOW

inherit
	CHAT_URL_RULES

create
	make

feature {NONE} -- Initialization

	make (a_server_url: READABLE_STRING_8; a_x, a_y: INTEGER)
			-- The door, prefilled with `a_server_url' (SERVICE_LOCATOR's answer, or the
			-- configured primary), at `a_x', `a_y'.
		require
			sane_position: a_x >= 0 and a_y >= 0
		local
			l_root: SW_COLUMN
			l_buttons: SW_ROW
			l_server_label, l_username_label, l_password_label: SW_LABEL
		do
			create theme.make_dark
				-- READABILITY. SW_THEME ships body text at 16 px; at arm's length
				-- on a high-DPI panel that is small, and Larry asked for two to
				-- three times it. `set_text_scale' multiplies every type role at
				-- once - body, label and chip together - so the proportions of the
				-- design are kept and only the size changes. Its own precondition
				-- caps the range at 0.5 .. 3.0.
				--
				-- Bubble heights follow, because a bubble is measured from
				-- `layout.total_height' and never from a line count times a
				-- constant - the one rule that makes scaling safe here.
			theme.set_text_scale (Text_scale)
			create window.make (Window_title, a_x, a_y, Window_width, Window_height, theme)
			window.enable_shaped_text
			create server_box.make_single_line (a_server_url)
			create username_box.make_single_line ("")
			create password_box.make_password ("")
			create remember_box.make (Text_remember, True, Void)
				-- THE REFUSAL LINE HAS TO BE ABLE TO BE THREE LINES. Since Phase 4's
				-- no-server pass it can carry CONNECTION_ADVICE - two sentences naming
				-- what to do next - and a single-line SW_LABEL would simply run off the
				-- right edge and take the instruction with it. `with_wrap' breaks it at
				-- word boundaries to the form's width instead.
				--
				-- The nominal size is NOT the form's: SW_LABEL steps a wrapped line by
				-- `size + 9.0' while SW_PAINTER draws it at `size * theme.text_scale',
				-- so at `Text_scale' 2.0 the two only agree while the nominal size stays
				-- small. `Error_text_size' is where they do.
			create error_label.make ({STRING_32} "", {SW_PAINTER}.Role_ui, Error_text_size, False)
			error_label.with_wrap.do_nothing
			create login_button.make_primary (Text_login, Void)
			create cancel_button.make (Text_cancel, Void)
			create l_buttons.make
			l_buttons.put (login_button)
			l_buttons.put (cancel_button)
			create l_root.make
			create l_server_label.make_ui (Text_server)
			create l_username_label.make_ui (Text_username)
			create l_password_label.make_ui (Text_password)
			l_root.put (l_server_label)
			l_root.put (server_box)
			l_root.put (l_username_label)
			l_root.put (username_box)
			l_root.put (l_password_label)
			l_root.put (password_box)
			l_root.put (remember_box)
			l_root.put (error_label)
			l_root.put (l_buttons)
			root := l_root
			window.set_root (l_root)
				-- The agents come LAST: an agent on Current lets Current escape, so every
				-- attribute has to be set before one is made (void safety, not taste).
			login_button.set_on_click (agent try_login)
			cancel_button.set_on_click (agent cancel)
		ensure
			prefilled: server_box.text.same_string_general (a_server_url)
			nothing_typed: username.is_empty and password.is_empty
			open: not is_accepted and not is_cancelled
			remembers_by_default: remembers
			nothing_refused: last_error = Void
		end

feature -- Access

	window: SW_WINDOW
			-- The native window and its pump.

	root: SW_COLUMN
			-- The form.

	server_box: SW_TEXT_BOX
	username_box: SW_TEXT_BOX
	password_box: SW_TEXT_BOX
	remember_box: SW_CHECK_BOX

	last_error: detachable STRING_32
			-- Why the last attempt was refused; Void until one is.

	attempt: detachable FUNCTION [READABLE_STRING_8, READABLE_STRING_8, READABLE_STRING_GENERAL, detachable STRING_32]
			-- The host's login: server, name, password in; Void out on success, and the
			-- message to show on failure. Void here means the button does nothing at all.

	server_url: STRING_8
			-- What is typed in the address box, when it is plain ASCII; empty otherwise.
		do
			Result := ascii_of (server_box.text)
		end

	username: STRING_8
			-- What is typed in the name box, when it is plain ASCII; empty otherwise.
		do
			Result := ascii_of (username_box.text)
		end

	password: STRING_32
			-- What is typed in the masked box. Never stored, never logged, never saved.
		do
			Result := password_box.text
		end

feature -- Status report

	remembers: BOOLEAN
			-- Should the session be sealed into the config (DPAPI) on success?
		do
			Result := remember_box.is_checked
		end

	is_accepted: BOOLEAN
			-- Did an attempt succeed?

	is_cancelled: BOOLEAN
			-- Did the member give up (Cancel, or the window closed)?

	validation_error: detachable STRING_32
			-- Why the fields as they stand cannot even be tried; Void when they can.
		do
			if server_url.is_empty or else not is_acceptable_url (server_url) then
				Result := Text_bad_server
			elseif username.is_empty then
				Result := Text_bad_username
			elseif across username as c some c.natural_32_code <= 32 end then
				Result := Text_bad_username
			elseif password.is_empty then
				Result := Text_bad_password
			end
		ensure
			url_checked: (Result = Void) implies is_acceptable_url (server_url)
			named: (Result = Void) implies not username.is_empty
			secret_given: (Result = Void) implies not password.is_empty
		end

	is_usable: BOOLEAN
			-- Can the fields as they stand be tried at all?
		do
			Result := validation_error = Void
		ensure
			definition: Result = (validation_error = Void)
		end

feature -- Element change

	set_attempt (a_action: FUNCTION [READABLE_STRING_8, READABLE_STRING_8, READABLE_STRING_GENERAL, detachable STRING_32])
			-- What the Log in button actually tries.
		do
			attempt := a_action
		ensure
			set: attempt = a_action
		end

	set_fields (a_server, a_username: READABLE_STRING_8; a_password: READABLE_STRING_GENERAL; a_remember: BOOLEAN)
			-- Fill the form (a prefill, or an assault typing into it).
		do
			server_box.set_text (a_server)
			username_box.set_text (a_username)
			password_box.set_text (a_password)
			remember_box.set_checked (a_remember)
		ensure
			server_set: server_box.text.same_string_general (a_server)
			username_set: username_box.text.same_string_general (a_username)
			password_set: password_box.text.same_string_general (a_password)
			remember_set: remembers = a_remember
		end

feature -- Basic operations

	try_login
			-- Validate, then ask the host. A refusal is a line on the form, never an exception.
		require
			open: not is_accepted
		local
			l_why: detachable STRING_32
		do
			l_why := validation_error
			if l_why = Void and then attached attempt as a then
				l_why := a.item ([server_url, username, password])
			end
			if l_why = Void and then attached attempt then
				is_accepted := True
				last_error := Void
				error_label.set_text ({STRING_32} "")
				close
			elseif attached l_why as w then
				last_error := w
				error_label.set_text (w)
				redraw
			end
		ensure
			accepted_was_usable: is_accepted implies is_usable
			refusal_explained: (not is_accepted and not is_usable) implies attached last_error
			never_uncancelled: is_accepted implies not is_cancelled
		end

	cancel
			-- The member gave up; the pump ends and the host does not open a room.
		do
			is_cancelled := True
			close
		ensure
			cancelled: is_cancelled
		end

	run
			-- Show the door and pump until it closes. Blocks the caller. A window shut
			-- with no successful attempt counts as a cancellation, whichever way it shut.
		do
			if username.is_empty then
				window.give_focus (username_box)
			else
				window.give_focus (password_box)
			end
			window.run
			if not is_accepted then
				is_cancelled := True
			end
		ensure
			settled: is_accepted xor is_cancelled
		end

	close
			-- End the pump from the program's side.
		do
			if window.hwnd /= default_pointer then
				window.close
			end
		end

feature -- Constants

	Window_title: STRING_32 = "simple_chat - log in"
	Window_width: INTEGER = 640
	Window_height: INTEGER = 420
			-- Wider and taller than Task 10's 460 x 340: the refusal line now wraps
			-- CONNECTION_ADVICE, and an instruction the member cannot read whole is
			-- no instruction.

	Error_text_size: REAL_64 = 9.0
			-- The nominal size of the refusal line, drawn at `Error_text_size' *
			-- `Text_scale'. See the note in `make': a wrapped SW_LABEL steps its lines
			-- by `size + 9.0' and paints them at `size * text_scale', so the nominal
			-- size has to stay under about 7.3 for the two to agree exactly; 9.0 buys
			-- back readable height (18 px drawn) at a two-pixel tightening between
			-- lines, which is the trade Larry's eyes want.

	Text_server: STRING_32 = "Server"
	Text_username: STRING_32 = "Name"
	Text_password: STRING_32 = "Password"
	Text_remember: STRING_32 = "Remember me on this PC"
	Text_login: STRING_32 = "Log in"
	Text_cancel: STRING_32 = "Cancel"

	Text_bad_server: STRING_32 = "The server address must be https://... or this machine's http://127.0.0.1:<port>"
	Text_bad_username: STRING_32 = "Type your name: plain letters and digits, no spaces"
	Text_bad_password: STRING_32 = "Type your password"

feature {NONE} -- Text

	ascii_of (a_text: STRING_32): STRING_8
			-- `a_text' as bytes when every character is plain ASCII; empty otherwise, so a
			-- non-ASCII field is refused by `validation_error' and never reaches `to_string_8'.
		do
			create Result.make (a_text.count)
			if across a_text as c all c.natural_32_code < 128 end then
				across a_text as c loop
					Result.append_character (c.to_character_8)
				end
			end
		ensure
			same_when_ascii: (across a_text as c all c.natural_32_code < 128 end) implies Result.count = a_text.count
			empty_when_not: (across a_text as c some c.natural_32_code >= 128 end) implies Result.is_empty
		end

feature {NONE} -- Painting

	redraw
		do
			if window.hwnd /= default_pointer then
				window.request_render
			end
		end

feature {NONE} -- Implementation

	theme: SW_THEME
	error_label: SW_LABEL
	login_button: SW_BUTTON
	cancel_button: SW_BUTTON

feature -- Constants

	Text_scale: REAL_64 = 2.0
			-- How much larger than SW_THEME's own sizes this window draws
			-- its text. 1.0 is the library default; 2.0 is twice that.
			-- SW_THEME.set_text_scale caps the range at 0.5 .. 3.0, so 3.0
			-- is the most that can be asked for.

invariant
	one_outcome_at_most: not (is_accepted and is_cancelled)
	refusal_is_explained: (attached last_error as e) implies not e.is_empty

end
