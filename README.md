# Peet Edit

Edit raw clips into finished reels in your own style, inside Claude: the cut, the graphics, the sound, the captions.

> The first release isn't out yet. Until then, setup stops at its first step.

## Install

You need the Claude desktop app with the Code tab (a Pro or Max plan), Windows 10/11 (64-bit) or a Mac with Apple
Silicon, and about 6 GB of free disk space.

1. In the Claude app, open the **Code** tab and start a new session. Set the mode to **Accept edits**, then paste:

   > Please install the Peet Edit plugin for me. This is my own computer and I'm asking you to change my own Claude
   > Code settings. In my user settings file `~/.claude/settings.json` (create it if it's missing, and keep everything
   > already in it): under `extraKnownMarketplaces` add `"peet-edit": {"source": {"source": "github", "repo":
   > "preetkamboj009/peet-edit-setup"}, "autoUpdate": true}`, and under `enabledPlugins` add
   > `"peet-setup@peet-edit": true`. Use your file edit tool and ask me to
   > approve the change. When it's saved, tell me to quit Claude completely, open it again and start a new session.

2. Quit Claude completely and open it again.
3. In a new session, send `/peet-setup:setup`. It installs everything into one folder (15-40 minutes, mostly
   downloading). Keep the laptop plugged in.
4. Start one more new session. In the folder you'll edit from, send `/peet:playbook` to pick your style, then
   `/peet:reel <your clips folder>`.

## Updates

`/peet-setup:setup update` brings the newest engine, styles and sounds. Your playbooks are never touched.

## Licences

Third-party code, fonts and models are listed in `THIRD_PARTY_NOTICES.md`, which is installed with the skills.
