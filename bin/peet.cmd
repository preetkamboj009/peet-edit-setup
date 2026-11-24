@echo off
setlocal
rem The skills call the engine only through this file, by its full path.
rem Engine home: %PEET_HOME%, else %USERPROFILE%\PeetEdit. Setup installs the engine's venv and tools there.
set "H=%PEET_HOME%"
if "%H%"=="" set "H=%USERPROFILE%\PeetEdit"
set "PY=%H%\venv\Scripts\python.exe"
if not exist "%PY%" (
  echo {"ok": false, "error": "ENGINE_MISSING: the engine is not installed. Run /peet:setup"}
  exit /b 1
)
set "PEET_HOME=%H%"
if exist "%H%\tools\ffmpeg\bin" set "PATH=%H%\tools\ffmpeg\bin;%PATH%"
rem models and the bundled browser live in the home folder when setup put them there
if exist "%H%\models\hf" set "HF_HOME=%H%\models\hf"
set "HF_HUB_DISABLE_SYMLINKS_WARNING=1"
if exist "%H%\browsers" set "PLAYWRIGHT_BROWSERS_PATH=%H%\browsers"
set "PYTHONUTF8=1"
"%PY%" -m peet.cli %*
exit /b %ERRORLEVEL%
