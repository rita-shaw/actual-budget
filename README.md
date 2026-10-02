# Actual Budget Server

Configuration and operational notes for the Actual sync server
(`@actual-app/sync-server`).

This repository documents **two independent deployments**. They are separate
installations with separate data directories and therefore **separate budget
datasets** — they do not sync with each other, and nothing in this repository
replicates data between them. Point a given client at one host only.

## Hosts at a glance

| | `rita.shaw` | `spaceforce` |
|---|---|---|
| Platform | Linux (OpenClaw server) | macOS 15.7.9 (24G830), x86_64 |
| Init system | systemd, system-wide | launchd, **per-user LaunchAgent** |
| Starts at | boot (`multi-user.target`) | user login |
| Server version | 26.5.2 | 26.7.0 |
| Install method | Yarn + `yarn.lock` (tracked here) | global npm install |
| Repo checkout | `/home/biscuit/configs/actual-budget` | none — host is not a checkout |
| Listen address | `0.0.0.0:5006` | `0.0.0.0:5006` |
| Data directory | `/home/biscuit/.openclaw/workspace/actual-budget/data` | `/Users/biscuit/actual-budget-server/data` |
| Public hostname | none | `budget.badmath.org` via Cloudflare Tunnel |

The tracked files in this repository (`config.json`, `package.json`,
`yarn.lock`, `setup.sh`, `scripts/setup.sh`, `actual-budget.service`) all belong
to the `rita.shaw` deployment. The `spaceforce` deployment is documented inline
below rather than tracked as files, matching how the systemd unit is also
reproduced inline.

## Public access and Cloudflare Tunnel

`budget.badmath.org` resolves to the **`spaceforce`** host through a named
Cloudflare Tunnel called `spaceforce`. The `badmath.org` zone is on Cloudflare
nameservers (`annalise.ns.cloudflare.com`, `roan.ns.cloudflare.com`).

- Tunnel name: `spaceforce`
- Tunnel ID: `<TUNNEL_ID>`  (see "Placeholders" below)
- Ingress: `budget.badmath.org` to `http://127.0.0.1:5006`, catch-all returns 404
- Credentials: `/Users/biscuit/.cloudflared/<TUNNEL_ID>.json` (not in this repo)
- Account certificate: `/Users/biscuit/.cloudflared/cert.pem` (not in this repo)
- Config: `/Users/biscuit/.cloudflared/config.yml`

DNS is a proxied `CNAME` from `budget.badmath.org` to
`<TUNNEL_ID>.cfargotunnel.com`, created by
`cloudflared tunnel route dns spaceforce budget.badmath.org`. Because the record is
proxied, public resolvers return Cloudflare edge addresses
(`104.21.47.189`, `172.67.150.144`, TTL 300) rather than the `CNAME` target.

On the `spaceforce` LAN the configured resolver is the LAN router (`<LAN_RESOLVER>`), and
it may serve a cached `NXDOMAIN` for a newly created hostname while the apex and
unrelated names resolve normally. That is negative caching, not a zone problem —
confirm against authority and bypass the cache to test:

```bash
dig @annalise.ns.cloudflare.com +short budget.badmath.org   # ground truth
dig @1.1.1.1 +short budget.badmath.org
curl -sS --resolve budget.badmath.org:443:104.21.47.189 https://budget.badmath.org/info
```

### Placeholders

This repository is public, so host-specific identifiers are written as
placeholders. Resolve them on the host rather than storing them here:

| Placeholder | Where to read the real value |
|---|---|
| `<TUNNEL_ID>` | `cloudflared tunnel list`, or the `tunnel:` key in `~/.cloudflared/config.yml` |
| `<ACCESS_AUD>` | Zero Trust dashboard (Access > Applications), or the `aud` claim in the `302` redirect from the hostname |
| `<LAN_RESOLVER>` | `scutil --dns \| awk '/nameserver\[0\]/{print $3; exit}'` on macOS |

Credentials are never in this repository: the tunnel credentials JSON and the
account `cert.pem` live only in `~/.cloudflared/` on the host, mode `600`.

### Hostname ownership conflict

`rita.shaw` runs its own cloudflared under `cloudflared.service` with
`/etc/cloudflared/config.yml`, and that config **also names
`budget.badmath.org`** mapped to its own `http://127.0.0.1:5006`. That route was
commented out, with an active fallback returning 404, and no DNS record existed
for the hostname before the `spaceforce` tunnel claimed it.

Leave it commented out. If both tunnels advertise the same hostname, Cloudflare
balances requests across them and clients will be served two divergent budget
datasets at random. Only one host may own `budget.badmath.org` at a time.

### Direct exposure

Both hosts bind Actual to `0.0.0.0:5006`, so each also accepts direct
connections wherever the host firewall permits. On `rita.shaw` that has
historically meant `http://159.54.167.172:5006` — plaintext HTTP, so the Actual
password and all budget data traverse the network unencrypted. Prefer the
tunnel, which terminates TLS at Cloudflare. Narrowing either host's `hostname`
to `127.0.0.1` closes direct access and leaves the tunnel as the only ingress;
cloudflared connects to the local listener and is unaffected.

