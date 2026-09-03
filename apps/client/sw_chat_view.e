note
	description: "[
		The room, on screen: CHAT_VIEW effected over simple_widgets, with
		no browser process anywhere on the machine (D-015).

		THE PANE. An SW_CHAT_THREAD with SHAPED TEXT ENABLED - the whole
		reason this class waited for simple_shaping.
		`SW_WINDOW.enable_shaped_text' builds one SW_SHAPING kit for the
		window's life (a simple_shaping facade plus its cairo bridge, the
		layout cache and the decoded emoji surfaces surviving every theme
		swap and every offscreen re-allocation) and points it at the Noto
		artwork beside the RUNNING EXECUTABLE. That is what makes the
		acceptance line come out with the Hebrew rightmost, the robot as
		the same picture on every member's screen and the Greek intact.
		Missing artwork is not a crash: simple_shaping degrades to a note
		and a box, so a client run out of an unstaged F_code still talks -
		it just does not draw the robot.

		WHAT IT SHOWS AND WHAT IT DOES NOT. Text messages become bubbles by
		role (mine right, theirs left, system centred). An IMAGE event
		becomes an attachment LINE - a marker, the original file name, the
		byte count and the caption - and not the picture itself: WIC
		decoding is the deferred half of D-020 and no image decoder is
		linked into this client. That is a deliberate, stated limit, not
		an oversight; the wire already carries the bytes and the name.

		THE UNREAD BADGE. CHAT_PRESENTER owns the count; this class only
		SHOWS it, through `set_unread', which the host calls after every
		pump. It goes in the header strip, beside the room name. It does
		NOT go in the native title bar: simple_shell publishes no
		SetWindowText and is not this project's to change, so the two
		places a member can see the count are this strip and the tray
		tooltip TRAY_NOTIFIER keeps.

		IS THE ROOM IN FRONT? The presenter's whole unread law turns on
		`is_foreground', and simple_shell raises no activation event. So
		the question is put to Windows directly - GetForegroundWindow
		against this window's own handle - and answered False whenever
		there is no native window at all, which is exactly right: a window
		that has not been created is in front of nobody, and a headless
		assault therefore drives the counting branch.

		THE VERTICAL ACCOUNTING. Two of this pane's five rows are silent
		most of the time, and simple_widgets 0.4.0 measures a label from the
		FONT whether or not it has anything in it - so an empty status line
		and an empty error line reserved a full row each (about forty-seven
		pixels apiece at this window's 2x scale) and the column charged a
		theme gap for each of them on top. That is the fixed band Larry saw
		between the last bubble and the composer. STATUS_LINE makes silence
		free and COLLAPSING_COLUMN stops charging a join for a flat child, so
		the thread sits ONE theme gap above the composer and gets the row
		back the instant there is something to say.

		And the composer strip is a COMPOSER_ROW, not a plain SW_ROW, because
		a plain row measures a wrapping child at the whole row's width while
		arranging it at its share of that width - which made the composer's
		second line paint below the box until the text was long enough to
		wrap at the wider measuring width too.

		SENDING. `on_submit' on the composer and the Send button run the
		same `submit', which hands the text to the host's agent and clears
		the line. Nothing here posts: the presenter owns that, and the
		echo comes back through the poller like everybody else's.
	]"
	author: "Larry Rix"

class
	SW_CHAT_VIEW

inherit
	CHAT_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_room_title: READABLE_STRING_GENERAL; a_x, a_y, a_width, a_height: INTEGER)
			-- A room pane titled `a_room_title', at `a_x', `a_y', `a_width' x `a_height',
			-- with shaped text on and nothing shown yet.
		require
			named: not a_room_title.is_empty
			sane_size: a_width > 0 and a_height > 0
		local
			l_root: COLLAPSING_COLUMN
			l_header: SW_ROW
			l_composer: COMPOSER_ROW
		do
			create room_title.make_from_string_general (a_room_title)
			create shown_ids.make (64)
			create errors.make (4)
			create status_text.make_empty
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
			create window.make (Window_title, a_x, a_y, a_width, a_height, theme)
			window.enable_shaped_text
			create thread.make
			thread.set_grow (1.0)
			create title_label.make_ui (room_title)
			title_label.set_grow (1.0)
			create unread_label.make_ui ("")
			create connection_label.make_ui (Text_unreachable)
			connection_label.set_muted (True)
			create {STATUS_LINE} status_label.make_ui ("")
			status_label.set_muted (True)
			create {STATUS_LINE} error_label.make_ui ("")
			create input.make_wrapping ("")
			input.set_grow (1.0)
			create send_button.make_primary (Text_send, Void)
			create l_header.make
			l_header.put (title_label)
			l_header.put (unread_label)
			l_header.put (connection_label)
			create l_composer.make
			l_composer.put (input)
			l_composer.put (send_button)
			create l_root.make
			l_root.put (l_header)
			l_root.put (thread)
			l_root.put (status_label)
			l_root.put (error_label)
			l_root.put (l_composer)
			root := l_root
			composer := l_composer
			window.set_root (l_root)
				-- The agents come LAST, and that is void safety, not taste: an agent on
				-- Current lets Current escape, so every attribute has to be set first.
			input.set_on_submit (agent submit)
			send_button.set_on_click (agent submit)
		ensure
			nothing_shown: shown_count = 0
			nothing_said_of_the_server: not is_connected
			not_in_front_until_it_exists: not is_foreground
			shaped: attached window.shaping
			titled: room_title.same_string_general (a_room_title)
		end

