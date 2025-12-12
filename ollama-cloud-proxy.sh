#!/usr/bin/env bash
set -e

# ================= CONFIG =================
HOSTNAME="ollama-cloud-proxy"
STORAGE="local-lvm"
MEMORY=512
CORES=1
DISK=4
NET="name=eth0,bridge=vmbr0,ip=dhcp"
ALPINE_VERSION=""
# ==========================================

echo "==========================================="
echo "  Ollama Cloud Proxy – Proxmox Helper"
echo "==========================================="
echo

# 🔐 Ask for token (hidden)
read -s -p "Enter Ollama Cloud API Token: " OLLAMA_TOKEN
echo
echo

if [ -z "$OLLAMA_TOKEN" ]; then
  echo "❌ Token cannot be empty"
  exit 1
fi

# 🔢 Next available CTID
CTID=$(pvesh get /cluster/nextid)
echo "==> Using CTID: $CTID"
echo

# 📦 Template handling (NO wildcards)
echo "==> Updating template list"
pveam update

TEMPLATE=$(pveam available --section system | \
  awk "/alpine-$ALPINE_VERSION.*default/ {print \$2}" | tail -n1)

if [ -z "$TEMPLATE" ]; then
  echo "❌ Alpine $ALPINE_VERSION template not found"
  exit 1
fi

echo "==> Downloading template: $TEMPLATE"
pveam download local "$TEMPLATE"

# 🧱 Create container
echo "==> Creating LXC $CTID"
pct create "$CTID" "local:vztmpl/$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --rootfs "$STORAGE:$DISK" \
  --net0 "$NET" \
  --unprivileged 1 \
  --features nesting=1

pct start "$CTID"
sleep 5

# ⚙️ Provision container
echo "==> Provisioning container"

pct exec "$CTID" -- sh <<EOF
set -e

apk update
apk add python3 py3-pip py3-virtualenv build-base curl

mkdir -p /opt/ollama-cloud-proxy
mkdir -p /etc/ollama-cloud

echo "$OLLAMA_TOKEN" > /etc/ollama-cloud/token
chmod 600 /etc/ollama-cloud/token

cd /opt/ollama-cloud-proxy
python3 -m venv venv
. venv/bin/activate

pip install --no-cache-dir fastapi uvicorn requests

cat > main.py <<'PYEOF'
from fastapi import FastAPI, Request, HTTPException
import requests

TOKEN_FILE = "/etc/ollama-cloud/token"
OLLAMA_CHAT_URL = "https://ollama.com/api/chat"

def token():
    with open(TOKEN_FILE) as f:
        return f.read().strip()

app = FastAPI()

# -------------------------------------------------
# /api/chat  (messages-based)
# -------------------------------------------------
@app.post("/api/chat")
async def chat(req: Request):
    body = await req.json()

    model = body.get("model")
    messages = body.get("messages")

    if not model or not messages:
        raise HTTPException(status_code=400, detail="Invalid chat request")

    payload = {
        "model": model,
        "messages": messages,
        "stream": False
    }

    headers = {
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json"
    }

    r = requests.post(
        OLLAMA_CHAT_URL,
        json=payload,
        headers=headers,
        timeout=120
    )

    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=r.text)

    return r.json()


# -------------------------------------------------
# /api/generate  (prompt-based)
# -------------------------------------------------
@app.post("/api/generate")
async def generate(req: Request):
    body = await req.json()

    model = body.get("model")
    prompt = body.get("prompt")

    if not model or not prompt:
        raise HTTPException(status_code=400, detail="Invalid generate request")

    # Traduz generate -> chat (Cloud só fala chat)
    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": prompt
            }
        ],
        "stream": False
    }

    headers = {
        "Authorization": f"Bearer {token()}",
        "Content-Type": "application/json"
    }

    r = requests.post(
        OLLAMA_CHAT_URL,
        json=payload,
        headers=headers,
        timeout=120
    )

    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=r.text)

    cloud = r.json()

    # Converter resposta chat -> generate (compatível Ollama)
    try:
        content = cloud["message"]["content"]
    except Exception:
        raise HTTPException(status_code=502, detail="Invalid cloud response")

    return {
        "model": model,
        "response": content,
        "done": True
    }


# -------------------------------------------------
# /api/tags
# -------------------------------------------------
@app.get("/api/tags")
async def tags():
    headers = {
        "Authorization": f"Bearer {token()}"
    }
    r = requests.get("https://ollama.com/api/tags", headers=headers, timeout=30)
    return r.json()
PYEOF

cat > /etc/init.d/ollama-cloud-proxy <<'RCEOF'
#!/sbin/openrc-run

description="Ollama Cloud Proxy"

directory="/opt/ollama-cloud-proxy"
command="/opt/ollama-cloud-proxy/venv/bin/uvicorn"
command_args="main:app --host 0.0.0.0 --port 11434"

supervisor="supervise-daemon"
pidfile="/run/ollama-cloud-proxy.pid"

depend() {
    need net
}
RCEOF

chmod +x /etc/init.d/ollama-cloud-proxy
rc-update add ollama-cloud-proxy default

# 🚀 Start immediately
rc-service ollama-cloud-proxy start
EOF

# 📡 Show result
echo
echo "✅ Ollama Cloud Proxy installed and running"
echo "➡ Container ID: $CTID"
echo "➡ OpenWebUI URL:"
echo "   http://<LXC-IP>:11434"
echo

pct exec "$CTID" -- ip addr show eth0 | awk '/inet / {print "➡ LXC IP:", $2}'
