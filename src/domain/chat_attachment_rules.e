note
	description: "The attachment rules the codec and the store share: which mime types are allowed and which extension each gets on disk."
	author: "Larry Rix"

class
	CHAT_ATTACHMENT_RULES

feature -- Validation

	is_allowed_mime (a_mime: READABLE_STRING_8): BOOLEAN
		do
			Result := a_mime.same_string ({CHAT_ATTACHMENT}.Mime_png) or a_mime.same_string ({CHAT_ATTACHMENT}.Mime_jpeg)
		end

	extension_of (a_mime: READABLE_STRING_8): STRING_8
			-- ".png" or ".jpg".
		require
			allowed: is_allowed_mime (a_mime)
		do
			if a_mime.same_string ({CHAT_ATTACHMENT}.Mime_png) then
				Result := ".png"
			else
				Result := ".jpg"
			end
		ensure
			dotted: Result.starts_with (".")
		end

end
