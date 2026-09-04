note
	description: "[
		The member's executable - the thick client (D-015), now with its
		window. Loads the config, LOCATES the server (the local service
		first, D-016), tries the session this PC remembers, asks for a
		password when it will not do, opens the room and runs the pane.

		THREE PROCESSORS (approach section 8). The root runs the window,
		the presenter and the GUI's own CHAT_CLIENT for posting; a
		POLLER_HOST runs the EVENT_POLLER with a transport and CHAT_CLIENT
		of its own; an EVENT_INBOX sits between them and never blocks.
		Only bytes cross: the session is copied into the host's client
		(`hand_session_to'), pages come back as bytes through the inbox.
		No routine here holds the inbox or the host across anything long:
		`start_polling' hands the inbox over in one short call and then
		launches the loop asynchronously with no separate argument at all,
		so the launch does not wait for the loop to end.

		THE HEARTBEAT IS THE PUMP. `SW_WINDOW' fires `on_tick' every 250
		ms on the ROOT processor - the GUI thread - and `tick' does one
		`CHAT_PRESENTER.pump' there. That is the whole live path: the
		poller holds the server's doorbell open on its own processor for
		up to {CHAT_CLIENT}.Max_wait_seconds and the window never waits
		for it. Two separate reasons, and both are needed. The inbox is a
		processor that never blocks, so no call the GUI makes on it can
		queue behind the poll. And the exchange itself is spent inside an
		external the runtime has been TOLD about - SIMPLE_WINHTTP.c_send
		is `external "C blocking inline"' since 0.1.1 - so ISE's
		collector, which stops every thread of the system before it
		collects, runs without waiting for the poll to come back. Before
		that marker (2026-09-02) it did wait, and the GUI froze at its
		very next allocation for the rest of the poll: 21,058 ms measured,
		against 1 ms now. If a transport is ever swapped in under
		HTTP_TRANSPORT, read its externals before trusting this window.

		THE SESSION CAN DIE UNDER THE WINDOW. When the poller meets a 401
		the presenter closes the room, drops the token with no exchange
		and sets `session_lost'; `tick' sees it, shuts the pane and `run'
		goes round again - straight back to the door. simple_shell owns
		ONE native window at a time, so the login window and the room pane
		are never up together: the door runs, closes, and then the room
		does.

		WHAT IS REMEMBERED. "Remember me" seals the session into
		client.toml with DPAPI (`CHAT_CLIENT.remember_session_in' - the
		token never leaves the client in clear) and, at shutdown, the
		client does NOT log out: revoking the token would make the next
		launch ask for a password anyway. Unticked, the reverse: log out,
		forget the blob. The window's placement is saved either way.
	]"
	author: "Larry Rix"

class
	CLIENT_APP

create
	make, make_for_test

