# Actual Budget Server

Installed and running on rita.shaw (OpenClaw server).

- **Version:** v26.5.2
- **Port:** 5006
- **Data:** `data/` directory
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
npm update -g @actual-app/sync-server
sudo systemctl restart actual-budget.service
```
