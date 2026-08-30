note
	description: "[
		The attachment rules the codec and the store share: which mime
		types are allowed, which extension each gets on disk, what a
		content hash looks like, and what an original file name may be.
	]"
	author: "Larry Rix"

class
	CHAT_ATTACHMENT_RULES

feature -- Validation

	is_allowed_mime (a_mime: READABLE_STRING_8): BOOLEAN
		do
			Result := a_mime.same_string ({CHAT_ATTACHMENT}.Mime_png) or a_mime.same_string ({CHAT_ATTACHMENT}.Mime_jpeg)
		end

	is_sha256_hex (a_text: READABLE_STRING_8): BOOLEAN
			-- Exactly 64 lowercase hexadecimal characters?
		do
			Result := a_text.count = 64 and then across a_text as ch all (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') end
		ensure
			length: Result implies a_text.count = 64
		end

	is_valid_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- 1..255 code points, no path separators, no controls.
		local
			i: INTEGER
			c: NATURAL_32
		do
			Result := a_name.count >= 1 and a_name.count <= Name_maximum
			from
				i := 1
			until
				i > a_name.count or not Result
			loop
				c := a_name.code (i)
				Result := c >= 32 and c /= 0x7F and c /= 47 and c /= 92
				i := i + 1
			end
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

	stored_path_for (a_sha256, a_mime: READABLE_STRING_8): STRING_8
			-- uploads/<sha256>.<ext> - the only name a stored file ever has.
		require
			hash: is_sha256_hex (a_sha256)
			allowed: is_allowed_mime (a_mime)
		do
			Result := {CHAT_ATTACHMENT}.Uploads_prefix + a_sha256.to_string_8 + extension_of (a_mime)
		ensure
			under_uploads: Result.starts_with ({CHAT_ATTACHMENT}.Uploads_prefix)
			no_traversal: not Result.has_substring ("..")
		end

feature -- Constants

	Name_maximum: INTEGER = 255

end
