; ================================================================
; myTraductor.ahk — AutoHotkey v1
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
#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

LIBRETRANSLATE := "http://127.0.0.1:5000"
SOURCE         := "es"
TARGET         := "en"

; ── F12 solo activo cuando Ascension (WoW) tiene el foco ────────
#IfWinActive ahk_exe Ascension.exe
F12::
    ; Feedback inmediato: si ves este tooltip saber que AHK capturó F12
    ToolTip, [Traductor] Capturando texto...
    Sleep, 60

    ; 1. Seleccionar todo el texto del chat input
    Send, ^a
    Sleep, 80

    ; 2. Copiar al portapapeles
    ClipSaved := ClipboardAll
    Clipboard =
    Send, ^c
    ClipWait, 1

    original := Trim(Clipboard)

    if (original = "") {
        ToolTip, [Traductor] Sin texto en portapapeles.
        Sleep, 1500
        ToolTip
        Clipboard  := ClipSaved
        ClipSaved  :=
        Send, {Enter}
        return
    }

    ToolTip, [Traductor] Traduciendo: %original%
    Sleep, 200

    ; 3. Traducir vía LibreTranslate
    translated := Translate(original)

    if (translated = "") {
        ToolTip, [Traductor] ERROR - LibreTranslate no responde. Enviando original.
        Sleep, 2000
        ToolTip
        Clipboard  := ClipSaved
        ClipSaved  :=
        Send, {Enter}
        return
    }

    ToolTip, [Traductor] OK: %translated%
    Sleep, 200

    ; 4. Borrar el texto original del chat input
    Send, ^a
    Sleep, 30
    Send, {Delete}
    Sleep, 30

    ; 5. Pegar la traducción
    Clipboard := translated
    Send, ^v
    Sleep, 80

    ; 6. Enviar el mensaje
    Send, {Enter}

    ; 7. Restaurar portapapeles y limpiar tooltip
    Sleep, 100
    Clipboard  := ClipSaved
    ClipSaved  :=
    ToolTip
return
#IfWinActive


; ================================================================
; Translate(text) → string traducido | "" si falla
; ================================================================
Translate(text) {
    global LIBRETRANSLATE, SOURCE, TARGET

    body := "{""q"":""" . EscapeJSON(text) . ""","
           . """source"":""" . SOURCE . ""","
           . """target"":""" . TARGET . ""","
           . """format"":""text""}"

    req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    req.Open("POST", LIBRETRANSLATE . "/translate", false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetTimeouts(10000, 10000, 10000, 10000)

    try {
        req.Send(body)
    } catch e {
        ToolTip, [Traductor] HTTP ERROR: %e%
        Sleep, 3000
        ToolTip
        return ""
    }

    status := req.Status
    resp   := req.ResponseText

    if (status != 200) {
        ToolTip, [Traductor] HTTP %status%: %resp%
        Sleep, 3000
        ToolTip
        return ""
    }

    ; Parsear {"translatedText":"..."}
    if RegExMatch(resp, """translatedText""\s*:\s*""((?:[^""\\]|\\.)*)""", m)
        return UnescapeJSON(m1)

    ; Si llegamos aquí el JSON no tiene translatedText
    ToolTip, [Traductor] JSON inesperado: %resp%
    Sleep, 3000
    ToolTip
    return ""
}


; ================================================================
; Helpers JSON mínimos
; ================================================================
EscapeJSON(str) {
    str := StrReplace(str, "\",   "\\")
    str := StrReplace(str, """",  "\""")
    str := StrReplace(str, "`n",  "\n")
    str := StrReplace(str, "`r",  "\r")
    str := StrReplace(str, "`t",  "\t")
    return str
}

UnescapeJSON(str) {
    str := StrReplace(str, "\n",   "`n")
    str := StrReplace(str, "\r",   "`r")
    str := StrReplace(str, "\t",   "`t")
    str := StrReplace(str, "\""",  """")
    str := StrReplace(str, "\\",   "\")
    return str
}
