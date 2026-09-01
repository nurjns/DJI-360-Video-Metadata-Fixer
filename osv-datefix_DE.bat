:: Version 1.0.4 - 01.09.2026 - @nurjns

@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title DJI Osmo 360 - Aufnahmedatum aus OSV wiederherstellen

echo ==========================================================
echo  DJI Osmo 360 - Aufnahmedatum aus .OSV wiederherstellen
echo ==========================================================
echo.

:: ExifTool suchen: zuerst im Script-Ordner, danach im PATH
set "EXIFTOOL="
if exist "%~dp0exiftool.exe" set "EXIFTOOL=.\exiftool.exe"
if not defined EXIFTOOL (
	where exiftool >nul 2>&1
	if not errorlevel 1 set "EXIFTOOL=exiftool"
)
if not defined EXIFTOOL (
	echo [FEHLER] ExifTool nicht gefunden^^! exiftool.exe ^(inkl. Ordner "exiftool_files"^) in diesen Ordner legen oder in den PATH aufnehmen.
	pause & exit /b 1
)

"%EXIFTOOL%" -ver >nul 2>&1
if errorlevel 1 (
	echo [FEHLER] ExifTool laesst sich nicht ausfuehren. Fehlt der Ordner "exiftool_files"?
	pause & exit /b 1
)

:: PowerShell wird fuer Datums- und Offset-Berechnung benoetigt
where powershell >nul 2>&1
if errorlevel 1 (
	echo [FEHLER] PowerShell nicht gefunden^^! Wird fuer die Zeitzonen-Berechnung benoetigt.
	pause & exit /b 1
)

:: Pruefen ob ueberhaupt OSV-Dateien vorhanden sind
set "OSV_COUNT=0"
for %%F in (*.osv) do set /a OSV_COUNT+=1
if %OSV_COUNT%==0 (
	echo [FEHLER] Keine .OSV-Dateien in diesem Ordner gefunden.
	echo Das Script muss gemeinsam mit den OSV- und den exportierten MP4-Dateien im selben Ordner liegen.
	echo Aktueller Ordner: %CD%
	pause & exit /b 1
)

echo [INFO] %OSV_COUNT% OSV-Datei^(en^) gefunden.
echo.

:: Benutzerabfrage: Quelle fuer das Aufnahmedatum
echo Welche Quelle soll fuer das Aufnahmedatum verwendet werden?
echo 1 - Dateiname der OSV (Standard)
echo 2 - Aenderungsdatum der OSV
set /p DATESOURCE="Eingabe (1 oder 2): "

if not "%DATESOURCE%"=="1" if not "%DATESOURCE%"=="2" (
	echo Ungueltige Eingabe. Standard: Dateiname wird verwendet.
	set DATESOURCE=1
)

:: Benutzerabfrage: Zeitzone
:: Automatisch Sommer-/Winterzeit erkennen fuer Deutschland
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time'); $now = Get-Date; if($tz.IsDaylightSavingTime($now)) {'+02:00'} else {'+01:00'}"`) do set "SYSTEM_TZ=%%i"

:ASK_TZ
set "TIMEZONE="
echo.
set /p "TIMEZONE=Zeitzone fuer Metadaten (Format: +/-XX:00, leer fuer Standard: !SYSTEM_TZ!): "
if "!TIMEZONE!"=="" (
	echo Leere Eingabe. Standard: !SYSTEM_TZ! wird verwendet
	set "TIMEZONE=!SYSTEM_TZ!"
) else (
	echo !TIMEZONE!| findstr /r "^[+-][0-9][0-9]:[0-9][0-9]$" >nul
	if errorlevel 1 (
		echo Ungueltige Eingabe bei Zeitzone^^! Beispiel: +02:00
		goto ASK_TZ
	)
)

:: Benutzerabfrage: Videos zusaetzlich komprimieren?
echo.
set "COMPRESS="
set /p "COMPRESS=Videos zusaetzlich mit ffmpeg komprimieren? (y/n): "
if /i "!COMPRESS!"=="y" (
	set "COMPRESS=y"
	call :SETUP_COMPRESS
) else (
	set "COMPRESS=n"
)

echo.
echo ----------------------------------------------------------
echo.

set "CNT_OK=0"
set "CNT_SKIP=0"
set "CNT_ERR=0"

