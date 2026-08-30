note
	description: "[
		Whatever terminates TLS on the public port and forwards to the
		server on localhost (D-013). Caddy as a supervised child process
		now; an in-process Eiffel door later; none when a tunnel or an
		external proxy does the job. The chat never knows which: it speaks
		plain HTTP on 127.0.0.1 and reads the forwarded headers every
		public door promises to set.

		Implementations live in the server application's `ops' cluster
		(intent-v2 Q1); this contract lives in the library. Under SCOOP a
		door with a child to supervise runs on its own processor.
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
			-- Is a child of this door alive right now (not merely remembered)?
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
			cleared_on_success: is_serving implies last_error = Void
		end

	stop
		deferred
		ensure
			stopped: not is_serving
			no_orphan: not has_child_process
		end

	check_health
			-- Supervisor tick: restart a dead child, refresh `last_error'. Never starts a door that was stopped.
		deferred
		ensure
			reported: is_serving or last_error /= Void
			no_silent_start: (not old is_serving and not old has_child_process) implies not is_serving
		end

feature -- Validation (contract support)

	is_hostname (a_name: READABLE_STRING_8): BOOLEAN
			-- 1..253 characters of labels [a-z0-9-] joined by dots, no label empty or starting/ending with a dash.
		local
			l_labels: LIST [READABLE_STRING_8]
		do
			Result := a_name.count >= 1 and a_name.count <= 253 and then not a_name.has (' ')
			if Result then
				l_labels := a_name.split ('.')
				Result := across l_labels as l all is_label (l) end
			end
		end

	is_label (a_label: READABLE_STRING_8): BOOLEAN
		local
			i: INTEGER
			c: CHARACTER_8
		do
			Result := a_label.count >= 1 and a_label.count <= 63 and then (a_label [1] /= '-' and a_label [a_label.count] /= '-')
			from
				i := 1
			until
				i > a_label.count or not Result
			loop
				c := a_label [i]
				Result := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c = '-'
				i := i + 1
			end
		end

invariant
	serving_has_name: (is_serving and is_public) implies not public_name.is_empty
	public_doors_forward: (is_serving and is_public) implies sets_forwarded_headers
	public_name_is_hostname: not public_name.is_empty implies is_hostname (public_name)

end
