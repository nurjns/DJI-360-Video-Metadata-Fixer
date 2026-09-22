:: Version 1.1.2 - 22.09.2026 - @nurjns

@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title DJI 360 Video Metadata Fixer

echo ==========================================================
echo  DJI 360 Video Metadata Fixer
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

:: Pruefen ob ueberhaupt OSV- oder eigenstaendige MP4-Dateien vorhanden sind
set "OSV_COUNT=0"
for %%F in (*.osv) do set /a OSV_COUNT+=1
set "MP4_COUNT=0"
for %%F in (dji_mimo_*.mp4 compose_video_*.mp4) do set /a MP4_COUNT+=1
if %OSV_COUNT%==0 if %MP4_COUNT%==0 (
	echo [FEHLER] Keine .OSV- oder unterstuetzten MP4-Dateien in diesem Ordner gefunden.
	echo Das Script muss gemeinsam mit den OSV- und den exportierten MP4-Dateien im selben Ordner liegen.
	echo Aktueller Ordner: %CD%
	pause & exit /b 1
)

echo [INFO] %OSV_COUNT% OSV-Datei^(en^), %MP4_COUNT% eigenstaendige MP4-Datei^(en^) gefunden.
echo.

:: Benutzerabfrage: Quelle fuer das Aufnahmedatum (nur bei OSV-Dateien relevant)
set "DATESOURCE=1"
if %OSV_COUNT%==0 goto :SKIP_DATESOURCE
echo Welche Quelle soll fuer das Aufnahmedatum verwendet werden?
echo 1 - Dateiname der OSV (Standard)
echo 2 - Aenderungsdatum der OSV
set /p DATESOURCE="Eingabe (1 oder 2): "

if not "%DATESOURCE%"=="1" if not "%DATESOURCE%"=="2" (
	echo Ungueltige Eingabe. Standard: Dateiname wird verwendet.
	set DATESOURCE=1
)
:SKIP_DATESOURCE

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

:: Temporaere Liste der bereits einer OSV zugeordneten MP4-Dateien
set "DONE_LIST=%TEMP%\osv-datefix_%RANDOM%.tmp"
type nul > "%DONE_LIST%"

:: Schleife durch alle OSV-Dateien
for %%F in (*.osv) do (
	call :PROCESS "%%F"
	echo.
)

:: Schleife durch MP4-Dateien ohne gleichnamige OSV (z.B. mehrere Exporte einer OSV)
if %OSV_COUNT% GTR 0 (
	set "IDX=0"
	for %%F in (*.osv) do (
		set /a IDX+=1
		set "OSV_!IDX!=%%F"
		set "OSVBASE_!IDX!=%%~nF"
	)
	for %%F in (*.mp4) do (
		call :PROCESS_ORPHAN "%%F"
	)
)

:: Schleife durch eigenstaendige MP4-Dateien ohne OSV (dji_mimo / compose_video)
for %%F in (dji_mimo_*.mp4 compose_video_*.mp4) do (
	call :PROCESS_NOOSV "%%F"
	echo.
)

echo ----------------------------------------------------------
echo Fertig. Erfolgreich: %CNT_OK%  Uebersprungen: %CNT_SKIP%  Fehler: %CNT_ERR%
del "%DONE_LIST%" >nul 2>&1
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
set "MP4=%~2"

if not defined MP4 echo Bearbeite: !OSV!

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

