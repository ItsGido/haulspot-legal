#!/usr/bin/env bash
# Downloads the command-line tools into .tools/ (Linux x86_64). On Windows/macOS use Rokit instead:
#   rokit install   (reads rokit.toml)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tools && cd .tools
get() { curl -sSL -o "$2" "$1" && unzip -oq "$2" && rm "$2"; }
[ -x rojo ] || get https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-linux-x86_64.zip rojo.zip
[ -x luau-lsp ] || get https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.32.1/luau-lsp-linux.zip lsp.zip
[ -x selene ] || get https://github.com/Kampfkarren/selene/releases/download/0.27.1/selene-0.27.1-linux.zip selene.zip
[ -x stylua ] || get https://github.com/JohnnyMorganz/StyLua/releases/download/v0.20.0/stylua-linux-x86_64.zip stylua.zip
[ -x luau ] || get https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip luau.zip
[ -f globalTypes.d.luau ] || curl -sSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
chmod +x rojo luau-lsp selene stylua luau* 2>/dev/null || true
echo "Tools ready in .tools/"
