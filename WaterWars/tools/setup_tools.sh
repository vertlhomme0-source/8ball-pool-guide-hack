#!/usr/bin/env bash
# Telecharge la chaine d'outils Luau utilisee par tools/check.sh.
# Ces binaires ne sont pas versionnes (voir .gitignore) : ce script les remet
# en place en une commande.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.tools"
LSP_VERSION="${LSP_VERSION:-1.60.0}"
mkdir -p "$BIN"
cd "$BIN"

echo "== Luau (compilateur + REPL) =="
curl -sSL -o luau.zip "https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip"
unzip -o -q luau.zip
rm -f luau.zip

echo "== luau-lsp $LSP_VERSION (typecheck contre l'API Roblox) =="
curl -sSL -o lsp.zip \
  "https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LSP_VERSION/luau-lsp-linux-x86_64.zip"
unzip -o -q lsp.zip
rm -f lsp.zip

chmod +x luau luau-compile luau-analyze luau-ast luau-lsp 2>/dev/null || true

echo "== definitions de types Roblox =="
curl -sSL -o "$ROOT/tools/globalTypes.d.luau" \
  "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

echo "Termine. Lancez : bash tools/check.sh"
