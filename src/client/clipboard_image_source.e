note
	description: "[
		Where a pasted picture comes from. The composer asks three things
		of it - is there a bitmap, is there text beside it, and the bitmap
		as PNG bytes - and nothing else, so the client stack never names
		the shell. The window hands it a SHELL_CLIPBOARD_IMAGE (simple_shell
		reads the DIB, simple_cairo writes the PNG); the assault hands it a
		MEMORY_CLIPBOARD_IMAGE, a clipboard nobody else can see, scripted
		rather than clobbered.

		TEXT WINS. A word copied out of a document often travels with a
		rendering of itself, and a member who pastes a word means the word;
		a screenshot, a snip or a browser's "Copy image" travels alone. So
		the picture is taken only when nothing else is on offer. The rule is
		the caller's (SW_CHAT_VIEW.route_paste); the two facts are here.
	]"
	author: "Larry Rix"

deferred class
	CLIPBOARD_IMAGE_SOURCE

feature -- Status report

	has_image: BOOLEAN
			-- Is there a bitmap to paste?
		deferred
		end

	has_text: BOOLEAN
			-- Is there text beside it?
		deferred
		end

feature -- Access

	width: INTEGER
			-- The bitmap's width in pixels; 0 when there is none.
		deferred
		ensure
			non_negative: Result >= 0
			none_means_zero: not has_image implies Result = 0
		end

	height: INTEGER
			-- The bitmap's height in pixels; 0 when there is none.
		deferred
		ensure
			non_negative: Result >= 0
			none_means_zero: not has_image implies Result = 0
		end

	png_bytes: SPECIAL [NATURAL_8]
			-- The bitmap encoded as PNG; EMPTY when it could not be read -
			-- gone from the clipboard since `has_image', an unreadable DIB, a
			-- failed encode. Never raises: a paste that fails says so on the
			-- status line, it does not take the window down.
		require
			has_image: has_image
		deferred
		ensure
			png_or_nothing: Result.count > 0 implies is_png (Result)
		end

feature -- Validation (contract support)

	is_png (a_bytes: SPECIAL [NATURAL_8]): BOOLEAN
			-- Does `a_bytes' open with the eight-byte PNG signature?
		do
			Result := a_bytes.count >= 8
				and then a_bytes [0] = {NATURAL_8} 0x89 and then a_bytes [1] = {NATURAL_8} 0x50
				and then a_bytes [2] = {NATURAL_8} 0x4E and then a_bytes [3] = {NATURAL_8} 0x47
				and then a_bytes [4] = {NATURAL_8} 0x0D and then a_bytes [5] = {NATURAL_8} 0x0A
				and then a_bytes [6] = {NATURAL_8} 0x1A and then a_bytes [7] = {NATURAL_8} 0x0A
		ensure
			long_enough: Result implies a_bytes.count >= 8
		end

end
