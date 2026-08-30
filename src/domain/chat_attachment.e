note
	description: "[
		One uploaded file, kept on disk under the data folder as
		uploads/<sha256>.<ext> - never under a name the uploader chose -
		and referenced by an image event. The original name is metadata.
	]"
	author: "Larry Rix"

class
	CHAT_ATTACHMENT

create
	make

feature {NONE} -- Initialization

	make (a_id, a_uploader_id: INTEGER_64; a_original_name: READABLE_STRING_GENERAL; a_mime: READABLE_STRING_8;
			a_size: INTEGER_64; a_sha256: READABLE_STRING_8; a_stored_relpath: READABLE_STRING_8; a_created_at: SIMPLE_DATE_TIME)
		require
			id_non_negative: a_id >= 0
			uploader_stored: a_uploader_id > 0
			has_bytes: a_size > 0
			allowed_type: is_allowed_mime (a_mime)
			hash_shape: a_sha256.count = 64
			under_uploads: a_stored_relpath.starts_with (Uploads_prefix)
		do
			id := a_id
			uploader_id := a_uploader_id
			original_name := a_original_name.to_string_32
			mime := a_mime.to_string_8
			size := a_size
			sha256 := a_sha256.to_string_8
			stored_relpath := a_stored_relpath.to_string_8
			created_at := a_created_at
		ensure
			set: id = a_id and uploader_id = a_uploader_id and size = a_size
			hash_set: sha256.same_string (a_sha256)
		end

feature -- Access

	id, uploader_id: INTEGER_64
	original_name: STRING_32
	mime: STRING_8
	size: INTEGER_64
	sha256: STRING_8
	stored_relpath: STRING_8
	created_at: SIMPLE_DATE_TIME

feature -- Element change

	set_id (a_id: INTEGER_64)
		require
			not_yet_stored: id = 0
			positive: a_id > 0
		do
			id := a_id
		ensure
			set: id = a_id
		end

feature -- Validation (contract support)

	is_allowed_mime (a_mime: READABLE_STRING_8): BOOLEAN
		do
			Result := a_mime.same_string (Mime_png) or a_mime.same_string (Mime_jpeg)
		end

feature -- Constants

	Mime_png: STRING_8 = "image/png"
	Mime_jpeg: STRING_8 = "image/jpeg"
	Uploads_prefix: STRING_8 = "uploads/"

invariant
	id_non_negative: id >= 0
	uploader_stored: uploader_id > 0
	has_bytes: size > 0
	allowed_type: is_allowed_mime (mime)
	hash_shape: sha256.count = 64
	under_uploads: stored_relpath.starts_with (Uploads_prefix)

end
