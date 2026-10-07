BLACK SHIFT — Relay conflict
============================

Network FPS prototype: Elixir/OTP authoritative server, Qt/OpenGL client.
Each archive contains the game client and its own copy of the server.

Quick start
-----------
Windows  double-click Play.cmd
Linux    ./play.sh
macOS    double-click Play.command

The macOS build is not signed or notarized. After unpacking, remove the
download quarantine once, otherwise macOS blocks the game and the server:

    xattr -dr com.apple.quarantine BlackShift-*-macos-arm64

The launcher starts a local server and opens a practice match (you and two
bots against three bots). Closing the game stops the server.

Other modes:

    Windows (PowerShell)                    Linux / macOS
    .\Play.ps1 -Online                      ./play.sh --online
    .\Play.ps1 -NoServer -Server HOST:7777  ./play.sh --no-server --server HOST:7777
    .\Play.ps1 -Name Alpha -Role warden     ./play.sh --name Alpha --role warden

Hosting a server
----------------
    BS_BIND=0.0.0.0 BS_PORT=7777 server/bin/blackshift start     (Linux / macOS)
    set BS_BIND=0.0.0.0 & server\bin\blackshift.bat start       (Windows)

or with Docker (the exact image name is in the release notes):

    docker run -d -p 7777:7777 -v blackshift-data:/data ghcr.io/<owner>/<repo>-server

Allow TCP port 7777 in the firewall. Players connect to YOUR-IP:7777.

Controls
--------
WASD move, mouse aim, Shift sprint, Space jump, left mouse fire, Q ability,
Tab scoreboard, Esc release/capture the mouse, Enter (released) leave match,
F11 fullscreen.

Requirements: 64-bit Windows 10/11, Linux (glibc 2.39+, X11 or XWayland) or
macOS 14+ on Apple Silicon; a graphics driver with OpenGL 2.1.
Match results are stored in data/mnesia next to the launcher.

License: MIT, see LICENSE.
