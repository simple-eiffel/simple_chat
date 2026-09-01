note
	description: "[
		One simple_chat server: starts the web face, the front door and
		dynamic DNS from a SERVER_CONFIG, in order, and reports health.
		Holds no domain rule. Under SCOOP (D1) the service, store, bus,
		limiter and participants are built on the API's own processor
		(CHAT_SHARED.shared_api) from the settings this facade shares
		before starting; the participant dispatcher is launched on its own
		processor through DISPATCHER_HOST when the configuration has
		participants; the door and DNS are supplied by the application
		(its `ops' cluster) through the library's contracts.
	]"
	author: "Larry Rix"

class
	SIMPLE_CHAT_SERVER

inherit
	CHAT_SHARED

create
	make

feature {NONE} -- Initialization

	make
			-- An unconfigured server.
		do
		ensure
			not_configured: not is_configured
			not_running: not is_running
		end

feature -- Configuration (Builder Pattern)

	set_config (a_config: SERVER_CONFIG): like Current
		require
			not_running: not is_running
			valid: a_config.is_valid
		do
			config := a_config
			Result := Current
		ensure
			set: config = a_config
			result_current: Result = Current
		end

	set_front_door (a_door: FRONT_DOOR): like Current
		require
			not_running: not is_running
		do
			front_door := a_door
			Result := Current
		ensure
			set: front_door = a_door
			result_current: Result = Current
		end

	set_dynamic_dns (a_dns: DYNAMIC_DNS): like Current
		require
			not_running: not is_running
		do
			dynamic_dns := a_dns
			Result := Current
		ensure
			set: dynamic_dns = a_dns
			result_current: Result = Current
		end

	set_log (a_log: CHAT_LOG): like Current
		require
			not_running: not is_running
		do
			log := a_log
			Result := Current
		ensure
			set: log = a_log
			result_current: Result = Current
		end

feature -- Core Operations

	start
			-- Share the configuration, bring the API up on its processor,
			-- create the web face, start the door and DNS.
		require
			configured: is_configured
			not_running: not is_running
			door_matches_config: is_door_matching_config
		local
			l_web: CHAT_WEB_APP
			l_host: DISPATCHER_HOST
		do
			if attached config as c then
				shared_put (Config_path_key, {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (c.source_path))
				api := shared_api
				if c.ai_enabled and then dispatcher_host = Void and then attached api as a then
						-- Once per process: `shared_api' (and the bus behind it) survives stop/start,
						-- so a second launch would subscribe a second dispatcher and answer twice.
					create l_host.make
					l_host.launch (a)
					dispatcher_host := l_host
				end
				create l_web.make (c)
				l_web.start
				web_app := l_web
				if attached front_door as d then
					d.start
				end
				if attached dynamic_dns as n then
					n.update
				end
				is_running := l_web.is_running
				if not is_running then
					last_error := l_web.last_error
				else
					last_error := Void
				end
			end
		ensure
			running_or_reported: is_running xor (last_error /= Void)
			api_up: is_running implies api /= Void
			dispatcher_up: (attached config as c2 and then c2.ai_enabled) implies (attached dispatcher_host as h and then h.is_launched)
			no_dispatcher_unasked: (attached config as c3 and then not c3.ai_enabled and old dispatcher_host = Void) implies dispatcher_host = Void
			launched_once: (old dispatcher_host) /= Void implies dispatcher_host = old dispatcher_host
			door_started: is_running implies (attached front_door as d implies (d.is_serving or d.last_error /= Void))
		end

	run
			-- Serve until stopped (blocking on the caller's processor).
		require
			running: is_running
		do
			if attached web_app as w then
				w.run
			end
		end

	stop
			-- Reverse order. Never leaves a child process behind.
		do
			if attached front_door as d then
				d.stop
			end
			if attached web_app as w then
				w.stop
			end
			web_app := Void
			is_running := False
		ensure
			stopped: not is_running
			door_stopped: attached front_door as d implies (not d.is_serving and not d.has_child_process)
		end

feature -- Status

	is_configured: BOOLEAN
		do
			Result := attached config as c and then c.is_valid
		end

	is_door_matching_config: BOOLEAN
			-- Does the door's public stance agree with the configuration's
			-- (M-G)? A public configuration needs a door, and that door's
			-- `is_public' must equal the configuration's.
		do
			Result := attached config as c implies
				((c.is_public = (attached front_door as d and then d.is_public)) and (c.is_public implies front_door /= Void))
		end

	is_running: BOOLEAN

	last_error: detachable CHAT_ERROR

	health: CHAT_HEALTH
		require
			running: is_running
		do
			create Result.make (api /= Void, attached web_app as w and then w.is_running,
				attached front_door as d and then d.is_serving,
				attached dynamic_dns as n and then n.last_result.same_string ({DYNAMIC_DNS}.Result_ok),
				attached dispatcher_host as h and then h.is_launched)
		end

feature -- Access

	api: detachable separate CHAT_API
			-- The API, on its own processor, once started.

feature {NONE} -- Implementation

	config: detachable SERVER_CONFIG
	web_app: detachable CHAT_WEB_APP
	front_door: detachable FRONT_DOOR
	dynamic_dns: detachable DYNAMIC_DNS
	log: detachable CHAT_LOG

	dispatcher_host: detachable DISPATCHER_HOST
			-- The participant dispatcher's home, once `start' launched it (ai_enabled only).

invariant
	running_implies_configured: is_running implies is_configured
	running_implies_parts: is_running implies (web_app /= Void and api /= Void)

end
