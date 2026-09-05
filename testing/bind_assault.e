note
	description: "[
		THE LISTENER, not the configuration value. SERVER_CONFIG has always
		pinned `bind_address' to 127.0.0.1, refused the key in server.toml
		("not configurable; the server always binds 127.0.0.1") and asserted
		it in two invariants - and until 2026-09-05 none of that reached a
		socket. CHAT_WEB_APP.start built the simple_web server with `make
		(port)' and nothing else, EWF's standalone launcher was handed no
		address, and HTTPD_SERVER_I took its `make_server_by_port' branch:
		every interface, 0.0.0.0. The live room was observed there, on
		0.0.0.0:8090.

		So this assault refuses to read a value. It boots the REAL finalized
		server executable on a scratch port and asks WINDOWS what the socket
		is bound to:

		  1. `Get-NetTCPConnection -State Listen -LocalPort <port>' must
		     report LocalAddress 127.0.0.1, and must NOT report 0.0.0.0.
		     One is not the negation of the other on a machine that could
		     hold two listeners on one port, so both are asserted.
		  2. A real HTTP request to this machine's own LAN address on the
		     same port must be REFUSED. That is the half a reader believes:
		     the address a friend on the network would type does not answer.

		A machine with no non-loopback IPv4 address FAILS this assault
		rather than quietly proving half of it - a skip that counts as a
		pass is a lie told in green, and this file exists because a contract
		that proved nothing was believed for weeks.

		The scratch server is copied to `sc_bind_server.exe' before it is
		booted. Every target of this system finalizes to simple_chat.exe,
		this test runner included, so a kill by that image name would kill
		the runner; the distinct name is what makes the teardown safe, and it
		is distinct from WIRING_ASSAULT's `sc_wiring_server.exe' too, so
		neither assault's teardown can reach into the other's. Its stdout
		goes to a FILE, never a pipe: a console write into an undrained pipe
		wedges the server mid-request (found the hard way; see
		WIRING_ASSAULT's class note). Teardown runs before the verdict, so no
		failing assert can strand a server.
	]"
	author: "Larry Rix"

class
	BIND_ASSAULT

inherit
	TEST_SET_BASE