feature -- Model Queries (for MML postconditions)

	shown_model: MML_SEQUENCE [INTEGER_64]
			-- Ids shown, in order.
		do
			create Result
			across shown_ids as ic loop
				Result := Result & ic
			end
		end

feature -- Access

	window: SW_WINDOW
			-- The native window and its message pump; `run' shows it.

	thread: SW_CHAT_THREAD
			-- The bubbles, laid out by simple_shaping.

	input: CHAT_INPUT_BOX
			-- The composer; Return submits.

	root: SW_COLUMN
			-- Header, thread, status, error, composer.

	composer: SW_ROW
			-- The strip along the bottom: the wrapping box and the Send button.

	status_label: SW_LABEL
			-- The ephemeral line between the thread and the composer.

	error_label: SW_LABEL
			-- The last error, on its own line under the status line.

	room_title: STRING_32
			-- What the header strip calls this room.

	shown_ids: ARRAYED_LIST [INTEGER_64]
			-- Every id shown, in order.

	errors: ARRAYED_LIST [STRING_32]
			-- Every error shown, in order (the last one is on screen).

	status_text: STRING_32
			-- The ephemeral line as it stands.

	endpoint: detachable CHAT_ENDPOINT
			-- Which server the last `show_connection' named.

	unread: INTEGER
			-- What `set_unread' was last told; the presenter owns the count.

	shown_count: INTEGER
			-- Events shown so far.
		do
			Result := shown_ids.count
		end

	on_send: detachable PROCEDURE [READABLE_STRING_GENERAL]
			-- What a submit MEANS; the host's, not this class's.

feature -- Status report

	is_foreground: BOOLEAN
			-- Is the room window the one Windows has in front? False while there is
			-- no native window: a pane that was never created is in front of nobody.
		do
			Result := window.hwnd /= default_pointer and then c_foreground_window = window.hwnd
		end

	is_connected: BOOLEAN
			-- What the window last said about the server.

	hint_count: INTEGER
			-- How many `show_hint' bubbles have been added.

