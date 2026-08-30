note
	description: "[
		A participant's reply: text and optionally an image the dispatcher
		should post; or the reason there is none. An image is named by a
		path the dispatcher resolves only under the participant's own
		output directory, so the path itself must be relative, inside one
		tree and an image by extension (`is_safe_image_path', decision D3):
		a model that names "C:\Users\...\x.png" gets no picture posted.
	]"
	author: "Larry Rix"

class
	PARTICIPANT_ANSWER

create
	make_success,
	make_error

feature {NONE} -- Initialization

	make_success (a_text: READABLE_STRING_GENERAL; a_image_path: detachable READABLE_STRING_GENERAL)
		require
			text_given: not a_text.is_empty
			image_safe: attached a_image_path as p implies is_safe_image_path (p)
		do
			text := a_text.to_string_32
			if attached a_image_path as p then
				image_path := p.to_string_32
			end
			is_success := True
		ensure
			success: is_success
			text_set: text.same_string_general (a_text)
			image_set: (image_path = Void) = (a_image_path = Void)
		end

	make_error (a_error: CHAT_ERROR)
		do
			error := a_error
			create text.make_empty
		ensure
			failure: not is_success
			error_set: error = a_error
		end

feature -- Access

	is_success: BOOLEAN
	text: STRING_32
	image_path: detachable STRING_32
	error: detachable CHAT_ERROR

feature -- Validation (contract support)

	is_safe_image_path (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Relative, inside one directory tree, an image by extension, short:
			-- no "..", no ":" (drive or stream), no leading "\" or "/" (root or UNC),
			-- ".png" or ".jpg" in any case, 5..`Image_path_maximum' characters.
		local
			l_lower: STRING_32
		do
			if a_path.count >= 5 and a_path.count <= Image_path_maximum then
				l_lower := a_path.to_string_32.as_lower
				Result := not l_lower.has_substring ("..") and not l_lower.has_substring (":")
					and l_lower.code (1) /= 92 and l_lower.code (1) /= 47
					and (l_lower.ends_with (".png") or l_lower.ends_with (".jpg"))
			end
		ensure
			bounded: Result implies (a_path.count >= 5 and a_path.count <= Image_path_maximum)
			relative: Result implies (a_path.code (1) /= 92 and a_path.code (1) /= 47 and not a_path.has_substring (":"))
			no_parent: Result implies not a_path.has_substring ("..")
			an_image: Result implies (a_path.as_lower.ends_with (".png") or a_path.as_lower.ends_with (".jpg"))
		end

feature -- Constants

	Image_path_maximum: INTEGER = 200

invariant
	success_xor_error: is_success xor (error /= Void)
	success_has_text: is_success implies not text.is_empty
	image_safe: attached image_path as p implies is_safe_image_path (p)

end