feature -- The socket, as Windows sees it

	test_the_server_listens_on_loopback_and_not_on_every_interface
			-- The real server exe, booted on a scratch port, is bound to
			-- 127.0.0.1 and to nothing else; a request to this machine's own
			-- LAN address on that port is refused.
		local
			l_exe: SERVER_EXE
			l_process: SIMPLE_PROCESS
			l_server: SIMPLE_ASYNC_PROCESS
			l_transport: WINHTTP_TRANSPORT
			l_headers: HASH_TABLE [STRING_8, STRING_8]
			l_reply: HTTP_REPLY
			l_environment: EXECUTION_ENVIRONMENT
			l_tries: INTEGER
			l_alive, l_loopback_listening, l_every_interface_listening: BOOLEAN
			l_lan_found, l_lan_refused: BOOLEAN
			l_addresses, l_lan, l_transcript: STRING_8
		do
			create l_exe
			if not l_exe.is_built then
				report_unbuilt_server ("the bind assault")
			else
				create l_transcript.make (512)
				create l_process.make
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				prepare_scratch
				create l_server.make
					-- cmd redirects the server's stdout to a file: piped stdout wedges
					-- the server on its first log line (see the class note).
				l_server.start ("cmd /c " + Scratch_root + "\" + Scratch_server_name + " " + Scratch_root + "\server.toml > " + Scratch_root + "\server_boot.log 2>&1")
				assert ("server process started", l_server.was_started_successfully)
				create l_transport.make
				create l_headers.make (0)
				create l_environment
				from
					l_tries := 0
				until
					l_alive or l_tries >= 40
				loop
					l_reply := l_transport.send ("GET", Loopback_url, l_headers, Void, 2)
					l_alive := l_reply.is_exchanged and then l_reply.is_success
					if not l_alive then
						l_environment.sleep (500_000_000)
					end
					l_tries := l_tries + 1
				variant
					41 - l_tries
				end
				if l_alive then
					l_transcript.append ("    GET  " + Loopback_url + " -> answered, so the server is up%N")
						-- 1. What Windows says the socket is bound to.
					l_addresses := listening_addresses_on (Port)
					l_transcript.append ("    Get-NetTCPConnection -State Listen -LocalPort " + Port.out + " -> LocalAddress "
						+ (if l_addresses.is_empty then "(none reported)" else one_line (l_addresses) end) + "%N")
					l_loopback_listening := has_address (l_addresses, Loopback_address)
					l_every_interface_listening := has_address (l_addresses, Every_interface_address)
						-- 2. The address a friend on the network would type.
					l_lan := first_non_loopback_ipv4
					l_lan_found := not l_lan.is_empty
					if l_lan_found then
						l_reply := l_transport.send ("GET", "http://" + l_lan + ":" + Port.out + "/health", l_headers, Void, 3)
						l_lan_refused := not l_reply.is_exchanged
						l_transcript.append ("    GET  http://" + l_lan + ":" + Port.out + "/health -> "
							+ (if l_lan_refused then "REFUSED: " + utf8_head (l_reply.error, 90) else "ANSWERED " + l_reply.status.out + " - the room is on the network" end) + "%N")
					else
						l_transcript.append ("    this machine reports no non-loopback IPv4 address, so the second half could not be attempted%N")
					end
				else
					l_transcript.append ("    " + Loopback_url + " never answered after " + l_tries.out + " probes%N")
				end
					-- Teardown first: no assert may strand the scratch server.
				l_transcript.append ("    server said: " + head_of_file (Scratch_root + "\server_boot.log", 400) + "%N")
				if l_server.is_running then
					l_server.kill.do_nothing
				end
				l_server.close
				l_process.command_output ("taskkill /F /IM " + Scratch_server_name).do_nothing
				print (l_transcript)
				assert ("the scratch server answered on the loopback address", l_alive)
				assert ("Windows reports the listener at 127.0.0.1", l_loopback_listening)
				assert ("Windows reports NO listener at 0.0.0.0: the server is not on every interface", not l_every_interface_listening)
				assert ("this machine has a non-loopback IPv4 address to test the refusal against", l_lan_found)
				assert ("a request to this machine's own LAN address on that port is refused", l_lan_refused)
			end
		end

feature {NONE} -- What Windows says

	listening_addresses_on (a_port: INTEGER): STRING_8
			-- Every LocalAddress with a LISTEN socket on `a_port', one per line,
			-- as `Get-NetTCPConnection' reports them; empty when there is none.
		require
			positive: a_port > 0
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			Result := ascii_of (l_process.command_output (Powershell
				+ "%"Get-NetTCPConnection -State Listen -LocalPort " + a_port.out
				+ " -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress }%""))
		end

	first_non_loopback_ipv4: STRING_8
			-- This machine's own IPv4 address that is not 127.0.0.1 - the address
			-- a friend on the network would type; empty when there is none.
			--
			-- A DHCP address is preferred, then any address that is not link-local
			-- (169.254.*), then whatever is left. The order is not fussiness: this
			-- machine carries seven non-loopback IPv4 addresses, six of them
			-- link-local ones belonging to Bluetooth, a VPN adapter and three idle
			-- NICs, and the refusal is worth far more when it is measured against
			-- the address the room would really be reached at. Every one of them
			-- is covered by 0.0.0.0 either way, so the proof holds whichever is
			-- picked - it just reads better with the real one.
		local
			l_process: SIMPLE_PROCESS
		do
			create l_process.make
			Result := ascii_of (l_process.command_output (Powershell
				+ "%"$a=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' });"
				+ " $b=@($a | Where-Object { $_.PrefixOrigin -eq 'Dhcp' });"
				+ " if ($b.Count -eq 0) { $b=@($a | Where-Object { $_.IPAddress -notlike '169.254.*' }) };"
				+ " if ($b.Count -eq 0) { $b=$a };"
				+ " if ($b.Count -gt 0) { $b[0].IPAddress }%""))
			Result.adjust
		end

	has_address (a_text: STRING_8; a_address: STRING_8): BOOLEAN
			-- Does `a_text' - one address per line - carry `a_address' as a WHOLE
			-- line? Never a substring test: "10.0.0.1" has "0.0.0.1" inside it,
			-- and 0.0.0.0 is exactly the answer this assault must not get wrong.
		require
			address_given: not a_address.is_empty
		local
			l_line: STRING_8
		do
			across a_text.split ('%N') as ic loop
				l_line := ic.twin
				l_line.adjust
				Result := Result or l_line.same_string (a_address)
			end
		end

	Powershell: STRING_8 = "powershell -NoProfile -NonInteractive -Command "
			-- Every question about the socket goes through PowerShell: nothing in
			-- the fleet can enumerate this machine's listening sockets, and
			-- `netstat' would have to be parsed out of a table. SIMPLE_PROCESS
			-- creates the child with CREATE_NO_WINDOW, so no window appears.

	Loopback_address: STRING_8 = "127.0.0.1"

	Every_interface_address: STRING_8 = "0.0.0.0"

feature {NONE} -- Live-server fixtures

	prepare_scratch
			-- A clean C:\Users\Public\sc_bind_test: the server exe copied to its
			-- distinct name, a minimal server.toml, and no store at all - the
			-- server creates one. Nothing here needs an account: this assault
			-- never logs in, it only asks what the socket is bound to.
		local
			l_directory: DIRECTORY
			l_db: RAW_FILE
			l_process: SIMPLE_PROCESS
			l_exe: SERVER_EXE
			l_file: PLAIN_TEXT_FILE
			l_copied: RAW_FILE
		do
			create l_directory.make (Scratch_root + "\data")
			if not l_directory.exists then
				l_directory.recursive_create_dir
			end
			create l_db.make_with_name (Scratch_db_path)
			if l_db.exists then
				l_db.delete
			end
			delete_file (Scratch_root + "\server_boot.log")
			create l_process.make
			create l_exe
				-- The copy is made from WHEREVER the executable really is, not from
				-- a path that only resolves when the runner was started at the root.
			check built: attached l_exe.path as l_exe_path then
				l_process.command_output ("cmd /c copy /Y %"" + l_exe_path.name + "%" %"" + Scratch_root + "\" + Scratch_server_name + "%"").do_nothing
			end
			create l_copied.make_with_name (Scratch_root + "\" + Scratch_server_name)
			check server_exe_copied: l_copied.exists end
			create l_file.make_create_read_write (Scratch_root + "\server.toml")
			l_file.put_string ("port = " + Port.out + "%Ndata_dir = %"" + Scratch_data_dir_toml + "%"%N")
			l_file.close
		end

	Scratch_root: STRING_8 = "C:\Users\Public\sc_bind_test"

	Scratch_server_name: STRING_8 = "sc_bind_server.exe"
			-- Distinct from simple_chat.exe (which is this runner too) and from
			-- WIRING_ASSAULT's sc_wiring_server.exe, so a teardown by image name
			-- can only reach the server this assault started.

	Scratch_db_path: STRING_32 = "C:\Users\Public\sc_bind_test\data\simple_chat.db"

	Scratch_data_dir_toml: STRING_8 = "C:/Users/Public/sc_bind_test/data"
			-- Forward slashes: a TOML basic string treats backslash as an escape.

	Port: INTEGER = 18214
			-- Not 18213 (WIRING_ASSAULT's), and never 8090: that is the live room's.

	Loopback_url: STRING_8 = "http://127.0.0.1:18214/health"

feature {NONE} -- Small helpers

	ascii_of (a_text: STRING_32): STRING_8
			-- `a_text' as bytes, for text that is addresses and nothing else.
		do
			create Result.make (a_text.count)
			across a_text as ic loop
				if ic.natural_32_code < 128 then
					Result.append_character (ic.to_character_8)
				end
			end
		end

	one_line (a_text: STRING_8): STRING_8
			-- `a_text' with its line breaks turned into ", ", for a transcript.
		local
			l_piece: STRING_8
		do
			create Result.make (a_text.count)
			across a_text.split ('%N') as ic loop
				l_piece := ic.twin
				l_piece.adjust
				if not l_piece.is_empty then
					if not Result.is_empty then
						Result.append (", ")
					end
					Result.append (l_piece)
				end
			end
		end

	utf8_head (a_text: READABLE_STRING_GENERAL; a_maximum: INTEGER): STRING_8
			-- The first `a_maximum' characters of `a_text', as bytes.
		require
			positive: a_maximum > 0
		local
			i, n: INTEGER
			c: NATURAL_32
		do
			n := a_text.count.min (a_maximum)
			create Result.make (n)
			from
				i := 1
			until
				i > n
			loop
				c := a_text.code (i)
				if c < 128 and c /= 10 and c /= 13 then
					Result.append_character (c.to_character_8)
				end
				i := i + 1
			end
		end

	delete_file (a_path: READABLE_STRING_GENERAL)
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.delete
			end
		end

	head_of_file (a_path: READABLE_STRING_GENERAL; a_maximum: INTEGER): STRING_8
			-- The first `a_maximum' bytes at `a_path'; a note when there is no file.
		require
			positive: a_maximum > 0
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists and then l_file.is_readable and then l_file.count > 0 then
				l_file.open_read
				l_file.read_stream (l_file.count.min (a_maximum))
				Result := l_file.last_string.twin
				l_file.close
			else
				Result := "(no server output was written)"
			end
		ensure
			bounded: Result.count <= a_maximum.max (40)
		end

feature {NONE} -- The build this assault needs

	report_unbuilt_server (a_what: STRING_8)
			-- FAIL, never skip: `a_what' needs the finalized server executable
			-- and SERVER_EXE cannot find it. A skip that counts as a pass is a
			-- lie told in green.
		local
			l_exe: SERVER_EXE
		do
			create l_exe
			l_exe.explain_missing
			assert (a_what + " needs " + l_exe.Relative_path + ", which is not built", False)
		end

end
