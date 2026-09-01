note
	description: "[
		The member's executable - the thick client (D-015). Loads the
		config, locates the server (local service first, D-016), and
		assembles the whole UI-free stack: the GUI's own CHAT_CLIENT over
		WINHTTP_TRANSPORT, the presenter over a view and TRAY_NOTIFIER.
		Single-instance focus and the window itself are a later UI pass.

		Three processors (approach section 8): the root runs the window,
		the presenter and the GUI's own CHAT_CLIENT for posting; a
		POLLER_HOST runs the EVENT_POLLER with a transport and CHAT_CLIENT
		of its own; an EVENT_INBOX sits between them and never blocks.
		Only bytes cross: the session is copied into the host's client
		(`hand_session_to'), pages come back as bytes through the inbox.
		No routine here holds the inbox or the host across anything long:
		`start_polling' hands the inbox over in one short call and then
		launches the loop asynchronously with no separate argument at all,
		so the launch does not wait for the loop to end.

		The visible pane is deliberately absent: SW_CHAT_VIEW (the
		simple_widgets room pane) waits for simple_shaping, without which
		Hebrew cannot be rendered; until it lands, MEMORY_CHAT_VIEW
		stands in so the full stack assembles and this target compiles.
	]"
	author: "Larry Rix"

class
	CLIENT_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Assemble everything that needs no pane: config, transport, locator,
			-- endpoint, client, view, tray, notifier, presenter.
		local
			l_locator: SERVICE_LOCATOR
			l_endpoint: CHAT_ENDPOINT
			l_tray: SHELL_TRAY
		do
			create config.make_defaults
			config.load
			create transport.make
			create l_locator.make (transport)
			l_endpoint := l_locator.locate (config)
			create client.make (transport, l_endpoint)
			create view.make
			create l_tray.make ({TRAY_NOTIFIER}.Tooltip_base)
			create notifier.make (l_tray)
			create presenter.make (client, view, notifier)
				-- The interactive part is UI-gated and stays honestly unbuilt here:
				-- the login dialog and the room pane are SW_* panes (simple_widgets)
				-- whose text path waits for simple_shaping (SW_CHAT_VIEW renders
				-- Hebrew, or it does not ship). Once the pane lands, the flow is:
				-- login dialog -> client.login (or a remembered session:
				-- config.load_session handed back through the dialog);
				-- start_polling (presenter, room, since); the window timer calls
				-- presenter.pump every tick and, when presenter.session_lost is set
				-- afterwards (the server answered 401: the room is closed and the
				-- client logged out with no exchange), shows the login dialog again
				-- and start_polling from presenter.last_seen_id; on close:
				-- presenter.log_out while still logged in (the inbox is stopped and
				-- the host's loop ends on its next poll), then config.save.
		end

feature -- Access

	client: CHAT_CLIENT
			-- The GUI's own client: login and posting on the root processor.

	config: CLIENT_CONFIG
			-- What the member's machine remembers; saved again on close.

	transport: WINHTTP_TRANSPORT
			-- The root processor's transport: the locator's probes, the login,
			-- every post. The poller's lives in POLLER_HOST, on its processor.

	view: MEMORY_CHAT_VIEW
			-- Stand-in for SW_CHAT_VIEW until simple_shaping lands; the presenter
			-- talks only to CHAT_VIEW, so the swap will not touch it.

	notifier: TRAY_NOTIFIER
			-- Balloons and the unread badge on the notification area.

	presenter: CHAT_PRESENTER
			-- The logic between the client, the inbox, the view and the notifier.

feature -- Basic operations

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

feature {NONE} -- Processors

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

end
