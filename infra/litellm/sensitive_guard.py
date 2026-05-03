"""
Pre-Call-Hook: Sensitive-Aliase werfen 503, wenn Mac-Backend offline.
Verhindert, dass LiteLLM bei Fehlkonfigurationen in die Cloud ausweicht.
"""
import os, httpx, time
from litellm.integrations.custom_logger import CustomLogger

# Mac-Ollama IP via WireGuard
MAC_HEALTH_URL = "http://10.8.0.10:11434/api/tags"
CACHE_TTL = 30
_cache = {"ts": 0, "ok": False}

# DSGVO-Tiers
SENSITIVE_PREFIXES = ("voicebot-sensitive", "rag-sensitive", "chat-sensitive", "embed-sensitive")

def mac_alive() -> bool:
    if time.time() - _cache["ts"] < CACHE_TTL:
        return _cache["ok"]
    try:
        r = httpx.get(MAC_HEALTH_URL, timeout=3)
        ok = r.status_code == 200 and len(r.json().get("models", [])) > 0
    except Exception:
        ok = False
    _cache.update(ts=time.time(), ok=ok)
    return ok

class SensitiveGuard(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        model = data.get("model", "")
        if model.startswith(SENSITIVE_PREFIXES) and not mac_alive():
            from fastapi import HTTPException
            raise HTTPException(
                status_code=503,
                detail={
                    "error": "sensitive_backend_offline",
                    "message": "DSGVO-Tenant-Backend (Mac-Ollama) nicht erreichbar. Wartungsfenster.",
                    "retry_after": 3600,
                }
            )
        return data

proxy_handler_instance = SensitiveGuard()
