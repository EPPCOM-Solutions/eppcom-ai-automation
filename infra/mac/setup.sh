#!/bin/bash
# ==============================================================================
# Mac Setup & Hardening Script (Ollama + pf Firewall + Cloudflare)
# ==============================================================================

echo "Setting up Ollama Environment Variables..."
# Ollama auf 0.0.0.0 binden, Modell-Limits setzen (für 27GB Sequenziell-Strategie)
launchctl setenv OLLAMA_MODELS /Volumes/LLM/ollama
launchctl setenv OLLAMA_HOST 0.0.0.0:11434
launchctl setenv OLLAMA_MAX_LOADED_MODELS 1
launchctl setenv OLLAMA_KEEP_ALIVE 10m

# Permanent für CLI
cat << 'EOF' >> ~/.zshrc
export OLLAMA_MODELS=/Volumes/LLM/ollama
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_KEEP_ALIVE=10m
EOF

echo "Applying pf Firewall Hardening..."
# Sichert 0.0.0.0 ab, indem Zugriffe auf Port 11434 nur noch über WireGuard (utun) erlaubt sind.
# ACHTUNG: Interface (utun0, utun1...) kann je nach WireGuard-Verbindung variieren.
# Dieses Skript fügt die Regeln temporär hinzu. Für Dauerbetrieb muss es in /etc/pf.conf.

sudo tee /etc/pf.anchors/com.eppcom.ollama > /dev/null << 'EOF'
block in proto tcp from any to any port 11434
pass in on utun0 proto tcp from 10.8.0.1 to any port 11434
pass in on lo0 proto tcp from any to any port 11434
EOF

# pf konfigurieren, um den Anchor einzubinden
grep -q "anchor \"com.eppcom.ollama\"" /etc/pf.conf || sudo sed -i '' '/anchor "com.apple"/a\
anchor "com.eppcom.ollama"\
load anchor "com.eppcom.ollama" from "/etc/pf.anchors/com.eppcom.ollama"
' /etc/pf.conf

sudo pfctl -f /etc/pf.conf
sudo pfctl -E

echo "Ollama neustarten..."
brew services restart ollama

echo "Setting up Pre-Warm Cronjob for Tenant-Voicebot (qwen3.6:27b)..."
# Generiert einen Cronjob, der Mo-Fr um 8:00 das Modell für 12 Stunden vorlädt.
# Verhindert 5-15s Lade-Latenz für den ersten Anrufer des Tages.
CRON_JOB="0 8 * * 1-5 curl -s http://localhost:11434/api/generate -d '{\"model\":\"qwen3.6:27b\",\"keep_alive\":\"12h\",\"prompt\":\"\"}' > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "http://localhost:11434/api/generate"; echo "$CRON_JOB") | crontab -
echo "Cronjob installiert. Prüfe mit: crontab -l"

echo "Setup abgeschlossen. Prüfe Tunnel & Cloudflared falls public-Zugriff gewünscht ist."