### Cloudflare Access

`budget.badmath.org` sits behind a **Cloudflare Access application** that was
already in place when the tunnel was created — it was not configured as part of
this tunnel setup. Unauthenticated requests never reach the tunnel; the edge
answers `302` to the team login page with
`www-authenticate: Cloudflare-Access`:

- Team domain: `badmath.cloudflareaccess.com`
- Application `aud`: `<ACCESS_AUD>`
- Resource metadata: `https://budget.badmath.org/.well-known/cloudflare-access-protected-resource/`

Confirm the challenge and inspect it without a browser:

```bash
curl -sSI https://budget.badmath.org/ | grep -iE 'HTTP|location|www-authenticate'
cloudflared access login https://budget.badmath.org   # interactive browser SSO
cloudflared access curl  https://budget.badmath.org/info
```

The application's scope could not be enumerated from this host — doing so needs
a Cloudflare API token, and none is configured here. It may well be a wildcard
covering `*.badmath.org`, in which case **editing or removing it affects the
other tunnels in this account** (`badglen`, `carnac`, `hivemind`, `rita`,
`studio`). Check the scope in the Zero Trust dashboard before changing it.

#### Effect on Actual clients

Access gates the browser session, which is additive to Actual's own server
password. Two consequences:

- **Browser use works.** After SSO the `CF_Authorization` cookie is set for the
  hostname, and the web app's same-origin requests carry it. The Actual password
  prompt then applies as usual.
- **Native Actual clients (desktop app, iOS, Android) will fail to sync.** They
  authenticate with the server password over HTTP and cannot complete an
  interactive SSO flow, so they receive the `302` and never reach the server.
  Access service tokens do not help, because the Actual clients provide no way
  to send `CF-Access-Client-Id`/`CF-Access-Client-Secret` headers.

If native clients are required, the options are an Access **Bypass** policy for
this hostname (which reduces protection to the Actual password alone), or
enrolling the client devices in WARP and gating on device posture instead of
interactive SSO.

## `rita.shaw` — Linux, systemd

- **Version:** v26.5.2
- **Port:** 5006
- **Data:** `/home/biscuit/.openclaw/workspace/actual-budget/data`
- **Config:** `config.json`
- **Service:** `actual-budget.service` (systemd, enabled for auto-start)
- **Local URL:** http://rita.shaw:5006

### Management

```bash
sudo systemctl status actual-budget.service   # check status
sudo systemctl restart actual-budget.service  # restart
sudo systemctl stop actual-budget.service     # stop
```

### Installation

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

### Update

```bash
corepack yarn add --exact '@actual-app/sync-server@VERSION'
sudo systemctl restart actual-budget.service
```

Replace `VERSION` with the release to install. Back up the existing data directory
before upgrading; server startup can run database migrations. Keep `package.json`
and `yarn.lock` together when saving dependency updates.

### Dependencies and runtime

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

### Verification

```bash
sudo systemctl status actual-budget.service
sudo journalctl -u actual-budget.service -n 30 --no-pager
curl --fail http://127.0.0.1:5006/
cloudflared tunnel --config /etc/cloudflared/config.yml ingress rule https://budget.badmath.org
```

## `spaceforce` — macOS, launchd

- **Version:** v26.7.0
- **Port:** 5006
- **Data:** `/Users/biscuit/actual-budget-server/data`
- **Config:** `/Users/biscuit/actual-budget-server/config.json`
- **Service:** `org.actualbudget.server` (launchd LaunchAgent)
- **Local URL:** http://spaceforce.home:5006
- **Public URL:** https://budget.badmath.org
- **Logs:** `/Users/biscuit/actual-budget-server/actual-server.{log,error.log}`

Runtime is Node v22.23.1 at `/Users/biscuit/.hermes/node/bin/node`. The server is
a **global npm install** with prefix `/Users/biscuit/.local`, resolving to
`/Users/biscuit/.local/lib/node_modules/@actual-app/sync-server`. There is no
checkout of this repository on this host and no `package.json`/`yarn.lock`
pinning — the installed version is whatever npm last placed there.

`config.json` on this host is **not** the `config.json` tracked in this
repository (that one carries the `rita.shaw` data path). Its contents are:

```json
{
  "dataDir": "/Users/biscuit/actual-budget-server/data",
  "port": 5006,
  "hostname": "0.0.0.0"
}
```

### Per-user startup caveat

Both services on this host are **LaunchAgents in `~/Library/LaunchAgents`**, not
system-wide LaunchDaemons. They start when user `biscuit` logs in, not at boot,
and they stop when that session ends. After an unattended reboot the budget
server and tunnel stay down until someone logs in. Macs also sleep by default,
which drops the tunnel until the machine wakes. If `budget.badmath.org` needs to
be reachable unattended, convert both to LaunchDaemons in
`/Library/LaunchDaemons` and disable sleep (`sudo pmset -a sleep 0`).

