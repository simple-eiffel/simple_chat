note
	description: "[
		The room's composer: SW_TEXT_BOX, wrapping, that SENDS on Return.

		SW_TEXT_BOX wraps and grows only in multi-line mode, and in that
		mode its own Return inserts a newline - there is nowhere else for
		Return to go, since a text box does not know what "done" means.
		This descendant knows: plain Return fires `on_submit' and inserts
		nothing; Shift+Return inserts the newline the parent always would
		have. Every other key, the whole selection model, the undo stack
		and the clipboard rules are still the parent's, untouched.

		SEEING SHIFT. `handle_char' gets a bare character code - WM_CHAR
		carries no modifier state at all - so it cannot tell a plain
		Return from a shifted one by itself. `handle_key' can: SW_WINDOW
		dispatches WM_KEYDOWN to it with the live Shift flag BEFORE the
		paired WM_CHAR ever reaches `handle_char' (the two always arrive
		as a pair, keydown first, for one physical press). So `handle_key'
		remembers what Shift said the instant Return went down, and
		`handle_char' reads that a moment later - no external state, no
		SW_KEYS query, nothing a headless test cannot drive by calling
		both features directly in order, exactly as a real press would.

		GROWTH, THEN SCROLL. `preferred_height' grows with the wrapped
		line count exactly as the parent's does, up to `Line_cap' lines at
		the theme's own scaled line height; past that it holds, and
		`draw' clips to the held rectangle and shifts the parent's
		painting up so the tail - where typing happens - stays the part
		in view. Both read `row_height', the parent's own public measure,
		so the cap tracks the theme's text scale automatically.
	]"
	author: "Larry Rix"

class
	CHAT_INPUT_BOX

inherit
	SW_TEXT_BOX
		redefine
			handle_char, handle_key, preferred_height, draw
		end

create
	make_single_line, make_wrapping

feature {NONE} -- Initialization

	make_wrapping (a_text: READABLE_STRING_GENERAL)
			-- A multi-line composer that wraps, grows to `Line_cap' lines, then
			-- scrolls; plain Return sends, Shift+Return inserts a newline.
		do
			make (a_text)
		ensure
			wraps: not is_single_line
			text_kept: text.same_string_general (a_text)
		end

feature -- Access

	on_submit: detachable PROCEDURE
			-- Fired when a plain Return is pressed - Shift+Return never fires it.

feature -- Element change

	set_on_submit (a_action: PROCEDURE)
		do
			on_submit := a_action
		ensure
			set: on_submit = a_action
		end

feature -- Input

	handle_key (a_vk: INTEGER; a_shift: BOOLEAN)
			-- Remember Shift's state for a Return keydown - see the class note on
			-- why `handle_char' cannot see it directly - then defer to the parent.
		do
			if a_vk = Return_code then
				return_shift_down := a_shift
			end
			Precursor (a_vk, a_shift)
		end

	handle_char (a_code: INTEGER)
			-- Plain Return submits and inserts nothing; Shift+Return, and a
			-- single-line box's Return regardless of Shift, are the parent's.
		do
			if is_sending_return (a_code) then
				strip_trailing_newline
				if attached on_submit as a then
					a.call
				end
			else
				Precursor (a_code)
			end
		ensure then
			sent_leaves_no_trailing_newline: is_sending_return (a_code) implies
				(text.is_empty or else text.item (text.count) /= '%N')
		end

feature -- Layout

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- The parent's own measure, capped at `Line_cap' lines of the theme's
			-- scaled line height; `draw' scrolls instead of growing further.
		do
			natural_height := Precursor (a_p, a_width)
			capped_height := (Line_cap * row_height (a_p) + 2.0 * Composer_pad_y).max (a_p.min_control_height)
			Result := natural_height.min (capped_height)
		ensure then
			within_the_cap: Result <= (Line_cap * row_height (a_p) + 2.0 * Composer_pad_y).max (a_p.min_control_height)
			never_shrinks_the_cache: natural_height >= Result
		end

feature -- Drawing

	draw (a_p: SW_PAINTER)
			-- Past the cap, clip to the box and shift the parent's own painting up
			-- by the overflow, so the caret - typing always moves it forward - stays
			-- inside the visible rectangle instead of drawing below it unseen.
		local
			l_shift, l_saved_y: REAL_64
		do
			if natural_height > capped_height + Half_pixel then
				l_shift := natural_height - capped_height
				l_saved_y := y
				a_p.push_clip (x, y, width, height)
				y := y - l_shift
				Precursor (a_p)
				y := l_saved_y
				a_p.pop_clip
			else
				Precursor (a_p)
			end
		end

feature {NONE} -- Return and Shift

	return_shift_down: BOOLEAN
			-- What the last Return keydown said about Shift; False until one, which
			-- is exactly right for a test that calls `handle_char' on its own.

	is_sending_return (a_code: INTEGER): BOOLEAN
			-- Would `a_code', handled now, submit rather than insert? A single-line
			-- box (the legacy one-line composer) sends on any Return, Shift or not -
			-- it never wraps, so Shift+Return has nowhere to put a newline either.
		do
			Result := a_code = Return_code and then (is_single_line or else not return_shift_down)
		end

	strip_trailing_newline
			-- A Shift+Return typed as the very last character, followed by a plain
			-- Return with nothing after it, must not hand the host a blank tail line.
		do
			if not text.is_empty and then text.item (text.count) = '%N' then
				set_text (text.substring (1, text.count - 1))
			end
		ensure
			no_trailing_newline: text.is_empty or else text.item (text.count) /= '%N'
		end

feature {NONE} -- Growth and scroll

	natural_height: REAL_64
			-- What the last `preferred_height' call found the wrapped text needs,
			-- uncapped; `draw' reads it to decide how far to scroll.

	capped_height: REAL_64
			-- What the last `preferred_height' call actually returned.

feature -- Constants

	Return_code: INTEGER = 13
			-- VK_RETURN and the WM_CHAR code for Return are the same value on
			-- Windows, so one constant serves both `handle_key' and `handle_char'.

	Line_cap: INTEGER = 5
			-- Lines visible before the box scrolls instead of growing further.

	Composer_pad_y: REAL_64 = 6.0
			-- Mirrors SW_TEXT_BOX's own private inside inset (its `Pad_y', feature
			-- {NONE} so a same-named constant here would clash under VMFN); needed
			-- to compute the cap in the same units `preferred_height' uses, since
			-- the parent keeps that constant to itself.

	Half_pixel: REAL_64 = 0.5
			-- Rounding slack for "has the content actually grown past the cap".

end
