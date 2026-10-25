#!/usr/bin/env bash
#
#  Frosted Shell — translucent surfaces for GNOME Shell
#  Installer / uninstaller.  Safe to re-run.
#
#  Usage:
#     ./install.sh                  install the shell theme only
#     ./install.sh --with-effects   install the theme AND the rendering
#                                   engine + the settings snapshot
#     ./install.sh --uninstall      remove the theme, restore the old one
#     ./install.sh --uninstall --purge-effects
#                                   also delete the rendering engine
#
set -euo pipefail

THEME_NAME="FrostedShell"
BASE_THEME="Yaru-blue-dark"

# Rendering engine (MIT). Provides the actual refraction / blur behind the
# translucent surfaces produced by theme/overlay.css.
EXT_UUID="liquid-glass@thinkingcoding1231.gmail.com"
EXT_REPO="https://github.com/ryohsuke1231/liquid-glass.git"

EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
THEMES_DIR="$HOME/.themes"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_EFFECTS=0
UNINSTALL=0
PURGE_EFFECTS=0

for arg in "$@"; do
  case "$arg" in
    --with-effects)   WITH_EFFECTS=1 ;;
    --uninstall)      UNINSTALL=1 ;;
    --purge-effects)  PURGE_EFFECTS=1 ;;
    -h|--help)        sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^#\{0,1\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '  x %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- uninstall --
if [ "$UNINSTALL" -eq 1 ]; then
  echo "Removing Frosted Shell"
  rm -rf "${THEMES_DIR:?}/$THEME_NAME"
  say "theme removed: $THEMES_DIR/$THEME_NAME"

  if gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | grep -q "$THEME_NAME"; then
    gsettings set org.gnome.shell.extensions.user-theme name "$BASE_THEME" 2>/dev/null \
      && say "shell theme restored to $BASE_THEME" \
      || warn "could not reset the shell theme; do it in Extensions -> User Themes"
  fi

  if [ "$PURGE_EFFECTS" -eq 1 ]; then
    gnome-extensions disable "$EXT_UUID" 2>/dev/null || true
    rm -rf "${EXT_DIR:?}/$EXT_UUID"
    say "rendering engine removed: $EXT_DIR/$EXT_UUID"
  else
    say "rendering engine left in place (use --purge-effects to delete it)"
  fi

  echo
  echo "Log out and back in (or Alt+F2, r, Enter on X11) to finish."
  exit 0
fi

# ------------------------------------------------------------------ checks ---
echo "Frosted Shell"
have gnome-shell || die "GNOME Shell not found."
have gsettings  || die "gsettings not found (glib2 tools missing?)."

[ -d "/usr/share/themes/$BASE_THEME/gnome-shell" ] || \
  die "base theme '$BASE_THEME' is missing. Install it with:
       sudo apt install yaru-theme-gnome-shell"

gsettings list-schemas | grep -qx "org.gnome.shell.extensions.user-theme" || \
  die "the 'User Themes' extension is missing:
       sudo apt install gnome-shell-extensions"

# ------------------------------------------------------------------- theme ---
echo
echo "1/3  installing the shell theme"
DEST="$THEMES_DIR/$THEME_NAME"
rm -rf "$DEST"
mkdir -p "$DEST"

# -L: /usr/share/themes/Yaru-*/gnome-shell is a symlink into the package
cp -rL "/usr/share/themes/$BASE_THEME/gnome-shell" "$DEST/gnome-shell"
cp "$HERE/theme/index.theme" "$DEST/index.theme"

# Later rules of equal specificity win, so the overrides go last.
cat "$HERE/theme/overlay.css" >> "$DEST/gnome-shell/gnome-shell.css"

say "$DEST  ($(wc -l < "$DEST/gnome-shell/gnome-shell.css") lines of CSS)"

gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com 2>/dev/null || true
gsettings set org.gnome.shell.extensions.user-theme name "$THEME_NAME"
say "shell theme set to $THEME_NAME"

# ------------------------------------------------------------------ engine ---
if [ "$WITH_EFFECTS" -eq 1 ]; then
  echo
  echo "2/3  installing the rendering engine"

  if [ ! -d "$EXT_DIR/$EXT_UUID" ]; then
    have git || die "git is required to fetch the rendering engine."
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    git clone --depth 1 "$EXT_REPO" "$TMP/src" >/dev/null 2>&1 \
      || die "could not clone $EXT_REPO"
    mkdir -p "$EXT_DIR"
    cp -r "$TMP/src/$EXT_UUID" "$EXT_DIR/"
    say "fetched into $EXT_DIR/$EXT_UUID"
  else
    say "already present: $EXT_DIR/$EXT_UUID"
  fi

  have glib-compile-schemas && glib-compile-schemas "$EXT_DIR/$EXT_UUID/schemas"

  # Apply the settings snapshot to the engine's own dconf path.
  dconf load /org/gnome/shell/extensions/liquid-glass/ < "$HERE/config/effects.dconf"
  say "settings snapshot applied"

  python3 - "$EXT_UUID" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
cur = ast.literal_eval(subprocess.check_output(
    ['gsettings', 'get', 'org.gnome.shell', 'enabled-extensions']).decode())
if uuid not in cur:
    cur.append(uuid)
    val = '[' + ', '.join("'%s'" % x for x in cur) + ']'
    subprocess.check_call(
        ['gsettings', 'set', 'org.gnome.shell', 'enabled-extensions', val])
print('  enabled:', uuid)
PY

  # Blur my Shell, if present, must not blur the same surfaces: its blur is
  # drawn under the engine's glass and muddies it.
  if gsettings list-schemas | grep -qx org.gnome.shell.extensions.blur-my-shell; then
    dconf load /org/gnome/shell/extensions/blur-my-shell/ < "$HERE/config/coexist.dconf"
    say "Blur my Shell: panel / popup / window blur turned off (coexistence)"
  fi
else
  echo
  echo "2/3  effects skipped (run with --with-effects for the glass itself)"
fi

# ------------------------------------------------------------------- done ----
echo
echo "3/3  done"
cat <<'EOT'

  Restart the shell so the theme is loaded:
     X11      Alt+F2, type r, Enter
     Wayland  log out and back in

  Without --with-effects the theme only makes surfaces translucent; the
  refraction and blur come from the rendering engine.

EOT
