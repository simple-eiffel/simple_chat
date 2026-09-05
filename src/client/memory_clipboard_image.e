note
	description: "[
		A clipboard nobody else can see: the assault puts a bitmap here and
		says whether text stands beside it, and the window pastes from it
		exactly as it would from the real one - without a test ever writing
		to the clipboard Larry is using while the suite runs. `png_bytes'
		hands back what was given, empty meaning "unreadable", which is how
		the failure path is driven.
	]"
	author: "Larry Rix"

class
	MEMORY_CLIPBOARD_IMAGE

inherit
	CLIPBOARD_IMAGE_SOURCE

create
	make

feature {NONE} -- Initialization

	make
			-- An empty clipboard.
		do
			create bytes.make_empty (0)
		ensure
			nothing: not has_image and not has_text
		end

feature -- Status report

	has_image: BOOLEAN
			-- <Precursor>

	has_text: BOOLEAN
			-- <Precursor>

feature -- Access

	width: INTEGER
			-- <Precursor>

	height: INTEGER
			-- <Precursor>

	png_bytes: SPECIAL [NATURAL_8]
			-- What `set_image' gave; every ask is counted in `reads'.
		do
			reads := reads + 1
			Result := bytes
		ensure then
			counted: reads = old reads + 1
		end

	reads: INTEGER
			-- How many times the picture was asked for.

feature -- Element change

	set_image (a_bytes: SPECIAL [NATURAL_8]; a_width, a_height: INTEGER)
			-- A bitmap of `a_width' x `a_height' that reads as `a_bytes' -
			-- or, with `a_bytes' empty, one that cannot be read at all.
		require
			positive: a_width > 0 and a_height > 0
			png_or_nothing: a_bytes.count > 0 implies is_png (a_bytes)
		do
			has_image := True
			bytes := a_bytes
			width := a_width
			height := a_height
		ensure
			image: has_image
			sized: width = a_width and height = a_height
		end

	set_text (a_on: BOOLEAN)
			-- Whether text stands beside the picture.
		do
			has_text := a_on
		ensure
			set: has_text = a_on
		end

	clear
			-- Nothing on the clipboard.
		do
			has_image := False
			has_text := False
			width := 0
			height := 0
			create bytes.make_empty (0)
		ensure
			nothing: not has_image and not has_text
		end

feature {NONE} -- Implementation

	bytes: SPECIAL [NATURAL_8]
			-- What `png_bytes' answers.

invariant
	none_means_zero: not has_image implies (width = 0 and height = 0)

end