:: Schleife durch alle OSV-Dateien
for %%F in (*.osv) do (
	call :PROCESS "%%F"
	echo.
)

echo ----------------------------------------------------------
echo Fertig. Erfolgreich: %CNT_OK%  Uebersprungen: %CNT_SKIP%  Fehler: %CNT_ERR%
powershell -c [console]::beep(500,200)
pause
exit /b 0


:: ==========================================================
:: Verarbeitung einer einzelnen OSV-Datei
:: ==========================================================
:PROCESS
set "OSV=%~1"
set "BASE=%~n1"
set "TIMESTAMP="
set "MP4="

echo Bearbeite: !OSV!

:: --- Aufnahmedatum ermitteln ---
if "%DATESOURCE%"=="1" (
	call :DATE_FROM_NAME
	if not defined TIMESTAMP (
		echo [WARNUNG] Dateiname entspricht nicht dem Muster CAM_JJJJMMTTHHMMSS_... - verwende Aenderungsdatum
		call :DATE_FROM_MTIME
	)
) else (
	call :DATE_FROM_MTIME
)

if not defined TIMESTAMP (
	echo [FEHLER] Kein gueltiges Datum ermittelbar fuer !OSV! - uebersprungen
	set /a CNT_ERR+=1
	goto :eof
)

echo [INFO] Aufnahmedatum: !TIMESTAMP!!TIMEZONE!

:: --- Passende MP4 suchen ---
if exist "!BASE!.mp4" (
	set "MP4=!BASE!.mp4"
) else (
	echo [WARNUNG] Keine passende Datei "!BASE!.mp4" gefunden.
	set "CAND_COUNT=0"
	for %%C in ("!BASE!*.mp4") do (
		set /a CAND_COUNT+=1
		echo         Moeglicher Treffer: %%~nxC
	)
	if !CAND_COUNT! EQU 0 echo         Keine MP4 mit passendem Namensanfang im Ordner.
	goto :ASK_MP4
)
goto :MP4_OK

:ASK_MP4
set "MANUAL="
set /p "MANUAL=Anderen Dateinamen angeben (leer = ueberspringen): "
if "!MANUAL!"=="" (
	echo [OK] Uebersprungen: !OSV! - keine MP4 zugeordnet
	set /a CNT_SKIP+=1
	goto :eof
)
:: Endung ergaenzen, falls vergessen
echo !MANUAL!| findstr /i /e ".mp4" >nul
if errorlevel 1 set "MANUAL=!MANUAL!.mp4"
if not exist "!MANUAL!" (
	echo [FEHLER] Datei "!MANUAL!" existiert nicht.
	goto :ASK_MP4
)
:: Sicherstellen, dass es kein Verzeichnis ist
if exist "!MANUAL!\" (
	echo [FEHLER] "!MANUAL!" ist ein Verzeichnis.
	goto :ASK_MP4
)
set "MP4=!MANUAL!"

:MP4_OK
:: --- Pruefen ob es wirklich eine lesbare MP4-Datei ist ---
set "FILETYPE="
for /f "usebackq delims=" %%T in (`%EXIFTOOL% -s3 -FileType "!MP4!" 2^>nul`) do set "FILETYPE=%%T"
if /i not "!FILETYPE!"=="MP4" (
	echo [FEHLER] "!MP4!" ist keine gueltige oder lesbare MP4-Datei ^(erkannt: "!FILETYPE!"^) - uebersprungen
	set /a CNT_ERR+=1
	goto :eof
)

:: --- Datum in die Originaldatei schreiben ---
call :WRITE_DATE "!MP4!"
if "!WRITE_OK!"=="0" (
	set /a CNT_ERR+=1
	goto :eof
)

:: --- Optional: Video komprimieren und Datum auch dort setzen ---
if /i "%COMPRESS%"=="y" (
	call :COMPRESS_FILE
) else (
	set /a CNT_OK+=1
)
goto :eof


:: ==========================================================
:: Video mit ffmpeg komprimieren, danach Datum setzen
:: ==========================================================
:COMPRESS_FILE
for %%N in ("!MP4!") do set "OUTBASE=%%~nN"

:: Bereits komprimierte Dateien nicht erneut verarbeiten
echo !OUTBASE!| findstr /i "_crf" >nul
if not errorlevel 1 (
	echo [OK] Kompression uebersprungen: !MP4! - bereits komprimiertes Video
	set /a CNT_OK+=1
	goto :eof
)

