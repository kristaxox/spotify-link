#!/usr/bin/env bash
# Install AirPlay + Spotify Connect on Ubuntu Server (Raspberry Pi).
# Run as root: sudo ./install.sh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
  echo "Warning: this script is intended for Ubuntu/Debian."
fi

read -rp "Speaker name (shown in AirPlay and Spotify): " SPEAKER_NAME
SPEAKER_NAME="${SPEAKER_NAME:-Stereo Link}"

CURRENT_HOST="$(hostname)"
read -rp "Hostname [${CURRENT_HOST}]: " NEW_HOSTNAME
NEW_HOSTNAME="${NEW_HOSTNAME:-$CURRENT_HOST}"

echo ""
echo "Available ALSA playback devices:"
aplay -l 2>/dev/null || true
echo ""
read -rp "ALSA card number for audio output [0]: " ALSA_CARD
ALSA_CARD="${ALSA_CARD:-0}"

install_alsa_runtime() {
  # Ubuntu 24.10+ / Debian Trixie: libasound2 is a virtual package; apt must
  # install libasound2t64 explicitly before packages that depend on libasound2.
  if apt-cache show libasound2t64 >/dev/null 2>&1; then
    apt-get install -y libasound2t64
    apt-mark manual libasound2t64 >/dev/null 2>&1 || true
  elif apt-cache show libasound2 >/dev/null 2>&1; then
    apt-get install -y libasound2
  fi
}

install_raspotify() {
  local arch deb_url tmpdeb

  echo "=== Installing Raspotify (Spotify Connect) ==="
  install_alsa_runtime

  curl -sSfL https://dtcooper.github.io/raspotify/key.asc -o /usr/share/keyrings/raspotify_key.asc
  chmod 644 /usr/share/keyrings/raspotify_key.asc
  echo 'deb [signed-by=/usr/share/keyrings/raspotify_key.asc] https://dtcooper.github.io/raspotify raspotify main' \
    > /etc/apt/sources.list.d/raspotify.list

  apt-get update -qq
  if apt-get install -y raspotify; then
    return 0
  fi

  echo "Raspotify apt install failed; trying direct .deb download..."
  arch="$(dpkg --print-architecture)"
  deb_url="https://dtcooper.github.io/raspotify/raspotify-latest_${arch}.deb"
  tmpdeb="$(mktemp /tmp/raspotify.XXXXXX.deb)"
  curl -sSfL "${deb_url}" -o "${tmpdeb}"
  apt-get install -y "${tmpdeb}"
  rm -f "${tmpdeb}"
}

echo ""
echo "=== Installing packages ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
install_alsa_runtime
apt-get install -y --no-install-recommends \
  alsa-utils \
  pipewire \
  pipewire-pulse \
  wireplumber \
  avahi-daemon \
  avahi-utils \
  shairport-sync \
  curl \
  ca-certificates \
  unattended-upgrades

echo "=== Configuring hostname ==="
if [[ "${NEW_HOSTNAME}" != "${CURRENT_HOST}" ]]; then
  hostnamectl set-hostname "${NEW_HOSTNAME}"
  sed -i "s/${CURRENT_HOST}/${NEW_HOSTNAME}/g" /etc/hosts 2>/dev/null || true
fi

echo "=== Configuring ALSA default device (card ${ALSA_CARD}) ==="
cat > /etc/asound.conf <<EOF
# Managed by stereo-link install.sh — default playback device
defaults.pcm.card ${ALSA_CARD}
defaults.ctl.card ${ALSA_CARD}
EOF

echo "=== Enabling Pi audio (if present) ==="
for CONFIG in /boot/firmware/config.txt /boot/config.txt; do
  if [[ -f "${CONFIG}" ]] && ! grep -q '^dtparam=audio=on' "${CONFIG}"; then
    echo 'dtparam=audio=on' >> "${CONFIG}"
    echo "Enabled analog audio in ${CONFIG}"
  fi
done

if ! command -v librespot >/dev/null 2>&1 && [[ ! -f /etc/raspotify/conf ]]; then
  install_raspotify
else
  echo "Raspotify already installed, updating config only."
fi

mkdir -p /etc/raspotify
if [[ -f /etc/raspotify/conf ]]; then
  cp /etc/raspotify/conf "/etc/raspotify/conf.bak.$(date +%Y%m%d%H%M%S)"
fi

# Preserve any custom options; set the ones we need.
if [[ -f /etc/raspotify/conf ]]; then
  grep -v '^LIBRESPOT_NAME=' /etc/raspotify/conf | \
    grep -v '^LIBRESPOT_BACKEND=' | \
    grep -v '^LIBRESPOT_DEVICE_TYPE=' | \
    grep -v '^LIBRESPOT_BITRATE=' | \
    grep -v '^LIBRESPOT_INITIAL_VOLUME=' > /tmp/raspotify.conf.tmp || true
else
  : > /tmp/raspotify.conf.tmp
fi

cat >> /tmp/raspotify.conf.tmp <<EOF
LIBRESPOT_NAME="${SPEAKER_NAME}"
LIBRESPOT_BACKEND="pulseaudio"
LIBRESPOT_DEVICE_TYPE="speaker"
LIBRESPOT_BITRATE="320"
LIBRESPOT_INITIAL_VOLUME="50"
EOF
mv /tmp/raspotify.conf.tmp /etc/raspotify/conf

echo "=== Configuring shairport-sync (AirPlay) ==="
if [[ -f /etc/shairport-sync.conf ]]; then
  cp /etc/shairport-sync.conf "/etc/shairport-sync.conf.bak.$(date +%Y%m%d%H%M%S)"
fi

install -m 0644 "$(dirname "$0")/config/shairport-sync.conf" /etc/shairport-sync.conf
sed -i "s/@SPEAKER_NAME@/${SPEAKER_NAME}/g" /etc/shairport-sync.conf

echo "=== Configuring systemd overrides (auto-restart) ==="
mkdir -p /etc/systemd/system/shairport-sync.service.d
cat > /etc/systemd/system/shairport-sync.service.d/override.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=5
EOF

mkdir -p /etc/systemd/system/raspotify.service.d
cat > /etc/systemd/system/raspotify.service.d/override.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=5
EOF

echo "=== Enabling unattended security upgrades ==="
cat > /etc/apt/apt.conf.d/51unattended-upgrades-local <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
dpkg-reconfigure -f noninteractive unattended-upgrades 2>/dev/null || true

echo "=== Enabling and starting services ==="
systemctl daemon-reload
systemctl enable pipewire pipewire-pulse wireplumber avahi-daemon shairport-sync raspotify
systemctl restart avahi-daemon
systemctl restart pipewire pipewire-pulse wireplumber || true
sleep 2
systemctl restart shairport-sync
systemctl restart raspotify

echo ""
echo "=============================================="
echo " Installation complete"
echo "=============================================="
echo " Speaker name : ${SPEAKER_NAME}"
echo " Hostname     : ${NEW_HOSTNAME} (${NEW_HOSTNAME}.local)"
echo " ALSA card    : ${ALSA_CARD}"
echo ""
echo " Services:"
for svc in pipewire pipewire-pulse shairport-sync raspotify avahi-daemon; do
  printf "  %-18s %s\n" "${svc}" "$(systemctl is-active "${svc}" 2>/dev/null || echo unknown)"
done
echo ""
echo "Reboot recommended: sudo reboot"
echo "Then check AirPlay and Spotify Connect for \"${SPEAKER_NAME}\"."
