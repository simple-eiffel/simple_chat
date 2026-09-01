note
	description: "[
		The dispatcher's creation path (NEW-1): builds the one
		PARTICIPANT_DISPATCHER on its own SCOOP processor, starting after
		the store's last event id (`dispatcher_start_after', Issue 16), and
		subscribes it with the bus through `CHAT_API.dispatcher_subscribe'
		- the dispatcher is this process, so no token and no room check.
		The facade calls `launch (shared_api)' once at startup and keeps
		this host alive; the dispatcher then drives itself: every bus
		`wake' runs `dispatch_pending' on the dispatcher's processor.

		SCOOP: `a_api' is touched only as a formal argument of `launch';
		the dispatcher is created `separate' with the API passed straight
		through to its creation procedure (lock passing), and is held here
		only as a reference - never called across an engine run.
	]"
	author: "Larry Rix"

class
	DISPATCHER_HOST

create
	make

feature {NONE} -- Initialization

	make
			-- A host with nothing launched yet.
		do
		ensure
			nothing_launched: dispatcher = Void
		end

feature -- Access

	dispatcher: detachable separate PARTICIPANT_DISPATCHER
			-- The dispatcher this host launched, on its own processor; Void before `launch'.

feature -- Status report

	is_launched: BOOLEAN
			-- Has the dispatcher been created and subscribed?
		do
			Result := dispatcher /= Void
		ensure
			definition: Result = (dispatcher /= Void)
		end

feature -- Basic operations

	launch (a_api: separate CHAT_API)
			-- Create the dispatcher on its own processor, starting after the
			-- store's last event id, and subscribe it with the bus.
		require
			not_yet: not is_launched
		local
			l_dispatcher: separate PARTICIPANT_DISPATCHER
			l_settled: INTEGER_64
		do
			create l_dispatcher.make (a_api, a_api.dispatcher_start_after)
			a_api.dispatcher_subscribe (l_dispatcher)
				-- `dispatcher_subscribe' is an asynchronous command; the API
				-- executes it later and its bus must reach back into the
				-- subscriber. That reach-back is lawful ONLY while this
				-- routine still holds the dispatcher (passed locks). The
				-- synchronous query below makes the API drain the subscribe
				-- BEFORE we queue `populate' - otherwise the API's reach-back
				-- meets a dispatcher already blocked reserving the API for
				-- population: a mutual deadlock that froze the whole server.
			l_settled := a_api.dispatcher_start_after
			populate_later (l_dispatcher)
			dispatcher := l_dispatcher
		ensure
			launched: is_launched
		end

feature {NONE} -- Implementation

	populate_later (a_dispatcher: separate PARTICIPANT_DISPATCHER)
			-- Queue `populate' as the dispatcher's first own turn (an
			-- asynchronous command): population must not run during the
			-- creation, whose passed locks let ISE SCOOP execute calls on
			-- the creator's thread - the thread-affine SQLite store refuses
			-- any thread but its own.
		do
			a_dispatcher.populate
		end

end
