note
	description: "What /health reports: one flag per part."
	author: "Larry Rix"

class
	CHAT_HEALTH

create
	make

feature {NONE} -- Initialization

	make (a_store_ok, a_web_ok, a_door_serving, a_dns_fresh, a_dispatcher_enabled: BOOLEAN)
		do
			store_ok := a_store_ok
			web_ok := a_web_ok
			door_serving := a_door_serving
			dns_fresh := a_dns_fresh
			dispatcher_enabled := a_dispatcher_enabled
		ensure
			set: store_ok = a_store_ok and web_ok = a_web_ok and door_serving = a_door_serving
				and dns_fresh = a_dns_fresh and dispatcher_enabled = a_dispatcher_enabled
		end

feature -- Access

	store_ok, web_ok, door_serving, dns_fresh, dispatcher_enabled: BOOLEAN

feature -- Status report

	is_healthy: BOOLEAN
			-- Store and web are the essentials; a door or DNS problem is reported, not fatal.
		do
			Result := store_ok and web_ok
		ensure
			definition: Result = (store_ok and web_ok)
		end

end
