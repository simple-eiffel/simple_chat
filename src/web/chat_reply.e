note
	description: "[
		What CHAT_API answers: an HTTP status, a content type and a body
		that is already bytes. It is built on the service's processor and
		copied to the request's processor field by field (`make_from_separate'),
		so no domain object ever crosses processors - only JSON.
	]"
	author: "Larry Rix"

class
	CHAT_REPLY

create
	make,
	make_json,
	make_error,
	make_from_separate

feature {NONE} -- Initialization

	make (a_status: INTEGER; a_content_type: READABLE_STRING_8; a_body: READABLE_STRING_8)
		require
			http_status: a_status >= 200 and a_status <= 599
			typed: not a_content_type.is_empty
		do
			status := a_status
			content_type := a_content_type.to_string_8
			body := a_body.to_string_8
			item_count := 0
		ensure
			set: status = a_status and content_type.same_string (a_content_type) and body.same_string (a_body)
		end

	make_json (a_status: INTEGER; a_object: SIMPLE_JSON_OBJECT; a_item_count: INTEGER)
			-- A JSON reply; `a_item_count' says how many items a page carries (0 otherwise).
		require
			http_status: a_status >= 200 and a_status <= 599
			non_negative: a_item_count >= 0
		do
			status := a_status
			content_type := Json_content_type
			body := (create {CHAT_JSON}.make).bytes_of (a_object)
			item_count := a_item_count
		ensure
			set: status = a_status and item_count = a_item_count
			json: is_json
		end

	make_error (a_error: CHAT_ERROR)
			-- The error's status and its JSON form.
		do
			status := a_error.http_status
			content_type := Json_content_type
			body := (create {CHAT_JSON}.make).bytes_of ((create {CHAT_JSON}.make).error_to_json (a_error))
			item_count := 0
		ensure
			status_kept: status = a_error.http_status
			json: is_json
			failed: not is_success
		end

	make_from_separate (a_other: separate CHAT_REPLY)
			-- A copy on this processor.
		do
			status := a_other.status
			create content_type.make_from_separate (a_other.content_type)
			create body.make_from_separate (a_other.body)
			item_count := a_other.item_count
		ensure
			same_status: status = a_other.status
			same_count: item_count = a_other.item_count
			same_size: body.count = a_other.body.count
		end

feature -- Access

	status: INTEGER

	content_type: STRING_8

	body: STRING_8
			-- The bytes to send.

	item_count: INTEGER
			-- Items in a page reply (events); 0 for anything else.

feature -- Status report

	is_success: BOOLEAN
		do
			Result := status >= 200 and status <= 299
		end

	is_json: BOOLEAN
		do
			Result := content_type.same_string (Json_content_type)
		end

	is_empty_page: BOOLEAN
			-- A successful page with nothing in it - what a long-poll waits on.
		do
			Result := is_success and item_count = 0
		end

feature -- Constants

	Json_content_type: STRING_8 = "application/json; charset=utf-8"

invariant
	http_status: status >= 200 and status <= 599
	typed: not content_type.is_empty
	count_non_negative: item_count >= 0

end
