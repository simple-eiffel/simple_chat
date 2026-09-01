note
	description: "[
		The project's bridge from the test target to test-only hooks, on
		the pattern of simple_testing's TEST_SET_BRIDGE - which cannot be
		named in export clauses here, because production targets do not
		include simple_testing and an unknown client class is a VTCM
		warning. This class lives in the library cluster, so every target
		knows it; only test classes inherit it. Features exported to
		{CHAT_TEST_BRIDGE} (the door's `set_arguments_text' and
		`child_process_id', the updater's `set_service_base') are sealed
		away from production code, which never inherits this class.
	]"
	author: "Larry Rix"

class
	CHAT_TEST_BRIDGE

end
