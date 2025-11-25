<p align="right">
  🌐 <a href="README-en.md">English</a> | <strong>Deutsch</strong>
</p>

# 🛡️ NetBird + Authentik + Caddy #

Self-Hosted Zero-Trust Networking – Alles auf einem Host
<p align="center">
  <a href="https://github.com/jusecdev/netbird-authentik-setup/stargazers">
    <img src="https://img.shields.io/github/stars/jusecdev/netbird-authentik-setup?style=flat-square" />
  </a>
  <a href="https://github.com/jusecdev/netbird-authentik-setup/issues">
    <img src="https://img.shields.io/github/issues/jusecdev/netbird-authentik-setup?style=flat-square" />
  </a>
  <img src="https://img.shields.io/badge/Docker-Ready-blue?style=flat-square&logo=docker" />
  <img src="https://img.shields.io/badge/Authentik-OIDC-green?style=flat-square" />
  <img src="https://img.shields.io/badge/Caddy-Automatic%20TLS-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square" />
</p>

---
# 📘 Vollständige Anleitung #

Die komplette Dokumentation findest du hier:

👉 [Zum vollständigen Artikel](https://jusec.me/netbird-authentik)￼

---
# 🚀 Überblick #

Dieses Repository automatisiert das Setup von:

- 🔐 NetBird – Zero-Trust VPN
- 👤 Authentik – Identity Provider (OIDC)
- 🔁 Caddy – Reverse-Proxy mit automatischem TLS
- ⚙️ Automatische Setup-Skripte
- 🔒 Optionale Firewall-Härtung
- 🧩 Ein Host reicht völlig aus

---
# 📂 Repository-Struktur #
```
/
├── caddy/
├── authentik/
├── netbird/
├── firewall.sh
└── README.md
```
---
# 🧠 Schnellstart #
1. Repository klonen
```
git clone https://github.com/jusecdev/netbird-authentik-setup.git
cd netbird-authentik-setup
```
2. Caddy installieren & konfigurieren
3. Authentik einrichten
````
sudo bash authentik-init.sh
````
4.	NetBird konfigurieren & starten
5.	Optional Firewall aktivieren
```
sudo bash firewall.sh
```
---
# 🛠️ Voraussetzungen #
- Öffentlich erreichbarer Server
- Domain + DNS Einträge
- Docker & Docker Compose

---
# 🔒 Firewall-Härtung #
```
sudo bash firewall.sh
```
---
# ⭐ Unterstützen #

Wenn dir dieses Projekt geholfen hat:
⭐ Gib dem Repo einen Stern!

---
# 📜 Lizenz #

MIT-Lizenz
