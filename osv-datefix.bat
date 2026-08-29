:: Version 1.0.0 - 2026-08-26 - @nurjns

@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title DJI Osmo 360 - Restore recording date from OSV

echo ==========================================================
echo  DJI Osmo 360 - Restore recording date from .OSV
echo ==========================================================
echo.

:: Locate ExifTool: first in the script folder, then in PATH
set "EXIFTOOL="
if exist "%~dp0exiftool.exe" set "EXIFTOOL=.\exiftool.exe"
if not defined EXIFTOOL (
	where exiftool >nul 2>&1
	if not errorlevel 1 set "EXIFTOOL=exiftool"
)
if not defined EXIFTOOL (
	echo [ERROR] ExifTool not found^^! Place exiftool.exe ^(incl. "exiftool_files" folder^) in this directory or add it to PATH.
	pause & exit /b 1
)

"%EXIFTOOL%" -ver >nul 2>&1
if errorlevel 1 (
	echo [ERROR] ExifTool cannot be executed. Is the "exiftool_files" folder missing?
	pause & exit /b 1
)

:: PowerShell is required for date and offset calculation
where powershell >nul 2>&1
if errorlevel 1 (
	echo [ERROR] PowerShell not found^^! Required for timezone calculation.
	pause & exit /b 1
)

:: Check whether any OSV files exist at all
set "OSV_COUNT=0"
for %%F in (*.osv) do set /a OSV_COUNT+=1
if %OSV_COUNT%==0 (
	echo [ERROR] No .OSV files found in this folder.
	echo The script must be located in the same folder as the OSV and exported MP4 files.
	echo Current folder: %CD%
	pause & exit /b 1
)

echo [INFO] %OSV_COUNT% OSV file^(s^) found.
echo.

:: User prompt: source for the recording date
echo Which source should be used for the recording date?
echo 1 - Filename of the OSV (default)
echo 2 - Modification date of the OSV
set /p DATESOURCE="Input (1 or 2): "

if not "%DATESOURCE%"=="1" if not "%DATESOURCE%"=="2" (
	echo Invalid input. Default: filename will be used.
	set DATESOURCE=1
)

:: User prompt: timezone
:: Automatically detect daylight saving time for Germany
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time'); $now = Get-Date; if($tz.IsDaylightSavingTime($now)) {'+02:00'} else {'+01:00'}"`) do set "SYSTEM_TZ=%%i"

:ASK_TZ
set "TIMEZONE="
echo.
set /p "TIMEZONE=Timezone for metadata (format: +/-XX:00, leave blank for default: !SYSTEM_TZ!): "
if "!TIMEZONE!"=="" (
	echo Empty input. Default: !SYSTEM_TZ! will be used
	set "TIMEZONE=!SYSTEM_TZ!"
) else (
	echo !TIMEZONE!| findstr /r "^[+-][0-9][0-9]:[0-9][0-9]$" >nul
	if errorlevel 1 (
		echo Invalid timezone input^^! Example: +02:00
		goto ASK_TZ
	)
)

:: User prompt: additionally compress videos?
echo.
set "COMPRESS="
set /p "COMPRESS=Additionally compress videos with ffmpeg? (y/n): "
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

:: Loop through all OSV files
for %%F in (*.osv) do (
	call :PROCESS "%%F"
	echo.
)

echo ----------------------------------------------------------
echo Done. Successful: %CNT_OK%  Skipped: %CNT_SKIP%  Errors: %CNT_ERR%
powershell -c [console]::beep(500,200)
pause
exit /b 0


:: ==========================================================
:: Process a single OSV file
:: ==========================================================
:PROCESS
set "OSV=%~1"
set "BASE=%~n1"
set "TIMESTAMP="
set "MP4="

echo Processing: !OSV!

:: --- Determine recording date ---
if "%DATESOURCE%"=="1" (
	call :DATE_FROM_NAME
	if not defined TIMESTAMP (
		echo [WARNING] Filename does not match the pattern CAM_YYYYMMDDHHMMSS_... - using modification date
		call :DATE_FROM_MTIME
	)
) else (
	call :DATE_FROM_MTIME
)

