-- ================================================================
-- myTraductor v1.2 - Addon WoW 3.3.5
--
-- Uso:
--   /en <mensaje>  → traduce ES→EN y lo envía como SAY
--   Mensajes entrantes en EN se muestran con subtítulo en ES
--
-- Backend : LibreTranslate   (https://github.com/LibreTranslate/LibreTranslate)
-- Servidor: translator_server.py en localhost
--
-- Protocolo TCP (línea por mensaje):
--   → envía:   "O:hola como estas\n"   (O = Outgoing, ES→EN)
--   → envía:   "I:hello how are you\n" (I = Incoming, EN→ES)
--   ← recibe:  "texto traducido\n"
--
-- REQUISITO: Cliente WoW con LuaSocket expuesto como global `socket`
-- (típico en servidores privados con DLL loader — ej. winmm.dll proxy)
-- ================================================================

local ADDON_NAME  = "myTraductor"
local SERVER_HOST = "127.0.0.1"
local SERVER_PORT = 12345
local MAX_WAIT_S  = 2.0   -- Timeout máximo esperando respuesta del servidor


-- ================================================================
-- CONFIG — Comportamiento del addon (editable en tiempo de ejecución)
-- ================================================================
local Config = {
    translateIncoming = true,   -- EN→ES mostrar sub-título de mensajes ajenos
}


-- ================================================================
-- UI — Mensajes en el chat frame
-- ================================================================
local UI = {}

function UI.Log(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff44cc44[Traductor]|r " .. tostring(msg))
end

function UI.Warn(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8844[Traductor]|r " .. tostring(msg))
end

function UI.Error(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Traductor]|r " .. tostring(msg))
end

-- Muestra la traducción de un mensaje entrante como línea secundaria.
-- Formato idéntico al que badboy usa para mostrar info extra.
function UI.ShowTranslation(sender, translated)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffaaaaaa≈ " .. tostring(sender) .. ": " .. tostring(translated) .. "|r"
    )
end


-- ================================================================
-- SOCKET — Conexión TCP con el servidor Python
-- ================================================================
local Socket = {
    conn      = nil,
    connected = false,
    buffer    = "",
}

-- Detecta LuaSocket: algunos clientes lo exponen como global `socket`,
-- otros requieren require("socket").
local function resolveSocketLib()
    if type(socket) == "table" and type(socket.tcp) == "function" then
        return socket
    end
    if type(require) == "function" then
        local ok, lib = pcall(require, "socket")
        if ok and type(lib) == "table" then
            return lib
        end
    end
    return nil
end

function Socket.Connect()
    local lib = resolveSocketLib()
    if not lib then
        UI.Error("LuaSocket no encontrado. Requiere cliente WoW con socket habilitado.")
        return false
    end

    Socket.conn = lib.tcp()
    Socket.conn:settimeout(1)

    local ok, err = Socket.conn:connect(SERVER_HOST, SERVER_PORT)
    if not ok then
        UI.Error("No se pudo conectar a " .. SERVER_HOST .. ":" .. SERVER_PORT .. " — " .. tostring(err))
        UI.Warn("Inicia translator_server.py y usa /tr conectar")
        Socket.conn      = nil
        Socket.connected = false
        return false
    end

    Socket.conn:settimeout(0)   -- Non-blocking para el loop principal
    Socket.connected = true
    UI.Log("Conectado a LibreTranslate relay (" .. SERVER_HOST .. ":" .. SERVER_PORT .. ")")
    return true
end

function Socket.Disconnect()
    if Socket.conn then
        Socket.conn:close()
        Socket.conn = nil
    end
    Socket.connected = false
    Socket.buffer    = ""
end

function Socket.Send(text)
    if not Socket.connected then return false end
    local _, err = Socket.conn:send(text .. "\n")
    if err then
        UI.Error("Error enviando al servidor: " .. tostring(err))
        Socket.Disconnect()
        return false
    end
    return true
end

-- Non-blocking: retorna la primera línea completa del buffer, o nil.
function Socket.TryReadLine()
    if not Socket.connected then return nil end

    local chunk, err = Socket.conn:receive(4096)
    if chunk then
        Socket.buffer = Socket.buffer .. chunk
    elseif err ~= "timeout" then
        UI.Error("Conexión perdida: " .. tostring(err))
        Socket.Disconnect()
        return nil
    end

    local nl = Socket.buffer:find("\n", 1, true)
    if nl then
        local line    = Socket.buffer:sub(1, nl - 1)
        Socket.buffer = Socket.buffer:sub(nl + 1)
        return line
    end

    return nil
end


-- ================================================================
-- QUEUE — Cola unificada para mensajes entrantes y salientes
--
-- Cada item tiene:
--   direction  "O" | "I"
--   msg        texto a traducir
--   onSuccess  function(translated)   → qué hacer con la traducción
--   onTimeout  function()             → qué hacer si no llega respuesta
-- ================================================================
local Queue = {
    pending = {},
    active  = nil,
    elapsed = 0,
}

function Queue.Push(item)
    table.insert(Queue.pending, item)
end

function Queue.Tick(elapsed)
    -- ── Caso 1: esperando respuesta para el item activo ──────────
    if Queue.active then
        Queue.elapsed = Queue.elapsed + elapsed

        local line = Socket.TryReadLine()
        if line then
            Queue.active.onSuccess(line)
            Queue.active  = nil
            Queue.elapsed = 0
            return
        end

        if Queue.elapsed >= MAX_WAIT_S then
            UI.Warn("Timeout — sin respuesta del servidor.")
            Queue.active.onTimeout()
            Queue.active  = nil
            Queue.elapsed = 0
        end

        return  -- Esperar antes de procesar el siguiente
    end

    -- ── Caso 2: tomar el próximo de la cola ──────────────────────
    if #Queue.pending == 0 then return end

    local item = table.remove(Queue.pending, 1)

    if not Socket.connected then
        if not Socket.Connect() then
            item.onTimeout()
            return
        end
    end

    -- Protocolo: prefijo de dirección + texto
    local payload = item.direction .. ":" .. item.msg

    if Socket.Send(payload) then
        Queue.active  = item
        Queue.elapsed = 0
    else
        item.onTimeout()
    end
end


-- ================================================================
-- SALIENTE — Slash command /en <mensaje>  (ES → EN → SAY)
--
-- El jugador escribe:  /en hola como estas
-- El addon traduce y envía al chat como SAY: "hello how are you"
-- ================================================================
SLASH_MYTRADUCTOR_EN1 = "/en"

SlashCmdList["MYTRADUCTOR_EN"] = function(input)
    local msg = (input or ""):match("^%s*(.-)%s*$")  -- trim

    if msg == "" then
        UI.Warn("Uso: /en <mensaje en español>")
        return
    end

    if not Socket.connected then
        if not Socket.Connect() then
            -- Sin servidor: enviar original sin traducir
            SendChatMessage(msg, "SAY")
            return
        end
    end

    Queue.Push({
        direction = "O",
        msg       = msg,
        onSuccess = function(translated)
            SendChatMessage(translated, "SAY")
        end,
        onTimeout = function()
            UI.Warn("Timeout — enviando mensaje original.")
            SendChatMessage(msg, "SAY")
        end,
    })
end


-- ================================================================
-- ENTRANTE — Filtros de chat (patrón BadBoy: ChatFrame_AddMessageEventFilter)
--
-- Firma exacta de WoW 3.3.5:
--   function(_, event, msg, sender, _, _, _, _, channelId, _, _, _, lineId)
--
-- Retorna true  → suprime el mensaje del frame
-- Retorna nil   → deja pasar el mensaje (comportamiento de BadBoy para mensajes OK)
--
-- Estrategia: NO suprimimos el original. Lo dejamos pasar (nil) y
-- encolamos la traducción; cuando llega, se muestra como línea
-- secundaria con UI.ShowTranslation. Así el jugador ve ambos.
--
-- prevLineId evita procesar el mismo mensaje dos veces cuando está
-- registrado en múltiples chat frames (mismo truco que BadBoy).
-- ================================================================
local prevLineId = 0

local function incomingFilter(_, event, msg, sender, _, _, _, _, _, _, _, _, lineId)
    if not Config.translateIncoming then return end

    -- Deduplicación: mismo mensaje puede dispararse en varios chat frames
    if lineId == prevLineId then return end
    prevLineId = lineId

    -- Capturar `sender` en el cierre del callback
    local capturedSender = sender or "?"
    local capturedMsg    = msg    or ""

    Queue.Push({
        direction = "I",
        msg       = capturedMsg,
        onSuccess = function(translated)
            -- Solo mostrar si es diferente al original (evita ruido con textos ya en ES)
            if translated ~= capturedMsg then
                UI.ShowTranslation(capturedSender, translated)
            end
        end,
        onTimeout = function()
            -- No hacemos nada: el original ya se mostró normalmente
        end,
    })

    -- nil = dejar pasar el mensaje original (no lo bloqueamos)
end

-- Registrar el filtro para los mismos eventos que BadBoy cubre
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY",     incomingFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL",    incomingFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY",   incomingFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID",    incomingFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD",   incomingFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", incomingFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", incomingFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", incomingFilter)


-- ================================================================
-- FRAME PRINCIPAL — Eventos del sistema y loop OnUpdate
-- ================================================================
local MainFrame = CreateFrame("Frame", ADDON_NAME .. "_MainFrame")
MainFrame:RegisterEvent("ADDON_LOADED")
MainFrame:RegisterEvent("PLAYER_LOGOUT")

MainFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        UI.Log("v1.2 cargado. Conectando al servidor LibreTranslate...")
        Socket.Connect()

    elseif event == "PLAYER_LOGOUT" then
        Socket.Disconnect()
    end
end)

