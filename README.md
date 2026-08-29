# DJI 360 Video Metadata Fixer

A Windows batch script to automatically restore the original recording date, set correct timezones, and optionally compress 360° MP4 videos exported from DJI Studio.

## Features
* **Metadata Restoration:** Extracts original recording timestamps from `.OSV` raw files (via filename or modification date) and writes them to the exported `.mp4`.
* **Timezone Support:** Prompts for the recording timezone (defaults to your PC's local timezone) to fix offset issues in video players.
* **Optional Compression:** Re-encodes videos using FFmpeg with custom CRF settings (H.265 or AV1) while preserving all original metadata.

## Prerequisites
Place the required executable files in the same directory as the script, or add them to your system `PATH`:

* **[FFmpeg](https://www.gyan.dev/ffmpeg/builds/)** — Download `ffmpeg-release-essentials.zip`, extract it, and copy `ffmpeg.exe` from the `bin` folder into the script directory.
* **[ExifTool](https://exiftool.org/)** — Download the Windows executable zip, extract it, rename `exiftool(-k).exe` to `exiftool.exe`, and copy it into the script directory.

## How to Use
1. Save the batch script in the folder containing your `.OSV` raw files and exported `.mp4` videos.
2. Ensure `ffmpeg.exe` and `exiftool.exe` are present in the same folder.
3. Double-click the script to run it and follow the on-screen prompts.

## Disclaimer
This project is an independent open-source tool and is not affiliated, associated, authorized, endorsed by, or in any way officially connected with SZ DJI Technology Co., Ltd. (DJI) or any of its subsidiaries or affiliates.
