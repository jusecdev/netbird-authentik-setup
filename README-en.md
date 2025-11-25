<p align="right">
  🌐 <strong>English</strong> | <a href="README.md">Deutsch</a>
</p>

# 🛡️ NetBird + Authentik + Caddy #

Self-Hosted Zero-Trust Networking – All on a Single Host
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
# 📘 Full Guide #
The full documentation is available here:

👉 [Full article (German)](https://jusec.me/netbird-authentik)￼

---
# 🚀 Overview #

This repository automates the setup of:
- 🔐 NetBird – Zero-Trust VPN
- 👤 Authentik – Identity Provider (OIDC)
- 🔁 Caddy – Reverse Proxy with automatic TLS
- ⚙️ Automated setup scripts
- 🔒 Optional firewall hardening
- 🧩 Everything runs on a single host

---
# 📂 Repository Structure #
````
/
├── caddy/
├── authentik/
├── netbird/
├── firewall.sh
└── README-en.md
````

---
# 🧠 Quick Start
1.	Clone repository
````
git clone https://github.com/jusecdev/netbird-authentik-setup.git
cd netbird-authentik-setup
````
2.	Install & configure Caddy

3.	Set up Authentik
````
sudo bash authentik-init.sh
````
4.	Configure & start NetBird

5.	Optionally enable firewall
````
sudo bash firewall.sh
````

---
# 🛠️ Requirements #
- Publicly reachable server
- Domain + DNS records
- Docker & Docker Compose

---
# 🔒 Firewall Hardening #
````
sudo bash firewall.sh
````
---
# ⭐ Support

If this project helped you:
⭐ Give the repo a star!

---
# 📜 License

MIT License