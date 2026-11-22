#!/data/data/com.termux/files/usr/bin/bash
# SekexBot - easy setup for a new Android phone.
#
# The ONLY thing the user does: install Termux, open it, paste this one line and press Enter:
#
#   curl -L https://raw.githubusercontent.com/sekextrading-cloud/sekexbot-updates/main/setup.sh | bash
#
# This script then does everything else by itself:
#   - keeps the phone awake while it works
#   - installs the three helper apps (Termux:API, Termux:Boot, Termux:Widget): Android shows an
#     "Install" window for each one, the user taps Install
#   - downloads the newest SekexBot (the same file the in-app updater uses) and checks it is intact
#   - runs SekexBot's own installer: Python, every library, the sekex command, start-on-boot,
#     home-screen buttons, the phone setup check, and opens the dashboard
#
# No files to save in Download, no storage permission, nothing else to type.
# Safe to run again: it repairs or updates an existing install and keeps keys, settings and journal.

sekex_setup() {
  REPO_RAW="${SEKEX_REPO_RAW:-https://raw.githubusercontent.com/sekextrading-cloud/sekexbot-updates/main}"
  FDROID="${SEKEX_FDROID:-https://f-droid.org}"
  WORK="$HOME/.sekexbot_setup_tmp"
  LOG="$HOME/sekexbot-setup.log"

  say()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
  warn() { printf '\n\033[1;33m!!\033[0m %s\n' "$*"; }
  die()  { printf '\n\033[1;31mXX\033[0m %s\n\n' "$*"; termux-wake-unlock 2>/dev/null; exit 1; }
  have() { command -v "$1" >/dev/null 2>&1; }
  get()  { curl -fsSL --retry 3 --retry-delay 3 --connect-timeout 20 "$@"; }
  pause() {   # wait for Enter on the real keyboard (stdin is the script itself when piped from curl)
    printf '%s' "$1"
    if [ -r /dev/tty ]; then read -r _ < /dev/tty || true; else sleep 20; fi
  }
  has_pkg() {   # 0 installed, 1 not installed, 2 can't tell
    local out; out="$(pm path "$1" 2>&1)"
    case "$out" in package:*) return 0 ;; *xception*|*ailure*|*"not found"*|*denied*) return 2 ;; "") return 1 ;; *) return 2 ;; esac
  }

  [ -n "$PREFIX" ] && [ -d "$PREFIX" ] || { echo "This setup must be run inside the Termux app on an Android phone."; exit 1; }

  echo
  echo "  =========================================="
  echo "   SekexBot setup"
  echo "   Keep the phone plugged in and on Wi-Fi."
  echo "   This takes 10 to 40 minutes. Do not close Termux."
  echo "  =========================================="

  case "${TERMUX_APK_RELEASE:-}" in
    GOOGLE_PLAY_STORE) die "This Termux came from the Play Store, which does not work with SekexBot.
   Uninstall Termux, then install it from the SekexBot setup page (the green button) and try again." ;;
  esac

  have termux-wake-lock && termux-wake-lock 2>/dev/null || true
  rm -rf "$WORK"; mkdir -p "$WORK"

  # ---------- 1. make Termux able to install things, with no questions asked ----------
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p "$PREFIX/etc/apt/apt.conf.d"
  cat > "$PREFIX/etc/apt/apt.conf.d/99sekexbot-noninteractive" <<'APT'
