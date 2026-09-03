note
	description: "[
		A status or error line that costs NOTHING while it has nothing to say.

		SINCE simple_widgets 0.4.0 an SW_LABEL measures its height from the
		FONT - `line_step' is the measured ascent plus descent plus the
		theme's leading - and it does that whether or not there is any text
		to put in it. That is right for a label with a caption; it is wrong
		for a line that is empty most of the time, because an empty one then
		reserves a full row of blank pixels. At simple_chat's 2x text scale
		that is roughly forty-seven pixels EACH, and the room carries two of
		them - status and error - between the thread and the composer.

		So: no text, no height. `text.is_empty' is the whole test, and it is
		re-asked every frame (SW_WINDOW re-arranges the tree on every render,
		see COMPOSER_ROW), which is why the line does not have to be added or
		removed from anything to appear: `show_status' sets the text and the
		very next frame gives it its natural height back. Nothing is hidden,
		nothing is rebuilt, and there is no flag to get out of step.

		The zero height alone is not enough - a column still charges a GAP
		for a child that is there but flat. COLLAPSING_COLUMN is the other
		half.
	]"
	author: "Larry Rix"

class
	STATUS_LINE

inherit
	SW_LABEL
		redefine
			preferred_height, draw
		end

create
	make, make_ui, make_mono, make_body

feature -- Layout

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- The label's own measured height when there is text; zero when
			-- there is not, so an empty line reserves no row.
		do
			if text.is_empty then
				Result := 0.0
			else
				Result := Precursor (a_p, a_width)
			end
		ensure then
			silence_is_free: text.is_empty implies Result = 0.0
			speech_costs_a_row: not text.is_empty implies Result > 0.0
		end

feature -- Drawing

	draw (a_p: SW_PAINTER)
			-- Paint nothing at all when there is nothing to say. An empty
			-- label already draws no glyphs; saying so here means the font
			-- selection and the color work do not happen either, and a
			-- collapsed line can never leave a mark inside its zero rectangle.
		do
			if not text.is_empty then
				Precursor (a_p)
			end
		end

end
