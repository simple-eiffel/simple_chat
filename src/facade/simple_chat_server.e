note
	description: "[
		One simple_chat server: assembles store, service, web app, front
		door, dynamic DNS and the participant dispatcher from a
		SERVER_CONFIG, starts and stops them in order, reports health.
		Holds no domain rule. The front door and DNS are supplied by the
		application (its `ops' cluster) through the library's contracts.
	]"
	author: "Larry Rix"

class
	SIMPLE_CHAT_SERVER

create
	make

feature {NONE} -- Initialization

	make
			-- An unconfigured server.
		do
			create bus.make
			create limits.make (3600)
			create registry.make
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

	set_store (a_store: CHAT_STORE): like Current
		require
			not_running: not is_running
		do
			store := a_store
			Result := Current
		ensure
			set: store = a_store
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

	set_registry (a_registry: PARTICIPANT_REGISTRY): like Current
		require
			not_running: not is_running
		do
			registry := a_registry
			Result := Current
		ensure
			set: registry = a_registry
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
			-- Open and migrate the store, build the service and web app on
			-- localhost, start the door and DNS, subscribe the dispatcher.
		require
			configured: is_configured
			not_running: not is_running
		do
			-- Implementation in Phase 4
			last_error := not_implemented
		ensure
			running_or_reported: is_running xor (last_error /= Void)
			store_open: is_running implies (attached store as s and then s.is_open)
			door_started: is_running implies (attached front_door as d and then (d.is_serving or d.last_error /= Void))
			dispatcher_subscribed: (is_running and registry.count > 0) implies (attached dispatcher as p and then bus.subscribers_model.has (p))
		end

	run
			-- Serve until stopped (blocking).
		require
			running: is_running
		do
			-- Implementation in Phase 4: web_app.run
		end

	stop
			-- Reverse order. Never leaves a child process behind.
		do
			is_running := False
			-- Implementation in Phase 4
		ensure
			stopped: not is_running
			door_stopped: attached front_door as d implies (not d.is_serving and not d.has_child_process)
			store_closed: attached store as s implies not s.is_open
		end

feature -- Status

	is_configured: BOOLEAN
		do
			Result := attached config as c and then c.is_valid
		end

	is_running: BOOLEAN

	last_error: detachable CHAT_ERROR

	health: CHAT_HEALTH
		require
			running: is_running
		do
			create Result.make (attached store as s and then s.is_open, attached web_app as w and then w.is_running,
				attached front_door as d and then d.is_serving, attached dynamic_dns as n and then n.last_result.same_string ({DYNAMIC_DNS}.Result_ok),
				dispatcher /= Void)
		end

feature -- Access

	bus: EVENT_BUS
	limits: RATE_LIMITER
	registry: PARTICIPANT_REGISTRY

feature {NONE} -- Implementation

	config: detachable SERVER_CONFIG
	store: detachable CHAT_STORE
	service: detachable CHAT_SERVICE
	web_app: detachable CHAT_WEB_APP
	front_door: detachable FRONT_DOOR
	dynamic_dns: detachable DYNAMIC_DNS
	dispatcher: detachable PARTICIPANT_DISPATCHER
	log: detachable CHAT_LOG

	not_implemented: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501)
		end

invariant
	running_implies_configured: is_running implies is_configured
	running_implies_parts: is_running implies (store /= Void and service /= Void and web_app /= Void and front_door /= Void)

end
