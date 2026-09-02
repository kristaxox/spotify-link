# Ubuntu Server Pi — AirPlay + Spotify Connect Setup

This guide turns a headless Raspberry Pi into a stereo streamer that shows up in AirPlay and Spotify Connect without ongoing maintenance.

## Architecture

```
Phone / Mac / iPad                Raspberry Pi (Ubuntu Server)
┌─────────────────┐              ┌──────────────────────────────┐
│  AirPlay        │─── mDNS ────▶│  shairport-sync              │
│  (Apple Music,  │              │         │                    │
│   Podcasts…)    │              │         ▼                    │
└─────────────────┘              │  PipeWire (audio mixer)        │
                                 │         │                    │
┌─────────────────┐              │         ▼                    │
│  Spotify app    │─── mDNS ────▶│  Raspotify (librespot)       │
│  (Connect)      │              │         │                    │
└─────────────────┘              │         ▼                    │
                                 │  ALSA → 3.5 mm / USB DAC     │
                                 └──────────────┬───────────────┘
                                                │ analog
                                                ▼
                                         Older stereo (AUX)
```

Both protocols use **mDNS** (Bonjour) for discovery. Ethernet keeps discovery reliable; Wi‑Fi works but is easier to drop under load.

## 1. Prepare Ubuntu Server on the Pi

### Flash and first boot

