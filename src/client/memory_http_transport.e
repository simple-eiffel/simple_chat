note
	description: "[
		HTTP_TRANSPORT that replays a script: `script' queues the replies
		in order; each `send' consumes one and records the request (method,
		url, headers, body). An empty script answers with a transport
		failure, so a test that forgets to script sees it. `requests_model'
		is what the assault reads to prove a token travelled as a header
		and never in a URL.
	]"
	author: "Larry Rix"

class
	MEMORY_HTTP_TRANSPORT

inherit
	HTTP_TRANSPORT

create
	make

feature {NONE} -- Initialization

	make
		do
			create replies.make (4)
			create requests.make (8)
		ensure
			nothing_scripted: scripted_count = 0
			nothing_sent: exchange_count = 0
		end

feature -- Model Queries (for MML postconditions)

	requests_model: MML_SEQUENCE [HTTP_REQUEST_RECORD]
			-- Every request sent, in order.
		do
			create Result
			across requests as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = requests.count
		end

feature -- Access

	exchange_count: INTEGER
		do
			Result := requests.count
		end

	scripted_count: INTEGER
			-- Replies not yet consumed.
		do
			Result := replies.count
		end

	requests: ARRAYED_LIST [HTTP_REQUEST_RECORD]

	last_request: HTTP_REQUEST_RECORD
		require
			sent_something: exchange_count > 0
		do
			Result := requests.last
		end

feature -- Element change

	script (a_status: INTEGER; a_body: READABLE_STRING_8)
			-- The next unconsumed reply.
		require
			http_status: a_status >= 100 and a_status <= 599
		do
			replies.extend (create {HTTP_REPLY}.make (a_status, a_body))
		ensure
			queued: scripted_count = old scripted_count + 1
			requests_unchanged: requests_model |=| old requests_model
		end

	script_failure (a_error: READABLE_STRING_GENERAL)
			-- The next exchange fails at the transport.
		require
			explained: not a_error.is_empty
		do
			replies.extend (create {HTTP_REPLY}.make_failed (a_error))
		ensure
			queued: scripted_count = old scripted_count + 1
			requests_unchanged: requests_model |=| old requests_model
		end

feature -- Basic operations

	send (a_method, a_url: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER): HTTP_REPLY
		local
			l_record: HTTP_REQUEST_RECORD
		do
			create l_record.make (a_method, a_url, a_headers, a_body, a_timeout_seconds)
			requests.extend (l_record)
			if replies.is_empty then
				create Result.make_failed ("MEMORY_HTTP_TRANSPORT: no scripted reply for " + a_method + " " + a_url)
			else
				Result := replies.first
				replies.start
				replies.remove
			end
		ensure then
			recorded: requests_model |=| ((old requests_model) & last_request)
			consumed: scripted_count = (old scripted_count - 1).max (0)
		end

feature {NONE} -- Implementation

	replies: ARRAYED_LIST [HTTP_REPLY]

invariant
	model_consistent: requests_model.count = requests.count

end