feature -- Element change

	set_on_send (a_action: PROCEDURE [READABLE_STRING_GENERAL])
			-- What a submitted line is for.
		do
			on_send := a_action
		ensure
			set: on_send = a_action
		end

	set_room_title (a_title: READABLE_STRING_GENERAL)
			-- Name the room in the header strip (the room is known only after a login).
		require
			named: not a_title.is_empty
		do
			create room_title.make_from_string_general (a_title)
			refresh_header
		ensure
			titled: room_title.same_string_general (a_title)
			events_unchanged: shown_model |=| old shown_model
		end

	set_unread (a_count: INTEGER)
			-- Show `a_count' unread in the header strip; nothing at zero.
		require
			non_negative: a_count >= 0
		do
			unread := a_count
			refresh_header
			redraw
		ensure
			set: unread = a_count
			shown_when_any: a_count > 0 implies unread_label.text.has_substring (a_count.out)
			silent_at_zero: a_count = 0 implies unread_label.text.is_empty
			events_unchanged: shown_model |=| old shown_model
		end

feature -- Basic operations

	show_event (a_event: CHAT_EVENT; a_sender_name: READABLE_STRING_GENERAL; a_mine: BOOLEAN)
			-- One bubble, attributed; `a_mine' places it right, sender 0 centres it.
		do
			thread.add_message (role_for (a_event, a_mine), bubble_text (a_event, a_sender_name))
			shown_ids.extend (a_event.id)
			redraw
		ensure then
			bubbled: thread.count = old thread.count + 1
		end

	show_status (a_text: READABLE_STRING_GENERAL)
			-- An ephemeral line; replaces the previous one.
		do
			create status_text.make_from_string_general (a_text)
			status_label.set_text (status_text)
			redraw
		ensure then
			said: status_text.same_string_general (a_text)
		end

	show_error (a_message: READABLE_STRING_GENERAL)
			-- The last error, on its own line, kept until another replaces it.
		do
			errors.extend (a_message.to_string_32)
			error_label.set_text (a_message)
			redraw
		ensure then
			kept: errors.count = old errors.count + 1
			on_screen: error_label.text.same_string_general (a_message)
		end

	show_connection (a_endpoint: CHAT_ENDPOINT; a_connected: BOOLEAN)
			-- Which server, and whether it answers.
		do
			endpoint := a_endpoint
			is_connected := a_connected
			refresh_header
			redraw
		ensure then
			endpoint_kept: endpoint = a_endpoint
		end

	show_hint (a_text: READABLE_STRING_GENERAL)
			-- A system-role bubble in the thread - the same centred role a real
			-- system event draws with, but never added to `shown_ids': it named
			-- nobody's message and carries no server id.
		do
			thread.add_message ({SW_CHAT_THREAD}.Role_system, a_text)
			hint_count := hint_count + 1
			redraw
		ensure then
			bubbled: thread.count = old thread.count + 1
		end

	run
			-- Show the window and pump until it closes. Blocks the caller.
		do
			window.give_focus (input)
			window.run
		end

	close
			-- End the pump from the program's side (a lost session, a logout).
		do
			if window.hwnd /= default_pointer then
				window.close
			end
		end

feature -- Conversion (contract support)

	role_for (a_event: CHAT_EVENT; a_mine: BOOLEAN): INTEGER
			-- Mine right, the system centred, everybody else left.
		do
			if a_mine then
				Result := {SW_CHAT_THREAD}.Role_mine
			elseif a_event.sender_id = 0 then
				Result := {SW_CHAT_THREAD}.Role_system
			else
				Result := {SW_CHAT_THREAD}.Role_theirs
			end
		ensure
			known: Result >= {SW_CHAT_THREAD}.Role_mine and Result <= {SW_CHAT_THREAD}.Role_system
			mine_is_mine: a_mine implies Result = {SW_CHAT_THREAD}.Role_mine
			system_is_centred: (not a_mine and a_event.sender_id = 0) implies Result = {SW_CHAT_THREAD}.Role_system
		end

	bubble_text (a_event: CHAT_EVENT; a_sender_name: READABLE_STRING_GENERAL): STRING_32
			-- "<who>: <what>". An image says so, names its file and its size, and carries
			-- its caption; the picture itself is not decoded (no WIC in this client).
		require
			named: not a_sender_name.is_empty
		do
			create Result.make (64)
			Result.append_string_general (a_sender_name)
			Result.append ({STRING_32} ": ")
			if a_event.is_image and then attached a_event.attachment as a then
				Result.append (Attachment_mark)
				Result.append (a.original_name)
				Result.append ({STRING_32} " (")
				Result.append_string_general (a.size.out)
				Result.append ({STRING_32} " bytes)")
				if not a_event.body.is_empty then
					Result.append ({STRING_32} " - ")
					Result.append (a_event.body)
				end
			else
				Result.append (a_event.body)
			end
		ensure
			attributed: Result.starts_with_general (a_sender_name)
			body_carried: (not a_event.is_image and not a_event.body.is_empty) implies Result.has_substring (a_event.body)
			named_file: (a_event.is_image and attached a_event.attachment as a) implies Result.has_substring (a.original_name)
		end

feature -- Constants

	Window_title: STRING_32 = "simple_chat"
			-- The native title bar. It never changes: simple_shell publishes no
			-- SetWindowText, so the unread count lives in the header strip and the
			-- tray tooltip instead.

	Text_send: STRING_32 = "Send"

	Text_connected: STRING_32 = "connected"

	Text_unreachable: STRING_32 = "not answering"

	Attachment_mark: STRING_32 = "[image] "
			-- What an image event wears instead of the picture, until a decoder lands.

feature {NONE} -- The header strip

	refresh_header
			-- Room name, unread count and the connection line, as they stand.
		local
			l_line: STRING_32
		do
			title_label.set_text (room_title)
			if unread > 0 then
				create l_line.make (16)
				l_line.append_character ('(')
				l_line.append_string_general (unread.out)
				l_line.append_character (')')
				unread_label.set_text (l_line)
			else
				unread_label.set_text ({STRING_32} "")
			end
			create l_line.make (64)
			if is_connected then
				l_line.append (Text_connected)
			else
				l_line.append (Text_unreachable)
			end
			if attached endpoint as e then
				l_line.append ({STRING_32} ": ")
				l_line.append_string_general (e.base_url)
			end
			connection_label.set_text (l_line)
		ensure
			badge_when_any: unread > 0 implies unread_label.text.has_substring (unread.out)
			no_badge_at_zero: unread = 0 implies unread_label.text.is_empty
		end

feature {NONE} -- Sending

	submit
			-- The composer's line goes to the host; an empty line goes nowhere.
		local
			l_text: STRING_32
		do
			l_text := input.text.twin
			if not l_text.is_empty and then attached on_send as a then
				input.set_text ({STRING_32} "")
				a.call ([l_text])
				redraw
			end
		end

feature {NONE} -- Painting

	redraw
			-- Repaint, but only when there is a window to paint into: every operation
			-- of this class is exercised headless, where there is not.
		do
			if window.hwnd /= default_pointer then
				window.request_render
			end
		end

feature {NONE} -- The desktop

	c_foreground_window: POINTER
			-- GetForegroundWindow(): the top-level window the member is actually
			-- looking at. simple_shell raises no activation event and is not this
			-- project's to change, so the one question CHAT_VIEW must answer is
			-- asked of Windows itself.
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_POINTER) GetForegroundWindow();"
		end

feature {NONE} -- Implementation

	theme: SW_THEME
	title_label: SW_LABEL
	unread_label: SW_LABEL
	connection_label: SW_LABEL
	send_button: SW_BUTTON

feature -- Constants

	Text_scale: REAL_64 = 2.0
			-- How much larger than SW_THEME's own sizes this window draws
			-- its text. 1.0 is the library default; 2.0 is twice that.
			-- SW_THEME.set_text_scale caps the range at 0.5 .. 3.0, so 3.0
			-- is the most that can be asked for.

invariant
	model_consistent: shown_model.count = shown_ids.count
	unread_non_negative: unread >= 0
	hint_count_non_negative: hint_count >= 0
	titled: not room_title.is_empty
	shaped_text_on: attached window.shaping

end
