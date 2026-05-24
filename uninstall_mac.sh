#!/usr/bin/env bash
#
# ============================================================================
#  Ultimate macOS Dev Setup — UNINSTALLER / Откат ("антидот")
#  Обращает изменения, сделанные setup_mac.sh.
#  Безопасен и идемпотентен: чего нет — то пропускается.
#  Опасные шаги (SSH-ключ, удаление Homebrew) — только с подтверждением.
# ============================================================================

set -uo pipefail

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'; CYAN=$'\033[36m'

step()  { printf "\n${BOLD}${BLUE}▶ %s${RESET}\n" "$1"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
skip()  { printf "  ${DIM}• %s${RESET}\n" "$1"; }
warn()  { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
err()   { printf "  ${RED}✗ %s${RESET}\n" "$1"; }

# ============================================================================
#  TUI: меню со стрелками и чекбоксами (совместимо с bash 3.2, без namerefs)
# ============================================================================
TUI_G=$'\033[38;5;46m'; TUI_GD=$'\033[38;5;28m'; TUI_INV=$'\033[7m'
TUI_HIDE=$'\033[?25l'; TUI_SHOW=$'\033[?25h'

_tui_key() {
  local k rest
  IFS= read -rsn1 k
  if [[ $k == $'\033' ]]; then read -rsn2 -t 0.001 rest; k+="$rest"; fi
  printf '%s' "$k"
}
_aget() { eval "printf '%s' \"\${$1[$2]}\""; }
_aset() { eval "$1[$2]=\"\$3\""; }
_alen() { eval "printf '%s' \"\${#$1[@]}\""; }

multiselect() {
  local nname=$1 sname=$2 dname=$3 title=$4
  local cur=0 num key i all_on box label desc
  num=$(_alen "$nname")
  printf '%s' "$TUI_HIDE"
  while true; do
    printf '\033[H\033[J'
    printf "${TUI_G}${BOLD}  %s${RESET}\n" "$title"
    printf "${TUI_GD}  ↑/↓ двигаться · ПРОБЕЛ выбрать · A все · ENTER подтвердить${RESET}\n\n"
    for ((i=0; i<num; i++)); do
      box="[ ]"; [[ "$(_aget "$sname" "$i")" == "on" ]] && box="[x]"
      desc=""; [[ -n "$dname" ]] && desc="$(_aget "$dname" "$i")"
      label="$(_aget "$nname" "$i")"; [[ -n "$desc" ]] && label="$label  — $desc"
      if [[ $i -eq $cur ]]; then printf "  ${TUI_G}${TUI_INV} %s %s ${RESET}\n" "$box" "$label"
      else printf "  ${TUI_GD} %s %s${RESET}\n" "$box" "$label"; fi
    done
    key=$(_tui_key)
    case "$key" in
      $'\033[A'|k) ((cur=(cur-1+num)%num)) ;;
      $'\033[B'|j) ((cur=(cur+1)%num)) ;;
      ' ') [[ "$(_aget "$sname" "$cur")" == "on" ]] && _aset "$sname" "$cur" "off" || _aset "$sname" "$cur" "on" ;;
      a|A) all_on=1
           for ((i=0;i<num;i++)); do [[ "$(_aget "$sname" "$i")" == "off" ]] && all_on=0; done
           for ((i=0;i<num;i++)); do [[ $all_on -eq 1 ]] && _aset "$sname" "$i" "off" || _aset "$sname" "$i" "on"; done ;;
      ''|$'\n') break ;;
    esac
  done
  printf '%s' "$TUI_SHOW"
}

# yes/no с дефолтом NO для опасных операций
confirm() {
  local prompt="$1" ans
  read -r -p "  ${prompt} [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

clear
printf "${BOLD}${CYAN}"
cat << 'BANNER'
   ╔══════════════════════════════════════════════╗
   ║      Откат Dev Setup · возврат к исходному    ║
   ╚══════════════════════════════════════════════╝
BANNER
printf "${RESET}\n"

if [[ "$(uname)" != "Darwin" ]]; then err "Только для macOS."; exit 1; fi

ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] && BREW_PREFIX="/opt/homebrew" || BREW_PREFIX="/usr/local"

echo "  ${YELLOW}Это вернёт твой Mac к состоянию до setup_mac.sh.${RESET}"
echo "  ${DIM}Ничего не удаляется без твоего согласия. Можно выбрать секции.${RESET}"
echo
if ! confirm "Продолжить?"; then echo "  Отменено."; exit 0; fi

sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
trap 'kill %1 2>/dev/null' EXIT

# Подхватываем brew в PATH
[[ -x "$BREW_PREFIX/bin/brew" ]] && eval "$($BREW_PREFIX/bin/brew shellenv)"

