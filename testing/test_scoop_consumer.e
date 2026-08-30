note
	description: "SCOOP consumer compatibility: the library's main types in use, compiled with concurrency use=scoop."

class
	TEST_SCOOP_CONSUMER

feature -- Test

	test_scoop_compatibility
			-- Verify library types work in a SCOOP build: a facade, a config, an API over a memory store.
		local
			l_server: SIMPLE_CHAT_SERVER
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_service: CHAT_SERVICE
			l_api: CHAT_API
			l_registry: PARTICIPANT_REGISTRY
		do
			create l_server.make
			create l_config.make_defaults
			create l_store.make
			l_store.open
			create l_bus.make
			create l_limits.make (60)
			create l_logger
			create l_log.make (l_logger)
			create l_service.make (l_store, l_bus, l_limits, l_config, l_log)
			create l_api.make (l_service, l_config)
			create l_registry.make
			l_server.set_config (l_config).do_nothing
			check health_answers: l_api.health.status = 200 end
		end

end