if "%CODECWAHL%"=="1" (
	set "OUTFILE=!OUTBASE!_crf%CRF_WERT%.mp4"
) else (
	set "OUTFILE=!OUTBASE!_AV1_crf%CRF_WERT%.mp4"
)

if exist "!OUTFILE!" (
	echo [OK] Kompression uebersprungen: !OUTFILE! - bereits mit gleichen Einstellungen gerendert
	set /a CNT_SKIP+=1
	goto :eof
)

echo [INFO] Komprimiere nach: !OUTFILE!
if "%CODECWAHL%"=="1" (
	:: H.265
	ffmpeg -nostdin -y -i "!MP4!" -c:v libx265 -crf %CRF_WERT% -preset medium -pix_fmt yuv420p -tag:v hvc1 -movflags +faststart -c:a copy "!OUTFILE!"
) else (
	:: AV1
	if not "!PRESET_MANUAL!"=="" (
		set "PRESET=!PRESET_MANUAL!"
	) else (
		if !CRF_WERT! LEQ 24 (
			set "PRESET=3"
		) else if !CRF_WERT! LEQ 28 (
			set "PRESET=4"
		) else if !CRF_WERT! LEQ 35 (
			set "PRESET=5"
		) else (
			set "PRESET=8"
		)
	)
	ffmpeg -nostdin -y -i "!MP4!" -c:v libsvtav1 -crf %CRF_WERT% -preset !PRESET! -pix_fmt yuv420p -movflags +faststart -c:a copy "!OUTFILE!"
)

if errorlevel 1 (
	echo [FEHLER] ffmpeg konnte "!MP4!" nicht komprimieren
	if exist "!OUTFILE!" del "!OUTFILE!"
	set /a CNT_ERR+=1
	goto :eof
)

call :WRITE_DATE "!OUTFILE!"
if "!WRITE_OK!"=="0" (
	set /a CNT_ERR+=1
	goto :eof
)

set /a CNT_OK+=1
goto :eof

:: ==========================================================
:: Datum per ExifTool in eine Datei schreiben und kontrollieren
:: ==========================================================
:WRITE_DATE
set "TARGET=%~1"
set "WRITE_OK=1"

:: --- Pruefen ob das Datum bereits korrekt gesetzt ist ---
set "CURRENT="
for /f "usebackq delims=" %%T in (`%EXIFTOOL% -s3 -QuickTime:CreateDate "!TARGET!" 2^>nul`) do set "CURRENT=%%T"
if "!CURRENT!"=="!TIMESTAMP!" (
	echo [OK] Datum bereits korrekt: !TARGET!
	goto :eof
)

"%EXIFTOOL%" -overwrite_original ^
	"-DateTimeOriginal=!TIMESTAMP!!TIMEZONE!" ^
	"-OffsetTimeOriginal=!TIMEZONE!" ^
	"-QuickTime:CreateDate=!TIMESTAMP!" ^
	"-QuickTime:ModifyDate=!TIMESTAMP!" ^
	"-QuickTime:TrackCreateDate=!TIMESTAMP!" ^
	"-QuickTime:TrackModifyDate=!TIMESTAMP!" ^
	"-QuickTime:MediaCreateDate=!TIMESTAMP!" ^
	"-QuickTime:MediaModifyDate=!TIMESTAMP!" ^
	"-FileModifyDate=!TIMESTAMP!" ^
	"!TARGET!"

if errorlevel 1 (
	echo [FEHLER] ExifTool konnte "!TARGET!" nicht schreiben
	set "WRITE_OK=0"
	goto :eof
)

:: --- Kontrolle: geschriebenen Wert zurueckgelesen ---
set "VERIFY="
for /f "usebackq delims=" %%T in (`%EXIFTOOL% -s3 -QuickTime:CreateDate "!TARGET!" 2^>nul`) do set "VERIFY=%%T"
if not "!VERIFY!"=="!TIMESTAMP!" (
	echo [FEHLER] Kontrolle fehlgeschlagen fuer "!TARGET!" - gelesen: !VERIFY!
	set "WRITE_OK=0"
	goto :eof
)

echo [OK] Verarbeitet: !TARGET!
goto :eof

