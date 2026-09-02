# Stereo Link

Turn a Raspberry Pi running **Ubuntu Server** into a set-and-forget AirPlay and Spotify Connect speaker for an older stereo.

Plug the Pi into your network with Ethernet, connect analog audio to the stereo, run the installer once, and the speaker should appear automatically in AirPlay and Spotify after every boot — including after a power cut.

## Quick start

1. Flash [Ubuntu Server for Raspberry Pi](https://ubuntu.com/download/raspberry-pi) to a microSD card.
2. Boot the Pi with Ethernet connected and SSH into it.
3. Clone this repo and run the installer:

```bash
git clone https://github.com/YOUR_USER/spotify-link.git
cd spotify-link
sudo ./install.sh
```

4. Reboot when prompted. The speaker should show up as the name you chose in AirPlay and Spotify Connect.

## Requirements

- Raspberry Pi 3, 4, or 5 (Pi 4/5 recommended for AirPlay 2)
- Ubuntu Server 24.04 LTS (or 22.04 LTS) for Raspberry Pi
- Wired Ethernet (recommended for reliability)
- Audio out: 3.5 mm jack, HDMI, or USB DAC → stereo AUX input
- **Spotify Premium** (required for Spotify Connect; AirPlay works without Premium)

## What you get

- **AirPlay 1 & 2** via [shairport-sync](https://github.com/mikebrady/shairport-sync)
- **Spotify Connect** via [Raspotify](https://github.com/dtcooper/raspotify) (librespot)
- **ALSA dmix** audio mixing so both services can share one output on headless Ubuntu Server
- **systemd** services that start on boot and restart on failure
- **Avahi/mDNS** so devices discover the speaker automatically on the LAN

## Documentation

See [SETUP.md](SETUP.md) for the full walkthrough, troubleshooting, and manual configuration.
