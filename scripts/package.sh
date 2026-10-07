#!/usr/bin/env bash
# Assembles the Linux or macOS release archive from a built client and server release.
#   scripts/package.sh [version]
# Inputs (override with environment variables):
#   CLIENT_BUILD  CMake build directory with the client      (default build/client)
#   SERVER_DIR    OTP release built with `mix release`        (default build/server)
#   QMAKE         qmake of the Qt used for the build (Linux AppImage deployment)
# Output: dist/BlackShift-<version>-linux-x64.tar.gz or dist/BlackShift-<version>-macos-<arch>.zip
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-$(sed -n 's/^project(BlackShift VERSION \([0-9.]*\).*/\1/p' "$root/CMakeLists.txt")}"
version="${version#v}"
client_build="${CLIENT_BUILD:-$root/build/client}"
server_dir="${SERVER_DIR:-$root/build/server}"
[ -x "$server_dir/bin/blackshift" ] || { echo "Server release not found in $server_dir" >&2; exit 1; }

case "$(uname)" in
    Darwin) os=macos; arch="$(uname -m)" ;;
    Linux) os=linux; arch="$(uname -m | sed 's/x86_64/x64/')" ;;
    *) echo "Unsupported OS: $(uname)" >&2; exit 1 ;;
esac
name="BlackShift-$version-$os-$arch"
dist="$root/dist"
stage="$dist/$name"
rm -rf "$stage"
mkdir -p "$stage"

if [ "$os" = macos ]; then
    cp -R "$client_build/blackshift.app" "$stage/BlackShift.app"
    macdeployqt "$stage/BlackShift.app"
    cp "$root/packaging/unix/play.sh" "$stage/Play.command"
    chmod +x "$stage/Play.command"
else
    # Self-contained AppImage with the Qt libraries and plugins it needs.
    tools="$dist/tools"
    mkdir -p "$tools"
    for tool in linuxdeploy/linuxdeploy linuxdeploy-plugin-qt/linuxdeploy-plugin-qt; do
        file="$tools/$(basename "$tool")-x86_64.AppImage"
        [ -x "$file" ] || {
            curl -fsSL -o "$file" "https://github.com/linuxdeploy/$(dirname "$tool")/releases/download/continuous/$(basename "$tool")-x86_64.AppImage"
            chmod +x "$file"
        }
    done
    appdir="$dist/AppDir"
    rm -rf "$appdir"
    export APPIMAGE_EXTRACT_AND_RUN=1 NO_STRIP=1 LDAI_OUTPUT="$stage/BlackShift.AppImage"
    export PATH="$tools:$PATH"
    (cd "$dist" && linuxdeploy-x86_64.AppImage --appdir "$appdir" \
        --executable "$client_build/blackshift" \
        --desktop-file "$root/packaging/linux/blackshift.desktop" \
        --icon-file "$root/assets/icons/blackshift.png" \
        --plugin qt --output appimage)
    rm -rf "$appdir"
    cp "$root/packaging/unix/play.sh" "$stage/play.sh"
    chmod +x "$stage/play.sh"
fi

cp -R "$server_dir" "$stage/server"
cp "$root/packaging/README.txt" "$root/LICENSE" "$stage/"

if [ "$os" = macos ]; then
    (cd "$dist" && rm -f "$name.zip" && ditto -c -k --keepParent "$name" "$name.zip")
    echo "Packaged: $dist/$name.zip"
else
    tar -czf "$dist/$name.tar.gz" -C "$dist" "$name"
    echo "Packaged: $dist/$name.tar.gz"
fi