MainFrame:SetScript("OnUpdate", function(self, elapsed)
    Queue.Tick(elapsed)
end)


-- ================================================================
-- SLASH COMMANDS — /traductor  o  /tr
-- ================================================================
SLASH_MYTRADUCTOR1 = "/traductor"
SLASH_MYTRADUCTOR2 = "/tr"

SlashCmdList["MYTRADUCTOR"] = function(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")

    if cmd == "conectar" or cmd == "connect" then
        Socket.Disconnect()
        Socket.Connect()

    elseif cmd == "desconectar" or cmd == "disconnect" then
        Socket.Disconnect()
        UI.Log("Desconectado.")

    elseif cmd == "entrante" or cmd == "in" then
        Config.translateIncoming = not Config.translateIncoming
        UI.Log("Subtítulos EN→ES: " .. (Config.translateIncoming and "|cff44cc44ON|r" or "|cffff4444OFF|r"))

    elseif cmd == "estado" or cmd == "status" then
        local conn = Socket.connected and "|cff44cc44CONECTADO|r" or "|cffff4444DESCONECTADO|r"
        local inc  = Config.translateIncoming and "|cff44cc44ON|r" or "|cffff4444OFF|r"
        UI.Log("Servidor: " .. conn .. "  |  Subtítulos EN→ES: " .. inc)
        UI.Log("Cola: " .. #Queue.pending .. " pendiente(s)")

    elseif cmd == "ayuda" or cmd == "help" or cmd == "" then
        UI.Log("══════ myTraductor v1.2 — Comandos ══════")
        UI.Log("  /en <mensaje>   — Traduce ES→EN y envía al chat (SAY)")
        UI.Log("  /tr conectar    — Conectar al servidor Python")
        UI.Log("  /tr desconectar — Desconectar del servidor")
        UI.Log("  /tr entrante    — Toggle subtítulos EN→ES en mensajes ajenos")
        UI.Log("  /tr estado      — Estado de conexión")
        UI.Log("  /tr ayuda       — Mostrar esta ayuda")

    else
        UI.Warn("Comando desconocido: '" .. cmd .. "'. Usa /tr ayuda.")
    end
end

UI.Log("myTraductor v1.2 | /en <msg> para traducir | /tr ayuda")
