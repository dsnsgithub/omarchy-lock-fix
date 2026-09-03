#!/bin/bash
# gaze-setup.sh -- install Gaze (https://gaze.gundulabs.com) and enroll a face
# so the dsns.lock lock screen unlocks like Windows Hello.
#
# The plugin's setup card launches this in a visible terminal on purpose:
# the AUR build and `sudo systemctl enable` want to talk to you, and
# `gaze add-face` shows the camera preview in the terminal.
#
# Safe to rerun at any time; every step checks before it acts.

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
OFF='\033[0m'

ok()   { printf "${GREEN}${BOLD}%s${OFF}\n" "$1"; }
warn() { printf "${YELLOW}%s${OFF}\n" "$1"; }
err()  { printf "${RED}%s${OFF}\n" "$1" >&2; }

pam_module_present() {
  [[ -f /usr/lib/security/pam_gaze.so || -f /lib/security/pam_gaze.so ]]
}

install_gaze() {
  if command -v gaze >/dev/null 2>&1; then
    ok "Gaze is already installed."
    return 0
  fi

  echo "Installing Gaze from the AUR (gaze-bin: daemon, CLI and PAM module)."
  echo "Building can take a few minutes and may ask for your sudo password."
  echo

  local installed=1
  if command -v omarchy-pkg-aur-add >/dev/null 2>&1; then
    omarchy-pkg-aur-add gaze-bin || installed=0
  elif command -v paru >/dev/null 2>&1; then
    paru -S --noconfirm --needed gaze-bin || installed=0
  elif command -v yay >/dev/null 2>&1; then
    yay -S --noconfirm --needed gaze-bin || installed=0
  else
    err "No AUR helper found (omarchy-pkg-aur-add, paru, yay)."
    err "Install Gaze manually, then run this script again."
    exit 1
  fi

  if ! command -v gaze >/dev/null 2>&1; then
    err "gaze did not install. Scroll up for the failure and rerun this script."
    exit 1
  fi

  if ! pam_module_present; then
    warn "Warning: pam_gaze.so was not found in /usr/lib/security."
    warn "Run 'gaze doctor' after setup to diagnose PAM integration."
  fi

  ok "Gaze installed."
}

ensure_daemon() {
  if systemctl is-active --quiet gazed.service 2>/dev/null; then
    ok "gazed daemon is running."
    return 0
  fi

  echo "Enabling and starting the gazed daemon (asks for your sudo password)..."
  if ! sudo systemctl enable --now gazed.service; then
    err "Could not start gazed. Try 'sudo systemctl enable --now gazed' or reboot once and rerun."
    exit 1
  fi

  for _ in $(seq 1 25); do
    systemctl is-active --quiet gazed.service && break
    sleep 1
  done

  if ! systemctl is-active --quiet gazed.service; then
    err "gazed is still not running. Check 'journalctl -u gazed'."
    exit 1
  fi

  ok "gazed daemon is running."
}

list_faces() {
  gaze list-faces 2>/dev/null | grep -vi 'no faces found' || true
}

enroll_face() {
  if [[ -n $(list_faces) ]]; then
    ok "Face already enrolled:"
    list_faces
    echo "Add more angles anytime with: gaze refine-face default"
    return 0
  fi

  echo
  echo "Time to enroll your face. A live camera preview runs in this terminal:"
  echo "  1. Look straight at the camera."
  echo "  2. When asked, move slightly up, down, left and right."
  echo "  3. Stay reasonably well lit - this is your master template."
  echo
  warn "No password is typed anywhere. Enrollments never leave the machine."

  if ! gaze add-face default; then
    err "Enrollment failed. Close any app holding the camera and rerun this script,"
    err "or enroll by hand with: gaze add-face default"
    exit 1
  fi

  ok "Face enrolled."
}

verify_face() {
  echo
  echo "Verifying (gaze auth) - just look at the camera until it prints success."
  if gaze auth; then
    ok "Verified."
  else
    warn "Verification did not succeed. Check lighting/camera, then run: gaze refine-face default"
    warn "You can also re-enroll later by rerunning: bash gaze-setup.sh"
  fi
}

echo -e "${BOLD}Gaze face unlock for Omarchy's lock screen${OFF}"
echo "------------------------------------------"
echo

install_gaze
ensure_daemon
enroll_face
verify_face

echo
ok "Setup complete. The lock screen picks this up immediately:"
echo "  - press Super+Escape (or lock however you do) and look at the camera"
echo "  - unlock happens on a face match; your password always works as fallback"
echo
warn "Note: Gaze's own package normally enables face auth for sudo and polkit too."
warn "If a fresh install makes prompts unlock via your face, that is Gaze upstream, not this plugin."
warn "A reboot once, after installing, makes sure the daemon and PAM changes land."
echo
echo "Diagnostics if anything acts up: gaze doctor  |  journalctl -u gazed"
