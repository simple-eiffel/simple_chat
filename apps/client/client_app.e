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
		end

	tick
			-- The window's 250 ms heartbeat, on the ROOT processor: one pump, the badge,
			-- and - when the server has rejected the session - the end of this pane.
		do
			if presenter.is_room_open and then client.is_logged_in then
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
			-- The composer's line, posted. The echo comes back through the poller like
			-- everybody else's, so nothing is shown here.
		do
			if presenter.is_room_open and then client.is_logged_in and then not a_text.is_empty then
				presenter.send (a_text)
			end
		ensure
			nothing_shown_here: view.shown_model |=| old view.shown_model
		end

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
	Message_no_rooms: STRING_32 = "The server lists no room for this account"

	advice: CONNECTION_ADVICE
			-- The ONE place the words for a server that never answered live; nothing in
			-- this window invents its own sentence about an outage.
		once
			create Result
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
