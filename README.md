# My Linux Settings

## Zsh + Oh My Zsh Setup Script

Automated installer and configurator for **Zsh** with **Oh My Zsh** and a curated set of productivity plugins.

The script is **idempotent** — it can be safely re-run.  
It verifies that configuration changes were applied successfully.

---

## What This Script Does

### 1. Installs Required Packages
- `zsh`
- `git`
- `curl`

### 2. Installs Oh My Zsh
Uses the official installer.

### 3. Installs / Updates Plugins

The following plugins are installed (or updated if already present):

- `zsh-autosuggestions`
- `zsh-syntax-highlighting`
- `fast-syntax-highlighting`
- `zsh-autocomplete`
- `zsh-history-substring-search`

### 4. Updates `.zshrc`

Ensures the following plugins line exists:

```bash
plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete zsh-history-substring-search)
```
If a `plugins=` line already exists, it will be replaced.

### 5. Adds Utility Functions

Appends (if missing):
- `kp` - kill processes by pattern
- `fp` - find processes by pattern (formatted table output)
- `sr` - reload ~/.zshrc

### 6. Sets Zsh as Default Shell
Attempts to switch the default shell to zsh.

### 7. Verifies Installation
Checks that:
- Plugin list is correctly written
- Functions are present in .zshrc

### Requirements
- Debian/Ubuntu-based system (uses apt)
- Internet connection
- sudo access (may be required)

### Online execution
Run this command
```
curl -fsSL https://raw.githubusercontent.com/<username>/<repo>/main/setup-zsh.sh -o setup-zsh.sh
chmod +x install-zsh.sh
./install-zsh.sh
```

### Usage
Make the script executable:
```
chmod +x install-zsh.sh
```

Run it:
```
./install-zsh.sh
```

After completion, start a new shell:
```
exec zsh
```
or open a new terminal.

### Verify Setup

Inside Zsh:
```
type kp
type fp
type sr
```

If these commands are recognized, setup is successful.

### Notes
- Safe to re-run - plugins will be updated if already installed.
- Existing `plugins=` line will be replaced.
- Custom functions are appended only if not already present.
