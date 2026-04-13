' run-libretranslate.vbs
' Lanza LibreTranslate completamente oculto (sin ventana de consola).
' Invocado por la tarea del Task Scheduler al iniciar sesión.

Dim ltExe
ltExe = CreateObject("WScript.Shell").ExpandEnvironmentStrings( _
    "%LOCALAPPDATA%\Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0" & _
    "\LocalCache\local-packages\Python313\Scripts\libretranslate.exe")

' 0 = ventana oculta, False = no esperar a que termine (corre en background)
CreateObject("WScript.Shell").Run _
    Chr(34) & ltExe & Chr(34) & " --host 127.0.0.1 --port 5000 --load-only en,es", _
    0, False
