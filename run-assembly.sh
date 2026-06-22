#!/usr/bin/env bash
# Build the godot `multiplayer-fabric` assembly via the gitassembly recipe.
# Idempotent + restartable so it runs unattended under a systemd oneshot:
#   - re-stages the recipe/driver/assembler into the fork checkout
#   - resets any half-finished merge from a prior run
#   - gives .github/changed_files.yml a union merge driver so the recurring
#     exclusion-list conflict auto-resolves (keep both sides) without stopping
#   - runs the elixir driver in DRY-RUN (-n): builds the branch, no tag, no push
set -euo pipefail
export PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin
export GIT_AUTHOR_NAME="K. S. Ernest (iFire) Lee" GIT_AUTHOR_EMAIL="ernest.lee@chibifire.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

# This repo (holds the recipe, driver, and assembler).
ASM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The godot fork checkout to assemble into. Defaults to a side-by-side
# fabric-godot-core; override with GODOT_CHECKOUT.
CORE="${GODOT_CHECKOUT:-$(cd "$ASM/../fabric-godot-core" 2>/dev/null && pwd || true)}"
[ -n "$CORE" ] && [ -d "$CORE/.git" ] || { echo "set GODOT_CHECKOUT to the godot fork checkout (default: ../fabric-godot-core)" >&2; exit 1; }

echo "[assembly] elixir: $(elixir --version 2>/dev/null | tail -1)"
echo "[assembly] staging recipe/driver/assembler into the fork checkout"
cp "$ASM/update_godot_v_sekai.exs" "$ASM/gitassembly" "$CORE/"
mkdir -p "$CORE/thirdparty"; cp "$ASM/thirdparty/git-assembler" "$CORE/thirdparty/git-assembler"

cd "$CORE"
echo "[assembly] resetting any prior in-progress merge"
git merge --abort 2>/dev/null || true
git rev-parse --verify -q main >/dev/null || git branch main master
git checkout -f main
git reset --hard

echo "[assembly] union merge driver for the changed_files.yml exclusion list"
mkdir -p .git/info
grep -q 'changed_files.yml merge=union' .git/info/attributes 2>/dev/null || \
  echo '.github/changed_files.yml merge=union' >> .git/info/attributes
git config rerere.enabled true

if [ "${DRY_RUN:-1}" = "0" ]; then
  echo "[assembly] running REAL driver (tags the assembly and PUSHES the tag to the fork)"
  elixir update_godot_v_sekai.exs
  # Real run tags then deletes the local multiplayer-fabric branch, so verify the tag.
  target=$(git tag -l 'v*-multiplayer-fabric' | sort | tail -1)
  [ -n "$target" ] || { echo "[assembly] ERROR: no tag created"; exit 1; }
  echo "[assembly] new tag: $target -> $(git rev-parse --short "$target")"
  if git ls-remote --tags v-sekai-multiplayer-fabric "refs/tags/$target" 2>/dev/null | grep -q .; then
    echo "[assembly] tag pushed to fork: yes"
  else
    echo "[assembly] tag pushed to fork: NO"; exit 1
  fi
else
  echo "[assembly] running dry-run driver (-n; no tag, no push)"
  elixir update_godot_v_sekai.exs -n
  target=multiplayer-fabric
  git rev-parse --verify -q "$target" >/dev/null || { echo "[assembly] ERROR: branch not created"; exit 1; }
  echo "[assembly] multiplayer-fabric HEAD: $(git rev-parse --short "$target")"
fi

echo "[assembly] === verification (recipe branches are ancestors of $target) ==="
merged=0; miss=0
while read -r kw _tgt ref; do
  case "$kw" in stage|merge)
    if git merge-base --is-ancestor "$ref" "$target" 2>/dev/null; then
      merged=$((merged+1))
    else echo "[assembly] NOT merged: $ref"; miss=$((miss+1)); fi ;;
  esac
done < <(grep -E '^(stage|merge) ' gitassembly)
echo "[assembly] recipe branches merged: $merged  not-merged: $miss"
[ "$miss" -eq 0 ] && echo "[assembly] DONE: assembly complete" || { echo "[assembly] INCOMPLETE"; exit 1; }
