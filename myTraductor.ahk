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

; ── Solo activo cuando Ascension (WoW) tiene el foco ────────────
#IfWinActive ahk_exe Ascension.exe

F12::
    ; 1. Seleccionar todo el texto del chat input
    Send, ^a
    Sleep, 60

    ; 2. Copiar al portapapeles
    ClipSaved := ClipboardAll
    Clipboard =
    Send, ^c
    ClipWait, 1

    original := Trim(Clipboard)

    if (original = "") {
        Clipboard  := ClipSaved
        ClipSaved  :=
        Send, {Enter}
        return
    }

    ; 3. Traducir vía LibreTranslate
    translated := Translate(original)

    ; 4. Si falla la traducción, enviar el original sin cambios
    if (translated = "") {
        Clipboard  := ClipSaved
        ClipSaved  :=
        Send, {Enter}
        return
    }

    ; 5. Borrar el texto original del chat input
    Send, ^a
    Sleep, 30
    Send, {Delete}
    Sleep, 30

    ; 6. Pegar la traducción
    Clipboard := translated
    Send, ^v
    Sleep, 80

    ; 7. Enviar el mensaje
    Send, {Enter}

    ; 8. Restaurar portapapeles
    Sleep, 100
    Clipboard  := ClipSaved
    ClipSaved  :=
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
    req.SetTimeouts(3000, 3000, 3000, 3000)

    try {
        req.Send(body)
    } catch e {
        return ""
    }

    if (req.Status != 200)
        return ""

    ; Parsear {"translatedText":"..."}
    if RegExMatch(req.ResponseText, """translatedText""\s*:\s*""((?:[^""\\]|\\.)*)""", m)
        return UnescapeJSON(m1)

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
