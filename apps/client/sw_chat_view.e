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

		LINE BREAKS, WHOLE. A message reaches the thread EXACTLY as it was
		sent. simple_widgets 0.6.0 cuts a bubble into paragraphs before
		either text path lays anything out, so an LF ends a line instead of
		being shaped into the empty box Larry saw in every numbered list.
		BUBBLE_TEXT - the workaround that flattened a reply into one
		paragraph so it would not draw boxes - named this library release as
		its own retirement condition and is gone; the structure it cost is
		back.

		THE KEYBOARD. The menu bar owns the Alt key (`set_menu_bar') and its
		titles and items carry `&' mnemonics, so File draws with its F
		underlined. Ctrl+X / C / V / A and the room's own Ctrl+M and Ctrl+U
		are WINDOW-WIDE accelerators. THE RULE THAT MAKES THAT SAFE: a
		claimed accelerator is consulted BEFORE the focused widget and so
		takes the key away from it. Every editing key registered here
		therefore ROUTES - `route_copy' copies the pane's selection when the
		pane has focus and the composer's when the composer has - and the
		Edit menu calls the very same agents, so there is ONE meaning of
		Copy in this window and two ways to reach it.

		AND ALT+F OPENS FILE, which took closing a seam. simple_shell 1.9.3
		delivers Alt+letter at last - as the ORDINARY key-down event 4, with
		the virtual key, swallowing the WM_SYSCHAR behind it so DefWindowProc
		cannot open the system menu behind our back. But simple_widgets tries
		only its ACCELERATOR TABLE on event 4; `activate_mnemonic' - the
		feature that opens a pad - sits on the WM_CHAR door, which is the
		very message the shell now swallows. So the gesture would still not
		arrive. The library's own README names the way out ("a host can drive
		it from an accelerator or a click today"), and that is what
		`open_menu_pad' is: four Alt accelerators, one per pad, each opening
		the menu that underlines its letter. If simple_widgets later routes
		an unclaimed Alt+letter to `activate_mnemonic' itself, these four
		registrations become redundant and come out - they take nothing from
		any widget, since an Alt+letter reaching a text box does nothing.
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
			l_bar: SW_MENU_BAR
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
			create {STATUS_LINE} compose_strip.make_ui ("")
			compose_strip.set_muted (True)
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
			create l_bar.make
			menu_bar := l_bar
			create l_root.make
			l_root.put (l_bar)
			l_root.put (l_header)
			l_root.put (thread)
			l_root.put (compose_strip)
			l_root.put (status_label)
			l_root.put (error_label)
			l_root.put (l_composer)
			root := l_root
			composer := l_composer
			window.set_root (l_root)
				-- The agents come LAST, and that is void safety, not taste: an agent on
				-- Current lets Current escape, so every attribute has to be set first.
			input.set_on_submit (agent submit)
			input.set_on_cancel (agent cancel_compose_now)
			send_button.set_on_click (agent submit)
				-- The menu builders are agents on Current too, so they belong here
				-- with the rest and not beside the widget that holds them.
			l_bar.add_menu (Text_menu_file, agent file_menu)
			l_bar.add_menu (Text_menu_edit, agent edit_menu)
			l_bar.add_menu (Text_menu_room, agent room_menu)
			l_bar.add_menu (Text_menu_help, agent help_menu)
				-- Which bar owns the Alt key is told, never discovered: a window
				-- may hold several bars and only the application knows.
			window.set_menu_bar (l_bar)
			register_keys
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

	thread: MESSAGE_THREAD
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

	apply_edit (a_event_id: INTEGER_64; a_text: READABLE_STRING_GENERAL)
			-- The new words, on the bubble that already carries this id.
			-- `Role_keep' keeps the speaker: an edit changes what was said,
			-- never who said it.
		local
			i: INTEGER
		do
			i := bubble_of (a_event_id)
			if i > 0 and then not thread.is_tombstone (i) then
				thread.set_message (i, {SW_CHAT_THREAD}.Role_keep, a_text)
				if not thread.is_edited (i) then
					thread.mark_edited (i)
				end
				redraw
			end
		end

	apply_delete (a_event_id: INTEGER_64)
			-- A tombstone, never a gap: the bubble keeps its place so the
			-- order of the thread still says who answered whom.
		local
			i: INTEGER
		do
			i := bubble_of (a_event_id)
			if i > 0 and then not thread.is_tombstone (i) then
				thread.tombstone (i)
				redraw
			end
		end

	apply_reactions (a_event_id: INTEGER_64; a_list: LIST [TUPLE [emoji: STRING_32; tally: INTEGER; mine: BOOLEAN]])
		local
			i: INTEGER
		do
			i := bubble_of (a_event_id)
			if i > 0 and then not thread.is_tombstone (i) then
				thread.set_reactions (i, a_list)
				redraw
			end
		end

	apply_reply_quote (a_event_id: INTEGER_64; a_author, a_text: READABLE_STRING_GENERAL)
		local
			i: INTEGER
		do
			i := bubble_of (a_event_id)
			if i > 0 and then not thread.is_tombstone (i) then
				thread.set_reply_quote (i, a_author, a_text)
				redraw
			end
		end

	bubble_of (a_event_id: INTEGER_64): INTEGER
			-- WHICH BUBBLE carries `a_event_id', 0 for one this view never
			-- showed. `shown_ids' is filled by `show_event' in step with the
			-- thread's own indices, so the two cannot drift.
		local
			i: INTEGER
		do
			from i := 1 until i > shown_ids.count or Result > 0 loop
				if shown_ids.i_th (i) = a_event_id then
					Result := i
				end
				i := i + 1
			end
		ensure
			in_range: Result >= 0 and Result <= shown_ids.count
			right_one: Result > 0 implies shown_ids.i_th (Result) = a_event_id
		end

	event_of_bubble (a_index: INTEGER): INTEGER_64
			-- The event id bubble `a_index' carries; 0 when out of range.
			-- What a right-click needs once `message_at' has named a bubble.
		do
			if a_index >= 1 and a_index <= shown_ids.count then
				Result := shown_ids.i_th (a_index)
			end
		ensure
			non_negative: Result >= 0
		end

	set_on_cancel_compose (a_action: PROCEDURE)
			-- What Escape in the composer backs out of; the host owns it.
		do
			on_cancel_compose := a_action
		ensure
			set: on_cancel_compose = a_action
		end

	on_cancel_compose: detachable PROCEDURE

	cancel_compose_now
		do
			if attached on_cancel_compose as c then
				c.call
			end
		end

	show_compose_strip (a_text: READABLE_STRING_GENERAL)
			-- The line above the composer that says what Return will do -
			-- who is being replied to, that an edit is in progress, or that a
			-- delete wants confirming. An empty string clears it, and an
			-- empty STATUS_LINE costs no height, so the strip takes no room
			-- at all when nothing is pending.
		do
			compose_strip.set_text (a_text.to_string_32)
			redraw
		ensure
			nothing_shown: shown_model |=| old shown_model
		end

	set_compose_text (a_text: READABLE_STRING_GENERAL)
			-- Put `a_text' in the composer - what Edit does so the member
			-- changes the words rather than retyping them.
		do
			input.set_text (a_text.to_string_32)
			redraw
		ensure
			nothing_shown: shown_model |=| old shown_model
		end

	reaction_is_mine (a_event_id: INTEGER_64; a_emoji: READABLE_STRING_32): BOOLEAN
			-- Has the reader already got `a_emoji' on this message? What
			-- decides whether a click ADDS or TAKES AWAY.
		local
			i: INTEGER
		do
			i := bubble_of (a_event_id)
			if i > 0 then
				across thread.reactions_of (i) as r loop
					if r.emoji.same_string (a_emoji) and then r.mine then
						Result := True
					end
				end
			end
		end

	compose_strip: STATUS_LINE
			-- The line above the composer; empty when nothing is pending.

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

feature -- Keyboard routing

	thread_has_focus: BOOLEAN
			-- Do the window's keys belong to the PANE right now? False when
			-- nothing holds focus at all, which is both the headless case and
			-- the one `run' arranges - it hands the caret to the composer - so
			-- the composer is the default target and the pane is the exception,
			-- reached by clicking a bubble.
		do
			Result := window.focused = thread
		ensure
			definition: Result = (window.focused = thread)
		end

	can_cut: BOOLEAN
			-- Cut belongs to the composer alone. A bubble is the record of what
			-- somebody said and nothing in this client removes text from it.
		do
			Result := not thread_has_focus and then input.has_selection and then not input.is_read_only
		ensure
			never_from_the_pane: thread_has_focus implies not Result
		end

	can_copy: BOOLEAN
			-- Whoever has focus, and only when they have something to give.
		do
			if thread_has_focus then
				Result := thread.has_selection
			else
				Result := input.has_selection
			end
		ensure
			the_panes: thread_has_focus implies Result = thread.has_selection
			the_composers: not thread_has_focus implies Result = input.has_selection
		end

	can_paste: BOOLEAN
			-- Nothing pastes into a transcript.
		do
			Result := not thread_has_focus and then not input.is_read_only
		ensure
			never_into_the_pane: thread_has_focus implies not Result
		end

	can_select_all: BOOLEAN
			-- Is there anything for Ctrl+A to take?
		do
			if thread_has_focus then
				Result := thread.count > 0
			else
				Result := input.text.count > 0
			end
		ensure
			empty_pane_offers_nothing: (thread_has_focus and thread.count = 0) implies not Result
		end

	route_cut
			-- Ctrl+X, and Edit > Cut.
		do
			if can_cut then
				input.cut_selection
				redraw
			end
		end

	route_copy
			-- Ctrl+X's quieter neighbour, and the one that matters most here:
			-- the accelerator TOOK Ctrl+C away from both widgets' own handling
			-- (SW_TEXT_BOX reads control code 3, SW_CHAT_THREAD reads it too),
			-- so this is now the ONLY path either of them has, and it must hand
			-- the gesture to whichever one the member is looking at.
		do
			if thread_has_focus then
				thread.copy_selection
			elseif input.has_selection then
				input.copy_selection
			end
		end

	route_paste
			-- Ctrl+V, and Edit > Paste.
		do
			if can_paste then
				input.paste_clipboard
				redraw
			end
		end

	route_select_all
			-- Ctrl+A. In the composer, the whole line. In the pane, the whole of
			-- ONE bubble: simple_widgets keeps a selection inside a single
			-- message deliberately - a thread is a list of utterances by
			-- different speakers and a range spanning three of them has no
			-- honest text to hand the clipboard - so `all' here means the message
			-- the selection is already in, or the last thing said.
		do
			if thread_has_focus then
				if thread.count > 0 then
					if thread.sel_message > 0 and thread.sel_message <= thread.count then
						thread.select_message (thread.sel_message)
					else
						thread.select_message (thread.count)
					end
				end
			else
				input.select_all
			end
			redraw
		end

	run_summary
			-- Ctrl+M, and Room > Summarize. One meaning, two doors; silent when
			-- the host has not said what a summary is.
		do
			if attached on_summary as a then
				a.call
			end
		end

	run_catch_up
			-- Ctrl+U, and Room > Catch me up.
		do
			if attached on_catch_up as a then
				a.call
			end
		end

	open_menu_pad (a_letter: CHARACTER_32)
			-- Alt+`a_letter': drop the menu bar pad that underlines that letter,
			-- under the pad itself. The oldest gesture on the platform, and the
			-- last mile of it is wired HERE - see the class note.
		do
			if window.activate_mnemonic (a_letter) then
				redraw
			end
		end

feature {NONE} -- The keyboard, registered

	register_keys
			-- The window-wide table: six Ctrl keys for what they do, and four
			-- Alt keys for the menu bar. See the class note for why the four
			-- are here and not in the library.
		do
			window.register_accelerator (Vk_x, True, False, False, agent route_cut)
			window.register_accelerator (Vk_c, True, False, False, agent route_copy)
			window.register_accelerator (Vk_v, True, False, False, agent route_paste)
			window.register_accelerator (Vk_a, True, False, False, agent route_select_all)
			window.register_accelerator (Vk_m, True, False, False, agent run_summary)
			window.register_accelerator (Vk_u, True, False, False, agent run_catch_up)
			window.register_accelerator (Vk_f, False, True, False, agent open_menu_pad ({CHARACTER_32} 'f'))
			window.register_accelerator (Vk_e, False, True, False, agent open_menu_pad ({CHARACTER_32} 'e'))
			window.register_accelerator (Vk_r, False, True, False, agent open_menu_pad ({CHARACTER_32} 'r'))
			window.register_accelerator (Vk_h, False, True, False, agent open_menu_pad ({CHARACTER_32} 'h'))
		end

feature -- Constants

	Window_title: STRING_32 = "simple_chat"

	Text_menu_file: STRING_32 = "&File"
			-- The `&' marks the mnemonic letter; `labels' and `items.label'
			-- keep the PLAIN reading, so nothing that reads a label sees one.
	Text_menu_edit: STRING_32 = "&Edit"
	Text_menu_room: STRING_32 = "&Room"
	Text_menu_help: STRING_32 = "&Help"

	Text_item_close: STRING_32 = "&Close"
	Text_key_close: STRING_32 = "Alt+F4"
	Text_item_cut: STRING_32 = "Cu&t"
	Text_key_cut: STRING_32 = "Ctrl+X"
	Text_item_copy: STRING_32 = "&Copy"
	Text_key_copy: STRING_32 = "Ctrl+C"
	Text_item_paste: STRING_32 = "&Paste"
	Text_key_paste: STRING_32 = "Ctrl+V"
	Text_item_select_all: STRING_32 = "Select &All"
	Text_key_select_all: STRING_32 = "Ctrl+A"
	Text_item_summarize: STRING_32 = "&Summarize the room now"
	Text_key_summarize: STRING_32 = "Ctrl+M"
	Text_item_catch_up: STRING_32 = "&Catch me up on what I missed"
	Text_key_catch_up: STRING_32 = "Ctrl+U"
	Text_item_how_to_address: STRING_32 = "&How to address the assistant"
	Text_item_about: STRING_32 = "&About simple_chat"

	Text_addressing_help: STRING_32 = "Mention the assistant anywhere in a message. Ask it for a summary with sum, recap or catch me up - or press Ctrl+M for the summary and Ctrl+U to catch up. That answer is yours alone and never goes to the room."
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

feature -- The menu bar

	menu_bar: detachable SW_MENU_BAR
			-- File / Edit / Room / Help across the top. Every menu is built
			-- FRESH on each open (SW_MENU_BAR takes builder agents, not menus),
			-- so an item is greyed exactly when the thing it does is impossible
			-- right now - nothing offers to paste an empty clipboard.

	set_on_summary (a_action: PROCEDURE)
			-- What "Summarize the room now" does.
		do
			on_summary := a_action
		ensure
			set: on_summary = a_action
		end

	set_on_catch_up (a_action: PROCEDURE)
			-- What "Catch me up on what I missed" does.
		do
			on_catch_up := a_action
		ensure
			set: on_catch_up = a_action
		end

	on_summary: detachable PROCEDURE
	on_catch_up: detachable PROCEDURE

feature {NONE} -- The menus, built fresh on every open

	file_menu: SW_MENU
		do
			create Result.make
			Result.add_item (Text_item_close, Text_key_close, True, agent close)
		end

	edit_menu: SW_MENU
			-- Editing, routed. Every item calls the SAME agent the matching
			-- accelerator calls, and every item's greying reads the SAME
			-- `can_*' query the agent guards itself with - so the menu can
			-- never offer what the key would refuse, whichever of the two
			-- widgets holds focus. Ctrl+Z and Ctrl+Y are deliberately NOT
			-- accelerators: unclaimed, they still reach the composer's own
			-- undo stack exactly as they always did.
		do
			create Result.make
			Result.add_item (Text_item_cut, Text_key_cut, can_cut, agent route_cut)
			Result.add_item (Text_item_copy, Text_key_copy, can_copy, agent route_copy)
			Result.add_item (Text_item_paste, Text_key_paste, can_paste, agent route_paste)
			Result.add_separator
			Result.add_item (Text_item_select_all, Text_key_select_all, can_select_all, agent route_select_all)
		end

	room_menu: SW_MENU
			-- The two things a member can ask of the room that are not messages.
			-- Both are also typeable ("@claude sum"), and both answer to this
			-- member alone - a summary is never a room event.
		do
			create Result.make
			Result.add_item (Text_item_summarize, Text_key_summarize, on_summary /= Void, agent run_summary)
			Result.add_item (Text_item_catch_up, Text_key_catch_up, on_catch_up /= Void, agent run_catch_up)
		end

	help_menu: SW_MENU
		do
			create Result.make
			Result.add_item (Text_item_how_to_address, {STRING_32} "", True, agent show_addressing_help)
			Result.add_separator
			Result.add_item (Text_item_about, {STRING_32} "", True, agent show_about)
		end

	show_about
			-- Larry's ask, in his own words: "an Help with an About that will
			-- tell me the version of simple_chat that I am using". The version,
			-- the build date and the fleet it was built against - all from
			-- CHAT_VERSION, which is the one place any of them is written.
		do
			show_hint ((create {CHAT_VERSION}).About_text)
		end

	show_addressing_help
		do
			show_hint (Text_addressing_help)
		end

feature {NONE} -- Implementation

	theme: SW_THEME
	title_label: SW_LABEL
	unread_label: SW_LABEL
	connection_label: SW_LABEL
	send_button: SW_BUTTON

feature -- Constants

	Vk_a: INTEGER = 65
			-- Win32 virtual keys. A letter's virtual key IS its uppercase
			-- ASCII code, which is also what SW_WINDOW folds a Ctrl+letter
			-- control code back to (code + 64), so one number serves both
			-- of the doors the library tries.
	Vk_c: INTEGER = 67
	Vk_e: INTEGER = 69
	Vk_f: INTEGER = 70
	Vk_h: INTEGER = 72
	Vk_m: INTEGER = 77
	Vk_r: INTEGER = 82
	Vk_u: INTEGER = 85
	Vk_v: INTEGER = 86
	Vk_x: INTEGER = 88

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
