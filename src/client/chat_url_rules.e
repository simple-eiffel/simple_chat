note
	description: "[
		The one rule for where a client may send its token: https to a
		valid authority - a host name (labels of letters, digits and
		hyphens joined by dots, any case) or a bracketed IPv6 literal,
		with an optional port 1..65535 and nothing else - or plain http
		to this machine's loopback; and nothing that merely starts like
		either. The authority is parsed, not prefix-matched, so
		`http://localhost@evil.example', `http://127.0.0.1.evil.example',
		`http://localhost.evil.example' and `https://user:pw@host' all
		fail, `https://:443', `https://host:0' and `https://host:' are
		refused as URLs that could never work, and a base URL carrying a
		query or fragment (which `url_for' would append a path to) is
		refused outright. CHAT_ENDPOINT and CLIENT_CONFIG inherit it; the
		assault fires the hostile forms at it directly.
	]"
	author: "Larry Rix"

class
	CHAT_URL_RULES

feature -- Validation (contract support)

	is_acceptable_url (a_url: READABLE_STRING_8): BOOLEAN
			-- https to a valid authority, or loopback http; clean throughout; no trailing slash.
		do
			Result := is_clean_url (a_url) and then not a_url.ends_with ("/")
				and then ((a_url.starts_with (Https_scheme) and then is_valid_authority (authority_of (a_url))) or is_loopback_url (a_url))
		ensure
			clean: Result implies is_clean_url (a_url)
			no_trailing_slash: Result implies not a_url.ends_with ("/")
			https_or_loopback: Result implies (a_url.starts_with (Https_scheme) or is_loopback_url (a_url))
			has_authority: Result implies not authority_of (a_url).is_empty
			authority_valid: Result implies is_valid_authority (authority_of (a_url))
		end

	is_loopback_url (a_url: READABLE_STRING_8): BOOLEAN
			-- A web URL whose authority is exactly a loopback host (127.0.0.1, localhost, [::1])
			-- with an optional digits-only port 1..65535 - nothing else before the first "/" or the end.
		local
			l_authority: STRING_8
		do
			if is_clean_url (a_url) and then is_web_url (a_url) then
				l_authority := authority_of (a_url)
				Result := is_loopback_host (host_of (l_authority)) and then is_valid_port_suffix (port_suffix_of (l_authority))
			end
		ensure
			web: Result implies is_web_url (a_url)
			clean: Result implies is_clean_url (a_url)
			valid_authority: Result implies is_valid_authority (authority_of (a_url))
		end

	is_loopback_host (a_host: READABLE_STRING_8): BOOLEAN
			-- Exactly 127.0.0.1, [::1], or localhost (any case)?
		do
			Result := a_host.same_string ("127.0.0.1") or a_host.same_string ("[::1]") or a_host.as_lower.same_string ("localhost")
		ensure
			valid_host: Result implies (is_valid_host_name (a_host) or is_ipv6_literal (a_host))
		end

	is_valid_authority (a_authority: READABLE_STRING_8): BOOLEAN
			-- A host name or a bracketed IPv6 literal, then nothing or ":" + a port 1..65535 - and nothing else?
		do
			Result := (is_valid_host_name (host_of (a_authority)) or is_ipv6_literal (host_of (a_authority)))
				and then is_valid_port_suffix (port_suffix_of (a_authority))
		ensure
			given: Result implies not a_authority.is_empty
			host_named: Result implies (is_valid_host_name (host_of (a_authority)) or is_ipv6_literal (host_of (a_authority)))
			port_checked: Result implies is_valid_port_suffix (port_suffix_of (a_authority))
			no_userinfo: Result implies not a_authority.has ('@')
			no_path: Result implies not a_authority.has ('/')
		end

	is_valid_host_name (a_host: READABLE_STRING_8): BOOLEAN
			-- Non-empty labels of letters, digits and hyphens (any case), joined by single dots?
		do
			Result := not a_host.is_empty and then a_host [1] /= '.' and then a_host [a_host.count] /= '.'
				and then not a_host.has_substring ("..")
				and then across a_host as c all is_host_character (c) end
		ensure
			given: Result implies not a_host.is_empty
			no_empty_label: Result implies (a_host [1] /= '.' and a_host [a_host.count] /= '.' and not a_host.has_substring (".."))
			characters: Result implies across a_host as c all is_host_character (c) end
		end

	is_host_character (a_character: CHARACTER_8): BOOLEAN
			-- A letter (either case), a digit, a hyphen or a dot?
		do
			Result := (a_character >= 'a' and a_character <= 'z') or (a_character >= 'A' and a_character <= 'Z')
				or (a_character >= '0' and a_character <= '9') or a_character = '-' or a_character = '.'
		ensure
			ascii: Result implies a_character.code < 128
		end

	is_ipv6_literal (a_host: READABLE_STRING_8): BOOLEAN
			-- "[" + hexadecimal digits, colons and dots, at least one colon + "]"? The shape only;
			-- the address is the resolver's to judge.
		do
			Result := a_host.count >= 3 and then a_host [1] = '[' and then a_host [a_host.count] = ']'
				and then a_host.has (':')
				and then across a_host.substring (2, a_host.count - 1) as c all is_ipv6_character (c) end
		ensure
			bracketed: Result implies (a_host.starts_with ("[") and a_host.ends_with ("]"))
			has_colon: Result implies a_host.has (':')
		end

	is_ipv6_character (a_character: CHARACTER_8): BOOLEAN
			-- A hexadecimal digit (either case), a colon or a dot?
		do
			Result := (a_character >= '0' and a_character <= '9') or (a_character >= 'a' and a_character <= 'f')
				or (a_character >= 'A' and a_character <= 'F') or a_character = ':' or a_character = '.'
		ensure
			ascii: Result implies a_character.code < 128
		end

	host_of (a_authority: READABLE_STRING_8): STRING_8
			-- The host part of an authority: a bracketed literal up to its "]", else everything
			-- before the first ":" (the whole authority when there is neither).
		do
			if a_authority.starts_with ("[") and then a_authority.has (']') then
				Result := a_authority.substring (1, a_authority.index_of (']', 1)).to_string_8
			elseif not a_authority.starts_with ("[") and then a_authority.has (':') then
				Result := a_authority.substring (1, a_authority.index_of (':', 1) - 1).to_string_8
			else
				Result := a_authority.to_string_8
			end
		ensure
			prefix: a_authority.starts_with (Result)
		end

	port_suffix_of (a_authority: READABLE_STRING_8): STRING_8
			-- What follows the host in an authority: empty, or ":" and whatever came after it.
		do
			Result := a_authority.substring (host_of (a_authority).count + 1, a_authority.count).to_string_8
		ensure
			partition: (host_of (a_authority) + Result).same_string (a_authority)
		end

	is_valid_port_suffix (a_suffix: READABLE_STRING_8): BOOLEAN
			-- Empty, or ":" + `is_valid_port'?
		do
			Result := a_suffix.is_empty
				or else (a_suffix.count >= 2 and then a_suffix [1] = ':' and then is_valid_port (a_suffix.substring (2, a_suffix.count)))
		ensure
			empty_or_port: Result implies (a_suffix.is_empty or a_suffix.starts_with (":"))
		end

	is_valid_port (a_text: READABLE_STRING_8): BOOLEAN
			-- One to five digits, 1..65535?
		do
			Result := a_text.count >= 1 and then a_text.count <= 5
				and then (across a_text as c all c.is_digit end)
				and then (a_text.to_integer >= 1 and a_text.to_integer <= 65535)
		ensure
			digits_only: Result implies across a_text as c all c.is_digit end
		end

	is_clean_url (a_url: READABLE_STRING_8): BOOLEAN
			-- Non-empty, printable ASCII only, and nowhere an "@", "?" or "#".
		do
			Result := not a_url.is_empty
				and then across a_url as c all (c.code >= 33 and c.code <= 126 and c /= '@' and c /= '?' and c /= '#') end
		end

	is_web_url (a_url: READABLE_STRING_8): BOOLEAN
		do
			Result := a_url.starts_with (Http_scheme) or a_url.starts_with (Https_scheme)
		end

	authority_of (a_url: READABLE_STRING_8): STRING_8
			-- What follows the scheme up to the first "/" or the end; empty when `a_url' is not a web URL.
		local
			l_start, l_slash: INTEGER
		do
			l_start := scheme_of (a_url).count + 1
			if l_start > 1 then
				l_slash := a_url.index_of ('/', l_start)
				if l_slash = 0 then
					Result := a_url.substring (l_start, a_url.count).to_string_8
				else
					Result := a_url.substring (l_start, l_slash - 1).to_string_8
				end
			else
				create Result.make_empty
			end
		ensure
			no_slash: not Result.has ('/')
			empty_unless_web: not is_web_url (a_url) implies Result.is_empty
		end

	scheme_of (a_url: READABLE_STRING_8): STRING_8
			-- "https://", "http://", or empty.
		do
			if a_url.starts_with (Https_scheme) then
				Result := Https_scheme
			elseif a_url.starts_with (Http_scheme) then
				Result := Http_scheme
			else
				create Result.make_empty
			end
		ensure
			prefix: a_url.starts_with (Result)
		end

	same_url (a_first, a_second: READABLE_STRING_8): BOOLEAN
			-- Equal once scheme and authority are compared without regard to case; the path compares as is.
		do
			Result := normalized_url (a_first).same_string (normalized_url (a_second))
		ensure
			same_length: Result implies a_first.count = a_second.count
		end

	normalized_url (a_url: READABLE_STRING_8): STRING_8
			-- `a_url' with its scheme and authority lowered (whatever case they came in) and the rest untouched.
		local
			l_lower: STRING_8
			l_end: INTEGER
		do
			create l_lower.make_from_string (a_url)
			l_lower.to_lower
			l_end := scheme_of (l_lower).count + authority_of (l_lower).count
			create Result.make (a_url.count)
			Result.append (l_lower.substring (1, l_end))
			Result.append (a_url.substring (l_end + 1, a_url.count))
		ensure
			same_length: Result.count = a_url.count
		end

feature -- Constants

	Http_scheme: STRING_8 = "http://"
	Https_scheme: STRING_8 = "https://"

end