### Management

```bash
UID_=$(id -u)
launchctl print    gui/$UID_/org.actualbudget.server   # status
launchctl kickstart -k gui/$UID_/org.actualbudget.server  # restart
launchctl bootout  gui/$UID_/org.actualbudget.server   # stop
launchctl bootstrap gui/$UID_ ~/Library/LaunchAgents/org.actualbudget.server.plist  # start

launchctl print    gui/$UID_/com.cloudflare.cloudflared  # tunnel status
launchctl kickstart -k gui/$UID_/com.cloudflare.cloudflared  # restart tunnel
```

### Installation

Install the server globally with the `/Users/biscuit/.local` npm prefix, then
load the LaunchAgent:

```bash
npm install -g @actual-app/sync-server
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.actualbudget.server.plist
```

`~/Library/LaunchAgents/org.actualbudget.server.plist` runs Node directly against
the installed `actual-server.js` with `RunAtLoad` and `KeepAlive`, so launchd
restarts it if it exits:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>org.actualbudget.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/biscuit/.hermes/node/bin/node</string>
    <string>/Users/biscuit/.local/lib/node_modules/@actual-app/sync-server/build/bin/actual-server.js</string>
    <string>--config</string>
    <string>/Users/biscuit/actual-budget-server/config.json</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/Users/biscuit/actual-budget-server</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/biscuit/actual-budget-server/actual-server.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/biscuit/actual-budget-server/actual-server.error.log</string>
</dict>
</plist>
```

### Cloudflare Tunnel setup

cloudflared 2026.9.3 is installed with Homebrew at `/usr/local/bin/cloudflared`.
The tunnel was established with:

```bash
brew install cloudflared
cloudflared tunnel login                 # authorize the badmath.org zone
cloudflared tunnel create spaceforce
cloudflared tunnel route dns spaceforce budget.badmath.org
cloudflared service install              # LaunchAgent, reads ~/.cloudflared/config.yml
```

**`cloudflared service install` writes a plist that does not work for a named
tunnel.** It sets `ProgramArguments` to the bare binary with no subcommand, so
the agent exits 1 immediately and launchd restarts it on a loop, logging
``use `cloudflared tunnel run` to start tunnel <id>`` to
`~/Library/Logs/com.cloudflare.cloudflared.err.log`. `ProgramArguments` must be
patched to invoke the subcommand, with global flags *before* `tunnel run`:

```xml
<key>ProgramArguments</key>
<array>
	<string>/usr/local/bin/cloudflared</string>
	<string>--no-autoupdate</string>
	<string>--config</string>
	<string>/Users/biscuit/.cloudflared/config.yml</string>
	<string>tunnel</string>
	<string>run</string>
</array>
```

`--no-autoupdate` is set because the binary is Homebrew-managed; let `brew
upgrade cloudflared` handle updates rather than having cloudflared replace its
own binary underneath launchd. Reload after editing:

```bash
launchctl bootout   gui/$(id -u)/com.cloudflare.cloudflared
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cloudflare.cloudflared.plist
```

The agent keeps launchd's `KeepAlive`/`SuccessfulExit=false` semantics: it is
restarted after a crash or dropped connection, but a clean exit (an explicit
`bootout`) leaves it stopped.

`/Users/biscuit/.cloudflared/config.yml`:

```yaml
tunnel: <TUNNEL_ID>
credentials-file: /Users/biscuit/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: budget.badmath.org
    service: http://127.0.0.1:5006
  - service: http_status:404
```

The catch-all `http_status:404` rule is required; cloudflared refuses to start
without a final rule that matches everything.

### Update

```bash
npm install -g @actual-app/sync-server@VERSION
launchctl kickstart -k gui/$(id -u)/org.actualbudget.server
```

Back up `data/` before upgrading — startup can run database migrations, and this
host has no lockfile to roll back to. Ad-hoc pre-change snapshots live in
`/Users/biscuit/actual-budget-server/backups`. Note that upgrading via
`npm install -g` with no version pin tracks latest and is not reproducible; pin
`VERSION` explicitly.

### Verification

```bash
launchctl print gui/$(id -u)/org.actualbudget.server | head -20
curl --fail http://127.0.0.1:5006/info
cloudflared tunnel info spaceforce
cloudflared tunnel --config /Users/biscuit/.cloudflared/config.yml ingress rule https://budget.badmath.org
curl --fail https://budget.badmath.org/info
dig +short budget.badmath.org
```

`/info` returns the server name, description, and version as JSON, which confirms
the request reached Actual rather than a Cloudflare error page. While the Access
application is enforced, the public `curl` returns the `302` challenge instead;
use `cloudflared access curl` to exercise the full path.

Note the cloudflared argument order: `--config` is a global flag and must come
**before** the subcommand. `cloudflared tunnel --config FILE ingress rule URL`
works; `cloudflared tunnel ingress rule --config FILE URL` fails with
`flag provided but not defined: -config`.