feature {NONE} -- Initialization

	make
			-- The whole client: assemble, then run until the member closes the window
			-- (or gives up at the door).
		do
			settle_working_directory
			build (Void, Void)
			run
		end

	settle_working_directory
			-- Move to a folder this member can WRITE, before anything opens a
			-- window.
			--
			-- SW_WINDOW's session log is a RELATIVE name ("sw_session.log"),
			-- so it lands in the WORKING DIRECTORY - and `open_write' on a
			-- folder the member cannot write RAISES an operating-system
			-- exception rather than returning quietly, which its
			-- `is_open_write' guard never sees. Launched from a Start Menu
			-- shortcut whose working directory was the install folder under
			-- Program Files, the client therefore died at "root's creation"
			-- with "Permission denied" and the window never appeared: it
			-- flashed and vanished. A read-only install folder is the NORMAL
			-- case for a per-machine install, so this is not an edge.
			--
			-- %APPDATA%\simple_chat is the folder the client already owns -
			-- client.toml lives there - so it is writable by definition for
			-- whoever is running.
			--
			-- Nothing else wants the working directory: SW_SHAPING resolves
			-- the emoji artwork beside the RUNNING EXECUTABLE, never the
			-- working directory, and cairo.dll is found on the executable's
			-- own search path. Moving is therefore free.
			--
			-- Every failure here is survivable - the worst case is the old
			-- behaviour - so nothing is allowed to raise out of it.
		local
			l_env: EXECUTION_ENVIRONMENT
			l_directory: DIRECTORY
			l_path: PATH
			l_failed: BOOLEAN
		do
			if not l_failed then
				create l_env
				if attached l_env.item ("APPDATA") as l_appdata and then not l_appdata.is_empty then
					create l_path.make_from_string (l_appdata)
					l_path := l_path.extended ("simple_chat")
					create l_directory.make_with_path (l_path)
					if not l_directory.exists then
						l_directory.recursive_create_dir
					end
					if l_directory.exists then
						l_env.change_working_path (l_path)
					end
				end
			end
		rescue
			l_failed := True
			retry
		end

	make_for_test (a_transport: HTTP_TRANSPORT; a_config: CLIENT_CONFIG)
			-- The same assembly over a scripted transport and a scratch config, with
			-- nothing shown and nothing run: the assault drives `try_remembered_session',
			-- `attempt_login', `open_room' and `tick' itself, exactly as `run' does.
		do
			build (a_transport, a_config)
		ensure
			config_kept: config = a_config
			transport_kept: transport = a_transport
			logged_out: not client.is_logged_in
			no_room: not presenter.is_room_open
			nothing_shown: view.shown_count = 0
		end

	build (a_transport: detachable HTTP_TRANSPORT; a_config: detachable CLIENT_CONFIG)
			-- Config, transport, locator, endpoint, client, view, tray, notifier, presenter -
			-- and the two agents that make the window a client: the tick that pumps and the
			-- submit that posts.
		local
			l_locator: SERVICE_LOCATOR
			l_tray: SHELL_TRAY
			l_winhttp: WINHTTP_TRANSPORT
		do
			if attached a_config as l_given then
				config := l_given
			else
				create config.make_defaults
				config.load
			end
			if attached a_transport as l_wire then
				transport := l_wire
			else
				create l_winhttp.make
				transport := l_winhttp
			end
			create l_locator.make (transport)
			endpoint := l_locator.locate (config)
			create client.make (transport, endpoint)
			create view.make (Default_room_title,
				config.window_x.max (0), config.window_y.max (0),
				config.window_width.max (Minimum_window_width),
				config.window_height.max (Minimum_window_height))
			create l_tray.make ({TRAY_NOTIFIER}.Tooltip_base)
			create notifier.make (l_tray)
			create presenter.make (client, view, notifier)
			view.set_on_send (agent send_text)
			view.window.set_on_tick (agent tick)
		ensure
			logged_out: not client.is_logged_in
			no_room: not presenter.is_room_open
		end

feature -- Access

	client: CHAT_CLIENT
			-- The GUI's own client: login and posting on the root processor.

	config: CLIENT_CONFIG
			-- What the member's machine remembers; saved again on close.

	transport: HTTP_TRANSPORT
			-- The root processor's transport: the locator's probes, the login, every
			-- post. WINHTTP_TRANSPORT in a real run; the poller's lives in POLLER_HOST,
			-- on its own processor.

	endpoint: CHAT_ENDPOINT
			-- Where SERVICE_LOCATOR said to talk, or where the door was pointed.

	view: SW_CHAT_VIEW
			-- The room pane: simple_widgets, shaped text, no browser.

	notifier: TRAY_NOTIFIER
			-- Balloons and the unread badge on the notification area.

	presenter: CHAT_PRESENTER
			-- The logic between the client, the inbox, the view and the notifier.
			-- Rebuilt when the door is pointed at a different server, because a
			-- presenter is bound to one client for its life.

	room_id: INTEGER_64
			-- The open room; 0 before one is.

	last_seen_id: INTEGER_64
			-- The highest id shown, carried across a re-login so a new session does not
			-- replay the whole room.

feature -- Status report

	remembers: BOOLEAN
			-- Did the member tick "remember me"? Then the session is sealed and the
			-- shutdown does not revoke it.

	session_was_lost: BOOLEAN
			-- Did the last pane close because the server rejected the session?

