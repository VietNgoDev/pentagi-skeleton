#!/usr/bin/env bash
# Generates .env from .env.example, injecting secrets from Codespace env:
#   OPENCODE_API_KEY (required) - OpenCode Go / Console API key
#   GEMINI_API_KEY   (optional)  - fallback provider
# Idempotent: does nothing if .env already exists (delete it to regenerate).
set -euo pipefail
cd "$(dirname "$0")"

if [ -f .env ]; then
  echo "setup: .env already exists, leaving it untouched"
  exit 0
fi

if [ -z "${OPENCODE_API_KEY:-}" ]; then
  echo "setup: OPENCODE_API_KEY is not set." >&2
  echo "  Add it as a Codespace secret (github.com/settings/codespaces > New secret)" >&2
  echo "  or export it, then re-run: bash setup.sh" >&2
  exit 1
fi

cp .env.example .env
chmod 600 .env

salt() { openssl rand -hex 32; }

sed -i.bak -E \
  -e "s|^COOKIE_SIGNING_SALT=salt( .*)?$|COOKIE_SIGNING_SALT=$(salt)|" \
  -e "s|^PENTAGI_POSTGRES_PASSWORD=postgres( .*)?$|PENTAGI_POSTGRES_PASSWORD=$(openssl rand -hex 16)|" \
  -e "s|^NEO4J_PASSWORD=devpassword( .*)?$|NEO4J_PASSWORD=$(openssl rand -hex 16)|" \
  -e "s|^LANGFUSE_POSTGRES_PASSWORD=postgres( .*)?$|LANGFUSE_POSTGRES_PASSWORD=$(openssl rand -hex 16)|" \
  -e "s|^SCRAPER_PRIVATE_URL=https://someuser:somepass@scraper/\$|SCRAPER_PRIVATE_URL=https://scraper:$(openssl rand -hex 8)@scraper/|" \
  -e "s|^LLM_SERVER_URL=\$|LLM_SERVER_URL=http://opencode-gateway:8000/inference/go/openai/v1|" \
  -e "s|^LLM_SERVER_KEY=\$|LLM_SERVER_KEY=${OPENCODE_API_KEY}|" \
  -e "s|^LLM_SERVER_MODEL=\$|LLM_SERVER_MODEL=gpt-6-luna|" \
  -e "s|^LLM_SERVER_CONFIG_PATH=\$|LLM_SERVER_CONFIG_PATH=/opt/pentagi/conf/custom.provider.yml|" \
  .env

if [ -n "${GEMINI_API_KEY:-}" ]; then
  sed -i.bak -E \
    -e "s|^GEMINI_API_KEY=\$|GEMINI_API_KEY=${GEMINI_API_KEY}|" \
    -e "s|^LLM_FALLBACK_PROVIDER=\$|LLM_FALLBACK_PROVIDER=gemini|" \
    .env
fi
# Point the compose bind-mount for the custom provider config at our file
sed -i.bak -E \
  -e "s|^PENTAGI_LLM_SERVER_CONFIG_PATH=\$|PENTAGI_LLM_SERVER_CONFIG_PATH=./conf/opencode.provider.yml|" \
  .env

# compose mounts these two too (defaults in docker-compose.yml); keep them empty files
touch example.ollama.provider.yml example.bedrock.provider.yml

# Knowledge graph (docker-compose-graphiti.yml)
sed -i.bak -E \
  -e "s|^GRAPHITI_ENABLED=false\$|GRAPHITI_ENABLED=true|" \
  -e "s|^GRAPHITI_URL=\$|GRAPHITI_URL=http://graphiti:8000|" \
  -e "s|^GRAPHITI_LLM_CLIENT_TYPE=openai\$|GRAPHITI_LLM_CLIENT_TYPE=custom|" \
  .env
rm -f .env.bak

# the compose overlays declare these networks as external; create missing ones
for net in pentagi-network observability-network langfuse-network; do
  docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net"
done
echo "setup: .env generated. Start the stack with:"
echo "  docker compose -f docker-compose.yml -f docker-compose-gateway.yml -f docker-compose-observability.yml -f docker-compose-graphiti.yml up -d"
