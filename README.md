<div align="center">

# 🔍 IP Lookup

**A fast CLI tool for IP geolocation and DNS lookups — one command instead of juggling whois, dig, and geoIP sites during an incident.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

</div>

---

## 🎯 The Problem

Mid-incident, jumping between `whois`, `dig`, and a browser tab for geoIP wastes time you don't have.

## ✨ The Solution

One command, all the answers: country, region, city, ISP, ASN, and a direct Google Maps link — with caching so repeat lookups on the same IP are instant.

## 🚀 Features

- 🌍 **Full lookup in one call** — country, region, city, lat/long, ISP, ASN
- 🗺️ **Maps link generated automatically**
- 💾 **Local caching** — repeat lookups skip the API entirely
- 📂 **Bulk mode** — feed it a file of IPs/domains
- 🔁 **Automatic retry** — handles API rate limits gracefully

## 📋 Requirements

```
✓ Bash
✓ curl
✓ jq
```

## 🎮 Usage

```bash
git clone https://github.com/Nextera-Matt/ip-lookup.git
cd ip-lookup
chmod +x iplookup.sh

# Single lookup
./iplookup.sh 8.8.8.8

# Bulk lookup from a file
./iplookup.sh --file ips.txt

# Clear the cache
./iplookup.sh --clear-cache
```

## 🛠️ Stack

<p align="center">
  <img src="https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" />
  <img src="https://img.shields.io/badge/ip--api-000000?style=for-the-badge" />
</p>

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file.

## 📬 Support

<div align="center">

[![GitHub Issues](https://img.shields.io/github/issues/Nextera-Matt/ip-lookup)](https://github.com/Nextera-Matt/ip-lookup/issues)

[Open an Issue](https://github.com/Nextera-Matt/ip-lookup/issues) • [Visit Portfolio](https://matthodges.uk)

</div>

---

<div align="center">

**Made by [Matt Hodges](https://matthodges.uk)**

</div>
