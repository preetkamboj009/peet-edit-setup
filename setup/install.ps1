<#
  Peet Edit installer (Windows). Everything goes into one folder, PEET_HOME (default %USERPROFILE%\PeetEdit):
  uv, Python 3.12, the engine and its packages, ffmpeg, the models, Chromium (only if there is no Edge/Chrome),
  the sound packs, and the skills (copied to Claude's skills folder). No admin rights. Safe to run again: every
  finished step is skipped, a broken download resumes. Progress lines look like "[3/11] ..."; the last line is JSON.

    -Release <file|url>   release.json (default: the one next to this script)
    -AppSource <dir>      use an unpacked app folder instead of downloading it (development)
    -Update               fetch the app and sound packs again even if the version matches
    -SkipModels           skip the speech model (~1.6 GB; transcribe downloads it on first use)
    -SkipSounds           skip the sound packs
    -Home <dir>           install somewhere else than %USERPROFILE%\PeetEdit (env PEET_HOME too)
    -SkillsDir <dir>      Claude's skills folder (default %USERPROFILE%\.claude\skills)
#>
param([string]$Release = '', [string]$AppSource = '', [switch]$Update, [switch]$SkipModels, [switch]$SkipSounds,
      [Alias('Home')][string]$PeetHome = $env:PEET_HOME, [string]$SkillsDir = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$UV_VERSION = '0.11.23'
$FFMPEG_NAME = 'ffmpeg-9.0.2-essentials_build'
$FFMPEG_URLS = @("https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/$FFMPEG_NAME.zip",
                 "https://www.gyan.dev/ffmpeg/builds/packages/$FFMPEG_NAME.zip")
$FFMPEG_SHA = '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba'
$RVM_URL = 'https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3_fp32.onnx'
$RVM_SHA = '88d4531297118f595bf2fd60f6f566aec2e559393802d1f436c380f0cbbd2828'
$WHISPER_REPO = 'mobiuslabsgmbh/faster-whisper-large-v3-turbo'

if (-not $PeetHome) { $PeetHome = Join-Path $env:USERPROFILE 'PeetEdit' }
$PeetHome = [IO.Path]::GetFullPath($PeetHome)
if (-not $SkillsDir) {
  $SkillsDir = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR 'skills' } else { Join-Path $env:USERPROFILE '.claude\skills' }
}
if (-not $Release) { $Release = Join-Path $PSScriptRoot 'release.json' }
$App = Join-Path $PeetHome 'app'; $Tools = Join-Path $PeetHome 'tools'; $Venv = Join-Path $PeetHome 'venv'
$VenvPy = Join-Path $Venv 'Scripts\python.exe'; $Uv = Join-Path $Tools 'uv\uv.exe'
$Dl = Join-Path $PeetHome 'scratch\downloads'; $State = Join-Path $PeetHome 'state'; $LogFile = Join-Path $PeetHome 'install.log'
$TOTAL = 11; $script:Step = 'start'

# every download, cache and temp file stays inside the home folder
$env:UV_CACHE_DIR = if ($env:PEET_UV_CACHE) { $env:PEET_UV_CACHE } else { Join-Path $PeetHome 'cache\uv' }
$env:UV_PYTHON_INSTALL_DIR = Join-Path $PeetHome 'python'
$env:HF_HOME = Join-Path $PeetHome 'models\hf'
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $PeetHome 'browsers'
$env:PEET_HOME = $PeetHome

function Log([string]$m) { Add-Content -Path $LogFile -Value ("{0} {1}" -f (Get-Date -Format s), $m) -Encoding utf8 }
function Info([string]$m) { Write-Host "    $m"; Log $m }
function Step([int]$n, [string]$name, [string]$m) { $script:Step = $name; Write-Host "[$n/$TOTAL] $m"; Log "[$n/$TOTAL] $m" }
function Finish([bool]$ok, [hashtable]$extra) {
  Remove-Item (Join-Path $State 'install.lock') -Force -ErrorAction SilentlyContinue
  $o = @{ ok = $ok; home = $PeetHome } + $extra
  Write-Host ($o | ConvertTo-Json -Compress -Depth 5)
  exit $(if ($ok) { 0 } else { 1 })
}
function Native([string]$exe, [string[]]$a) {
  # Windows PowerShell 5.1 turns every stderr line of a program into an error, and with 'Stop' that ends the script
  # (uv prints its progress on stderr). Programs are judged by their exit code only.
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = @(& $exe @a 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
  $global:LASTEXITCODE = 0
  return @{ out = $out; code = $code }
}
function Run([string]$exe, [string[]]$a) {
  Log "> $exe $($a -join ' ')"
  $r = Native $exe $a
  $r.out | ForEach-Object { Log "  $_" }
  if ($r.code -ne 0) { throw "$([IO.Path]::GetFileName($exe)) failed (exit $($r.code)): $(($r.out | Select-Object -Last 3) -join ' ')" }
  return $r.out
}
function Sha([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }
function Download([string[]]$urls, [string]$out, [string]$sha = '') {
  if ((Test-Path -LiteralPath $out) -and ((-not $sha) -or (Sha $out) -eq $sha)) { return }
  $part = "$out.part"
  New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
  $last = ''
  foreach ($u in $urls) {
    for ($i = 1; $i -le 3; $i++) {
      try {
        if ($u -notmatch '^https?://') { Copy-Item -LiteralPath $u -Destination $part -Force }  # a local release
        else {
          $r = Native 'curl.exe' @('-L', '--fail', '--silent', '--show-error', '--retry', '3', '-C', '-', '-o', $part, $u)
          $r.out | ForEach-Object { Log "  curl: $_" }
          if ($r.code -ne 0) { throw "curl exit $($r.code)" }
        }
        if ($sha -and (Sha $part) -ne $sha) { Remove-Item $part -Force; throw 'checksum mismatch' }
        Move-Item -Force $part $out
        Info ("got {0} ({1:N0} MB)" -f (Split-Path $out -Leaf), ((Get-Item -LiteralPath $out).Length / 1MB))
        return
      } catch { $last = $_.Exception.Message; Log "download try $i failed ($u): $last"; $global:LASTEXITCODE = 0 }
    }
  }
  throw "download failed: $($urls[0]) ($last)"
}
function Unzip([string]$z, [string]$to) {
  if (Test-Path $to) { Remove-Item $to -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $to | Out-Null
  $r = Native 'tar.exe' @('-xf', $z, '-C', $to)  # Windows 10 1803+ ships bsdtar; much faster than Expand-Archive
  if ($r.code -ne 0) { throw "could not unpack $(Split-Path $z -Leaf): $($r.out -join ' ')" }
}
function Has-Browser {
  $c = @("$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
         "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
         "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
  return [bool]($c | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1)
}

$hint = @{
  platform = 'Peet Edit needs 64-bit Windows 10 or 11.'; disk = 'Free up space, then run setup again.'
  app = 'Check the internet connection and run setup again; it resumes.'; uv = 'Check the internet connection and run setup again.'
  python = 'Run setup again; if it keeps failing, restart the PC (a stuck download or antivirus).'
  engine = 'Run setup again; downloads resume. Antivirus HTTPS scanning or an office proxy can block packages.'
  ffmpeg = 'Run setup again; the download resumes.'; browser = 'Install Google Chrome, then run setup again.'
  models = 'Run setup again; finished downloads are kept.'; sounds = 'Run setup again; finished packs are kept.'
  skills = 'Close Claude, run setup again.'; doctor = 'Run setup again, or tell us what doctor says.'
}

try {
  New-Item -ItemType Directory -Force -Path $PeetHome, $State, $Dl, $Tools | Out-Null
  $lock = Join-Path $State 'install.lock'
  if (Test-Path $lock) {
    $pidOld = [int]((Get-Content $lock -Raw).Trim())
    if (Get-Process -Id $pidOld -ErrorAction SilentlyContinue) {
      Finish $false @{ step = 'busy'; error = 'Another Peet Edit setup is already running.'; hint = 'Let it finish (install.log shows its progress).' }
    }
  }
  Set-Content -Path $lock -Value $PID -Encoding ascii
  Log "---- setup start: home=$PeetHome update=$Update"

  # ---- 1 checks -------------------------------------------------------------------------------------------------
  Step 1 'platform' "Checking this PC ($PeetHome)"
  if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Major -lt 10) {
    Finish $false @{ step = 'platform'; error = 'Peet Edit needs 64-bit Windows 10 or 11.'; hint = $hint.platform }
  }
  $need = if (Test-Path $VenvPy) { 2 } else { 6 }
  $free = [math]::Round((Get-PSDrive -Name ($PeetHome.Substring(0, 1))).Free / 1GB, 1)
  if ($free -lt $need) {
    Finish $false @{ step = 'disk'; error = "Setup needs about $need GB free on $($PeetHome.Substring(0, 2)); there is $free GB."; hint = $hint.disk }
  }
  $rel = if ($Release -match '^https?://') { Invoke-RestMethod -Uri $Release -UseBasicParsing } else { Get-Content -Raw $Release | ConvertFrom-Json }
  $gpu = [bool](Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue)
  Info "release $($rel.version); NVIDIA GPU: $gpu"

  # ---- 2 app ----------------------------------------------------------------------------------------------------
  Step 2 'app' "The Peet Edit app $($rel.version) (engine, skills, styles)"
  $stamp = Join-Path $State 'app.version'
  $have = if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { '' }
  if ($AppSource) {
    Info "copying from $AppSource"
    foreach ($d in 'engine', 'plugin') {
      & robocopy (Join-Path $AppSource $d) (Join-Path $App $d) /MIR /NFL /NDL /NJH /NJS /NP /XD __pycache__ .venv | Out-Null
      if ($LASTEXITCODE -ge 8) { throw "robocopy $d failed ($LASTEXITCODE)" }
    }
    $global:LASTEXITCODE = 0
    Set-Content $stamp 'local' -Encoding ascii
  } elseif ($have -ne $rel.version -or $Update -or -not (Test-Path (Join-Path $App 'engine\pyproject.toml'))) {
    $z = Join-Path $Dl $rel.app.file
    Download @($rel.app.url) $z $rel.app.sha256
    $x = Join-Path $Dl 'app-x'; Unzip $z $x
    foreach ($d in 'engine', 'plugin') { if (-not (Test-Path (Join-Path $x $d))) { throw "the app zip has no $d folder" } }
    if (Test-Path $App) { Remove-Item $App -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $App | Out-Null
    Move-Item (Join-Path $x 'engine'), (Join-Path $x 'plugin') $App
    Remove-Item $z, $x -Recurse -Force
    Set-Content $stamp $rel.version -Encoding ascii
  } else { Info "app $($rel.version) already in place" }

  # ---- 3 uv -----------------------------------------------------------------------------------------------------
  Step 3 'uv' "uv $UV_VERSION (Python manager)"
  $uvOk = $false
  if (Test-Path $Uv) { try { $uvOk = ((& $Uv --version) -match [regex]::Escape($UV_VERSION)) } catch {} }
  if ($uvOk) { Info 'already installed' } else {
    $asset = 'uv-x86_64-pc-windows-msvc.zip'
    $base = "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/$asset"
    $shaFile = Join-Path $Dl "$asset.sha256"
    Remove-Item $shaFile -Force -ErrorAction SilentlyContinue
    Download @("$base.sha256") $shaFile
    $z = Join-Path $Dl $asset
    Download @($base) $z (((Get-Content -Raw $shaFile).Trim() -split '\s+')[0])
    $x = Join-Path $Dl 'uv-x'; Unzip $z $x
    New-Item -ItemType Directory -Force -Path (Join-Path $Tools 'uv') | Out-Null
    $exe = Get-ChildItem $x -Recurse -Filter uv.exe | Select-Object -First 1
    Copy-Item (Join-Path $exe.DirectoryName '*') (Join-Path $Tools 'uv') -Force
    Remove-Item $z, $x -Recurse -Force
  }

  # ---- 4 python -------------------------------------------------------------------------------------------------
  Step 4 'python' 'Python 3.12 and a virtual environment'
  $pyOk = $false
  if (Test-Path $VenvPy) { try { $pyOk = ((& $VenvPy -c "import sys; print(sys.version_info[:2] == (3, 12))") -eq 'True') } catch {}; $global:LASTEXITCODE = 0 }
  if ($pyOk) { Info 'already in place' } else {
    if (Test-Path $Venv) { Remove-Item $Venv -Recurse -Force }
    Run $Uv @('python', 'install', '3.12') | Out-Null
    Run $Uv @('venv', $Venv, '--python', '3.12') | Out-Null
  }

  # ---- 5 engine -------------------------------------------------------------------------------------------------
  Step 5 'engine' $(if ($gpu) { 'The engine and its packages, with NVIDIA GPU support (~1.5 GB)' } else { 'The engine and its packages (~500 MB)' })
  $req = Join-Path $Dl 'requirements.txt'
  $exp = @('export', '--project', (Join-Path $App 'engine'), '--frozen', '--no-dev', '--no-emit-project', '--no-hashes', '-q', '-o', $req)
  if ($gpu) { $exp += @('--extra', 'gpu') }
  Run $Uv $exp | Out-Null
  Run $Uv @('pip', 'sync', '--python', $VenvPy, $req) | Out-Null       # exactly the locked set, nothing else
  Run $Uv @('pip', 'install', '--python', $VenvPy, '--no-deps', '-e', (Join-Path $App 'engine')) | Out-Null
  Remove-Item $req -Force

  # ---- 6 ffmpeg -------------------------------------------------------------------------------------------------
  Step 6 'ffmpeg' 'ffmpeg 9.0.2 (~100 MB, checksum-verified)'
  $ff = Join-Path $Tools 'ffmpeg'
  if ((Test-Path (Join-Path $ff 'bin\ffmpeg.exe')) -and (Test-Path (Join-Path $ff 'bin\ffprobe.exe'))) { Info 'already installed' } else {
    $z = Join-Path $Dl "$FFMPEG_NAME.zip"
    Download $FFMPEG_URLS $z $FFMPEG_SHA
    $x = Join-Path $Dl 'ffmpeg-x'; Unzip $z $x
    if (Test-Path $ff) { Remove-Item $ff -Recurse -Force }
    Move-Item (Get-ChildItem $x | Select-Object -First 1).FullName $ff
    Remove-Item (Join-Path $ff 'bin\ffplay.exe'), (Join-Path $ff 'doc') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $z, $x -Recurse -Force
  }
  $env:PATH = (Join-Path $ff 'bin') + ';' + $env:PATH

  # ---- 7 browser ------------------------------------------------------------------------------------------------
  Step 7 'browser' 'A browser for drawing the graphics'
  if (Has-Browser) { Info 'Edge or Chrome found: using it' } else {
    Info 'no Edge or Chrome: downloading Chromium (~350 MB)'
    Run $VenvPy @('-m', 'playwright', 'install', 'chromium') | Out-Null
  }

  # ---- 8 models -------------------------------------------------------------------------------------------------
  Step 8 'models' 'AI models: person cut-out (15 MB), speech-to-text (~1.6 GB)'
  $rvm = Join-Path $PeetHome 'models\rvm_mobilenetv3_fp32.onnx'
  if (-not (Test-Path $rvm)) { Download @($RVM_URL) $rvm $RVM_SHA } else { Info 'cut-out model already present' }
  New-Item -ItemType Directory -Force -Path $env:HF_HOME | Out-Null
  if ($SkipModels) { Info 'speech model skipped (-SkipModels): the first transcribe downloads it' } else {
    $pyFile = Join-Path $Dl 'whisper.py'
    Set-Content -Path $pyFile -Encoding ascii -Value @"
from huggingface_hub import snapshot_download
print(snapshot_download('$WHISPER_REPO', allow_patterns=['config.json', 'preprocessor_config.json', 'model.bin', 'tokenizer.json', 'vocabulary.*']))
"@
    Info 'speech model: downloading (resumes if interrupted; the long one)'
    Run $VenvPy @($pyFile) | Out-Null
  }

  # ---- 9 sounds -------------------------------------------------------------------------------------------------
  Step 9 'sounds' 'Sound packs'
  if ($SkipSounds) { Info 'skipped (-SkipSounds)' } else {
    foreach ($p in $rel.sfx) {
      $mark = Join-Path $PeetHome "sfx\$($p.pack)\.sha256"
      if ((Test-Path $mark) -and ((Get-Content $mark -Raw).Trim() -eq $p.sha256) -and -not $Update) { Info "$($p.pack): already in place"; continue }
      $z = Join-Path $Dl $p.file
      Download @($p.url) $z $p.sha256
      $x = Join-Path $Dl 'sfx-x'; Unzip $z $x
      $dst = Join-Path $PeetHome "sfx\$($p.pack)"
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      & robocopy (Join-Path $x $p.pack) $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null  # adds and refreshes; keeps fetched files
      if ($LASTEXITCODE -ge 8) { throw "could not place the $($p.pack) sounds" }
      $global:LASTEXITCODE = 0
      Set-Content $mark $p.sha256 -Encoding ascii
      Remove-Item $z, $x -Recurse -Force
      Info "$($p.pack): $($p.sounds) sounds"
    }
  }

  # ---- 10 skills ------------------------------------------------------------------------------------------------
  Step 10 'skills' 'The Peet Edit skills for Claude'
  New-Item -ItemType Directory -Force -Path (Join-Path $PeetHome 'playbooks') | Out-Null
  $dst = Join-Path $SkillsDir 'peet'
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  & robocopy (Join-Path $App 'plugin') $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "could not copy the skills to $dst" }
  $global:LASTEXITCODE = 0
  $default = Join-Path $env:USERPROFILE 'PeetEdit'
  if ($PeetHome -ne $default) {  # a home elsewhere: the skills' wrappers must find it without PEET_HOME
    $cmd = Join-Path $dst 'bin\peet.cmd'
    (Get-Content -Raw $cmd).Replace('set "H=%USERPROFILE%\PeetEdit"', "set ""H=$PeetHome""") | Set-Content -NoNewline -Encoding ascii $cmd
    $sh = Join-Path $dst 'bin\peet'
    $posix = '/' + $PeetHome.Substring(0, 1).ToLower() + $PeetHome.Substring(2).Replace('\', '/')
    $t = (Get-Content -Raw $sh).Replace('H="${PEET_HOME:-$HOME/PeetEdit}"', "H=""`${PEET_HOME:-$posix}""")
    [IO.File]::WriteAllText($sh, $t.Replace("`r`n", "`n"))
  }
  Info "skills at $dst (start a new Claude session to use them)"

  # ---- 11 doctor ------------------------------------------------------------------------------------------------
  Step 11 'doctor' "Putting peet on your PATH and checking everything"
  $bin = Join-Path $PeetHome 'bin'
  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  Copy-Item (Join-Path $dst 'bin\peet.cmd') (Join-Path $bin 'peet.cmd') -Force
  $up = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not (($up -split ';') -contains $bin)) {
    [Environment]::SetEnvironmentVariable('Path', ((@($up, $bin) | Where-Object { $_ }) -join ';'), 'User')
    Info "added $bin to your PATH (new terminals know 'peet')"
  }
  $r = Native (Join-Path $bin 'peet.cmd') @('doctor')
  $d = ($r.out | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json
  Remove-Item (Join-Path $PeetHome 'scratch') -Recurse -Force -ErrorAction SilentlyContinue
  if (-not $env:PEET_UV_CACHE) { Remove-Item $env:UV_CACHE_DIR -Recurse -Force -ErrorAction SilentlyContinue }  # ~1 GB, not needed after
  $size = (Get-ChildItem $PeetHome -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  Finish $true @{ version = $rel.version; doctor_ready = [bool]$d.ready; problems = @($d.problems); checks = $d.checks
                  skills = $dst; size_mb = [int]($size / 1MB); gpu = $gpu }
} catch {
  $msg = $_.Exception.Message
  Log "FAILED at $script:Step : $msg"
  Write-Host "FAILED at step '$script:Step': $msg"
  Finish $false @{ step = $script:Step; error = $msg; hint = $hint[$script:Step] }
}
