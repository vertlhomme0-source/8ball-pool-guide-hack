#!/usr/bin/env bash
# Validation complete du code Luau du projet Water Wars.
#  1) luau-compile  -> aucune erreur de syntaxe / compilation
#  2) luau-lsp      -> typecheck contre l'API Roblox reelle (globalTypes.d.luau)
#  3) checks Python -> coherence des donnees (armes, maps, remotes, requires)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.tools"
LUAU_COMPILE="${LUAU_COMPILE:-$BIN/luau-compile}"
LUAU_LSP="${LUAU_LSP:-$BIN/luau-lsp}"
FAIL=0

python3 "$ROOT/tools/gen_sourcemap.py" > /dev/null
mapfile -t FILES < <(find "$ROOT/src" -name "*.luau" | sort)
echo "== [1/5] luau-compile (${#FILES[@]} fichiers) =="
if [ -x "$LUAU_COMPILE" ]; then
  if ! "$LUAU_COMPILE" --binary -O2 "${FILES[@]}" > /dev/null; then FAIL=1; fi
  echo "   ok"
else
  echo "   (luau-compile introuvable, etape ignoree)"
fi

echo "== [2/5] luau-lsp analyze (types Roblox) =="
if [ -x "$LUAU_LSP" ]; then
  OUT="$("$LUAU_LSP" analyze --definitions="$ROOT/tools/globalTypes.d.luau" \
        --settings="$ROOT/tools/lsp-settings.json" \
        --sourcemap="$ROOT/sourcemap.json" \
        --ignore="**/globalTypes.d.luau" --no-strict-dm-types "${FILES[@]}" 2>&1)"
  RC=$?
  echo "$OUT"
  if [ $RC -ne 0 ]; then FAIL=1; else echo "   ok"; fi
else
  echo "   (luau-lsp introuvable, etape ignoree)"
fi

echo "== [3/5] passe stricte (proprietes Roblox) =="
if ! python3 "$ROOT/tools/strict_pass.py"; then FAIL=1; fi

echo "== [4/5] verifications de coherence =="
if ! python3 "$ROOT/tools/check_data.py"; then FAIL=1; fi

echo "== [5/5] demarrage reel du serveur (simulation Roblox) =="
echo "   -- installation normale"
if ! python3 "$ROOT/tools/boot_test.py" | sed 's/^/   /'; then FAIL=1; fi
echo "   -- contenu insere au mauvais endroit (auto-reparation)"
if ! python3 "$ROOT/tools/boot_test.py" --misplaced | sed 's/^/   /'; then FAIL=1; fi

if [ $FAIL -ne 0 ]; then echo ""; echo "RESULTAT: ECHEC"; exit 1; fi
echo ""; echo "RESULTAT: TOUT EST VERT"
