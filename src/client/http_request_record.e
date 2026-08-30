note
	description: "One request as MEMORY_HTTP_TRANSPORT saw it: what the client actually sent."
	author: "Larry Rix"

class
	HTTP_REQUEST_RECORD

create
	make

feature {NONE} -- Initialization

	make (a_method, a_url: READABLE_STRING_8; a_headers: HASH_TABLE [STRING_8, STRING_8]; a_body: detachable READABLE_STRING_8;
			a_timeout_seconds: INTEGER)
		do
			method := a_method.to_string_8
			url := a_url.to_string_8
			headers := a_headers.twin
			if attached a_body as b then
				body := b.to_string_8
			else
				create body.make_empty
			end
			timeout_seconds := a_timeout_seconds
		ensure
			set: method.same_string (a_method) and url.same_string (a_url) and timeout_seconds = a_timeout_seconds
			headers_copied: headers.count = a_headers.count
		end

feature -- Access

	method: STRING_8
	url: STRING_8
	headers: HASH_TABLE [STRING_8, STRING_8]
	body: STRING_8
	timeout_seconds: INTEGER

feature -- Status report

	has_header (a_name: READABLE_STRING_8): BOOLEAN
		do
			Result := headers.has (a_name.to_string_8)
		end

	header (a_name: READABLE_STRING_8): STRING_8
		require
			present: has_header (a_name)
		do
			check attached headers [a_name.to_string_8] as v then
				Result := v
			end
		end

	mentions (a_text: READABLE_STRING_8): BOOLEAN
			-- Does `a_text' appear anywhere in the URL, a header value, or the body?
		require
			given: not a_text.is_empty
		do
			Result := url.has_substring (a_text) or body.has_substring (a_text)
				or across headers as ic some ic.has_substring (a_text) end
		end

end