:: --- MP4 bereits zugeordnet (aus :PROCESS_ORPHAN)? Dann Suche ueberspringen ---
if defined MP4 goto :MP4_OK

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
:: Zugeordnete MP4 merken, damit sie spaeter nicht erneut abgefragt wird
>>"%DONE_LIST%" echo(!MP4!

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
:: MP4 ohne gleichnamige OSV einer OSV zuordnen
:: ==========================================================
:PROCESS_ORPHAN
set "ORPHAN=%~1"
set "ORPHAN_BASE=%~n1"

:: dji_mimo / compose_video werden separat verarbeitet
echo !ORPHAN_BASE!| findstr /r /i "^dji_mimo_ ^compose_video_" >nul
if not errorlevel 1 goto :eof

:: Bereits komprimierte Ableitungen ignorieren (z.B. *_crf28.mp4)
echo !ORPHAN_BASE!| findstr /i "_crf" >nul
if not errorlevel 1 goto :eof

:: MP4 mit gleichnamiger OSV wurde bereits in der OSV-Schleife verarbeitet
if exist "!ORPHAN_BASE!.osv" goto :eof

:: Bereits manuell einer OSV zugeordnet
findstr /x /l /i /c:"!ORPHAN!" "%DONE_LIST%" >nul 2>&1
if not errorlevel 1 goto :eof

echo Bearbeite: !ORPHAN!
echo [WARNUNG] Keine gleichnamige OSV gefunden. Zu welcher OSV gehoert diese MP4?
for /l %%I in (1,1,%OSV_COUNT%) do call :SHOW_OSV %%I

:ASK_OSV
set "OSV_CHOICE="
set /p "OSV_CHOICE=Nummer der OSV (leer = ueberspringen): "
if "!OSV_CHOICE!"=="" (
	echo [OK] Uebersprungen: !ORPHAN! - keine OSV zugeordnet
	set /a CNT_SKIP+=1
	echo.
	goto :eof
)
echo !OSV_CHOICE!| findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 goto :OSV_FEHLER
if !OSV_CHOICE! GTR %OSV_COUNT% goto :OSV_FEHLER
goto :OSV_OK
:OSV_FEHLER
echo Ungueltige Eingabe^^! Bitte eine Zahl von 1 bis %OSV_COUNT% eingeben.
goto :ASK_OSV
:OSV_OK

for %%N in (!OSV_CHOICE!) do set "OSV_PICK=!OSV_%%N!"
call :PROCESS "!OSV_PICK!" "!ORPHAN!"
echo.
goto :eof


:: ==========================================================
:: OSV-Eintrag der Auswahlliste anzeigen (mit Hinweis, wenn der Name passt)
:: ==========================================================
:SHOW_OSV
set "MARK="
echo !ORPHAN_BASE!| findstr /b /l /i /c:"!OSVBASE_%~1!" >nul
if not errorlevel 1 set "MARK= [Name passt]"
echo         %~1 - !OSV_%~1!!MARK!
goto :eof


:: ==========================================================
:: Eigenstaendige MP4-Datei ohne OSV verarbeiten (dji_mimo / compose_video)
:: ==========================================================
:PROCESS_NOOSV
set "MP4=%~1"
set "BASE=%~n1"
set "TIMESTAMP="

:: Bereits komprimierte Ableitungen ignorieren (z.B. *_crf28.mp4)
echo !BASE!| findstr /i "_crf" >nul
if not errorlevel 1 goto :eof

echo Bearbeite: !MP4!

:: --- Aufnahmedatum ermitteln ---
:: dji_mimo-Dateien tragen das Datum im Namen, alles andere wird per Fenster abgefragt
call :DATE_FROM_MIMO
if not defined TIMESTAMP (
	echo [INFO] Kein Datum im Dateinamen - bitte im Fenster auswaehlen
	call :DATE_FROM_PICKER "!MP4!"
)

if not defined TIMESTAMP (
	echo [OK] Uebersprungen: !MP4! - keine Datumsauswahl
	set /a CNT_SKIP+=1
	goto :eof
)

echo [INFO] Aufnahmedatum: !TIMESTAMP!!TIMEZONE!

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
	ffmpeg -nostdin -y -i "!MP4!" -c:v libsvtav1 -crf %CRF_WERT% -preset !PRESET! -g 240 -pix_fmt yuv420p10le -svtav1-params tune=0 -movflags +faststart -c:a copy "!OUTFILE!"
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
	"-FileModifyDate=!TIMESTAMP!!TIMEZONE!" ^
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
	echo AV1 CRF-Wert ^(22=sehr hoch, 28=hoch, 35=normal, 45=niedrig, 55=sehr niedrig^)
)
set /p CRF_WERT="Welcher CRF-Wert soll verwendet werden? "

