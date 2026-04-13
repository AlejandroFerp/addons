; ================================================================
; myTraductor.ahk — AutoHotkey v2
;
; Traduce lo que escribes en el chat de WoW (ES → EN)
; SIN modificar el cliente de WoW.
;
; Uso:
;   1. Abre el chat en WoW (Enter)
;   2. Escribe tu mensaje en español
;   3. Presiona F12 en lugar de Enter
;   → El addon traduce y envía automáticamente
;
; Requisito: LibreTranslate corriendo en 127.0.0.1:5000
; ================================================================
#Requires AutoHotkey v2.0

LIBRETRANSLATE := "http://127.0.0.1:5000"
SOURCE := "es"
TARGET := "en"

; ── Solo activo cuando la ventana de WoW tiene el foco ──────────
#HotIf WinActive("ahk_exe Wow.exe") or WinActive("ahk_exe WoW.exe")

; F12 = traducir el texto del chat input y enviarlo
F12:: {
    ; 1. Seleccionar todo el texto del chat input (Ctrl+A)
    Send "^a"
    Sleep 60

    ; 2. Copiar al portapapeles (Ctrl+C)
    oldClip := ClipboardAll()
    A_Clipboard := ""
    Send "^c"
    ClipWait 1

    original := Trim(A_Clipboard)

    ; Restaurar portapapeles original al terminar
    if (original = "") {
        A_Clipboard := oldClip
        Send "{Enter}"   ; sin texto → enviar normal
        return
    }

    ; 3. Traducir vía LibreTranslate
    translated := Translate(original, SOURCE, TARGET)

    ; 4. Si falla la traducción, enviar el original sin cambios
    if (translated = "") {
        A_Clipboard := oldClip
        Send "{Enter}"
        return
    }

    ; 5. Borrar el texto original del chat input
    Send "^a"
    Sleep 30
    Send "{Delete}"
    Sleep 30

    ; 6. Pegar la traducción (más rápido que tipear letra a letra)
    A_Clipboard := translated
    Send "^v"
    Sleep 80

    ; 7. Enviar el mensaje
    Send "{Enter}"

    ; 8. Restaurar portapapeles
    Sleep 100
    A_Clipboard := oldClip
}

#HotIf   ; Desactivar el contexto WoW


; ================================================================
; Translate(text, source, target) → string | ""
; Llama directamente a la API REST de LibreTranslate.
; ================================================================
Translate(text, source, target) {
    global LIBRETRANSLATE

    body := '{"q":"' . EscapeJSON(text) . '",'
          . '"source":"' . source . '",'
          . '"target":"' . target . '",'
          . '"format":"text"}'

    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("POST", LIBRETRANSLATE . "/translate", false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetTimeouts(3000, 3000, 3000, 3000)   ; 3 s timeout

    try {
        req.Send(body)
    } catch {
        return ""
    }

    if (req.Status != 200) {
        return ""
    }

    ; Parsear "translatedText" del JSON de respuesta
    ; Ejemplo: {"translatedText":"hello how are you"}
    if RegExMatch(req.ResponseText, '"translatedText"\s*:\s*"((?:[^"\\]|\\.)*)"', &m) {
        return UnescapeJSON(m[1])
    }

    return ""
}


; ================================================================
; Helpers JSON mínimos (sin dependencias externas)
; ================================================================
EscapeJSON(str) {
    str := StrReplace(str, "\",  "\\")
    str := StrReplace(str, '"',  '\"')
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    return str
}

UnescapeJSON(str) {
    str := StrReplace(str, "\\n", "`n")
    str := StrReplace(str, "\\r", "`r")
    str := StrReplace(str, "\\t", "`t")
    str := StrReplace(str, '\\"', '"')
    str := StrReplace(str, "\\\\", "\")
    return str
}
