note
	description: "[
		The one CHAT_API of this process, on its own processor (D1), for
		every request handler to reach: a once ("PROCESS") of separate
		type, the form SCOOP requires. It is built on first use from the
		settings the root put into SIMPLE_WEB_SHARED before starting the
		server ("config_path"). Inherit from this wherever the API is
		needed on another processor; hold the API only inside routines
		that take it as a separate argument.
	]"
	author: "Larry Rix"

class
	CHAT_SHARED

inherit
	SIMPLE_WEB_SHARED

feature -- Access

	shared_api: separate CHAT_API
			-- The API, on its own processor; the service, store, bus and limiter live there with it.
		once ("PROCESS")
			create Result.make_from_shared
		end

feature -- Constants

	Config_path_key: STRING_8 = "config_path"
			-- The shared setting the root fills before `start'.

end
