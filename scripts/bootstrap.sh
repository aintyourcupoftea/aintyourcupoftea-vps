#!/usr/bin/env bash
# Idempotent setup of a small VPS as a lightweight Docker Compose host.
# Supports Ubuntu/Debian (apt) and Oracle Linux/RHEL-likes (dnf).
# Usage (as the login user, needs sudo):  bash bootstrap.sh
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-$(id -un)}"
APPS_DIR="${APPS_DIR:-/opt/apps}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

log() { printf '\n==> %s\n' "$*"; }

if command -v apt-get >/dev/null; then PM=apt; elif command -v dnf >/dev/null; then PM=dnf; else
  echo "Unsupported distro (need apt or dnf)"; exit 1; fi

log "Updating packages ($PM)"
if [ "$PM" = apt ]; then
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y
  $SUDO apt-get upgrade -y
  $SUDO apt-get install -y ca-certificates curl git rsync unattended-upgrades iptables-persistent
  $SUDO dpkg-reconfigure -f noninteractive unattended-upgrades || true
else
  $SUDO dnf -y upgrade
  $SUDO dnf -y install ca-certificates curl git rsync dnf-automatic
  $SUDO systemctl enable --now dnf-automatic-install.timer || true
fi

log "Installing Docker Engine + Compose plugin"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | $SUDO sh
fi
$SUDO mkdir -p /etc/docker
# Log rotation keeps disk use small; live-restore keeps containers up across daemon restarts.
$SUDO tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
JSON
$SUDO systemctl enable docker
$SUDO systemctl restart docker
$SUDO usermod -aG docker "$DEPLOY_USER"
docker_cmd() { $SUDO docker "$@"; }
docker_cmd compose version

log "Shared 'web' network for the reverse proxy"
docker_cmd network inspect web >/dev/null 2>&1 || docker_cmd network create web

log "Apps directory at $APPS_DIR"
$SUDO mkdir -p "$APPS_DIR"
$SUDO chown "$DEPLOY_USER":"$DEPLOY_USER" "$APPS_DIR"

log "Swap ($SWAP_SIZE) if none exists"
if ! $SUDO swapon --show | grep -q .; then
  $SUDO fallocate -l "$SWAP_SIZE" /swapfile || $SUDO dd if=/dev/zero of=/swapfile bs=1M count=2048
  $SUDO chmod 600 /swapfile
  $SUDO mkswap /swapfile
  $SUDO swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab
  echo 'vm.swappiness=10' | $SUDO tee /etc/sysctl.d/99-swappiness.conf
  $SUDO sysctl --system >/dev/null
fi

log "Opening HTTP/HTTPS in the host firewall"
# Oracle Cloud images ship iptables rules that REJECT everything except 22.
if command -v firewall-cmd >/dev/null && $SUDO firewall-cmd --state >/dev/null 2>&1; then
  $SUDO firewall-cmd --permanent --add-service=http --add-service=https
  $SUDO firewall-cmd --permanent --add-port=443/udp
  $SUDO firewall-cmd --reload
elif command -v iptables >/dev/null; then
  for rule in "tcp 80" "tcp 443" "udp 443"; do
    set -- $rule
    $SUDO iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null \
      || $SUDO iptables -I INPUT 5 -p "$1" --dport "$2" -j ACCEPT 2>/dev/null \
      || $SUDO iptables -I INPUT -p "$1" --dport "$2" -j ACCEPT
  done
  command -v netfilter-persistent >/dev/null && $SUDO netfilter-persistent save || true
fi

log "SSH hardening (keys only)"
$SUDO tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
CONF
$SUDO sshd -t && ($SUDO systemctl reload ssh 2>/dev/null || $SUDO systemctl reload sshd)

log "Weekly Docker cleanup"
$SUDO tee /etc/cron.weekly/docker-prune >/dev/null <<'CRON'
#!/bin/sh
docker system prune -af --filter "until=168h" >/dev/null 2>&1
CRON
$SUDO chmod +x /etc/cron.weekly/docker-prune

log "Done. Log out and back in so '$DEPLOY_USER' can run docker without sudo."
docker_cmd --version
