#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
die() { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

maybe_sudo() {
  # Use sudo only if we are not root and sudo exists
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if need_cmd sudo; then
      sudo "$@"
    else
      die "sudo is required for: $* (but sudo is not installed). Run as root or install sudo."
    fi
  else
    "$@"
  fi
}

append_if_missing() {
  local file="$1"
  local marker="$2"
  local content="$3"

  if grep -Fq "$marker" "$file" 2>/dev/null; then
    log "Already present in $file: $marker"
    return 0
  fi

  log "Appending block to $file: $marker"
  {
    echo ""
    echo "# --- added by setup script ---"
    echo "$content"
    echo "# --- end added by setup script ---"
  } >> "$file"
}

ensure_zshrc_exists() {
  local zshrc="$HOME/.zshrc"
  if [[ ! -f "$zshrc" ]]; then
    log "Creating missing $zshrc"
    touch "$zshrc"
  fi
}

install_ohmyzsh() {
  # Official install command (interactive by default)
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log "Oh My Zsh already installed at ~/.oh-my-zsh"
    return 0
  fi

  need_cmd curl || die "curl is required but not found. Install it first (apt install curl)."
  log "Installing Oh My Zsh (official installer)..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

apt_install_if_missing() {
  # installs packages only if not installed (dpkg-based systems)
  local pkgs=("$@")
  local missing=()

  if ! need_cmd dpkg-query; then
    warn "dpkg-query not found; skipping package-installed checks and attempting install."
    maybe_sudo apt-get update -y
    maybe_sudo apt-get install -y "${pkgs[@]}"
    return 0
  fi

  for p in "${pkgs[@]}"; do
    if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
      :
    else
      missing+=("$p")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    log "Installing packages: ${missing[*]}"
    maybe_sudo apt-get update -y
    maybe_sudo apt-get install -y "${missing[@]}"
  else
    log "All packages already installed: ${pkgs[*]}"
  fi
}

clone_or_update_plugin() {
  local repo="$1"
  local dest="$2"

  if [[ -d "$dest/.git" ]]; then
    log "Updating plugin in $dest"
    git -C "$dest" pull --ff-only || warn "Could not update $dest (continuing)"
    return 0
  fi

  if [[ -d "$dest" && ! -d "$dest/.git" ]]; then
    warn "Directory exists but is not a git repo: $dest (skipping clone)"
    return 0
  fi

  log "Cloning $repo -> $dest"
  git clone --depth 1 "$repo" "$dest"
}

ensure_plugins_line() {
  local zshrc="$HOME/.zshrc"
  local desired='plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete zsh-history-substring-search)'

  log "Ensuring plugins= line in ~/.zshrc"

  # If there is any plugins= line, replace it.
  if grep -Eq '^[[:space:]]*plugins=' "$zshrc"; then
    # Replace the first match of plugins=... (and any leading spaces)
    sed -i -E "0,/^[[:space:]]*plugins=.*/s//${desired}/" "$zshrc"
  else
    # Otherwise insert it after ZSH_THEME line if present; else append near top.
    if grep -Eq '^[[:space:]]*ZSH_THEME=' "$zshrc"; then
      # Insert after first ZSH_THEME= line
      awk -v ins="$desired" '
        BEGIN{done=0}
        {
          print
          if(!done && $0 ~ /^[[:space:]]*ZSH_THEME=/){
            print ins
            done=1
          }
        }
        END{
          if(!done){
            print ins
          }
        }
      ' "$zshrc" > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
    else
      # Prepend for visibility
      { echo "$desired"; cat "$zshrc"; } > "$zshrc.tmp" && mv "$zshrc.tmp" "$zshrc"
    fi
  fi

  # Verify
  grep -Fq "$desired" "$zshrc" || die "Failed to set plugins line in $zshrc"
}

ensure_default_shell_zsh() {
  need_cmd zsh || die "zsh is not installed"
  local zsh_path
  zsh_path="$(command -v zsh)"

  # If already default, skip
  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    log "Default shell already set to zsh ($zsh_path)"
    return 0
  fi

  log "Attempting to set default shell to zsh ($zsh_path)"
  # chsh may or may not require sudo depending on system policy
  if need_cmd chsh; then
    if chsh -s "$zsh_path" >/dev/null 2>&1; then
      log "Default shell changed to zsh for current user."
    else
      warn "chsh without sudo failed; trying with sudo (may still fail if policy disallows)."
      if maybe_sudo chsh -s "$zsh_path" "$USER" >/dev/null 2>&1; then
        log "Default shell changed to zsh (via sudo)."
      else
        warn "Could not change default shell automatically. You can run: chsh -s $zsh_path"
      fi
    fi
  else
    warn "chsh not found; cannot set default shell automatically."
  fi
}

main() {
  log "Installing prerequisites (zsh, git, curl)..."
  apt_install_if_missing zsh git curl

  # Oh My Zsh must run early (as you requested)
  install_ohmyzsh

  # Ensure ~/.zshrc exists (installer usually creates it, но на всякий)
  ensure_zshrc_exists

  # Plugins: install packages if you still want distro packages (optional but safe)
  # (On Ubuntu/Debian эти пакеты существуют, но мы всё равно ставим плагины через git как ты хотел.)
  log "Installing optional zsh plugin packages from apt (if available)..."
  # Some distros don't have these packages — apt-get will fail if missing.
  # We'll try, but won't die if apt can't find them.
  if maybe_sudo apt-get install -y zsh-autosuggestions zsh-syntax-highlighting >/dev/null 2>&1; then
    log "Apt plugin packages installed (or already installed)."
  else
    warn "Apt plugin packages not installed (maybe not available on this distro). Continuing with git plugins."
  fi

  # Install plugins via git under Oh My Zsh custom dir
  need_cmd git || die "git is required but not found"
  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local plugdir="$custom/plugins"

  mkdir -p "$plugdir"

  log "Installing/Updating Oh My Zsh plugins in: $plugdir"
  clone_or_update_plugin https://github.com/zsh-users/zsh-autosuggestions.git           "$plugdir/zsh-autosuggestions"
  clone_or_update_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git      "$plugdir/zsh-syntax-highlighting"
  clone_or_update_plugin https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$plugdir/fast-syntax-highlighting"
  clone_or_update_plugin https://github.com/marlonrichert/zsh-autocomplete.git         "$plugdir/zsh-autocomplete"
  clone_or_update_plugin https://github.com/zsh-users/zsh-history-substring-search.git "$plugdir/zsh-history-substring-search"

  # Update plugins= line in ~/.zshrc (replace any existing plugins=)
  ensure_plugins_line

  # Append kp/fp/alias block if missing (marker = "kp() {")
  local zshrc="$HOME/.zshrc"
  local block
  block="$(cat <<'EOF'
kp() {
  emulate -L zsh
  setopt pipefail

  local sig="-TERM"
  local dry=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--dry-run) dry=1; shift ;;
      -9|-KILL|-TERM|-HUP|-INT|-QUIT|-USR1|-USR2)
        sig="$1"; shift ;;
      --) shift; break ;;
      -*) sig="$1"; shift ;;
      *) break ;;
    esac
  done

  if [[ -z "$1" ]]; then
    echo "Usage: kp [-n|--dry-run] [SIGNAL] <pattern>"
    return 2
  fi

  local pattern="$*"
  local pids
  pids=$(pgrep -f -- "$pattern" 2>/dev/null) || true

  if [[ -z "$pids" ]]; then
    echo "kp: no processes found matching: $pattern"
    return 1
  fi

  echo "kp: matched PIDs:"
  echo "$pids" | tr ' ' '\n'

  if (( dry )); then
    echo "kp: dry-run, not killing."
    return 0
  fi

  echo "kp: sending $sig to PIDs..."
  echo "$pids" | xargs -r kill "$sig"
}

