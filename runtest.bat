@echo off
cd /d "C:\Users\esc10\Documents\GitHub\Rhythian-client"
C:\godot\godot.exe --no-window --quit-after 400 --path . --verbose > test_run.log 2>&1
echo EXITCODE=%ERRORLEVEL% >> test_run.log