echo !CRF_WERT!| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 goto :CRF_FEHLER
if "!CRF_WERT!" LSS "16" goto :CRF_FEHLER
if "!CRF_WERT!" GTR "60" goto :CRF_FEHLER
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

:: ==========================================================
:: Datum aus einem DJI-Mimo-Dateinamen (dji_mimo_JJJJMMTT_HHMMSS_...)
:: ==========================================================
:DATE_FROM_MIMO
echo !BASE!| findstr /r /i "^dji_mimo_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]_" >nul
if errorlevel 1 goto :eof

for /f "tokens=3,4 delims=_" %%A in ("!BASE!") do (
	set "DATEPART=%%A"
	set "TIMEPART=%%B"
)
set "YYYY=!DATEPART:~0,4!"
set "MM=!DATEPART:~4,2!"
set "DD=!DATEPART:~6,2!"
set "hh=!TIMEPART:~0,2!"
set "nn=!TIMEPART:~2,2!"
set "ss=!TIMEPART:~4,2!"

set "TIMESTAMP=!YYYY!:!MM!:!DD! !hh!:!nn!:!ss!"
goto :eof

:: ==========================================================
:: Aufnahmedatum grafisch abfragen (Windows-Fenster)
:: ==========================================================
:DATE_FROM_PICKER
set "PICK_FILE=%~1"
set "TIMESTAMP="
for /f "usebackq delims=" %%T in (`powershell -NoProfile -STA -Command "$ErrorActionPreference='SilentlyContinue'; Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $f=New-Object System.Windows.Forms.Form; $f.Text='Aufnahmedatum waehlen'; $f.ClientSize=New-Object System.Drawing.Size(320,150); $f.StartPosition='CenterScreen'; $f.FormBorderStyle='FixedDialog'; $f.MaximizeBox=$false; $f.MinimizeBox=$false; $f.TopMost=$true; $l=New-Object System.Windows.Forms.Label; $l.Text='Datei: '+$env:PICK_FILE; $l.AutoSize=$false; $l.Size=New-Object System.Drawing.Size(300,30); $l.Location=New-Object System.Drawing.Point(10,10); $f.Controls.Add($l); $dp=New-Object System.Windows.Forms.DateTimePicker; $dp.Format='Custom'; $dp.CustomFormat='dd.MM.yyyy'; $dp.ShowUpDown=$true; $dp.Location=New-Object System.Drawing.Point(10,55); $dp.Width=150; $f.Controls.Add($dp); $tp=New-Object System.Windows.Forms.DateTimePicker; $tp.Format='Time'; $tp.ShowUpDown=$true; $tp.Location=New-Object System.Drawing.Point(170,55); $tp.Width=130; $f.Controls.Add($tp); try{$fi=Get-Item -LiteralPath $env:PICK_FILE; $dp.Value=$fi.LastWriteTime; $tp.Value=$fi.LastWriteTime}catch{}; $b=New-Object System.Windows.Forms.Button; $b.Text='OK'; $b.Location=New-Object System.Drawing.Point(10,100); $b.DialogResult=[System.Windows.Forms.DialogResult]::OK; $f.Controls.Add($b); $f.AcceptButton=$b; $c=New-Object System.Windows.Forms.Button; $c.Text='Abbrechen'; $c.Location=New-Object System.Drawing.Point(120,100); $c.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $f.Controls.Add($c); $f.CancelButton=$c; if($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){($dp.Value.Date + $tp.Value.TimeOfDay).ToString('yyyy:MM:dd HH:mm:ss')}"`) do set "TIMESTAMP=%%T"
set "PICK_FILE="
goto :eof