# ============================================================================
#  МЕНЮ: что откатывать
# ============================================================================
clear
printf "${BOLD}${CYAN}Что откатить?${RESET}\n"
printf "${DIM}Цифра — переключить. [a]=всё · [Enter]=выполнить выбранное${RESET}\n\n"

SEC_NAMES=(
  "GUI-приложения (casks)"
  "CLI-инструменты и SRE-набор"
  "Языки/рантаймы (go, python, nvm, node)"
  "Swift-инструменты"
  "Docker (colima/desktop)"
  "Deck"
  "Системные твики macOS (вернуть дефолты)"
  "Zsh: блок алиасов, Oh-My-Zsh, p10k, плагины"
  "Touch ID для sudo (sudo_local)"
  "Шрифт JetBrains Mono Nerd"
)
# По умолчанию НЕ трогаем CLI-базу и языки (могли быть нужны до setup) и Docker
SEC_PICK=( on off off on off off on on on on )

multiselect SEC_NAMES SEC_PICK "" "ЧТО ОТКАТИТЬ?  (SSH-ключ, Git-конфиг и Homebrew — отдельно, ниже)"

picked() { [[ "${SEC_PICK[$1]}" == "on" ]]; }

# хелпер удаления formula
rm_formula() {
  if brew list --formula "$1" &>/dev/null; then
    brew uninstall --ignore-dependencies "$1" >/dev/null 2>&1 && ok "удалён $1" || warn "$1 — не удалось (возможно, зависимость)"
  else
    skip "$1 (не установлен)"
  fi
}
rm_cask() {
  if brew list --cask "$1" &>/dev/null; then
    brew uninstall --cask --zap "$1" >/dev/null 2>&1 && ok "удалён $1" || warn "$1 — не удалось"
  else
    skip "$1 (не установлен)"
  fi
}

clear
echo "${BOLD}Начинаю откат выбранных секций...${RESET}"

# ---------- 1. GUI casks ----------
if picked 0; then
  step "Удаление GUI-приложений"
  for c in iterm2 visual-studio-code spotify rectangle google-chrome raycast \
           stats telegram maccy the-unarchiver monitorcontrol dockdoor \
           appcleaner bruno; do
    rm_cask "$c"
  done
fi

# ---------- 6. Deck (отдельно — свой tap) ----------
if picked 5; then
  step "Удаление Deck"
  rm_cask "deckclip"
  brew untap yuzeguitarist/deck >/dev/null 2>&1 && ok "tap yuzeguitarist/deck удалён" || skip "tap уже отсутствует"
fi

# ---------- 7. Caffeine (входит в casks, но если секция casks выкл — снимем тут) ----------
if picked 0; then
  rm_cask "domzilla-caffeine"
fi

# ---------- 2. CLI ----------
if picked 1; then
  step "Удаление CLI-инструментов"
  warn "git/curl/wget могли быть до setup — пропускаю их во избежание поломок"
  for f in gh tmux btop neovim jq ripgrep fd eza bat fzf zoxide \
           kubectl k9s kubectx helm stern; do
    rm_formula "$f"
  done
  skip "git, curl, wget оставлены намеренно"
fi

# ---------- 3. Языки/рантаймы ----------
if picked 2; then
  step "Удаление языков/рантаймов"
  # node, установленный через nvm — удаляем сам nvm-каталог
  for f in go python nvm; do rm_formula "$f"; done
  if [[ -d "$HOME/.nvm" ]]; then
    if confirm "Удалить ~/.nvm со всеми версиями Node?"; then
      rm -rf "$HOME/.nvm" && ok "~/.nvm удалён"
    else skip "~/.nvm оставлен"; fi
  fi
fi

# ---------- 4. Swift ----------
if picked 3; then
  step "Удаление Swift-инструментов"
  for f in swiftlint swiftformat xcbeautify; do rm_formula "$f"; done
fi

# ---------- 5. Docker ----------
if picked 4; then
  step "Удаление Docker-стека"
  # Остановим Colima, если запущена
  if command -v colima &>/dev/null; then
    colima stop >/dev/null 2>&1 && ok "Colima остановлена"
    colima delete -f >/dev/null 2>&1 && ok "Colima VM удалена"
  fi
  for f in colima docker docker-compose docker-buildx docker-credential-helper; do rm_formula "$f"; done
  rm_cask "docker"  # Docker Desktop, если ставился
fi

# ---------- 10. Шрифт ----------
if picked 9; then
  step "Удаление шрифта"
  rm_cask "font-jetbrains-mono-nerd-font"
fi

