note
	description: "SCOOP consumer compatibility: the library's main types in use, compiled with concurrency support scoop."

class
	TEST_SCOOP_CONSUMER

feature -- Test

	test_scoop_compatibility
			-- Verify library types work in a SCOOP-capable build.
		local
			l_server: SIMPLE_CHAT_SERVER
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_registry: PARTICIPANT_REGISTRY
		do
			create l_server.make
			create l_config.make_defaults
			create l_store.make
			create l_bus.make
			create l_limits.make (60)
			create l_registry.make
			l_server.set_config (l_config).set_store (l_store).set_registry (l_registry).do_nothing
		end

end
