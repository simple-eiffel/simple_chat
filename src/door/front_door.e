note
	description: "[
		Whatever terminates TLS on the public port and forwards to the
		server on localhost (D-013). Caddy as a supervised child process
		now; an in-process Eiffel door later; none when a tunnel or an
		external proxy does the job. The chat never knows which: it speaks
		plain HTTP on 127.0.0.1 and reads the forwarded headers every
		public door promises to set.

		Implementations live in the server application's `ops' cluster
		(intent-v2 Q1); this contract lives in the library.
	]"
	author: "Larry Rix"

deferred class
	FRONT_DOOR

feature -- Access

	public_name: STRING_8
			-- The DNS name members use; empty when not public.
		deferred
		end

	upstream_port: INTEGER
			-- Where the chat listens on localhost.
		deferred
		ensure
			positive: Result > 0
		end

	last_error: detachable CHAT_ERROR
			-- Why the door is not serving, when it is not.
		deferred
		end

feature -- Status report

	is_serving: BOOLEAN
		deferred
		end

	is_public: BOOLEAN
			-- Does this door own the public port itself?
		deferred
		end

	has_child_process: BOOLEAN
		deferred
		end

	sets_forwarded_headers: BOOLEAN
			-- Will requests reach the chat with X-Forwarded-Proto/For set?
		deferred
		end

feature -- Basic operations

	start
		require
			not_serving: not is_serving
			named_when_public: is_public implies not public_name.is_empty
		deferred
		ensure
			outcome: is_serving xor (last_error /= Void)
		end

	stop
		deferred
		ensure
			stopped: not is_serving
			no_orphan: not has_child_process
		end

	check_health
			-- Supervisor tick: restart a dead child, refresh `last_error'.
		deferred
		ensure
			reported: is_serving or last_error /= Void
		end

invariant
	serving_has_name: (is_serving and is_public) implies not public_name.is_empty
	public_doors_forward: (is_serving and is_public) implies sets_forwarded_headers

end
