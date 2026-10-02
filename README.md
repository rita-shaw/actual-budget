# Actual Budget Server

Installed and running on rita.shaw (OpenClaw server).

- **Version:** v26.5.2
- **Port:** 5006
- **Data:** `/home/biscuit/.openclaw/workspace/actual-budget/data`
- **Config:** `config.json`
- **Service:** `actual-budget.service` (systemd, enabled for auto-start)

## URLs

- Local: http://rita.shaw:5006
- Public: http://159.54.167.172:5006

## Management

```bash
sudo systemctl status actual-budget.service  # check status
sudo systemctl restart actual-budget.service  # restart
sudo systemctl stop actual-budget.service     # stop
```

## Update

```bash
corepack yarn add --exact '@actual-app/sync-server@VERSION'
sudo systemctl restart actual-budget.service
```

Replace `VERSION` with the release to install. Back up the existing data directory
before upgrading; server startup can run database migrations. Keep `package.json`
and `yarn.lock` together when saving dependency updates.

## Installation

With Node.js 22 or newer and Corepack available, run `./setup.sh` to install
the pinned server from `yarn.lock` with Yarn (via Corepack).
The service uses NVM's `default` Node alias and runs `yarn start:server`.
To run manually from this directory, use `corepack yarn start:server`.

```bash
sudo install -m 644 actual-budget.service /etc/systemd/system/actual-budget.service
sudo systemctl daemon-reload
sudo systemctl enable actual-budget.service
sudo systemctl restart actual-budget.service
```

The unit runs as `biscuit` from `/home/biscuit/configs/actual-budget`. It starts
after `network.target`, launches
`/home/biscuit/.config/nvm/nvm-exec corepack yarn start:server`, and restarts
after failures with a five-second delay. `multi-user.target` starts it at boot.
The complete unit is:

```ini
[Unit]
Description=Actual Budget Server
After=network.target

[Service]
Type=exec
User=biscuit
WorkingDirectory=/home/biscuit/configs/actual-budget
Environment=NODE_VERSION=default
Environment=COREPACK_HOME=/home/biscuit/configs/actual-budget/.cache/corepack
ExecStart=/home/biscuit/.config/nvm/nvm-exec corepack yarn start:server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

`actual-budget.service` is the installable copy of this unit.

## Dependencies and runtime

- `package.json` pins `@actual-app/sync-server` to 26.5.2 and Yarn to 1.22.22;
  `yarn.lock` records the resolved dependency versions.
- `node_modules/` contains the local server installation. `./setup.sh` delegates
  to `scripts/setup.sh`, which installs with `--frozen-lockfile`.
- NVM is required at `/home/biscuit/.config/nvm`. The service runs as `biscuit`
  from `/home/biscuit/configs/actual-budget` and selects NVM's `default` alias.
  Corepack must be installed in that selected Node environment. Global npm
  packages are specific to a Node installation; check Corepack after switching Node.
- Setup and systemd store downloaded Yarn releases in `.cache/corepack/`.
  `node_modules/` and `.cache/` are ignored by Git and can be recreated by setup.
- The server includes a native SQLite dependency. If changing Node causes a
  native-module compatibility error, rebuild dependencies with the selected Node
  before restarting the service.
- The tracked unit is installed into `/etc/systemd/system/actual-budget.service`.
  After editing it, repeat the install and daemon-reload commands above, then
  restart. It restarts on failure after five seconds.

## Cloudflare Tunnel

Cloudflared is managed separately by `cloudflared.service`, using
`/etc/cloudflared/config.yml` and a credentials file outside this repository.
The intended route is `budget.badmath.org` to `http://127.0.0.1:5006`.
At the last check, that route was commented out and the active fallback returned
404. Enabling it requires updating the external config and restarting cloudflared.

Actual binds to `0.0.0.0:5006`, so it also accepts direct connections where the
host firewall permits them. Cloudflared connects to its local HTTP listener.

## Verification

```bash
sudo systemctl status actual-budget.service
sudo journalctl -u actual-budget.service -n 30 --no-pager
curl --fail http://127.0.0.1:5006/
cloudflared tunnel --config /etc/cloudflared/config.yml ingress rule https://budget.badmath.org
```
