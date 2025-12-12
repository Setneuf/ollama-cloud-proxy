------------------------------------------------------------
OLLAMA-CLOUD-PROXY
-

Ollama-compatible proxy that translates local Ollama API calls
into Ollama Cloud API requests.

This allows tools like OpenWebUI to use Ollama Cloud exactly
as if it were a local "ollama serve" instance.

Designed for:
- Proxmox VE
- LXC containers (Alpine Linux)
- Low resource usage
- Zero UI hacks

------------------------------------------------------------
FEATURES
-

- Full Ollama API compatibility:
  * POST /api/chat
  * POST /api/generate
  * GET  /api/tags

- Transparent translation:
  Local Ollama API  ->  Ollama Cloud API

- Works out-of-the-box with OpenWebUI
- Alpine-based (small, fast, predictable)
- OpenRC supervised service (no shell blocking)
- API token stored in a file (not hardcoded)
- Proxmox Helper Script style installer
- Tested and stable with:
  * 1 vCPU
  * 512 MB RAM

------------------------------------------------------------
REQUIREMENTS
-

- Proxmox VE (tested on 9.1)
- LXC support enabled
- Internet access from the container
- Ollama Cloud API token

------------------------------------------------------------
INSTALLATION (PROXMOX SCRIPT)
-

Run on the Proxmox host as root:

    chmod +x ollama-cloud-proxy.sh
    ./ollama-cloud-proxy.sh

During installation you will be prompted for your Ollama Cloud
API token.

The script will automatically:

- Pick the next available CTID
- Create an Alpine LXC container
- Allocate 1 vCPU and 512 MB RAM
- Install Python, FastAPI and Uvicorn
- Deploy the proxy service
- Enable OpenRC supervision
- Start the service immediately
- Print the container IP address

No manual steps required after installation.

------------------------------------------------------------
TOKEN MANAGEMENT
-

The Ollama Cloud API token is stored in:

    /etc/ollama-cloud/token

Permissions:
    600 (readable only by root)

To rotate the token:

    nano /etc/ollama-cloud/token
    rc-service ollama-cloud-proxy restart

------------------------------------------------------------
OPENWEBUI CONFIGURATION
-

In OpenWebUI:

    Admin Panel -> Settings -> Ollama

Set:

    Base URL = http://<LXC-IP>:11434

OpenWebUI will now behave as if it were connected to a local
Ollama daemon.

------------------------------------------------------------
SUPPORTED ENDPOINTS
-

POST /api/chat
- Standard Ollama chat API using messages[]

POST /api/generate
- Prompt-based API
- Automatically translated to chat format internally

GET /api/tags
- Lists available models from Ollama Cloud

------------------------------------------------------------
TESTING
-

Quick health check:

    curl http://<LXC-IP>:11434/api/tags

If models are listed, the proxy is operational.

------------------------------------------------------------
DESIGN NOTES
-

- Ollama Cloud exposes only /api/chat
- Ollama local exposes both chat and generate
- This proxy performs semantic translation, not raw forwarding
- Defensive validation prevents OpenWebUI crashes
- OpenRC supervise-daemon ensures stable background execution

------------------------------------------------------------
RESOURCE USAGE
-

Typical idle usage:

- RAM: ~60-90 MB
- CPU: ~0%
- Disk: ~300 MB

1 vCPU and 512 MB RAM are sufficient for multiple users.

------------------------------------------------------------
LIMITATIONS
-

- Streaming (stream=true) not yet supported  ***ALREADY SUPPORTED!***
- Tool / function calling not implemented
- Cloud latency applies by design

------------------------------------------------------------
FINAL NOTE
-

If OpenWebUI thinks it is talking to Ollama,
then the proxy has done its job.

Less stress, more magic engineering.
