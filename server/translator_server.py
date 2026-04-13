#!/usr/bin/env python3
"""
translator_server.py
────────────────────
Servidor TCP para el addon myTraductor (WoW 3.3.5).
Recibe texto del addon, lo traduce vía LibreTranslate y devuelve la traducción.

Protocolo (línea por mensaje):
  ← addon: "O:hola como estas\n"   → ES→EN → "hello how are you\n"
  ← addon: "I:hello how are you\n" → EN→ES → "hola como estás\n"

Inicio:
  # 1. Arrancar LibreTranslate (sólo la primera vez):
  pip install libretranslate
  libretranslate --host 127.0.0.1 --port 5000 --load-only en,es

  # 2. Arrancar este servidor:
  pip install -r requirements.txt
  python translator_server.py
"""

import asyncio
import logging
import os
import signal
import sys

import httpx

# ── Configuración ────────────────────────────────────────────────
HOST = "127.0.0.1"
PORT = 12345

LIBRETRANSLATE_URL = os.getenv("LIBRETRANSLATE_URL", "http://127.0.0.1:5000")
LIBRETRANSLATE_KEY = os.getenv("LIBRETRANSLATE_KEY", "")   # vacío = sin clave

# Direcciones soportadas
DIRECTIONS = {
    "O": ("es", "en"),   # Outgoing: Español → Inglés
    "I": ("en", "es"),   # Incoming: Inglés  → Español
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("myTraductor")

# Cliente HTTP reutilizable (connection pooling automático)
_http = httpx.AsyncClient(timeout=5.0)


# ── Traducción ───────────────────────────────────────────────────

async def translate(text: str, source: str, target: str) -> str:
    """
    Llama a LibreTranslate de forma asíncrona.
    Retorna el texto original si la traducción falla (fallback seguro).
    """
    if not text.strip():
        return text

    payload: dict = {
        "q":      text,
        "source": source,
        "target": target,
        "format": "text",
    }
    if LIBRETRANSLATE_KEY:
        payload["api_key"] = LIBRETRANSLATE_KEY

    try:
        resp = await _http.post(f"{LIBRETRANSLATE_URL}/translate", json=payload)
        resp.raise_for_status()
        return resp.json().get("translatedText", text)
    except httpx.HTTPStatusError as exc:
        log.error("LibreTranslate HTTP %s: %s", exc.response.status_code, exc.response.text[:200])
        return text
    except Exception as exc:
        log.error("Error al traducir %r: %s", text, exc)
        return text


# ── Manejo de clientes ───────────────────────────────────────────

async def handle_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
) -> None:
    addr = writer.get_extra_info("peername")
    log.info("Conexión desde %s", addr)

    try:
        while True:
            raw = await reader.readline()

            if not raw:
                log.info("Cliente %s cerró la conexión.", addr)
                break

            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue

            # ── Parsear dirección ────────────────────────────────
            # Formato esperado: "O:texto" o "I:texto"
            # Cualquier otro formato: asumir O: (compatibilidad hacia atrás)
            if len(line) >= 2 and line[1] == ":" and line[0].upper() in DIRECTIONS:
                direction = line[0].upper()
                text      = line[2:]
            else:
                direction = "O"
                text      = line

            source, target = DIRECTIONS[direction]

            log.info("[%s] %s→%s  ← %r", direction, source.upper(), target.upper(), text)

            translated = await translate(text, source, target)

            log.info("[%s]           → %r", direction, translated)

            writer.write((translated + "\n").encode("utf-8"))
            await writer.drain()

    except asyncio.IncompleteReadError:
        log.info("Cliente %s desconectado abruptamente.", addr)
    except ConnectionResetError:
        log.info("Cliente %s resetó la conexión.", addr)
    except Exception as exc:
        log.error("Error inesperado con %s: %s", addr, exc)
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


# ── Servidor principal ───────────────────────────────────────────

async def main() -> None:
    # Verificar que LibreTranslate responde antes de aceptar conexiones
    try:
        resp = await _http.get(f"{LIBRETRANSLATE_URL}/languages")
        resp.raise_for_status()
        langs = [l["code"] for l in resp.json()]
        log.info("LibreTranslate OK — idiomas disponibles: %s", langs)
    except Exception as exc:
        log.warning("LibreTranslate no responde en %s: %s", LIBRETRANSLATE_URL, exc)
        log.warning("Continúa de todas formas; habrá fallback al texto original.")

    server = await asyncio.start_server(handle_client, HOST, PORT)
    addrs  = [str(s.getsockname()) for s in server.sockets]
    log.info("Servidor escuchando en %s", ", ".join(addrs))
    log.info("Backend: %s | Ctrl+C para detener", LIBRETRANSLATE_URL)

    loop       = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    def _on_signal():
        log.info("Señal recibida. Cerrando...")
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _on_signal)
        except NotImplementedError:
            pass  # Windows: usa KeyboardInterrupt

    async with server:
        try:
            await stop_event.wait()
        except asyncio.CancelledError:
            pass

    await _http.aclose()
    log.info("Servidor detenido.")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Servidor detenido.")
        sys.exit(0)

