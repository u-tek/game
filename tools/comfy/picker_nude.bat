@echo off
rem Art picker for the nude set: double-click to open. Close this window to stop the page.
cd /d "%~dp0..\.."
start "" http://127.0.0.1:8766
python tools\comfy\picker.py --run art_src\_review\nude_run --port 8766
pause
