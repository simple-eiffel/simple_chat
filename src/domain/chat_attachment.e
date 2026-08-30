note
	description: "[
		An uploaded image, stored on disk under its content hash - never
		under a name the uploader chose. `stored_relpath' is computed, not
		given: uploads/<sha256>.<png|jpg>, so no caller and no wire form
		can name a path. `original_name' is metadata for display only.
		`id' is 0 until the store has assigned one.
	]"
	author: "Larry Rix"

class
	CHAT_ATTACHMENT

create
	make

feature {NONE} -- Initialization

	make (a_id, a_uploader_id: INTEGER_64; a_original_name: READABLE_STRING_GENERAL; a_mime: READABLE_STRING_8;
			a_size: INTEGER_64; a_sha256: READABLE_STRING_8; a_created_at: SIMPLE_DATE_TIME)
		require
			id_non_negative: a_id >= 0
			uploader_stored: a_uploader_id > 0
			valid_name: rules.is_valid_name (a_original_name)
			has_bytes: a_size > 0
			allowed_type: rules.is_allowed_mime (a_mime)
			hash_shape: rules.is_sha256_hex (a_sha256)
		do
			id := a_id
			uploader_id := a_uploader_id
			original_name := a_original_name.to_string_32
			mime := a_mime.to_string_8
			size := a_size
			sha256 := a_sha256.to_string_8
			stored_relpath := rules.stored_path_for (sha256, mime)
			created_at := a_created_at
		ensure
			set: id = a_id and uploader_id = a_uploader_id and size = a_size
			name_set: original_name.same_string_general (a_original_name)
			mime_set: mime.same_string (a_mime)
			hash_set: sha256.same_string (a_sha256)
			created_set: created_at = a_created_at
			path_computed: stored_relpath.same_string (rules.stored_path_for (a_sha256, a_mime))
		end

feature -- Access

	id, uploader_id: INTEGER_64
	original_name: STRING_32
	mime: STRING_8
	size: INTEGER_64
	sha256: STRING_8
	stored_relpath: STRING_8
	created_at: SIMPLE_DATE_TIME

feature -- Status report

	is_stored: BOOLEAN
		do
			Result := id > 0
		ensure
			definition: Result = (id > 0)
		end

feature -- Element change

	set_id (a_id: INTEGER_64)
		require
			not_yet_stored: id = 0
			positive: a_id > 0
		do
			id := a_id
		ensure
			set: id = a_id
			rest_unchanged: uploader_id = old uploader_id and sha256 = old sha256 and stored_relpath = old stored_relpath
		end

feature -- Validation (contract support)

	is_allowed_mime (a_mime: READABLE_STRING_8): BOOLEAN
		do
			Result := rules.is_allowed_mime (a_mime)
		end

	rules: CHAT_ATTACHMENT_RULES
		once
			create Result
		end

feature -- Constants

	Mime_png: STRING_8 = "image/png"
	Mime_jpeg: STRING_8 = "image/jpeg"
	Uploads_prefix: STRING_8 = "uploads/"

invariant
	id_non_negative: id >= 0
	uploader_stored: uploader_id > 0
	name_shape: rules.is_valid_name (original_name)
	has_bytes: size > 0
	allowed_type: rules.is_allowed_mime (mime)
	hash_shape: rules.is_sha256_hex (sha256)
	path_pinned: stored_relpath.same_string (rules.stored_path_for (sha256, mime))

end
