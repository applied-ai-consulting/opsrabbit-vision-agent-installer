# OpsRabbit Vision Agent Installer

Public bootstrap installer for the OpsRabbit Vision Agent on Raspberry Pi 5 /
Raspberry Pi OS arm64.

The script contains no proprietary agent code. It downloads the private
`opsrabbit-vision-agent_*.deb` from a GitHub Release using a token you provide,
installs the package, writes secure local configuration, runs preflight, and
starts the systemd service.

## Security model

Do not put AWS/S3 access keys on the Raspberry Pi for normal Conveyor Vision
operation.

Object storage is configured in OpsRabbit / the Conveyor Vision plugin. The
agent stores only its OpsRabbit device API token locally. For images and video,
the agent asks OpsRabbit for short-lived upload authorizations, uploads directly
to the configured object store, and keeps local evidence until remote
verification succeeds.

The installer asks whether object storage is already configured in OpsRabbit so
operators do not forget that step, but it does not collect AWS credentials.

## Prerequisites

In OpsRabbit:

1. Install, approve, deploy, and tenant-enable the Conveyor Vision plugin.
2. Configure the plugin's object-store/S3 destination.
3. Register and approve the Vision device, for example `pi5-belt-line-1`.
4. Create a scoped plugin/device API token for that device.

In GitHub:

1. Publish the agent Debian package as a release asset in the configured
   release repository.
2. Create a GitHub token that can read the private release asset.

On the Raspberry Pi:

1. Raspberry Pi OS arm64.
2. Camera and Hailo AI Kit packages available from the Pi apt sources.
3. Network access to OpsRabbit backend and GitHub.

## Interactive install

Run from an interactive SSH session:

```bash
curl -fsSL https://raw.githubusercontent.com/applied-ai-consulting/opsrabbit-vision-agent-installer/main/install.sh | sudo bash
```

The installer prompts for:

- GitHub token for downloading the private `.deb` release asset;
- OpsRabbit backend base URL reachable from the Pi;
- OpsRabbit Vision device API token;
- device id, defaulting to `pi5-belt-line-1`;
- optional Hailo package installation.

## Non-interactive install

Prefer token files over command-line token values. Command-line arguments can be
visible in shell history and process listings.

```bash
sudo bash install.sh \
  --release-repository applied-ai-consulting/oriental \
  --release-version latest \
  --asset-name opsrabbit-vision-agent_0.1.0_arm64.deb \
  --device-id pi5-belt-line-1 \
  --base-url https://opsrabbit.example.internal \
  --github-token-file /root/github-release-token.txt \
  --device-token-file /root/opsrabbit-vision-device-token.txt \
  --install-hailo yes \
  --non-interactive
```

For local development over plain HTTP:

```bash
sudo bash install.sh \
  --base-url http://192.168.1.50:8384 \
  --github-token-file /root/github-release-token.txt \
  --device-token-file /root/opsrabbit-vision-device-token.txt \
  --non-interactive
```

The installer automatically sets `verify_tls = false` in the generated agent
configuration when the base URL starts with `http://`.

## Custom spool storage

Use an absolute path for a mounted SSD or larger data volume:

```bash
sudo bash install.sh \
  --data-dir /mnt/vision-spool \
  --base-url https://opsrabbit.example.internal
```

The agent package's `configure` command writes a systemd drop-in that grants the
service write access to the custom path.

## After install

Check service status:

```bash
sudo systemctl status opsrabbit-vision --no-pager
```

Follow logs:

```bash
journalctl -u opsrabbit-vision -f
```

Run preflight again:

```bash
sudo runuser -u opsrabbit-vision -- \
  /opt/opsrabbit-vision/venv/bin/opsrabbit-vision preflight \
  --config /etc/opsrabbit-vision/vision-agent.toml
```

If an inspection was already started in OpsRabbit, the running agent should pick
up the pending `start_capture` command, acknowledge it, and emit
`capture_started`, which moves the record to the capturing state.