# ---------- 8. Zsh ----------
if picked 7; then
  step "Откат конфигурации Zsh"
  # Удаляем наш блок алиасов из .zshrc
  if grep -q "### DEV-SETUP-BLOCK ###" ~/.zshrc 2>/dev/null; then
    # удаляем строки между маркерами включительно
    sed -i '' '/### DEV-SETUP-BLOCK ###/,/### END-DEV-SETUP-BLOCK ###/d' ~/.zshrc
    ok "блок алиасов удалён из .zshrc"
  else
    skip "блок алиасов не найден"
  fi
  # Возвращаем тему по умолчанию
  if grep -q 'powerlevel10k' ~/.zshrc 2>/dev/null; then
    sed -i '' 's|ZSH_THEME="powerlevel10k/powerlevel10k"|ZSH_THEME="robbyrussell"|' ~/.zshrc
    ok "тема возвращена на robbyrussell"
  fi
  # Возвращаем дефолтный список плагинов
  sed -i '' 's|^plugins=(git zsh-autosuggestions zsh-syntax-highlighting docker kubectl)|plugins=(git)|' ~/.zshrc 2>/dev/null
  # Удаляем p10k и кастомные плагины
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  rm -rf "$ZSH_CUSTOM/themes/powerlevel10k" 2>/dev/null && ok "powerlevel10k удалён"
  rm -rf "$ZSH_CUSTOM/plugins/zsh-autosuggestions" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null && ok "плагины удалены"
  [[ -f ~/.p10k.zsh ]] && { rm -f ~/.p10k.zsh; ok "~/.p10k.zsh удалён"; }
  # Oh-My-Zsh целиком — по подтверждению
  if [[ -d ~/.oh-my-zsh ]]; then
    if confirm "Удалить Oh-My-Zsh полностью?"; then
      rm -rf ~/.oh-my-zsh && ok "Oh-My-Zsh удалён"
      warn "Проверь ~/.zshrc — может ссылаться на удалённый oh-my-zsh"
    else skip "Oh-My-Zsh оставлен"; fi
  fi
fi

# ---------- 9. Touch ID для sudo ----------
if picked 8; then
  step "Отключение Touch ID для sudo"
  if [[ -f /etc/pam.d/sudo_local ]]; then
    sudo rm -f /etc/pam.d/sudo_local && ok "/etc/pam.d/sudo_local удалён"
  else
    skip "sudo_local отсутствует"
  fi
  rm_formula "pam-reattach"
fi

# ---------- 7. Системные твики macOS ----------
if picked 6; then
  step "Возврат системных твиков macOS к дефолтам"
  # delete вернёт системное значение по умолчанию
  defaults delete com.apple.finder AppleShowAllFiles 2>/dev/null
  defaults delete NSGlobalDomain AppleShowAllExtensions 2>/dev/null
  defaults delete com.apple.finder ShowPathbar 2>/dev/null
  defaults delete com.apple.finder ShowStatusBar 2>/dev/null
  defaults delete com.apple.finder FXDefaultSearchScope 2>/dev/null
  defaults delete com.apple.finder FXEnableExtensionChangeWarning 2>/dev/null
  defaults delete com.apple.finder FXPreferredViewStyle 2>/dev/null
  defaults delete NSGlobalDomain NSAutomaticSpellingCorrectionEnabled 2>/dev/null
  defaults delete NSGlobalDomain NSAutomaticCapitalizationEnabled 2>/dev/null
  defaults delete NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled 2>/dev/null
  defaults delete NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled 2>/dev/null
  defaults delete NSGlobalDomain NSAutomaticDashSubstitutionEnabled 2>/dev/null
  defaults delete NSGlobalDomain NSNavPanelExpandedStateForSaveMode 2>/dev/null
  defaults delete NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 2>/dev/null
  defaults delete NSGlobalDomain PMPrintingExpandedStateForPrint 2>/dev/null
  defaults delete NSGlobalDomain PMPrintingExpandedStateForPrint2 2>/dev/null
  defaults delete NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null
  defaults delete NSGlobalDomain KeyRepeat 2>/dev/null
  defaults delete NSGlobalDomain InitialKeyRepeat 2>/dev/null
  defaults delete com.apple.dock autohide-delay 2>/dev/null
  defaults delete com.apple.dock autohide-time-modifier 2>/dev/null
  defaults delete com.apple.dock show-recents 2>/dev/null
  defaults delete com.apple.screencapture location 2>/dev/null
  defaults delete com.apple.screencapture type 2>/dev/null
  defaults delete com.apple.screencapture disable-shadow 2>/dev/null
  defaults delete com.apple.desktopservices DSDontWriteNetworkStores 2>/dev/null
  defaults delete com.apple.desktopservices DSDontWriteUSBStores 2>/dev/null
  killall Finder 2>/dev/null || true
  killall Dock 2>/dev/null || true
  ok "системные настройки возвращены к значениям по умолчанию"
