# PentAGI Codespace

Run [PentAGI](https://pentagi.com/) — the self-hosted autonomous pentesting multi-agent platform — in a GitHub Codespace, from anywhere, using your **OpenCode** API key as the LLM provider (OpenAI-compatible endpoint), with Gemini as failover and the Grafana/OpenTelemetry observability + Neo4j/Graphiti knowledge-graph stacks layered on.

> Only use PentAGI against systems you own or are explicitly authorized to test. Installing/using it implies acceptance of the [EULA](https://github.com/vxcontrol/pentagi/blob/main/EULA.md).

## One-time setup

1. Push this repo to GitHub (public is fine — no secrets are committed; `.env` is gitignored).
2. Add Codespace secrets at `github.com/settings/codespaces` (or repo-level Settings → Codespaces):
   - `OPENCODE_API_KEY` — your OpenCode Console API key (Go plan: `https://opencode.ai/console`)
   - `GEMINI_API_KEY` — a free Google AI Studio key, used as `LLM_FALLBACK_PROVIDER`
3. Open a Codespace on main (`< >` button → Open with Codespaces) and pick the **4-core machine** (`standardLinux32gb` — 2 vCPU/4 GB is PentAGI's bare floor; DinD + Postgres + Neo4j + observability need more).
4. On creation, `postCreateCommand` runs `setup.sh`, which generates `.env` with random salts and injects the secrets.

## Start / stop

```bash
docker compose -f docker-compose.yml -f docker-compose-gateway.yml -f docker-compose-observability.yml -f docker-compose-graphiti.yml up -d
```

Open the forwarded **port 8443** (`https://localhost:8443` inside the Codespace, forwarded to your browser) and sign in with `admin@example.com` / `admin`, then change the password. Grafana is forwarded on port 3000.

Stop with `docker compose -f docker-compose.yml -f docker-compose-gateway.yml -f docker-compose-observability.yml -f docker-compose-graphiti.yml down` (add `-v` if you also want to wipe flow data — Postgres, Neo4j).

## How the provider is wired

- `.env`: `LLM_SERVER_URL=http://opencode-gateway:8000/inference/go/openai/v1`, `LLM_SERVER_KEY=${OPENCODE_API_KEY}` → PentAGI's *custom OpenAI-compatible provider*.
- `docker-compose.gateway.yml` + `gateway/nginx.conf`: a tiny nginx sidecar that injects the `x-opencode-session` header and an identifying User-Agent — both required by the OpenCode **Go** endpoint (plain calls get `400 … Request is missing x-opencode-session`) — then proxies to `https://opencode.ai`. This is the same gateway pattern PentAGI's docs recommend for endpoints with extra requirements.
- `conf/opencode.provider.yml` assigns a model per agent type (strong: `gpt-6-luna` for primary/pentester/adviser/assistant; light: `deepseek-v4.1-flash`, `glm-5.3-flash` for searcher/enricher/summarization) — adjust freely; valid IDs: `curl https://opencode.ai/inference/go/v1/models`. Pay-as-you-go instead of Go? Point the nginx `proxy_pass` straight through (or bypass the gateway and set the URL to `https://opencode.ai/inference/openai/v1` in `.env`).
- Fallback: `LLM_FALLBACK_PROVIDER=gemini`.
- Knowledge graph: `GRAPHITI_ENABLED=true` + `graphiti/custom.yaml` reuses the same OpenCode endpoint (via the gateway).

## Repo layout

| File | What it is |
| --- | --- |
| `docker-compose.yml`, `docker-compose-observability.yml`, `docker-compose-graphiti.yml` | Pinned copies of upstream `vxcontrol/pentagi` compose files |
| `docker-compose.gateway.yml`, `gateway/nginx.conf` | nginx sidecar injecting OpenCode Go's required session header |
| `observability/`, `graphiti/` | Vendored upstream configs (Grafana/Loki/OTel/Jaeger-plugin; Graphiti model config) |
| `.env.example` | Upstream env template; `setup.sh` turns it into `.env` |
| `conf/opencode.provider.yml` | Per-agent-type models for the custom provider |
| `setup.sh` | Idempotent `.env` generation from Codespace secrets + external-network creation |
| `.devcontainer/devcontainer.json` | Docker-in-Docker feature, port forwards, setup hook |

To pick up upstream changes, re-download the compose/env files from <https://github.com/vxcontrol/pentagi>.

## Costs

The Codespace runs only while open — stop/delete it when idle. 4-core = 120 core-hours of the free monthly Codespace allowance (personal accounts). LLM spend is on your OpenCode plan.
