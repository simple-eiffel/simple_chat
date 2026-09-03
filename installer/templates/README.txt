SimpleChat 0.1.0
================

A private group chat for a circle of friends. One of you hosts the room on
their own PC; everybody else connects to it. No company in the middle, no
account with anyone, no browser.


JUST USING THE CHAT
-------------------

Start Menu -> SimpleChat.

The first time, put the address your host gave you in the "Server" box - it
looks like  https://something.duckdns.org  - then your username and password.
Tick "Remember me on this PC" and you will not be asked again on this PC.

Your settings live in
    %APPDATA%\simple_chat\client.toml
and are never removed by an uninstall. No password is ever stored there. If
you ticked "remember me", the session is sealed to your Windows account with
DPAPI - unreadable by another user or on another PC.


HOSTING THE ROOM
----------------

Only if you ticked the hosting box when you installed.

Hosting requires an ADMINISTRATOR install - say yes when Windows asks for
permission as the installer starts. A per-user ("just for me") install does not
offer the hosting option at all, by design: the server writes to a machine-wide
folder and registers a startup task for the whole PC. Re-run the installer,
allow it to elevate, and tick the box.

Start Menu -> SimpleChat Server -> Hosting guide.

That guide is written for a non-programmer and covers the whole job: making
the first account, getting a free DuckDNS name, forwarding the port on your
router (including how to tell whether your provider's CGNAT makes that
impossible), turning the front door on by editing two lines, backups, and
setting up a friend as a standby host who can take over if your PC dies.

The short version - the server is private to this PC until you edit two lines
in
    C:\ProgramData\SimpleChat\server.toml
namely
    front_door = "caddy"
    public_name = "yourname.duckdns.org"

Accounts are made by you, never signed up for: "Create first admin" once, then
"Create user" for each friend. If somebody forgets their password - including
you - "Reset a password" gives them a new one and signs out everyone who was
logged in as them. Stop the server before any of the three: they open the
database directly and refuse to run while it is up.


WHERE THINGS ARE
----------------

  Programs          C:\Program Files\SimpleChat
  Server settings   C:\ProgramData\SimpleChat\server.toml
  The room itself   C:\ProgramData\SimpleChat\data\simple_chat.db
  Server log        C:\ProgramData\SimpleChat\server.log
  Backups           C:\ProgramData\SimpleChat\backups
  Your settings     %APPDATA%\simple_chat\client.toml


UNINSTALLING
------------

Uninstalling removes the programs and leaves everything else. The room - every
account, room and message - stays in C:\ProgramData\SimpleChat\data, along with
your settings and your backups. Reinstalling picks up exactly where you left
off. If you really want it all gone, delete C:\ProgramData\SimpleChat yourself.


ADDING HOSTING LATER
--------------------

Run the installer again and tick the hosting box. It adds the server, Caddy and
the hosting tools to what you already have and leaves your chat settings alone.
That is also how a friend is promoted to a standby host.


DIAGNOSTICS
-----------

The binaries installed here are the lean release builds, with contract checking
compiled out - that is the shipping build and the fast one. A second pair built
with every precondition, postcondition and class invariant left in
(simple_chat_dbc.exe) is produced by the same release build and is what to run
when chasing a defect. It is not shipped in this installer; build it from
source with:  ec.sh release -config simple_chat.ecf -target simple_chat_server


Third-party components and their licences: THIRD-PARTY.md in this folder.
SimpleChat itself is MIT.