fi

# ============================================================================
#  Откат структуры папок — ТОЛЬКО пустые (rmdir не тронет папки с файлами)
# ============================================================================
step "Откат файловой структуры (безопасно — только пустые папки)"
warn "Папки с твоими файлами НЕ удаляются — только пустые каркасные"
# rmdir физически не может удалить непустую папку → твои документы в безопасности.
# Идём от самых вложенных к корневым, чтобы пустые родители тоже схлопнулись.
FOLDERS=(
  "$HOME/Documents/00_Inbox" "$HOME/Documents/Personal/IDs"
  "$HOME/Documents/Personal/Medical" "$HOME/Documents/Personal"
  "$HOME/Documents/Finances" "$HOME/Documents/Work"
  "$HOME/Documents/Business" "$HOME/Documents/_Archive"
  "$HOME/Pictures/00_Inbox" "$HOME/Pictures/Screenshots"
  "$HOME/Pictures/Wallpapers" "$HOME/Pictures/_Archive"
  "$HOME/Developer/00_Inbox" "$HOME/Developer/_Archive"
)
for d in "${FOLDERS[@]}"; do
  if [[ -d "$d" ]]; then
    if rmdir "$d" 2>/dev/null; then
      ok "удалена пустая ${d/#$HOME/~}"
    else
      skip "${d/#$HOME/~} — НЕ пустая, оставлена (там твои файлы)"
    fi
  fi
done
# Developer/README.md и сам Developer — по подтверждению (README мы создавали сами)
if [[ -f "$HOME/Developer/README.md" ]]; then
  if confirm "Удалить ~/Developer/README.md (памятку, созданную скриптом)?"; then
    rm -f "$HOME/Developer/README.md" && ok "README удалён"
    rmdir "$HOME/Developer" 2>/dev/null && ok "~/Developer удалена (была пустой)" || skip "~/Developer оставлена (есть проекты)"
  else skip "README оставлен"; fi
fi

# ============================================================================
#  ОПАСНАЯ ЗОНА: SSH-ключ, Git-конфиг, сам Homebrew — всегда спрашиваем
# ============================================================================
step "Опасная зона (по отдельному подтверждению каждое)"

# Git-конфиг подписи
if git config --global --get commit.gpgsign &>/dev/null; then
  if confirm "Откатить Git-настройки подписи коммитов (signingkey, gpgsign)?"; then
    git config --global --unset commit.gpgsign 2>/dev/null
    git config --global --unset tag.gpgsign 2>/dev/null
    git config --global --unset gpg.format 2>/dev/null
    git config --global --unset user.signingkey 2>/dev/null
    git config --global --unset gpg.ssh.allowedSignersFile 2>/dev/null
    ok "Git-подпись отключена (user.name/email оставлены)"
  else skip "Git-конфиг не тронут"; fi
fi

# SSH-ключ — самое опасное
if [[ -f ~/.ssh/id_ed25519 ]]; then
  echo "  ${RED}${BOLD}ВНИМАНИЕ:${RESET} удаление SSH-ключа = потеря доступа к GitHub,"
  echo "  ${RED}если ключ нигде не сохранён. Обычно его НЕ нужно удалять.${RESET}"
  if confirm "Всё равно удалить ~/.ssh/id_ed25519 и .pub?"; then
    rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
    ok "SSH-ключ удалён"
    [[ -f ~/.config/git/allowed_signers ]] && rm -f ~/.config/git/allowed_signers && ok "allowed_signers удалён"
  else
    skip "SSH-ключ сохранён (правильный выбор в большинстве случаев)"
  fi
fi

# Сам Homebrew
if command -v brew &>/dev/null; then
  if confirm "Удалить САМ Homebrew целиком (и все оставшиеся пакеты)?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" || true
    ok "Homebrew удалён"
  else
    skip "Homebrew оставлен"
  fi
fi

# ============================================================================
clear
printf "${BOLD}${GREEN}"
cat << 'DONE'
   ╔══════════════════════════════════════════════╗
   ║          Откат завершён · Mac очищен          ║
   ╚══════════════════════════════════════════════╝
DONE
printf "${RESET}\n"
echo "  ${YELLOW}1.${RESET} Перезапусти терминал, чтобы изменения .zshrc вступили в силу"
echo "  ${YELLOW}2.${RESET} Некоторые системные твики применятся после перезагрузки"
echo "  ${YELLOW}3.${RESET} Xcode Command Line Tools НЕ удалялись (нужны системе)"
echo "     ${DIM}если очень нужно: sudo rm -rf /Library/Developer/CommandLineTools${RESET}"
echo
