# Cal.com Self-Hosted Setup — Mac mini

## Overview

Cal.com runs in Docker (via Colima) on the Mac mini, exposed publicly via the existing
Cloudflare Tunnel. No ports are opened on the router; SSL is handled by Cloudflare.

**URL:** https://cal.elladali.com  
**Stack:** Cal.com (amd64/Rosetta) + Postgres 15 + Cloudflare Tunnel  
**Project dir:** `~/git_projects/cal/`

---

## Architecture

```
Internet → Cloudflare (cal.elladali.com CNAME → tunnel)
         → cloudflared tunnel c2d88bb4-7d4a-4a52-a9d3-b2b0cd2aa6fd
         → localhost:3000
         → calcom container (Docker via Colima)
         → db container (Postgres 15)
```

---

## Steps Performed

### 1. Fix Colima sudo ownership
```bash
sudo brew services stop colima
sudo chown -R liang:admin /opt/homebrew/Cellar/colima /opt/homebrew/opt/colima /opt/homebrew/var/homebrew/linked/colima
```

### 2. Resize Colima (2 CPU/2 GB → 6 CPU/8 GB)
```bash
colima stop
colima start --cpu 6 --memory 8 --disk 100
```

### 3. Create docker-compose.yml and .env
- `~/git_projects/cal/docker-compose.yml` — Cal.com + Postgres services
- `~/git_projects/cal/.env` — NEXTAUTH_SECRET (keep secret)
- Cal.com image forced to `platform: linux/amd64` (runs via Rosetta — no ARM64 image available)
- Added required Cal.com env vars in compose:
    - `DATABASE_DIRECT_URL=postgresql://calcom:calpass2026@db:5432/calcom`
    - `CALENDSO_ENCRYPTION_KEY=<32-byte-random-hex>`
- Postgres exposes port 5432 only inside Docker network
- Cal.com binds to `127.0.0.1:3000` only (not exposed to LAN)

### 4. Update cloudflared config
File: `~/.cloudflared/config.yml`  
Added ingress rule: `cal.elladali.com → http://localhost:3000`
```bash
brew services restart cloudflared
```

Important runtime note:
- Homebrew service currently starts `cloudflared` without `tunnel run`, so it exits with code 1.
- Working command used to keep tunnel active:
```bash
cloudflared tunnel --config ~/.cloudflared/config.yml run c2d88bb4-7d4a-4a52-a9d3-b2b0cd2aa6fd
```

### 5. Create Cloudflare DNS record
CNAME `cal.elladali.com` → `c2d88bb4-7d4a-4a52-a9d3-b2b0cd2aa6fd.cfargotunnel.com` (proxied)
Created via Cloudflare API.

### 6. Start containers
```bash
cd ~/git_projects/cal
docker compose up -d
```

### 7. First-run setup
Visit https://cal.elladali.com → create admin account on first load.

---

## Day-to-day Operations

```bash
# Status
cd ~/git_projects/cal && docker compose ps

# Logs
docker compose logs -f calcom

# Quick local and public health checks
curl -I http://127.0.0.1:3000
curl -I https://cal.elladali.com

# Update Cal.com
docker compose pull && docker compose up -d

# Stop
docker compose down

# Stop + remove data (destructive)
docker compose down -v
```

## Auto-start on Mac boot

Colima must be running for Docker to work. Start it as your user at login:
```bash
brew services start colima   # runs as liang, starts at login
```
Then docker-compose containers use `restart: unless-stopped` — they auto-start when Colima starts.

---

## Notes

- Colima profile: `default`, 6 CPU, 8 GB RAM, 100 GB disk
- Cal.com image is amd64-only; runs under Rosetta 2 emulation inside Colima
- DB credentials: user=calcom, pass=calpass2026, db=calcom (internal only)
- NEXTAUTH_SECRET is in `~/git_projects/cal/.env` — do not commit to git
- Cal.com and Postgres both validated as healthy in Docker (`docker compose ps`)
- Local and public endpoint checks returned HTTP 307 (expected redirect behavior)
