note
	description: "[
		The real clipboard, as a picture. simple_shell reads the DIB into a
		cairo ARGB32 surface - SHELL_CLIPBOARD.image_into is the mirror of
		its own set_image, so the two layouts agree by construction - cairo
		writes the PNG, and the bytes come back through a file with an ASCII
		name in the WORKING DIRECTORY, which CLIENT_APP has already moved to
		%APPDATA%\simple_chat, the one folder a member can always write. The
		relative name is deliberate: cairo's PNG writer takes a path of one
		byte per character, and a member's profile folder need not be
		spellable that way. The scratch file is deleted before the bytes are
		handed on, success or not; a failure anywhere answers empty bytes.
	]"
	author: "Larry Rix"

class
	SHELL_CLIPBOARD_IMAGE

inherit
	CLIPBOARD_IMAGE_SOURCE

create
	make

feature {NONE} -- Initialization

	make
			-- Over the system clipboard.
		do
			create clipboard
		end

feature -- Status report

	has_image: BOOLEAN
			-- <Precursor>
		do
			Result := clipboard.has_image
		end

	has_text: BOOLEAN
			-- <Precursor>
		do
			Result := clipboard.has_text
		end

feature -- Access

	width: INTEGER
			-- <Precursor>
		do
			Result := clipboard.image_width
		end

	height: INTEGER
			-- <Precursor>
		do
			Result := clipboard.image_height
		end

	png_bytes: SPECIAL [NATURAL_8]
			-- <Precursor>
		local
			l_w, l_h: INTEGER
			l_surface: CAIRO_SURFACE
		do
			create Result.make_empty (0)
			l_w := width
			l_h := height
			if l_w > 0 and l_h > 0 then
				create l_surface.make_with_format ({SIMPLE_CAIRO}.Format_argb32, l_w, l_h)
				if l_surface.is_valid and then clipboard.image_into (l_surface.data, l_w, l_h, l_surface.stride) then
					l_surface.mark_dirty.do_nothing
					if l_surface.write_png (Scratch_name) then
						Result := bytes_of (Scratch_name)
					end
					delete_scratch
				end
				l_surface.destroy
			end
			if not is_png (Result) then
				create Result.make_empty (0)
			end
		end

feature {NONE} -- Implementation

	clipboard: SHELL_CLIPBOARD
			-- The system clipboard, through simple_shell.

	Scratch_name: STRING_8 = "pasted-image.tmp.png"
			-- Relative, ASCII: see the class note.

	bytes_of (a_name: READABLE_STRING_GENERAL): SPECIAL [NATURAL_8]
			-- The whole of the file at `a_name'; empty when it is not there.
		local
			l_file: RAW_FILE
			l_read: STRING_8
			i: INTEGER
		do
			create l_file.make_with_name (a_name)
			if l_file.exists and then l_file.is_readable and then l_file.count > 0 then
				l_file.open_read
				l_file.read_stream (l_file.count)
				l_read := l_file.last_string
				l_file.close
				create Result.make_filled (0, l_read.count)
				from
					i := 1
				until
					i > l_read.count
				loop
					Result.put (l_read.code (i).to_natural_8, i - 1)
					i := i + 1
				end
			else
				create Result.make_empty (0)
			end
		end

	delete_scratch
			-- Remove the scratch file if it is there.
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (Scratch_name)
			if l_file.exists then
				l_file.delete
			end
		end

end
