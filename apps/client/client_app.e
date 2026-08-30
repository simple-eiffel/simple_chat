note
	description: "[
		The member's executable - the thick client (D-015). Loads the
		config, locates the server (local service first, D-016), logs in,
		opens the room, and runs the simple_widgets window whose timer
		pumps the presenter. Single-instance: a second launch focuses the
		first. Everything below the window is UI-free and lives in the
		library's `client' cluster; this class only assembles it.
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
			l_client: CHAT_CLIENT
		do
			create l_config.make_defaults
			l_config.load
			create l_transport.make
			create l_locator.make (l_transport)
			l_endpoint := l_locator.locate (l_config)
			create l_client.make (l_transport, l_endpoint)
			-- Implementation in Phase 4: login dialog (SW_DIALOG), presenter over SW_CHAT_VIEW + TRAY_NOTIFIER,
			-- poller on a worker, window timer -> presenter.pump; save config on close
		end

end