if not defined TIMESTAMP (
	echo [ERROR] No valid date could be determined for !OSV! - skipped
	set /a CNT_ERR+=1
	goto :eof
)

echo [INFO] Recording date: !TIMESTAMP!!TIMEZONE!

:: --- Find matching MP4 ---
if exist "!BASE!.mp4" (
	set "MP4=!BASE!.mp4"
) else (
	echo [WARNING] No matching file "!BASE!.mp4" found.
	set "CAND_COUNT=0"
	for %%C in ("!BASE!*.mp4") do (
		set /a CAND_COUNT+=1
		echo         Possible match: %%~nxC
	)
	if !CAND_COUNT! EQU 0 echo         No MP4 with matching filename prefix in this folder.
	goto :ASK_MP4
)
goto :MP4_OK

:ASK_MP4
set "MANUAL="
set /p "MANUAL=Enter a different filename (leave blank to skip): "
if "!MANUAL!"=="" (
	echo [OK] Skipped: !OSV! - no MP4 assigned
	set /a CNT_SKIP+=1
	goto :eof
)
:: Add extension if forgotten
echo !MANUAL!| findstr /i /e ".mp4" >nul
if errorlevel 1 set "MANUAL=!MANUAL!.mp4"
if not exist "!MANUAL!" (
	echo [ERROR] File "!MANUAL!" does not exist.
	goto :ASK_MP4
)
:: Make sure it isn't a directory
if exist "!MANUAL!\" (
	echo [ERROR] "!MANUAL!" is a directory.
	goto :ASK_MP4
)
set "MP4=!MANUAL!"

:MP4_OK
:: --- Check whether it's really a readable MP4 file ---
set "FILETYPE="
for /f "usebackq delims=" %%T in (`%EXIFTOOL% -s3 -FileType "!MP4!" 2^>nul`) do set "FILETYPE=%%T"
if /i not "!FILETYPE!"=="MP4" (
	echo [ERROR] "!MP4!" is not a valid or readable MP4 file ^(detected: "!FILETYPE!"^) - skipped
	set /a CNT_ERR+=1
	goto :eof
)

:: --- Write the date to the original file ---
call :WRITE_DATE "!MP4!"
if "!WRITE_OK!"=="0" (
	set /a CNT_ERR+=1
	goto :eof
)

:: --- Optional: compress video and set the date there too ---
if /i "%COMPRESS%"=="y" (
	call :COMPRESS_FILE
) else (
	set /a CNT_OK+=1
)
goto :eof


:: ==========================================================
:: Compress video with ffmpeg, then set the date
:: ==========================================================
:COMPRESS_FILE
for %%N in ("!MP4!") do set "OUTBASE=%%~nN"

:: Do not process already compressed files again
echo !OUTBASE!| findstr /i "_crf" >nul
if not errorlevel 1 (
	echo [OK] Compression skipped: !MP4! - already a compressed video
	set /a CNT_OK+=1
	goto :eof
)

if "%CODECWAHL%"=="1" (
	set "OUTFILE=!OUTBASE!_crf%CRF_WERT%.mp4"
) else (
	set "OUTFILE=!OUTBASE!_AV1_crf%CRF_WERT%.mp4"
)

if exist "!OUTFILE!" (
	echo [OK] Compression skipped: !OUTFILE! - already rendered with the same settings
	set /a CNT_SKIP+=1
	goto :eof
)

echo [INFO] Compressing to: !OUTFILE!
if "%CODECWAHL%"=="1" (
	ffmpeg -nostdin -y -i "!MP4!" -c:v libx265 -crf %CRF_WERT% -preset slow -pix_fmt yuv420p -tag:v hvc1 -movflags +faststart -c:a copy "!OUTFILE!"
) else (
	ffmpeg -nostdin -y -i "!MP4!" -c:v libaom-av1 -crf %CRF_WERT% -cpu-used %CPU_USED% -pix_fmt yuv420p -movflags +faststart -c:a copy "!OUTFILE!"
)

