---
name: setup
description: Install Peet Edit on this computer (engine, Python, ffmpeg, models, sound packs and the editing skills), update it with "update", or check it with "doctor". Run this first after adding the plugin. Use when the user runs /peet-setup:setup, says "install Peet Edit", "update Peet", or when a Peet command says ENGINE_MISSING.
argument-hint: "[update | doctor]"
user-invocable: true
---
# setup

Installs everything Peet Edit needs into one folder, `PEET_HOME` (`%USERPROFILE%\PeetEdit` on Windows, `~/PeetEdit`
on a Mac). No admin
rights. Nothing else on the computer changes, apart from one folder added to the user's PATH and the skills copied to
Claude's skills folder. Talk to the user in their language (often Hinglish), in short plain lines; never show raw
logs or JSON.

**Plugin root** = two folders above this skill's base directory. The installer is `<plugin root>/setup/install.ps1`;
it reads `<plugin root>/setup/release.json` (the version and where to download it from).

**Which part:** no argument → **Install**. `update` → **Install** with `-Update`. `doctor` → **Doctor**.

## Install
1. Say what happens, in one or two lines: "Peet Edit install ho raha hai: engine, tools, AI models aur sounds
   (~4-6 GB, 15-40 minute internet ke hisaab se). Laptop charging pe rakho." The OS is in your environment details:
   Windows, or a Mac with Apple Silicon (an Intel Mac or Linux isn't supported: say so and stop).
2. Run it **in the background** (the shell tool's background option):
   - Windows, PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin root>\setup\install.ps1"`
     (add `-Update` for update)
   - Windows, Bash: `powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin root>/setup/install.ps1"`
   - Mac: `bash "<plugin root>/setup/install.sh"` (add `--update` for update)
3. Every minute or two, read its output (or `install.log` in `PEET_HOME` with the Read tool). Lines look like
   `[5/11] The engine and its packages`. Give one short line each time the step number changes, never the raw log.
4. The last line is JSON:
   - `"ok": true` → say it's installed, the size, and whether everything checked out (`doctor_ready`, any
     `problems` in plain words). Then: "Ab ek **naya Claude session** kholo (skills session ke start pe load hote
     hain). Jis folder mein reels banaoge wahan `/peet:playbook` se apna style chuno, phir `/peet:reel <clips
     folder>`."
   - `"ok": false` → say plainly which step failed (`step`) and what to do (`hint`), and offer to run setup again
     (it resumes; finished steps are skipped). `"step": "busy"` → another setup is running: wait for it.
5. A setup interrupted by closing Claude or a sleeping PC resumes when run again.

## Doctor
Run `& "$env:USERPROFILE\PeetEdit\bin\peet.cmd" doctor` (PowerShell) or `~/PeetEdit/bin/peet doctor` (Mac). Not found →
not installed: offer **Install**.
Report `ready`, the `version`, and any `problems` in plain words, each with its fix (most fixes: run setup again).