# Find process(es) by pattern and print a readable table.
# Usage:
#   fp <pattern>
fp() {
  emulate -L zsh
  setopt pipefail

  if [[ -z "$1" ]]; then
    echo "Usage: fp <pattern>"
    return 2
  fi

  local pattern="$*"
  local pids
  pids=$(pgrep -f -- "$pattern" 2>/dev/null) || true

  if [[ -z "$pids" ]]; then
    echo "fp: no processes found matching: $pattern"
    return 1
  fi

  echo "fp: found PIDs for \"$pattern\":"
  echo

  printf "%-12s %-7s %-6s %-6s %-8s %s\n" "USER" "PID" "%CPU" "%MEM" "START" "COMMAND"
  echo "--------------------------------------------------------------------------------"

  local pid
  for pid in ${(f)pids}; do
    ps -p "$pid" -o user=,pid=,%cpu=,%mem=,start=,args= 2>/dev/null | awk '
      {
        user=$1; pid=$2; cpu=$3; mem=$4; start=$5;
        $1=$2=$3=$4=$5="";
        sub(/^ +/,"",$0);
        cmd=$0;
        printf "%-12s %-7s %-6s %-6s %-8s %s\n", user, pid, cpu, mem, start, cmd
      }
    '
  done
}

alias sr="source ~/.zshrc"
EOF
)"
  append_if_missing "$zshrc" "kp() {" "$block"

  # Sanity checks: verify plugin list and markers
  log "Verifying changes..."
  grep -Eq '^[[:space:]]*plugins=\(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete zsh-history-substring-search\)' "$zshrc" \
    || die "plugins line is not set as expected in $zshrc"
  grep -Fq "kp() {" "$zshrc" || die "kp() block not found in $zshrc"
  grep -Fq "fp() {" "$zshrc" || die "fp() block not found in $zshrc"
  grep -Fq 'alias sr="source ~/.zshrc"' "$zshrc" || die "sr alias not found in $zshrc"

  # Default shell to zsh
  ensure_default_shell_zsh

  log "Done."
  echo
  echo "Next:"
  echo "  - Start a new terminal session, or run: zsh -i -c 'source ~/.zshrc; echo OK'"
  echo "  - Inside zsh you can test: type kp fp sr"
}

main "$@"
