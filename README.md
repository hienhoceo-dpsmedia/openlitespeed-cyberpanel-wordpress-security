# 🛡️ WordPress Security with OpenLiteSpeed on CyberPanel

<div align="center">

[![Security](https://img.shields.io/badge/Security-Hardening-green?style=for-the-badge&logo=security)](https://github.com/your-username/openlitespeed-cyberpanel-wordpress-security)
[![WordPress](https://img.shields.io/badge/WordPress-Protection-blue?style=for-the-badge&logo=wordpress)](https://wordpress.org)
[![OpenLiteSpeed](https://img.shields.io/badge/OpenLiteSpeed-Web%20Server-007A5A?style=for-the-badge&logo=litespeed)](https://openlitespeed.org)
[![CyberPanel](https://img.shields.io/badge/CyberPanel-Hosting%20Panel-FF6B35?style=for-the-badge&logo=cyberpanel)](https://cyberpanel.net)
[![License](https://img.shields.io/badge/License-MIT-purple?style=for-the-badge)](LICENSE)

**🚀 One-command WordPress security hardening for CyberPanel servers**

Protects WordPress sites at the OpenLiteSpeed level. Copy-paste friendly with no prior webserver knowledge required.

[⭐ **Give us a star**](https://github.com/your-username/openlitespeed-cyberpanel-wordpress-security) if this helps you!

</div>

## 🚀 Quick Start

```bash
# Install security for all WordPress sites
wget -qO- https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/install-direct.sh | sudo bash

# Test protections
wget -qO- https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/scripts/test-security.sh | bash -s your-domain.com
```

**Expected Results:**
- ✅ PHP execution in uploads → **HTTP 403 Forbidden**
- ✅ wp-config.php access → **HTTP 403 Forbidden**
- ✅ xmlrpc.php access → **HTTP 403 Forbidden**
- ✅ Normal pages → **HTTP 200 OK**

## 🛡️ What This Protects Against

| Protection | Files/Paths Blocked | Risk Level |
|------------|-------------------|-----------|
| **Config Files** | `wp-config.php`, `.env`, `xmlrpc.php` | 🔴 High |
| **Upload Security** | `*.php` in `/wp-content/uploads/` | 🔴 High |
| **Backup Files** | `*.bak`, `*.sql`, `*.tar.gz` | 🟡 Medium |
| **Known Exploits** | `timthumb.php`, `webshell.php` | 🔴 High |
| **Attack Patterns** | SQL injection, XSS patterns | 🔴 High |

**Total Coverage:** 20+ attack vectors blocked at webserver level

## ✨ Key Features

- 🛡️ **Comprehensive Protection** - Blocks PHP execution, sensitive files, backup files
- 🚫 **Request Validation** - Rejects bad HTTP verbs, spam referers, malicious bots
- 🚀 **One-Command Setup** - Install for all sites with single command
- 🔄 **Auto Updates** - Nightly cron protects new websites automatically
- ✅ **Built-in Testing** - Comprehensive security test scripts included
- 🔧 **CyberPanel Optimized** - Designed for CyberPanel directory structure
- 📊 **Progress Tracking** - Visual indicators during installation
- 🗂️ **Smart Backups** - Automatic backups before any changes

## 🚀 CyberPanel Directory Structure

This tool is designed for CyberPanel's standard layout:
```
/home/
├── domain.com/
│   ├── public_html/           # WordPress document root
│   ├── logs/                  # Site logs
│   └── etc/                   # Site-specific configs
```

## ⚡ Quick Reference

- Install everywhere:
  `wget -qO- https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/install-direct.sh | sudo bash`
- Run security verification:
  `wget -qO- https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/scripts/test-security.sh | bash -s your-domain.com`
- Uninstall (removes all includes + cron):
  ```bash
  curl -fsSL -o /tmp/wpsec-uninstall.sh \
    https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/scripts/uninstall.sh
  sudo bash /tmp/wpsec-uninstall.sh
  ```

## 📋 How It Works

- **Apache-compatible rules** that work with OpenLiteSpeed's rewrite engine
- **VirtualHost-level includes** that inject security rules into all WordPress sites
- **Request filtering** before PHP processing for maximum protection
- **Comprehensive testing** to verify all protection layers work correctly

## 🛠️ Manual Installation

If you prefer to clone first:

```bash
git clone https://github.com/your-username/openlitespeed-cyberpanel-wordpress-security.git
cd openlitespeed-cyberpanel-wordpress-security
sudo ./scripts/install.sh
```

## 🔧 Repository Structure

```
openlitespeed-cyberpanel-wordpress-security/
├── README.md                                    # This file
├── install-direct.sh                           # 🚀 1-command setup script (recommended)
├── configs/
│   └── wordpress-security.conf                 # Apache-compatible security rules
└── scripts/
    ├── install.sh                              # Automated installation script
    ├── update-vhosts-cyberpanel.sh            # Nightly CyberPanel vhost refresher
    ├── uninstall.sh                            # Automated uninstallation script
    └── test-security.sh                        # Comprehensive security testing
```

## 🔍 Testing Your Installation

After installation, run the security test suite:

```bash
# Basic test
wget -qO- https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/scripts/test-security.sh | bash -s your-domain.com

# Verbose test with detailed output
wget -qO- https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/scripts/test-security.sh | bash -s your-domain.com --verbose

# Test bypassing CDN
wget -qO- https://raw.githubusercontent.com/your-username/openlitespeed-cyberpanel-wordpress-security/master/scripts/test-security.sh | bash -s your-domain.com --skip-cdn
```

## 📊 Security Impact

| Protection Type | Files/Paths Blocked | Risk Mitigation |
|-----------------|-------------------|-----------------|
| **Config Files** | `wp-config.php`, `.env`, `xmlrpc.php` | 🔴 High - Prevents credential exposure |
| **Upload Security** | `*.php` in `/wp-content/uploads/` | 🔴 High - Stops shell uploads |
| **Backup Files** | `*.bak`, `*.sql`, `*.tar.gz` | 🟡 Medium - Prevents data leaks |
| **Development Files** | `readme.html`, `license.txt` | 🟢 Low - Reduces information disclosure |
| **Known Exploits** | `timthumb.php`, `webshell.php` | 🔴 High - Blocks common attacks |
| **Attack Patterns** | SQL injection, XSS patterns | 🔴 High - Filters malicious requests |

**🛡️ Total Coverage:** 20+ attack vectors blocked at the webserver level

## 🚨 Important Notes

- **Backup Safety**: The script automatically creates backups before modifying any files
- **Gradual Rollout**: Sites are updated individually to prevent issues
- **OpenLiteSpeed Compatibility**: All rules are Apache-compatible and tested with OpenLiteSpeed
- **CyberPanel Integration**: Works seamlessly with CyberPanel's management system

## 📄 License

MIT License - feel free to use and modify for your needs.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and enhancement requests:

- 🐛 **Bug Reports** - Found an issue? Please open an issue with details
- 💡 **Feature Requests** - Have an idea? We'd love to hear it
- 📚 **Documentation** - Help improve the guides and explanations
- 🔒 **Security** - Found a vulnerability? Please report responsibly

## 🔧 Repository Topics

**Recommended GitHub Topics for this repository:**
```
wordpress-security, openlitespeed, cyberpanel, web-security, wordpress, security-hardening,
server-security, php-security, web-server, litespeed-configuration, wordpress-protection,
cybersecurity, security-tools, web-hardening, server-hardening, penetration-testing,
security-audit, wordpress-hardening, litespeed-security, hosting-security
```

---

<div align="center">

**⭐ If this project helps secure your WordPress sites, please give it a star!**

Made with ❤️ for the WordPress community

[🔝 Back to top](#-wordpress-security-with-openlitespeed-on-cyberpanel)

</div>