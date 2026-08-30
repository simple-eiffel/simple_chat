note
	description: "[
		The member's executable - the thick client (D-015). Loads the
		config, locates the server (local service first, D-016), logs in,
		opens the room, and runs the simple_widgets window whose timer
		pumps the presenter. Single-instance: a second launch focuses the
		first. Everything below the window is UI-free and lives in the
		library's `client' cluster; this class only assembles it.

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
	]"
	author: "Larry Rix"

class
	CLIENT_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			l_config: CLIENT_CONFIG
			l_transport: WINHTTP_TRANSPORT
			l_locator: SERVICE_LOCATOR
			l_endpoint: CHAT_ENDPOINT
		do
			create l_config.make_defaults
			l_config.load
			create l_transport.make
			create l_locator.make (l_transport)
			l_endpoint := l_locator.locate (l_config)
			create client.make (l_transport, l_endpoint)
			-- Implementation in Phase 4: login dialog (SW_DIALOG) -> client.login; presenter over
			-- SW_CHAT_VIEW + TRAY_NOTIFIER; start_polling (presenter, room, since); the window timer
			-- calls presenter.pump every tick; on close: presenter.log_out (the inbox is stopped and
			-- the host's loop ends on its next poll), then l_config.save.
		end

feature -- Access

	client: CHAT_CLIENT
			-- The GUI's own client: login and posting on the root processor.

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
