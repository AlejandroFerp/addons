# myTraductor

Addon para **World of Warcraft 3.3.5 (Wrath of the Lich King)** que traduce mensajes del chat con LibreTranslate (100% local, sin APIs de pago ni Google).

## ¿Qué hace?

| Dirección | Cómo se activa | Resultado |
|-----------|----------------|-----------|
| ES → EN | Escribes `/en hola como estas` | Envía `"hello how are you"` al chat (SAY) |
| EN → ES | Llega un mensaje en inglés | Aparece una línea secundaria `≈ Jugador: hola como estás` |

Solo traducen los mensajes que tú decides (prefijo `/en`). El chat normal no se toca.

---

## Requisitos

| Componente | Para qué |
|------------|----------|
| WoW 3.3.5 con **LuaSocket** | El addon usa sockets TCP desde Lua |
| **Python 3.10+** | Servidor relay entre WoW y LibreTranslate |
| **LibreTranslate** | Motor de traducción local |

> **LuaSocket** es el único requisito no estándar. En servidores privados (TrinityCore / MaNGOS) se inyecta mediante un DLL proxy (`winmm.dll`). Si tu cliente ya lo tiene, el addon funciona. Si no lo tienes, busca *"WoW 3.3.5 LuaSocket DLL"* en los foros de tu servidor.

---

## Instalación paso a paso

### 1. Addon (Lua)

Copia la carpeta `myTraductor/` completa dentro de:

```
World of Warcraft/Interface/AddOns/myTraductor/
```

Verifica que existan estos dos archivos:
```
myTraductor.toc
myTraductor.lua
```

### 2. LibreTranslate (motor de traducción)

```powershell
pip install libretranslate
libretranslate --host 127.0.0.1 --port 5000 --load-only en,es
```

> `--load-only en,es` carga solo los modelos que necesitas. Sin eso tarda mucho más en arrancar.

La primera vez descarga los modelos de idioma (~500 MB). Las siguientes arranca en segundos.

### 3. Servidor relay (Python)

En otra terminal:

```powershell
cd server
pip install -r requirements.txt
python translator_server.py
```

Deberías ver:
```
10:32:01  INFO     LibreTranslate OK — idiomas disponibles: ['en', 'es', ...]
10:32:01  INFO     Servidor escuchando en ('127.0.0.1', 12345)
```

---

## Uso en el juego

```
/en hola como estas
```
→ El addon envía `"hello how are you"` al chat SAY.

```
/tr estado        — ver si está conectado al servidor
/tr conectar      — reconectar si el servidor se reinició
/tr entrante      — activar/desactivar subtítulos EN→ES
/tr ayuda         — lista completa de comandos
```

---

## Flujo técnico

```
/en hola como estas
      │
      ▼
 myTraductor.lua
 SlashCmdList["MYTRADUCTOR_EN"]
      │  TCP: "O:hola como estas\n"
      ▼
 translator_server.py  (puerto 12345)
      │  POST /translate  {q, source:es, target:en}
      ▼
 LibreTranslate        (puerto 5000)
      │  "hello how are you"
      ▼
 translator_server.py  → "hello how are you\n"
      │
      ▼
 myTraductor.lua
 SendChatMessage("hello how are you", "SAY")
```

---

## Variables de entorno (servidor)

| Variable | Default | Descripción |
|----------|---------|-------------|
| `LIBRETRANSLATE_URL` | `http://127.0.0.1:5000` | URL de la instancia LibreTranslate |
| `LIBRETRANSLATE_KEY` | *(vacío)* | API key (solo instancias públicas) |

---

## Estructura del proyecto

```
myTraductor/
├── myTraductor.toc          ← Manifiesto del addon (Interface: 30300)
├── myTraductor.lua          ← Lógica principal
└── server/
    ├── translator_server.py ← Servidor relay TCP → LibreTranslate
    └── requirements.txt     ← httpx>=0.27.0
```
