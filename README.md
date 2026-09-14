# DJI 360 Video Metadata Fixer

A Windows batch script to automatically restore the original recording date, set correct timezones, and optionally compress 360° MP4 videos exported from DJI Studio or the DJI Mimo app.

## Features
* **Metadata Restoration:** Extracts original recording timestamps from `.OSV` raw files (via filename or modification date) and writes them to the exported `.mp4`.
* **DJI Mimo Exports (from filename):** For videos exported directly from the DJI Mimo app (`dji_mimo_YYYYMMDD_HHMMSS_...`), the recording date is read straight from the filename — no `.OSV` file required.
* **Edited / Stitched Videos (interactive):** For finished, edited 360° videos from DJI Mimo that have no matching `.OSV` (e.g. `compose_video_...`), a small date & time picker window opens so you can set the recording date yourself.
* **Timezone Support:** Prompts for the recording timezone (defaults to your PC's local timezone) to fix offset issues in video players.
* **Optional Compression:** Re-encodes videos using FFmpeg with custom CRF settings (H.265 or AV1) while preserving all original metadata.

## Prerequisites
Place the executable files below in the same directory as the script, or add them to your system `PATH`. **ExifTool is required; FFmpeg is only needed for the optional compression** — if you just want to fix dates and timezones (e.g. for DJI Mimo exports), ExifTool alone is enough.

* **[FFmpeg](https://www.gyan.dev/ffmpeg/builds/)** *(optional, compression only)* — Download `ffmpeg-release-full.7z`, extract it, and copy `ffmpeg.exe` from the `bin` folder into the script directory.
* **[ExifTool](https://exiftool.org/)** *(required)* — Download the Windows executable zip, extract it, rename `exiftool(-k).exe` to `exiftool.exe`, and copy it into the script directory.

## How to Use
1. Save the batch script in the folder containing your exported `.mp4` videos (and any `.OSV` raw files, if you have them).
2. Ensure `ffmpeg.exe` and `exiftool.exe` are present in the same folder.
3. Double-click the script to run it and follow the on-screen prompts.

## Disclaimer
This project is an independent open-source tool and is not affiliated, associated, authorized, endorsed by, or in any way officially connected with SZ DJI Technology Co., Ltd. (DJI) or any of its subsidiaries or affiliates.