1. Download [Ubuntu Server for Raspberry Pi](https://ubuntu.com/download/raspberry-pi) (24.04 LTS recommended).
2. Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or `dd`.
3. During imaging (Imager advanced options), set:
   - Hostname, e.g. `stereo-link`
   - Username/password
   - **Enable SSH**
   - Configure Wi‑Fi only if you are not using Ethernet (Ethernet is preferred)
4. Insert the card, connect **Ethernet**, power on, and find the Pi:

```bash
# From another machine on the same LAN
ping stereo-link.local
ssh youruser@stereo-link.local
```

### Initial system update

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

## 2. Run the automated installer

On the Pi:

```bash
git clone <this-repo-url> stereo-link
cd stereo-link
sudo ./install.sh
```

The script will ask for:

| Prompt | Example | Used for |
|--------|---------|----------|
| Speaker name | `Living Room Stereo` | AirPlay + Spotify device name |
| Hostname | `stereo-link` | `stereo-link.local` on the network |
| Audio device | auto-detected | ALSA output (3.5 mm, USB DAC, HDMI) |

When it finishes, reboot:

```bash
sudo reboot
```

After reboot, open Spotify → speaker icon, or an Apple device → AirPlay menu. You should see your speaker name.

## 3. What the installer configures

### Services (all enabled for boot)

| Service | Role |
|---------|------|
| `pipewire` / `pipewire-pulse` | Audio routing; lets AirPlay and Spotify share one output |
| `shairport-sync` | AirPlay receiver |
| `raspotify` | Spotify Connect receiver |
| `avahi-daemon` | mDNS discovery |
| `unattended-upgrades` | Security updates without manual intervention |

### Resilience after power loss

Ubuntu Server boots automatically when power returns (no desktop “auto-login” needed). Every streaming service is:

- `enabled` — starts at boot
- `Restart=on-failure` — comes back if it crashes

No cron jobs or manual steps are required after a power cut.

### Optional: DHCP reservation

For the most stable discovery, reserve the Pi’s MAC address in your router so it always gets the same IP. mDNS (`stereo-link.local`) usually works without this, but a reservation avoids rare router quirks.

## 4. Manual installation (reference)

If you prefer to install by hand instead of using `install.sh`:

### Audio stack

```bash
sudo apt install -y alsa-utils pipewire pipewire-pulse wireplumber \
  avahi-daemon shairport-sync
```

### Raspotify (Spotify Connect)

```bash
curl -sL https://dtcooper.github.io/raspotify/install.sh | sh
```

Edit `/etc/raspotify/conf`:

```ini
LIBRESPOT_NAME="Living Room Stereo"
LIBRESPOT_BACKEND="pulseaudio"
LIBRESPOT_DEVICE_TYPE="speaker"
LIBRESPOT_BITRATE="320"
LIBRESPOT_INITIAL_VOLUME="50"
```

### shairport-sync (AirPlay)

Edit `/etc/shairport-sync.conf` (see `config/shairport-sync.conf` in this repo). Key settings:

```conf
general = {
  name = "Living Room Stereo";
  output_backend = "pa";   // PulseAudio / PipeWire
};

pa = {
  application_name = "Living Room Stereo";
};
```

Enable and start:

```bash
sudo systemctl enable --now pipewire pipewire-pulse shairport-sync raspotify avahi-daemon
```

## 5. Choosing audio output

List devices:

```bash
aplay -l
```

| Connection | Typical card | Notes |
|------------|--------------|-------|
| 3.5 mm jack (Pi 4) | `bcm2835 Headphones` | Built-in; acceptable quality |
| USB DAC | `USB Audio Device` | **Best** option for a stereo AUX input |
| HDMI | `vc4-hdmi` | Only if the stereo accepts HDMI audio somehow |

Set default in `/etc/asound.conf` (installer does this for you):

```conf
defaults.pcm.card 1
defaults.ctl.card 1
```

Replace `1` with your card number from `aplay -l`.

### Pi 3.5 mm jack on Pi 4 (if silent)

Uncomment in `/boot/firmware/config.txt` (path may be `/boot/config.txt` on older images):

```ini
dtparam=audio=on
```

Reboot after changing firmware config.

## 6. Verification checklist

```bash
# All services active
systemctl is-active pipewire pipewire-pulse shairport-sync raspotify avahi-daemon

# mDNS name resolves (from another machine)
avahi-resolve -n stereo-link.local

# Test speaker (should hear a short tone)
speaker-test -t wav -c 2 -l 1
```

On your phone:

1. **Spotify** → playing screen → devices → your speaker name
2. **iPhone** → Control Center → AirPlay → your speaker name

## 7. Troubleshooting

### Speaker not visible on the network

```bash
sudo systemctl status avahi-daemon shairport-sync raspotify
```

- Pi and phone must be on the **same subnet** (guest Wi‑Fi often blocks device-to-device traffic).
- Some routers isolate wireless clients; Ethernet on the Pi avoids most of this.
- Firewall: Ubuntu Server default `ufw` is usually inactive; if you enabled it, allow mDNS (UDP 5353) and don’t block local traffic.

### Spotify shows the speaker but won’t connect

- Spotify Connect requires **Premium**.
- Restart Raspotify: `sudo systemctl restart raspotify`

### AirPlay connects but no sound

- Check volume on the stereo and in Spotify/AirPlay.
- Confirm the correct ALSA card: `aplay -l` and `/etc/asound.conf`.
- Test: `speaker-test -t wav -c 2 -l 1`

### Only one of AirPlay / Spotify works at a time

Both services must use the **PulseAudio/PipeWire** backend, not raw ALSA. Re-run the installer or confirm:

- shairport-sync: `output_backend = "pa"`
- raspotify: `LIBRESPOT_BACKEND="pulseaudio"`

### Poor audio quality from 3.5 mm jack

Use a **USB DAC** (~$10–30). The Pi’s built-in DAC is fine for background music but a USB unit is noticeably cleaner into a proper stereo.

### View logs

```bash
journalctl -u shairport-sync -f
journalctl -u raspotify -f
journalctl -u pipewire -f
```

## 8. Security notes

- Keep SSH key-based login; disable password auth if exposed beyond your LAN.
- `unattended-upgrades` is enabled by the installer for security patches.
- Raspotify and shairport-sync are receive-only; they don’t open inbound ports from the internet unless you port-forward (don’t).

## 9. Changing the speaker name later

```bash
# Spotify
sudo sed -i 's/^LIBRESPOT_NAME=.*/LIBRESPOT_NAME="New Name"/' /etc/raspotify/conf
sudo systemctl restart raspotify

# AirPlay — edit name in /etc/shairport-sync.conf, then:
sudo systemctl restart shairport-sync
```

Or re-run `sudo ./install.sh` and enter a new name.
