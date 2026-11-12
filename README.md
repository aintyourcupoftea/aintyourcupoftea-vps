# aintyourcupoftea-vps

Lightweight Docker Compose hosting for the VPS at `92.4.74.185`.

```
scripts/bootstrap.sh   one-time, idempotent server setup
scripts/deploy.sh      rsync a stack to /opt/apps/<stack> and `docker compose up -d`
stacks/proxy/          Caddy reverse proxy (automatic HTTPS) on the shared `web` network
stacks/whoami/         tiny example app; delete once you have a real one
.github/workflows/     deploys on push to main (stacks/**) or on demand
```

## What bootstrap does

- Updates the OS and turns on automatic security updates
- Installs Docker Engine and the Compose plugin, with log rotation (10 MB × 3) and `live-restore`
- Adds the login user to the `docker` group and creates `/opt/apps`
- Adds a 2 GB swap file if the server has none (useful on 1 GB instances)
- Opens 80/443 in the host firewall. Oracle Cloud images block every port except 22 here.
- Allows SSH with keys only
- Prunes old Docker images and containers weekly
- Creates the external `web` network that the proxy and apps share

## Option A: run from your machine

```bash
ssh -i ~/.ssh/vps_key ubuntu@92.4.74.185 'bash -s' < scripts/bootstrap.sh
VPS=ubuntu@92.4.74.185 SSH_KEY=~/.ssh/vps_key scripts/deploy.sh proxy
VPS=ubuntu@92.4.74.185 SSH_KEY=~/.ssh/vps_key scripts/deploy.sh whoami
curl http://92.4.74.185/
```

On Oracle Linux, the login user is `opc` instead of `ubuntu`.

## Option B: GitHub Actions

Add these repository secrets (Settings → Secrets and variables → Actions):

| Secret        | Value                                 |
|---------------|---------------------------------------|
| `VPS_HOST`    | `92.4.74.185`                         |
| `VPS_USER`    | `ubuntu` (or `opc`)                   |
| `VPS_SSH_KEY` | full contents of the private key file |

Then go to Actions → Deploy → Run workflow and tick **bootstrap**. After that, every push to `main` that changes `stacks/**` redeploys.

## Cloud firewall

You also need to allow TCP 80 and 443 (and UDP 443 for HTTP/3) in the provider's firewall. On Oracle Cloud this is the subnet's Security List or an NSG.

## Adding an app

1. Create `stacks/myapp/compose.yaml` and attach the service to the external `web` network. Don't publish ports.
2. Add `myapp.example.com { reverse_proxy myapp:3000 }` to `stacks/proxy/Caddyfile`.
3. Deploy `myapp` and `proxy`.

Keep secrets in `/opt/apps/<stack>/.env` on the server. Deploys never sync or overwrite `.env`.
