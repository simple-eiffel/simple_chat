note
	description: "[
		The JSON handlers - the thick client's calls and the bot API are
		one set of routes (06-INTERFACE-DESIGN + spec/10). Every handler
		answers through SIMPLE_WEB_SERVER_RESPONSE with CHAT_JSON's wire
		forms; errors carry CHAT_ERROR's status and message. Nothing here
		renders HTML.
	]"
	author: "Larry Rix"

class
	CHAT_API

create
	make

feature {NONE} -- Initialization

	make (a_service: CHAT_SERVICE; a_config: SERVER_CONFIG)
		do
			service := a_service
			config := a_config
			create codec.make
		ensure
			set: service = a_service and config = a_config
		end

feature -- Handlers

	handle_health (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_login (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_logout (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_rooms (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_events (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- GET /rooms/{id}/events?since=N|before=N&limit=M
		do
			not_yet (a_response)
		end

	handle_wait (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- GET /rooms/{id}/wait?since=N&limit=M&seconds=S - the thick client's
			-- long-poll (D-018): CHAT_SERVICE.wait_for_events, answered as a page
			-- with the statuses the POLL_WAITER kept.
		do
			not_yet (a_response)
		end

	handle_stream (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- GET /rooms/{id}/stream?since=N - an SSE_STREAM over a WEB_STREAM_SINK (bots, curl).
		do
			not_yet (a_response)
		end

	handle_members (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- GET /rooms/{id}/members - the roster as CHAT_MEMBER wire forms (never a hash).
		do
			not_yet (a_response)
		end

	handle_post_message (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_upload (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- POST /rooms/{id}/images (multipart through simple_web's upload support).
		do
			not_yet (a_response)
		end

	handle_attachment (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- GET /attachments/{id}: the validated type, nosniff, immutable caching.
		do
			not_yet (a_response)
		end

	handle_me (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_change_password (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_admin_users (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_admin_create_user (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_admin_reset_password (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_admin_create_bot (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- The token is shown once, here, and never stored in clear.
		do
			not_yet (a_response)
		end

	handle_admin_revoke_bot (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_admin_backup (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			not_yet (a_response)
		end

	handle_participants (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- GET /participants: handles and display names, for @ completion.
		do
			not_yet (a_response)
		end

feature {NONE} -- Implementation

	service: CHAT_SERVICE
	config: SERVER_CONFIG
	codec: CHAT_JSON

	not_yet (a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- Phase 1: every route answers 501.
		do
			a_response.send_error (501, "Not implemented (Phase 1 skeleton)")
		end

end