feature -- Basic operations

	run
			-- The door, the room, and round again if the session dies under the window.
		local
			l_done: BOOLEAN
		do
			from
			until
				l_done
			loop
				if not client.is_logged_in then
					try_remembered_session
				end
				if not client.is_logged_in then
					ask_for_login
				end
				if client.is_logged_in then
					session_was_lost := False
					open_room
					view.run
					if presenter.is_room_open then
						presenter.close_room
					end
					l_done := not session_was_lost
				else
					l_done := True
				end
			end
			shut_down
		ensure
			nothing_left_open: not presenter.is_room_open
		end

	try_remembered_session
			-- The session this PC remembers, if it unseals and the server still honours
			-- it (GET /me). A blob that does not is forgotten rather than kept to fail again.
		require
			logged_out: not client.is_logged_in
		local
			l_token: detachable STRING_8
		do
			l_token := config.load_session
			if attached l_token as t and then client.is_hex_64 (t) then
				if not client.resume (t).is_success then
					config.forget_session
				else
					remembers := True
				end
			elseif config.has_session then
				config.forget_session
			end
		ensure
			no_blob_no_session: not (old config.has_session) implies not client.is_logged_in
			remembered_when_in: client.is_logged_in implies remembers
		end

	ask_for_login
			-- The door: run it until it is accepted or given up on, then seal the session
			-- if the member asked for that.
		require
			logged_out: not client.is_logged_in
		local
			l_door: LOGIN_WINDOW
		do
			create l_door.make (endpoint.base_url, config.window_x.max (0), config.window_y.max (0))
			l_door.set_attempt (agent attempt_login)
			l_door.run
			if l_door.is_accepted and then client.is_logged_in then
				remembers := l_door.remembers
				if remembers then
					client.remember_session_in (config)
				else
					config.forget_session
				end
			end
		end

	attempt_login (a_url, a_username: READABLE_STRING_8; a_password: READABLE_STRING_GENERAL): detachable STRING_32
			-- What the door's Log in button does: point the client at `a_url' (rebuilding
			-- the client and the presenter when it is a different server), then log in.
			-- Void on success; the server's own message on failure - EXCEPT when nothing
			-- answered at all (`CHAT_CLIENT.last_status' = 0), where the transport's own
			-- words name a mechanism the member cannot act on and CONNECTION_ADVICE names
			-- what he can do instead. A refusal the server DID send - a wrong password, an
			-- unknown name, a locked account - keeps the server's wording, untouched.
		require
			logged_out: not client.is_logged_in
			named: not a_username.is_empty
			secret_given: not a_password.is_empty
		local
			l_rules: CHAT_URL_RULES
			l_endpoint: CHAT_ENDPOINT
			l_result: CHAT_RESULT [CHAT_MEMBER]
		do
			create l_rules
			if not l_rules.is_acceptable_url (a_url) then
				Result := Message_bad_server
			else
				if not endpoint.base_url.same_string (a_url) then
					create l_endpoint.make (a_url)
					endpoint := l_endpoint
					create client.make (transport, l_endpoint)
					create presenter.make (client, view, notifier)
					config.set_primary_url (a_url)
				end
				l_result := client.login (a_username, a_password)
				if not l_result.is_success and then attached l_result.error as e then
					if client.last_status = 0 then
						Result := advice.advice_for (a_url, config)
					else
						Result := e.message
					end
				end
			end
		ensure
			in_or_explained: client.is_logged_in = (Result = Void)
			nothing_open: not presenter.is_room_open
		end

	open_room
			-- The member's first room: its name in the header, its roster remembered, its
			-- poller running, its pane ready. When the server will not say what rooms there
			-- are, the room stays closed and the reason goes on the pane's error line - the
			-- window still opens, because a member who is told nothing learns nothing.
			--
			-- A member who IS told something still has to know he can talk to it: if the
			-- roster names a bot, one hint bubble says so, by its real @username - never
			-- a hard-coded "@claude" that would lie the day a room's assistant is renamed
			-- or a second one joins.
		require
			logged_in: client.is_logged_in
			closed: not presenter.is_room_open
		local
			l_rooms: CHAT_RESULT [ARRAYED_LIST [TUPLE [id: INTEGER_64; name: STRING_32]]]
		do
			l_rooms := client.rooms
			if l_rooms.is_success and then attached l_rooms.value as l_list and then not l_list.is_empty then
				room_id := l_list.first.id
				view.set_room_title (l_list.first.name)
				presenter.load_roster (room_id)
				load_handles
					-- The Room menu does by click what the composer does by verb.
					-- Without these the items build DISABLED (their action is Void)
					-- and a click does nothing at all, which is what Larry hit.
				view.set_on_summary (agent ask_summary (0, 0, 0))
				view.set_on_catch_up (agent catch_up_now)
				if not presenter.bot_members.is_empty then
					view.show_hint (addressing_hint (presenter.bot_members))
				end
				start_polling (presenter, room_id, last_seen_id)
				view.set_unread (presenter.unread)
			elseif attached l_rooms.error as e then
				view.show_error (e.message)
			else
				view.show_error (Message_no_rooms)
			end
		ensure
			room_named_when_open: presenter.is_room_open implies room_id > 0
			explained_when_not: not presenter.is_room_open implies view.errors.count > old view.errors.count
			hinted_when_a_bot_is_present: (presenter.is_room_open and then not presenter.bot_members.is_empty)
				implies view.hint_count >= 1
		end

	tick
			-- The window's 250 ms heartbeat, on the ROOT processor: one pump, the badge,
			-- and - when the server has rejected the session - the end of this pane.
		do
			if presenter.is_room_open and then client.is_logged_in then
					-- BEFORE the pump, because the pump is what marks the missed
					-- messages seen and clears the very count this reads.
				note_foreground
				show_any_summary
				presenter.pump
				last_seen_id := presenter.last_seen_id
				view.set_unread (presenter.unread)
				if presenter.session_lost then
					session_was_lost := True
					view.close
				end
			end
		ensure
			badge_matches: presenter.is_room_open implies view.unread = presenter.unread
			seen_monotonic: last_seen_id >= old last_seen_id
		end

	send_text (a_text: READABLE_STRING_GENERAL)
			-- The composer's line. Ordinarily it is posted and the echo comes
			-- back through the poller like everybody else's, so nothing is shown
			-- here.
			--
			-- A line that MENTIONS an assistant and opens with a summary verb is
			-- not posted at all. It is a question this member is asking on their
			-- own account, and its answer belongs to them alone - so it goes
			-- straight to the summary endpoint and comes back as a hint bubble
			-- in this window. Nothing of it reaches the room, because the room's
			-- events are never per-person.
		do
			if presenter.is_room_open and then client.is_logged_in and then not a_text.is_empty then
				if is_summary_line (a_text) then
					ask_summary (0, 0, summary_ask.minutes_of (a_text))
				else
					presenter.send (a_text)
				end
			end
		ensure
			nothing_shown_here: view.shown_model |=| old view.shown_model
		end

feature {NONE} -- Summary and catch-up

	summary_ask: SUMMARY_ASK
			-- The rule that tells a summary request from an ordinary message.
		once
			create Result
		end

	was_foreground: BOOLEAN
			-- Was the window in front the last time `tick' looked? The only way
			-- to know it has come BACK: simple_shell raises no activation event,
			-- so the edge is found by watching, not by being told.

	left_at: detachable SIMPLE_DATE_TIME
			-- When the window last went out of the foreground; Void while it has
			-- not been away.

	seen_when_left: INTEGER_64
			-- The last event this member had seen when the window went away, so
			-- the catch-up summarises exactly the gap and not a line more.

	catch_ups_asked: INTEGER
			-- How many catch-ups this session has fired (for the assault).

	note_foreground
			-- Watch the window leave the foreground and come back, and catch up
			-- on the gap when the return is worth an engine call: away for at
			-- least `config.catch_up_away_seconds' AND at least
			-- `config.catch_up_minimum_messages' missed. Both, because a long
			-- lunch in a silent room is not a gap and three messages while the
			-- kettle boiled are not an absence.
		local
			l_now: SIMPLE_DATE_TIME
			l_is_front: BOOLEAN
			l_missed: INTEGER
		do
			l_is_front := view.is_foreground
			if was_foreground and not l_is_front then
				create l_now.make_now
				left_at := l_now
				seen_when_left := presenter.last_seen_id
			elseif l_is_front and not was_foreground and then attached left_at as l_left then
				create l_now.make_now
				l_missed := presenter.unread
				if config.catch_up_away_seconds > 0 and config.catch_up_minimum_messages > 0
					and then (l_now.to_timestamp - l_left.to_timestamp) >= config.catch_up_away_seconds.to_integer_64
					and then l_missed >= config.catch_up_minimum_messages
				then
					catch_ups_asked := catch_ups_asked + 1
					ask_summary (seen_when_left, 0, 0)
				end
				left_at := Void
			end
			was_foreground := l_is_front
		ensure
			remembered: was_foreground = view.is_foreground
			nothing_posted: view.shown_model |=| old view.shown_model
		end

	catch_up_now
			-- "Catch me up" from the menu: the gap since the last event this
			-- member had seen when the window went away; the recent room when
			-- it has not been away.
		do
			ask_summary (seen_when_left.max (0), 0, 0)
		end

	show_any_summary
			-- One short call on the slot per frame; a bubble when the answer has
			-- landed. This is the whole of what the GUI does about summaries.
		local
			l_text: STRING_32
		do
			if attached summary_slot as s then
				l_text := collect_summary (s)
				if not l_text.is_empty then
					view.show_hint (l_text)
					summaries_shown := summaries_shown + 1
				end
			end
		end

	bot_handles: ARRAYED_LIST [STRING_32]
			-- The handles the SERVER answers to ("@claude"), fetched from
			-- /participants when the room opens. NOT the roster's usernames:
			-- the bot user is "claude_bot" and addressing that matches nothing.
			-- Empty until fetched, which makes `is_summary_line' answer False -
			-- the safe way round, since a line it claims is never posted.
		attribute
			create Result.make (2)
		end

	load_handles
			-- Ask the server which handles it answers to.
		local
			l_result: CHAT_RESULT [ARRAYED_LIST [STRING_32]]
		do
			if client.is_logged_in then
				l_result := client.participant_handles
				if l_result.is_success and then attached l_result.value as v then
					bot_handles := v
				end
			end
		end

	is_summary_line (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_text' mention one of the room's assistants AND open (past
			-- the mention) with a summary verb? Both halves are required: "sum"
			-- alone is a message to the room, and "@claude what is 2+2" is a
			-- question for the room to see.
		do
			Result := not bot_handles.is_empty
				and then across bot_handles as h some mentions_handle (a_text, h) end
				and then summary_ask.is_summary_ask (a_text)
		end

	mentions_handle (a_text: READABLE_STRING_GENERAL; a_handle: READABLE_STRING_32): BOOLEAN
			-- Does `a_text' carry `a_handle' ("@claude"), in any case?
		require
			addressable: a_handle.count >= 2 and then a_handle.item (1) = '@'
		do
			Result := a_text.to_string_32.as_lower.has_substring (a_handle.to_string_32.as_lower)
		end

	ask_summary (a_since_id, a_until_id: INTEGER_64; a_minutes: INTEGER)
			-- Ask for a summary WITHOUT waiting for it. The engine call behind
			-- it is a `claude -p' run of several seconds, and a GUI thread that
			-- stops pumping for five is ghosted by Windows with its keystrokes
			-- thrown away - so the request goes to a SUMMARY_HOST on its own
			-- processor, launched asynchronously (scalars only), and this
			-- returns within the frame. The answer lands in the slot and `tick'
			-- collects it. Meanwhile the member gets a status line and a
			-- composer that still works.
		require
			since_non_negative: a_since_id >= 0
			until_non_negative: a_until_id >= 0
			minutes_non_negative: a_minutes >= 0
		local
			l_host: separate SUMMARY_HOST
			l_slot: separate SUMMARY_SLOT
		do
			if client.is_logged_in and room_id > 0 then
				if not attached summary_slot then
					create l_slot.make
					summary_slot := l_slot
				end
				if attached summary_slot as s then
					if slot_is_waiting (s) then
						view.show_status (Message_summary_busy)
					else
						note_slot_request (s)
						create l_host.make (client.endpoint.base_url)
						hand_session_to_summary (l_host)
						attach_slot (l_host, s)
						launch_summary (l_host, room_id, a_since_id, a_until_id, a_minutes)
						view.show_status (Message_summarizing)
						summaries_asked := summaries_asked + 1
					end
				end
			end
		ensure
			nothing_posted: view.shown_model |=| old view.shown_model
		end

	summary_slot: detachable separate SUMMARY_SLOT
			-- Where a summary lands. One per window; it never blocks.

	slot_is_waiting (a_slot: separate SUMMARY_SLOT): BOOLEAN
		do
			Result := a_slot.is_waiting
		end

	note_slot_request (a_slot: separate SUMMARY_SLOT)
		do
			a_slot.note_request
		end

	hand_session_to_summary (a_host: separate SUMMARY_HOST)
			-- Copy the session into the host's client (short; the token is read here).
		require
			logged_in: client.is_logged_in
		do
			client.hand_session_to (a_host.client)
		end

	attach_slot (a_host: separate SUMMARY_HOST; a_slot: separate SUMMARY_SLOT)
		do
			a_host.set_slot (a_slot)
		end

	launch_summary (a_host: separate SUMMARY_HOST; a_room_id, a_since_id, a_until_id: INTEGER_64; a_minutes: INTEGER)
			-- Asynchronous: every argument is a scalar, so nothing of this
			-- processor is passed and the call does not wait for the engine.
		do
			a_host.fetch (a_room_id, a_since_id, a_until_id, a_minutes)
		end

	collect_summary (a_slot: separate SUMMARY_SLOT): STRING_32
			-- Whatever the slot holds, taken and cleared under ONE reservation
			-- so a second answer cannot land between the read and the clear;
			-- empty when there is nothing yet. Never waits: the slot only ever
			-- assigns fields.
		do
			create Result.make_empty
			if a_slot.has_outcome then
				create Result.make_from_separate (a_slot.text)
				a_slot.clear
			end
		end


	summaries_asked: INTEGER
			-- Summaries this window has asked for, by hand or on returning.

	summaries_shown: INTEGER
			-- Summaries actually drawn in this window.

feature {NONE} -- Implementation


	shut_down
			-- Close the room, end the session unless it is being remembered, and write the
			-- window's placement back to client.toml.
		do
			if presenter.is_room_open then
				presenter.close_room
			end
			if client.is_logged_in and then not remembers then
				client.logout
				config.forget_session
			end
			config.set_window (view.window.win_x, view.window.win_y,
				view.window.win_w.max (Minimum_window_width),
				view.window.win_h.max (Minimum_window_height))
			config.save
		ensure
			closed: not presenter.is_room_open
			logged_out_unless_remembered: client.is_logged_in implies remembers
		end

feature -- Constants

	Default_room_title: STRING_32 = "main"
			-- What the header says before the server names the room.

	Minimum_window_width: INTEGER = 480
	Minimum_window_height: INTEGER = 360

	Message_bad_server: STRING_32 = "That is not an address this client will send a password to"
	Message_summarizing: STRING_32 = "Summarizing..."
			-- Shown the instant a summary is asked for, so the window says what
			-- it is doing while another processor waits on the engine.

	Message_summary_busy: STRING_32 = "Still summarizing - one at a time."

	Message_no_rooms: STRING_32 = "The server lists no room for this account"

	advice: CONNECTION_ADVICE
			-- The ONE place the words for a server that never answered live; nothing in
			-- this window invents its own sentence about an outage.
		once
			create Result
		end

feature {NONE} -- The bot hint

	addressing_hint (a_bots: ARRAYED_LIST [CHAT_MEMBER]): STRING_32
			-- What to tell the member: the server's own HANDLES when
			-- /participants has answered, and the roster's mentions only as a
			-- fallback.
			--
			-- The difference is not cosmetic. The bot USER is "claude_bot" and
			-- the roster knows nothing else, so a hint built from the roster
			-- tells the member to type "@claude_bot" - which the address parser,
			-- which matches HANDLES, will never recognise. That is what the
			-- window told Larry for three weeks.
		require
			some_bots: not a_bots.is_empty
		do
			if bot_handles.is_empty then
				Result := bot_hint_text (a_bots)
			else
				Result := handle_hint_text (bot_handles)
			end
		ensure
			said_something: not Result.is_empty
			handles_when_known: not bot_handles.is_empty implies across bot_handles as h all Result.has_substring (h) end
		end

	handle_hint_text (a_handles: ARRAYED_LIST [STRING_32]): STRING_32
			-- "Address the room's assistant by mentioning @claude, anywhere in a message."
		require
			given: not a_handles.is_empty
		local
			i: INTEGER
		do
			create Result.make (80)
			Result.append ({STRING_32} "Address the room's assistant")
			if a_handles.count > 1 then
				Result.append_character ('s')
			end
			Result.append ({STRING_32} " by mentioning ")
			from i := 1 until i > a_handles.count loop
				Result.append (a_handles [i])
				if i < a_handles.count - 1 then
					Result.append ({STRING_32} ", ")
				elseif i = a_handles.count - 1 then
					Result.append ({STRING_32} " or ")
				end
				i := i + 1
			end
			Result.append ({STRING_32} ", anywhere in a message.")
		ensure
			named: across a_handles as h all Result.has_substring (h) end
			says_where: Result.has_substring ({STRING_32} "anywhere")
		end

	bot_hint_text (a_bots: ARRAYED_LIST [CHAT_MEMBER]): STRING_32
			-- "Address the room's assistant by mentioning @claude." for one bot;
			-- "...assistants... @claude or @otherbot." for several - always the
			-- roster's own usernames, never a name typed into this file.
			--
			-- It said "by starting a line with" until the mention rule changed
			-- under it: a handle anywhere in the message addresses the
			-- assistant now, and a hint that teaches the superseded rule is
			-- worse than no hint.
		require
			some_bots: not a_bots.is_empty
		local
			i: INTEGER
		do
			create Result.make (80)
			Result.append ({STRING_32} "Address the room's assistant")
			if a_bots.count > 1 then
				Result.append_character ('s')
			end
			Result.append ({STRING_32} " by mentioning ")
			from
				i := 1
			until
				i > a_bots.count
			loop
				Result.append (a_bots [i].mention)
				if i < a_bots.count - 1 then
					Result.append ({STRING_32} ", ")
				elseif i = a_bots.count - 1 then
					Result.append ({STRING_32} " or ")
				end
				i := i + 1
			end
			Result.append_character ('.')
		ensure
			named: across a_bots as b all Result.has_substring (b.mention) end
		end

feature {NONE} -- Processors

	start_polling (a_presenter: CHAT_PRESENTER; a_room_id, a_since_id: INTEGER_64)
			-- The inbox on a processor of its own, the poller on another with the session copied into
			-- its own client; the presenter pumps the inbox from now on.
		require
			logged_in: client.is_logged_in
			closed: not a_presenter.is_room_open
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
		local
			l_inbox: separate EVENT_INBOX
			l_host: separate POLLER_HOST
		do
			create l_inbox.make
			create l_host.make (client.endpoint.base_url)
			hand_session (l_host)
			attach_inbox (l_host, l_inbox)
			a_presenter.open_room (a_room_id, a_since_id, l_inbox)
			launch (l_host, a_room_id, a_since_id)
		ensure
			open: a_presenter.is_room_open
		end

	hand_session (a_host: separate POLLER_HOST)
			-- Copy the session into the host's client (synchronous: the token is read from here).
		require
			logged_in: client.is_logged_in
		do
			client.hand_session_to (a_host.client)
		end

	attach_inbox (a_host: separate POLLER_HOST; a_inbox: separate EVENT_INBOX)
			-- Give the host its inbox (a short call; the inbox is held only for its duration).
		do
			a_host.set_inbox (a_inbox)
		end

	launch (a_host: separate POLLER_HOST; a_room_id, a_since_id: INTEGER_64)
			-- Start the host's loop: asynchronous, because no argument is a reference this processor controls.
		do
			a_host.poll (a_room_id, a_since_id)
		end

invariant
	room_iff_open: presenter.is_room_open implies room_id > 0
	seen_non_negative: last_seen_id >= 0
	client_at_endpoint: client.endpoint = endpoint

end
