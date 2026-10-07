#!/usr/bin/env bash
# Black Shift launcher for Linux (play.sh) and macOS (Play.command).
#   ./play.sh                                  local server + practice match against bots
#   ./play.sh --online                         local server + online queue
#   ./play.sh --no-server --server HOST:7777   join a remote server
# Other options (--name, --role) are passed to the game.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if [ "$(uname)" = Darwin ]; then
    client="$here/BlackShift.app/Contents/MacOS/blackshift"
else
    client="$here/BlackShift.AppImage"
fi
server_bin="$here/server/bin/blackshift"

mode=--practice
address=127.0.0.1:7777
local_server=1
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --online) mode=--online ;;
        --practice) mode=--practice ;;
        --no-server) local_server=0 ;;
        --server) address="$2"; shift ;;
        *) args+=("$1") ;;
    esac
    shift
done

if [ "$local_server" = 1 ]; then
    if [ "$address" != 127.0.0.1:7777 ]; then
        echo "Use --no-server to connect to a remote server." >&2
        exit 1
    fi
    export BS_BIND=127.0.0.1 BS_PORT=7777 BS_DB_DIR="$here/data/mnesia" RELEASE_NODE=blackshift@localhost
    "$server_bin" daemon
    trap '"$server_bin" stop >/dev/null 2>&1 || true' EXIT
    ready=0
    for _ in $(seq 1 100); do
        if "$server_bin" rpc 'BlackShift.Network.Listener.address()' >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.2
    done
    if [ "$ready" != 1 ]; then
        echo "The server did not start. Is port 7777 already in use?" >&2
        exit 1
    fi
fi

"$client" --server "$address" "$mode" ${args[@]+"${args[@]}"}
