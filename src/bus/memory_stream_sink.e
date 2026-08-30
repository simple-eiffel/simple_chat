note
	description: "A STREAM_SINK that keeps what was written: the test double for SSE_STREAM."
	author: "Larry Rix"

class
	MEMORY_STREAM_SINK

inherit
	STREAM_SINK

create
	make

feature {NONE} -- Initialization

	make
		do
			create buffer.make (256)
			is_open := True
		ensure
			open: is_open
			empty: bytes_written = 0
		end

feature -- Status report

	is_open: BOOLEAN

feature -- Access

	bytes_written: INTEGER_64
		do
			Result := buffer.count
		end

	content: STRING_8
			-- Everything written so far.
		do
			Result := buffer.twin
		ensure
			same_size: Result.count = bytes_written
		end

feature -- Basic operations

	write (a_text: READABLE_STRING_8)
		do
			buffer.append (a_text)
		end

	flush
		do
		end

	close
		do
			is_open := False
		end

feature {NONE} -- Implementation

	buffer: STRING_8

end
