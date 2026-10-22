@echo off
rem Art picker: double-click to open. Close this window to stop the page (renders already started keep going).
cd /d "%~dp0..\.."
start "" http://127.0.0.1:8765
python tools\comfy\picker.py
pause