APT::Get::Assume-Yes "true";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APT
  say "Step 1 of 4: getting Termux ready"
  yes | pkg update -y >>"$LOG" 2>&1 || pkg update -y || die "No internet, or the download servers are busy. Check Wi-Fi and run the setup line again."
  pkg install -y unzip curl termux-api termux-tools >>"$LOG" 2>&1 || pkg install -y unzip curl termux-api \
    || die "Could not install the basic tools. Check Wi-Fi and run the setup line again."

  # ---------- 2. the helper apps ----------
  say "Step 2 of 4: installing the helper apps"
  apk_url() {   # apk_url <package id> <github repo name>  -> download link, from the same store Termux came from
    if [ "${TERMUX_APK_RELEASE:-F_DROID}" = GITHUB ]; then
      get "https://api.github.com/repos/termux/$2/releases/latest" 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*\.apk"' | head -n 1 | sed 's/.*"\(https[^"]*\)"/\1/'
    else
      local code
      code="$(get "$FDROID/api/v1/packages/$1" 2>/dev/null | sed -n 's/.*"suggestedVersionCode" *: *\([0-9][0-9]*\).*/\1/p' | head -n 1)"
      [ -n "$code" ] && echo "$FDROID/repo/$1_$code.apk"
    fi
  }
  FIRST_APK=1
  install_app() {   # install_app <package id> <name> <github repo name> <what it is for>
    local id="$1" name="$2" gh="$3" why="$4" url f i
    has_pkg "$id"; local st=$?
    [ $st = 0 ] && { echo "  OK  $name is already installed"; return 0; }
    url="$(apk_url "$id" "$gh")"
    f="$WORK/$id.apk"
    if [ -z "$url" ] || ! get -o "$f" "$url" || [ ! -s "$f" ]; then
      warn "Could not download $name ($why). SekexBot still works; the setup check at the end will offer it again."
      return 0
    fi
    echo
    echo "  ------------------------------------------------------------"
    echo "   $name  ($why)"
    echo "   A window will pop up.  Tap  INSTALL,  then tap  DONE."
    if [ $FIRST_APK = 1 ]; then
      echo
      echo "   The first time, Android may say Termux is not allowed to"
      echo "   install apps.  Tap  SETTINGS,  switch on  'Allow from this"
      echo "   source',  press the BACK button, then tap INSTALL."
    fi
    echo "  ------------------------------------------------------------"
    FIRST_APK=0
    sleep 4
    termux-open "$f" 2>/dev/null || termux-open --content-type application/vnd.android.package-archive "$f" 2>/dev/null \
      || { warn "Could not open the installer for $name. The setup check at the end will offer it again."; return 0; }
    if [ $st = 2 ]; then
      pause "   When it says 'App installed', come back here and press ENTER... "
    else
      i=0
      while [ $i -lt 90 ]; do has_pkg "$id" && break; sleep 2; i=$((i + 1)); done
      if has_pkg "$id"; then echo "  OK  $name installed"; else warn "$name was not installed (skipped). The setup check at the end will offer it again."; fi
    fi
    rm -f "$f"
    return 0
  }
  install_app com.termux.api    "Termux:API"    termux-api    "notifications, voice, battery"
  install_app com.termux.widget "Termux:Widget" termux-widget "SekexBot button on the home screen"
  install_app com.termux.boot   "Termux:Boot"   termux-boot   "starts SekexBot when the phone turns on"
  # Termux:Boot only works after it has been opened once.
  if has_pkg com.termux.boot && [ ! -f "$HOME/.sekexbot/boot_opened" ]; then
    mkdir -p "$HOME/.sekexbot"
    am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.termux.boot >/dev/null 2>&1 \
      && touch "$HOME/.sekexbot/boot_opened" \
      && { sleep 3; am start -n com.termux/.app.TermuxActivity >/dev/null 2>&1 || true; }
  fi

  # ---------- 3. download the newest SekexBot ----------
  say "Step 3 of 4: downloading SekexBot"
  MAN="$(get "$REPO_RAW/latest.json")" || die "Could not reach the SekexBot download site. Check Wi-Fi and run the setup line again."
  # keep only the top level of the file (the admin add-on has its own version/url/sha256 inside "admin": {...})
  MAN1="$(printf '%s' "$MAN" | tr -d '\n\r' | sed 's/^[^{]*{//; s/{[^{}]*}//g')"
  VER="$(printf '%s' "$MAN1" | sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p')"
  ZIP="$(printf '%s' "$MAN1" | sed -n 's/.*"url" *: *"\([^"]*\)".*/\1/p')"
  SHA="$(printf '%s' "$MAN1" | sed -n 's/.*"sha256" *: *"\([0-9a-fA-F]*\)".*/\1/p')"
  VER="${VER:-?}"
  case "$ZIP" in SekexBot_Android_v*.zip) ;; *) die "The download list looks wrong. Tell your SekexBot contact (send a screenshot)." ;; esac
  [ ${#SHA} = 64 ] || die "The download list has no safety check code. Tell your SekexBot contact (send a screenshot)."
  echo "  SekexBot version $VER"
  get -o "$WORK/app.zip" "$REPO_RAW/$ZIP" || die "The download stopped. Check Wi-Fi and run the setup line again."
  GOT="$(sha256sum "$WORK/app.zip" | cut -d' ' -f1)"
  [ "$GOT" = "$(printf '%s' "$SHA" | tr 'A-F' 'a-f')" ] || die "The downloaded file is damaged or was changed. Run the setup line again; if it repeats, send a screenshot."
  echo "  OK  download checked"
  unzip -q -o "$WORK/app.zip" -d "$WORK" || die "Could not unpack SekexBot. Free up some phone storage and run the setup line again."
  [ -f "$WORK/SekexBot_Android/install.sh" ] || die "The SekexBot package is incomplete. Send a screenshot to your SekexBot contact."

  # ---------- 4. SekexBot's own installer does the rest ----------
  say "Step 4 of 4: installing SekexBot (the long part - leave the phone alone)"
  export SEKEX_SETUP_DIR="$WORK"
  # optional extras the owner may have put in Download: sekexbot-setup.conf (found by install.sh itself) and a SekexBot_data folder
  for d in /sdcard/Download "$HOME/storage/downloads"; do [ -d "$d/SekexBot_data" ] && export SEKEX_SETUP_DIR="$d" && break; done
  bash "$WORK/SekexBot_Android/install.sh" < /dev/null
  rc=$?
  rm -rf "$WORK"
  if [ $rc != 0 ]; then
    die "The install did not finish. Run the setup line again (it continues where it stopped).
   If it fails twice, send a screenshot of this screen to your SekexBot contact."
  fi
  echo
  echo "  =========================================="
  echo "   ALL DONE.  SekexBot is running."
  echo "   The dashboard opens in your browser."
  echo "   Next: tap  Broker keys  and enter your Alpaca keys."
  echo "  =========================================="
  echo
}

# Everything is inside one function, so a download that is cut off half-way runs nothing at all.
sekex_setup
