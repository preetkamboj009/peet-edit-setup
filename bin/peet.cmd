@echo off
setlocal
set "H=%PEET_HOME%"
if "%H%"=="" set "H=%CLAUDE_PLUGIN_OPTION_PEET_HOME%"
if "%H%"=="" call :defaulthome
set "PY="
if exist "%H%\venv\Scripts\python.exe" set "PY=%H%\venv\Scripts\python.exe"
if "%PY%"=="" if exist "%H%\dev-venv\Scripts\python.exe" set "PY=%H%\dev-venv\Scripts\python.exe"
if "%PY%"=="" (
  echo {"ok":false,"error":{"code":"ENGINE_MISSING","hint":"run /peet:setup"}}
  exit /b 1
)
set "PEET_HOME=%H%"
set "PLAYWRIGHT_BROWSERS_PATH=%H%\browsers"
set "HF_HOME=%H%\models\hf"
set "TORCH_HOME=%H%\models\torch"
set "MPLCONFIGDIR=%H%\cache\matplotlib"
set "PIP_CACHE_DIR=%H%\cache\pip"
if not exist "%H%\tmp\" mkdir "%H%\tmp" >nul 2>&1
if exist "%H%\tmp\" set "TMP=%H%\tmp"
if exist "%H%\tmp\" set "TEMP=%H%\tmp"
if exist "%H%\app" set "PEET_APP=%H%\app"
set "HF_HUB_DISABLE_SYMLINKS_WARNING=1"
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"
set "PATH=%H%\tools\ffmpeg\bin;%PATH%"
"%PY%" -m peet %*
exit /b %ERRORLEVEL%

rem Default PEET_HOME (same order as the engine's core.peet_home and install.ps1): %USERPROFILE%\PeetEdit if it
rem exists, else the 0.6.0 folder %LOCALAPPDATA%\PeetEdit if it holds an engine, else %USERPROFILE%\PeetEdit.
rem Outside AppData because the Claude desktop app (MSIX) has its AppData writes redirected. install.ps1 replaces the
rem call above with the installed folder in PEET_HOME\bin\peet.cmd and drops this part.
:defaulthome
set "H=%USERPROFILE%\PeetEdit"
if exist "%H%\" goto :eof
if exist "%LOCALAPPDATA%\PeetEdit\venv\Scripts\python.exe" set "H=%LOCALAPPDATA%\PeetEdit"
if exist "%LOCALAPPDATA%\PeetEdit\dev-venv\Scripts\python.exe" set "H=%LOCALAPPDATA%\PeetEdit"
goto :eof
