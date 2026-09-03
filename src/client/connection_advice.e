note
	description: "[
		What to tell a member whose sign-in never reached a server at
		all: HTTP_REPLY.status = 0, the transport having failed before
		any answer came back (CHAT_CLIENT.last_status says so). The raw
		transport text - a WinHTTP number, "the name could not be
		resolved" - names a mechanism, not an action, and the member is
		left staring at a window whose only other signal is the word
		"not answering". These two sentences name the action instead.

		THE ADDRESS DECIDES, and nothing else. This PC's own loopback -
		the address CLIENT_CONFIG.prefers_local and local_port build -
		means the room is meant to be hosted HERE and the server is not
		running, so the advice is the Start Menu entry that starts it.
		Any other address is a friend's server, so the advice is his
		server or the address in this PC's settings file. `is_this_pc'
		is the whole distinction.

		A REFUSAL IS NOT AN OUTAGE. A wrong password, an unknown name, a
		locked account - those are real HTTP statuses carrying the
		server's own words, and nothing here touches them. CLIENT_APP
		asks for this advice ONLY when the transport failed.
	]"
	author: "Larry Rix"

class
	CONNECTION_ADVICE

inherit
	CHAT_URL_RULES

feature -- Access

	advice_for (a_url: READABLE_STRING_8; a_config: CLIENT_CONFIG): STRING_32
			-- What to show a member whose sign-in at `a_url' never reached a server:
			-- `local_advice' when `a_url' is this PC's own loopback, `remote_advice'
			-- when it is somebody else's.
		require
			addressed: not a_url.is_empty
		do
			if is_this_pc (a_url, a_config) then
				Result := local_advice (a_url)
			else
				Result := remote_advice (a_url)
			end
		ensure
			given: not Result.is_empty
			names_the_address: Result.has_substring (a_url.to_string_32)
			names_the_settings_file: Result.has_substring (Settings_file)
			this_pc_names_the_start_menu: is_this_pc (a_url, a_config) implies Result.has_substring (Start_server_entry)
			a_friend_is_never_told_to_start_a_server: (not is_this_pc (a_url, a_config)) implies not Result.has_substring (Start_server_entry)
		end

	local_advice (a_url: READABLE_STRING_8): STRING_32
			-- (a) Nothing answers on this PC's own loopback: no server is running here.
		require
			addressed: not a_url.is_empty
		do
			create Result.make (240)
			Result.append ({STRING_32} "No chat server is running on this PC (nothing answers at ")
			Result.append_string_general (a_url)
			Result.append ({STRING_32} "). If this PC hosts the room: ")
			Result.append (Start_server_entry)
			Result.append ({STRING_32} ", then sign in again. If a friend hosts it: put their address in ")
			Result.append (Settings_file)
		ensure
			given: not Result.is_empty
			names_the_address: Result.has_substring (a_url.to_string_32)
			names_the_start_menu: Result.has_substring (Start_server_entry)
			names_the_settings_file: Result.has_substring (Settings_file)
		end

	remote_advice (a_url: READABLE_STRING_8): STRING_32
			-- (b) Nothing answers at a server this PC does not host.
		require
			addressed: not a_url.is_empty
		do
			create Result.make (200)
			Result.append ({STRING_32} "Cannot reach the room at ")
			Result.append_string_general (a_url)
			Result.append ({STRING_32} ". The host's server may be down, or the address in your settings file (")
			Result.append (Settings_file)
			Result.append ({STRING_32} ") may be wrong.")
		ensure
			given: not Result.is_empty
			names_the_address: Result.has_substring (a_url.to_string_32)
			names_the_settings_file: Result.has_substring (Settings_file)
			never_the_start_menu: not Result.has_substring (Start_server_entry)
		end

feature -- Status report

	is_this_pc (a_url: READABLE_STRING_8; a_config: CLIENT_CONFIG): BOOLEAN
			-- Does `a_url' name this PC's own loopback - the address `prefers_local' and
			-- `local_port' build, or any other spelling of the loopback host?
		do
			Result := is_loopback_url (a_url) or else same_url (a_url, a_config.local_url)
		ensure
			definition: Result = (is_loopback_url (a_url) or same_url (a_url, a_config.local_url))
			the_configured_local_service_is_always_this_pc: same_url (a_url, a_config.local_url) implies Result
		end

feature -- Constants

	Settings_file: STRING_32 = "%%APPDATA%%%/92/simple_chat%/92/client.toml"
			-- The client's settings file, spelled as README.md and CLIENT_CONFIG spell it.

	Start_server_entry: STRING_32 = "Start Menu > SimpleChat Server > Start server"
			-- The installer's own [Icons] entry (installer/SimpleChat.iss), word for word:
			-- a member reads it off his Start Menu, so it must match what is written there.

end
