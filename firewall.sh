#!/bin/bash
set -e

echo "[*] Starte UFW/Docker-Firewall-Setup..."

# Root-Check
if [ "$EUID" -ne 0 ]; then
  echo "[!] Bitte als root ausführen (sudo $0)"
  exit 1
fi

# Minimaler Check: Debian/Ubuntu-ähnlich?
if ! command -v apt-get >/dev/null 2>&1; then
  echo "[!] Dieses Script ist für Debian/Ubuntu gedacht (apt-get nicht gefunden)."
  exit 1
fi

#######################################
# 1. Pakete installieren
#######################################

echo "[*] Installiere benötigte Pakete (ufw, wget)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ufw wget

#######################################
# 2. IPv6 für UFW deaktivieren
#######################################

UFW_DEFAULT="/etc/default/ufw"

if [ -f "$UFW_DEFAULT" ]; then
  echo "[*] Deaktiviere IPv6 in $UFW_DEFAULT ..."
  sed -i 's/^IPV6=.*/IPV6=no/' "$UFW_DEFAULT"
else
  echo "[!] $UFW_DEFAULT nicht gefunden, IPv6 kann nicht explizit deaktiviert werden."
fi

#######################################
# 3. UFW zurücksetzen und Basis-Policies setzen
#######################################

echo "[*] Setze UFW zurück und konfiguriere Basis-Regeln..."

# Alles zurücksetzen
ufw --force reset

# Standard-Policies
ufw default deny incoming      # alles eingehende blocken
ufw default deny routed       # weitergeleitete Pakete blocken (wichtig für Docker)
ufw default allow outgoing    # ausgehender Traffic erlaubt

# Loopback ist automatisch erlaubt, aber zur Sicherheit:
ufw allow in on lo

# SSH nicht vergessen, sonst sperrst du dich aus
ufw allow 22/tcp

#######################################
# 4. Ports für deine Dienste freigeben
#######################################

echo "[*] Erlaube benötigte Ports (Host-Sicht)..."

# HTTP / HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# HTTP/3 (QUIC)
ufw allow 443/udp

# NetBird Turn
ufw allow 3478/udp

#######################################
# 5. UFW aktivieren
#######################################

echo "[*] Aktiviere UFW..."
ufw --force enable

#######################################
# 6. ufw-docker installieren
#######################################

if ! command -v ufw-docker >/dev/null 2>&1; then
  echo "[*] Installiere ufw-docker Helper..."
  wget -4 -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
  chmod +x /usr/local/bin/ufw-docker
else
  echo "[*] ufw-docker ist bereits installiert."
fi

#######################################
# 7. ufw-docker in UFW integrieren
#######################################

echo "[*] Führe 'ufw-docker install' aus, um UFW korrekt vor Docker zu hängen..."
ufw-docker install

# UFW neu laden, damit Regeln aus /etc/ufw/after.rules aktiv werden
echo "[*] Starte UFW neu..."
systemctl restart ufw || ufw reload

#######################################
# 8. Docker-Traffic für deine Ports erlauben
#######################################
# Wichtig: Diese Regeln betreffen NAT/Forwarded Traffic zu Containern.
# Es wird davon ausgegangen, dass Container ihre Services auf denselben Ports
# exposen (z.B. '80:80', '443:443', '3478:3478', etc.)

echo "[*] Erlaube Docker-Traffic auf die relevanten Ports (ufw route)..."

# HTTP / HTTPS zu Containern (z.B. Caddy im Container)
ufw route allow proto tcp from any to any port 80
ufw route allow proto tcp from any to any port 443

# HTTP/3 / QUIC zu Containern
ufw route allow proto udp from any to any port 443

# NetBird Relay / STUN / TURN zu Containern
ufw route allow proto udp from any to any port 3478

echo
echo "[*] Fertig!"
echo "[*] Aktueller UFW-Status:"
ufw status verbose
echo
echo "[Hinweis]"
echo "- IPv6 ist für UFW deaktiviert, d.h. praktisch komplett geblockt."
echo "- Eingehend sind NUR diese Ports offen: 22/tcp, 80/tcp, 443/tcp, 443/udp, 3478/udp."
echo "- Docker ist über ufw-docker hinter UFW gehängt; 'ufw route allow' regelt den Zugriff auf Container."