if errorlevel 1 (
	echo [ERROR] ffmpeg could not compress "!MP4!"
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
:: Write date via ExifTool to a file and verify it
:: ==========================================================
:WRITE_DATE
set "TARGET=%~1"
set "WRITE_OK=1"

:: --- Check whether the date is already set correctly ---
set "CURRENT="
for /f "usebackq delims=" %%T in (`%EXIFTOOL% -s3 -QuickTime:CreateDate "!TARGET!" 2^>nul`) do set "CURRENT=%%T"
if "!CURRENT!"=="!TIMESTAMP!" (
	echo [OK] Date already correct: !TARGET!
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
	echo [ERROR] ExifTool could not write "!TARGET!"
	set "WRITE_OK=0"
	goto :eof
)

:: --- Verification: read back the value that was written ---
set "VERIFY="
for /f "usebackq delims=" %%T in (`%EXIFTOOL% -s3 -QuickTime:CreateDate "!TARGET!" 2^>nul`) do set "VERIFY=%%T"
if not "!VERIFY!"=="!TIMESTAMP!" (
	echo [ERROR] Verification failed for "!TARGET!" - read back: !VERIFY!
	set "WRITE_OK=0"
	goto :eof
)

echo [OK] Processed: !TARGET!
goto :eof


:: ==========================================================
:: Ask for compression settings
:: ==========================================================
:SETUP_COMPRESS
:: ffprobe is not needed, since no cutting is done
where ffmpeg >nul 2>&1
if errorlevel 1 (
	if exist "%~dp0ffmpeg.exe" (
		set "PATH=%~dp0;%PATH%"
	) else (
		echo [ERROR] ffmpeg not found^^! Place ffmpeg.exe in this directory or add it to PATH.
		echo [INFO] Compression disabled, date will be set anyway.
		set "COMPRESS=n"
		goto :eof
	)
)

:: User prompt: codec selection
echo.
echo Choose codec:
echo 1 - H.265 - Good compression, faster encoding, wide support (default)
echo 2 - AV1 - Best compression, but very slow, for newer devices
set /p CODECWAHL="Input (1 or 2): "

if not "!CODECWAHL!"=="1" if not "!CODECWAHL!"=="2" (
	echo Invalid input. Default: H.265 will be used.
	set CODECWAHL=1
)

:: User prompt: CRF value
:ASK_CRF
set CRF_WERT=
if "!CODECWAHL!"=="1" (
	echo H.265 CRF value ^(18=high, 24=normal, 30=low, 35=very low^)
) else (
	echo AV1 CRF value ^(20=high, 30=normal, 38=low, 45=very low^)
)
set /p CRF_WERT="Which CRF value should be used? "

echo !CRF_WERT!| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 goto :CRF_FEHLER
if !CRF_WERT! LSS 16 goto :CRF_FEHLER
if !CRF_WERT! GTR 50 goto :CRF_FEHLER
goto :CRF_OK
:CRF_FEHLER
echo Invalid CRF value^^!
goto ASK_CRF
:CRF_OK

:: AV1 - determine cpu-used dynamically
if !CRF_WERT! LEQ 20 (
	set "CPU_USED=2"
) else if !CRF_WERT! LEQ 28 (
	set "CPU_USED=4"
) else if !CRF_WERT! LEQ 35 (
	set "CPU_USED=6"
) else (
	set "CPU_USED=8"
)
goto :eof


:: ==========================================================
:: Date from the OSV filename (CAM_YYYYMMDDHHMMSS_...)
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
:: Date from the OSV file's modification date
:: ==========================================================
:DATE_FROM_MTIME
for /f "usebackq delims=" %%T in (`powershell -NoLogo -NoProfile -Command "(Get-Item -LiteralPath '!OSV!').LastWriteTime.ToString('yyyy:MM:dd HH:mm:ss')"`) do (
	set "TIMESTAMP=%%T"
)
goto :eof
