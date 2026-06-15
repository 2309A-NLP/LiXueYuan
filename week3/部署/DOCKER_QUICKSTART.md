# RAGFlow Docker Quickstart

This repository already contains the official Docker Compose files in `docker/`.
The launcher in this directory wraps those files so you can start the local
stack with one command or by double-clicking a file on Windows.

## Start

Double-click:

```text
start-ragflow-docker.cmd
```

Or run from PowerShell:

```powershell
.\Start-RAGFlow-Docker.ps1
```

The default local stack uses:

- RAGFlow CPU image
- Infinity as the document/vector engine
- MySQL
- MinIO
- Redis

After startup, open:

- Web UI: <http://127.0.0.1:8080>
- API: <http://127.0.0.1:19380>
- Admin API: <http://127.0.0.1:19381>
- MinIO console: <http://127.0.0.1:19001>

The first run can take a while because Docker needs to download the RAGFlow and
database images.

## Common Commands

Show running containers:

```powershell
.\Start-RAGFlow-Docker.ps1 -Action status
```

Follow logs:

```powershell
.\Start-RAGFlow-Docker.ps1 -Action logs -Follow
```

Stop containers without deleting data:

```powershell
.\Start-RAGFlow-Docker.ps1 -Action stop
```

Stop and remove containers while keeping named Docker volumes:

```powershell
.\Start-RAGFlow-Docker.ps1 -Action down
```

Restart:

```powershell
.\Start-RAGFlow-Docker.ps1 -Action restart
```

Pull images manually:

```powershell
.\Start-RAGFlow-Docker.ps1 -Action pull
```

## Options

Use GPU mode:

```powershell
.\Start-RAGFlow-Docker.ps1 -Device gpu
```

Use Elasticsearch instead of Infinity:

```powershell
.\Start-RAGFlow-Docker.ps1 -DocEngine elasticsearch
```

Use another web port if port 80 is already occupied:

```powershell
.\Start-RAGFlow-Docker.ps1 -WebPort 8080
```

By default, the launcher uses isolated host ports so it does not conflict with
existing containers such as Redis, MySQL, MinIO, or Milvus. If you really want to
use the ports from `docker/.env`, run:

```powershell
.\Start-RAGFlow-Docker.ps1 -UseDockerEnvPorts
```

For persistent configuration, edit `docker/.env` directly.

## Notes

- For local use, the default passwords in `docker/.env` are convenient. Change
  them before exposing this deployment to a network.
- If Docker Desktop is not running, the PowerShell launcher tries to start it
  and waits for it to become ready.
- The launcher does not delete Docker volumes. Your MySQL, MinIO, Redis, and
  document engine data stay in Docker volumes unless you remove them manually.
- The default Compose project is `ragflow_local`, so `stop`, `down`, and
  `restart` only target containers created by this launcher.