:: ==========================================================
:: Einstellungen fuer die Kompression abfragen
:: ==========================================================
:SETUP_COMPRESS
:: ffprobe wird nicht benoetigt, da nicht geschnitten wird
where ffmpeg >nul 2>&1
if errorlevel 1 (
	if exist "%~dp0ffmpeg.exe" (
		set "PATH=%~dp0;%PATH%"
	) else (
		echo [FEHLER] ffmpeg nicht gefunden^^! ffmpeg.exe in diesen Ordner legen oder in den PATH aufnehmen.
		echo [INFO] Kompression wird deaktiviert, Datum wird trotzdem gesetzt.
		set "COMPRESS=n"
		goto :eof
	)
)

:: Benutzerabfrage: Codec-Auswahl
echo.
echo Waehle Codec:
echo 1 - H.265 - Gute Kompression, breite Unterstuetzung (Standard)
echo 2 - AV1 - Beste Kompression, Geschwindigkeit haengt von Qualitaetsstufe ab, fuer neuere Geraete
set /p CODECWAHL="Eingabe (1 oder 2): "

if not "!CODECWAHL!"=="1" if not "!CODECWAHL!"=="2" (
	echo Ungueltige Eingabe. Standard: H.265 wird verwendet.
	set CODECWAHL=1
)

:: Benutzerabfrage: CRF-Wert
:ASK_CRF
set CRF_WERT=
if "!CODECWAHL!"=="1" (
	echo H.265 CRF-Wert ^(18=hoch, 24=normal, 30=niedrig, 35=sehr niedrig^)
) else (
	echo AV1 CRF-Wert ^(20=sehr hoch, 26=hoch, 35=normal, 45=niedrig, 55=sehr niedrig^)
)
set /p CRF_WERT="Welcher CRF-Wert soll verwendet werden? "

echo !CRF_WERT!| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 goto :CRF_FEHLER
if "!CRF_WERT!" LSS "16" goto :CRF_FEHLER
if "!CRF_WERT!" GTR "55" goto :CRF_FEHLER
goto :CRF_OK
:CRF_FEHLER
echo Ungueltige Eingabe bei CRF-Wert^^!
goto ASK_CRF
:CRF_OK

set "PRESET_MANUAL="
if not "!CODECWAHL!"=="2" goto :PRESET_DONE

:ASK_PRESET
set "PRESET_MANUAL="
set /p PRESET_MANUAL="AV1 Preset (0-13, 0=langsam/kleine Datei, 13=schnell/grosse Datei, leer lassen = automatisch): "
if not "!PRESET_MANUAL!"=="" (
	echo !PRESET_MANUAL!| findstr /r "^[0-9][0-9]*$" >nul
	if errorlevel 1 goto :PRESET_FEHLER
	if "!PRESET_MANUAL!" GTR "13" goto :PRESET_FEHLER
)
goto :PRESET_DONE
:PRESET_FEHLER
echo Ungueltiger Preset-Wert^^!
goto ASK_PRESET

:PRESET_DONE
goto :eof

:: ==========================================================
:: Datum aus dem OSV-Dateinamen (CAM_JJJJMMTTHHMMSS_...)
:: ==========================================================
:DATE_FROM_NAME
echo !BASE!| findstr /r /i "^CAM_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_" >nul
if errorlevel 1 goto :eof

for /f "tokens=2 delims=_" %%A in ("!BASE!") do set "DATETIME=%%A"
set "YYYY=!DATETIME:~0,4!"
set "MM=!DATETIME:~4,2!"
set "DD=!DATETIME:~6,2!"
set "hh=!DATETIME:~8,2!"
set "nn=!DATETIME:~10,2!"
set "ss=!DATETIME:~12,2!"

set "TIMESTAMP=!YYYY!:!MM!:!DD! !hh!:!nn!:!ss!"
goto :eof

:: ==========================================================
:: Datum aus dem Aenderungsdatum der OSV-Datei
:: ==========================================================
:DATE_FROM_MTIME
for /f "usebackq delims=" %%T in (`powershell -NoLogo -NoProfile -Command "(Get-Item -LiteralPath '!OSV!').LastWriteTime.ToString('yyyy:MM:dd HH:mm:ss')"`) do (
	set "TIMESTAMP=%%T"
)
goto :eof
