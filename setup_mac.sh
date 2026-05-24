#!/usr/bin/env bash
#
# ============================================================================
#  Ultimate macOS Dev Setup — SRE + Swift Edition
#  Идемпотентный скрипт первичной настройки нового Mac (Apple Silicon / Intel).
#  Безопасно запускать повторно: всё проверяется перед установкой.
# ============================================================================

set -uo pipefail

# ---------- Цвета и хелперы вывода ----------
BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'; CYAN=$'\033[36m'

step()  { printf "\n${BOLD}${BLUE}▶ %s${RESET}\n" "$1"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
skip()  { printf "  ${DIM}• %s${RESET}\n" "$1"; }
err()   { printf "  ${RED}✗ %s${RESET}\n" "$1"; }

# ============================================================================
#  TUI: интерактивные меню со стрелками и чекбоксами (зелёный «терминальный» вид)
#  Чистый bash, СОВМЕСТИМ с bash 3.2 (дефолт macOS) — без namerefs/declare -A.
# ============================================================================
TUI_G=$'\033[38;5;46m'; TUI_GD=$'\033[38;5;28m'; TUI_INV=$'\033[7m'
TUI_HIDE=$'\033[?25l'; TUI_SHOW=$'\033[?25h'

_tui_key() {
  local k rest
  IFS= read -rsn1 k
  if [[ $k == $'\033' ]]; then read -rsn2 -t 0.001 rest; k+="$rest"; fi
  printf '%s' "$k"
}

# Косвенный доступ к массивам по ИМЕНИ (совместимо с bash 3.2)
_aget() { eval "printf '%s' \"\${$1[$2]}\""; }
_aset() { eval "$1[$2]=\"\$3\""; }
_alen() { eval "printf '%s' \"\${#$1[@]}\""; }

# multiselect NAMES_ARRNAME STATE_ARRNAME DESC_ARRNAME(или "") "Заголовок"
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
      if [[ $i -eq $cur ]]; then
        printf "  ${TUI_G}${TUI_INV} %s %s ${RESET}\n" "$box" "$label"
      else
        printf "  ${TUI_GD} %s %s${RESET}\n" "$box" "$label"
      fi
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

# singleselect OPTS_ARRNAME "Заголовок"  →  результат в $SELECTED_INDEX (0-based)
singleselect() {
  local oname=$1 title=$2
  local cur=0 num key i
  num=$(_alen "$oname")
  printf '%s' "$TUI_HIDE"
  while true; do
    printf '\033[H\033[J'
    printf "${TUI_G}${BOLD}  %s${RESET}\n" "$title"
    printf "${TUI_GD}  ↑/↓ двигаться · ENTER выбрать${RESET}\n\n"
    for ((i=0;i<num;i++)); do
      if [[ $i -eq $cur ]]; then printf "  ${TUI_G}${TUI_INV} ▸ %s ${RESET}\n" "$(_aget "$oname" "$i")"
      else printf "  ${TUI_GD}   %s${RESET}\n" "$(_aget "$oname" "$i")"; fi
    done
    key=$(_tui_key)
    case "$key" in
      $'\033[A'|k) ((cur=(cur-1+num)%num)) ;;
      $'\033[B'|j) ((cur=(cur+1)%num)) ;;
      ''|$'\n') break ;;
    esac
  done
  printf '%s' "$TUI_SHOW"
  SELECTED_INDEX=$cur
}

# ---------- 0. Предварительные проверки ----------
clear
printf "${BOLD}${CYAN}"
cat << 'BANNER'
   ╔══════════════════════════════════════════════╗
   ║   Ultimate macOS Dev Setup · SRE + Swift      ║
   ╚══════════════════════════════════════════════╝
BANNER
printf "${RESET}\n"

if [[ "$(uname)" != "Darwin" ]]; then
  err "Этот скрипт предназначен только для macOS."; exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi
ok "Архитектура: $ARCH · Homebrew prefix: $BREW_PREFIX"

# ---------- Запрос sudo и поддержание сессии ----------
step "Запрос прав администратора"
echo "  Введи пароль один раз — дальше скрипт всё сделает сам."
sudo -v
# Держим sudo живым, пока работает скрипт
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
ok "Сессия sudo активна"

# ---------- Touch ID для sudo (переживает обновления macOS) ----------
step "Touch ID для sudo в терминале"
# Проверяем наличие сенсора Touch ID
if [[ -e /usr/lib/pam/pam_tid.so.2 ]]; then
  SUDO_LOCAL="/etc/pam.d/sudo_local"
  TID_LINE="auth       sufficient     pam_tid.so"

  if [[ -f "$SUDO_LOCAL" ]] && grep -qE '^[^#]*pam_tid\.so' "$SUDO_LOCAL"; then
    skip "Touch ID для sudo уже включён"
  else
    # Если используешь tmux/screen — нужен pam_reattach, иначе Touch ID
    # не всплывает внутри мультиплексора. Ставим его и подключаем первым.
    REATTACH_LINE=""
    if brew list --formula pam-reattach &>/dev/null || brew install pam-reattach >/dev/null 2>&1; then
      REATTACH_PATH="$(brew --prefix)/lib/pam/pam_reattach.so"
      [[ -e "$REATTACH_PATH" ]] && REATTACH_LINE="auth       optional       $REATTACH_PATH"
    fi

    {
      echo "# sudo_local: локальный конфиг, переживает обновления macOS"
      [[ -n "$REATTACH_LINE" ]] && echo "$REATTACH_LINE"
      echo "$TID_LINE"
    } | sudo tee "$SUDO_LOCAL" >/dev/null
    sudo chmod 444 "$SUDO_LOCAL"
    sudo chown root:wheel "$SUDO_LOCAL"
    ok "Touch ID для sudo включён (sudo_local)"
  fi
else
  skip "На этом Mac нет сенсора Touch ID — пропускаю"
fi

# ============================================================================
#  ИНТЕРАКТИВНОЕ МЕНЮ ВЫБОРА (работает на bash 3.2 — дефолт macOS)
# ============================================================================

# --- Список GUI-приложений: имя | brew cask | по умолчанию(on/off) ---
APP_NAMES=(  "iTerm2"  "Visual Studio Code" "Spotify" "Rectangle" "Google Chrome" "Raycast" "Stats" "Telegram" "Maccy" "The Unarchiver" "MonitorControl" "DockDoor" "Caffeine" "AppCleaner" "Bruno" )
APP_CASKS=(  "iterm2"  "visual-studio-code" "spotify" "rectangle"  "google-chrome"  "raycast"  "stats"  "telegram" "maccy" "the-unarchiver" "monitorcontrol" "dockdoor" "domzilla-caffeine" "appcleaner" "bruno" )
APP_DESC=(
  "продвинутый терминал — замена встроенному Terminal"
  "редактор кода от Microsoft"
  "музыка"
  "тайлинг окон по хоткеям (пересекается с Raycast)"
  "браузер"
  "launcher-комбайн: запуск, буфер, окна, сниппеты, AI — замена Spotlight"
  "мониторинг CPU/RAM/сети/диска в меню-баре (опенсорс)"
  "мессенджер"
  "история буфера обмена (Raycast уже умеет это)"
  "открывает RAR/7z/tar и прочие архивы лучше встроенного"
  "яркость/звук внешних мониторов с клавиатуры (опенсорс)"
  "превью окон при наведении на иконку в Dock (опенсорс)"
  "не даёт маку уснуть — Caffeine от Domzilla (caffeine-app.net), поддержка свежих macOS"
  "удаляет приложения вместе со всеми хвостами"
  "локальный REST/API-клиент, опенсорс-альтернатива Postman"
)
APP_DEFAULT=("on"      "on"                 "on"      "on"         "on"             "on"       "off"    "off"      "off"   "on"             "on"             "off"      "on"       "on"         "off"   )

# Скопируем дефолты в рабочий массив выбора
APP_PICK=("${APP_DEFAULT[@]}")

multiselect APP_NAMES APP_PICK APP_DESC "ВЫБОР GUI-ПРИЛОЖЕНИЙ"

# --- Меню Deck (отдельно: сторонний tap + не нотаризован) ---
clear
printf "${BOLD}${CYAN}Deck — менеджер буфера обмена${RESET}\n\n"
printf "  Нативный clipboard-менеджер с поиском, очередью вставки и AI.\n"
printf "  ${DIM}Ставится из стороннего tap (yuzeguitarist/deck), не нотаризован Apple —${RESET}\n"
printf "  ${DIM}карантин снимается ТОЛЬКО для него, не глобально.${RESET}\n\n"
printf "  ${YELLOW}Учти после установки:${RESET}\n"
printf "  ${DIM}• выключи авто-выгрузку диагностики (Settings → Upload analytics)${RESET}\n"
printf "  ${DIM}• AI-фичи шлют буфер в OpenAI/Anthropic — используй Ollama локально,${RESET}\n"
printf "  ${DIM}  если в буфере бывают токены/kubeconfig/секреты${RESET}\n"
sleep 2
DECK_OPTS=("Не ставить Deck" "Установить Deck")
singleselect DECK_OPTS "DECK — МЕНЕДЖЕР БУФЕРА"
# 1 = установить, 0 = не ставить → приводим к старому формату (1/2)
[[ $SELECTED_INDEX -eq 1 ]] && DECK_CHOICE=1 || DECK_CHOICE=2

# --- Меню Swift-инструментов ---
SWIFT_OPTS=("Полный набор: SwiftLint + SwiftFormat + xcbeautify (рекомендуется)" "Минимум: только SwiftLint" "Ничего")
singleselect SWIFT_OPTS "SWIFT-ИНСТРУМЕНТЫ"
SWIFT_CHOICE=$((SELECTED_INDEX+1))

# --- Меню Docker ---
DOCKER_OPTS=("Colima + Docker CLI (лёгкий, без GUI, ~400MB RAM)" "Docker Desktop (GUI — твой выбор)" "Не ставить Docker")
singleselect DOCKER_OPTS "DOCKER / КОНТЕЙНЕРЫ"
DOCKER_CHOICE=$((SELECTED_INDEX+1))

clear
ok "Конфигурация выбрана. Поехали — дальше без вопросов (кроме GitHub-ключа)."
sleep 1

# ============================================================================
#  1. Xcode Command Line Tools
# ============================================================================
step "Xcode Command Line Tools"
if xcode-select -p &>/dev/null; then
  skip "Уже установлены"
else
  echo "  Запускаю установку (откроется системное окно)..."
  xcode-select --install || true
  echo "  ${YELLOW}Дождись завершения установки в системном окне.${RESET}"
  read -r -p "  Нажми [Enter], когда установка Xcode CLT завершится... "
  ok "Xcode CLT готовы"
fi

# ============================================================================
#  2. Homebrew
# ============================================================================
step "Homebrew"
if command -v brew &>/dev/null; then
  skip "Уже установлен"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Прописываем в .zprofile только если ещё нет
  if ! grep -q 'brew shellenv' ~/.zprofile 2>/dev/null; then
    echo "eval \"\$($BREW_PREFIX/bin/brew shellenv)\"" >> ~/.zprofile
  fi
  ok "Homebrew установлен"
fi
eval "$($BREW_PREFIX/bin/brew shellenv)"

echo "  Обновляю репозитории..."
brew update >/dev/null 2>&1 && ok "Репозитории обновлены"

# Хелпер: установка formula, если ещё нет
brew_install() {
  if brew list --formula "$1" &>/dev/null; then
    skip "$1 (уже установлен)"
  else
    brew install "$1" >/dev/null 2>&1 && ok "$1" || err "$1 — ошибка установки"
  fi
}
# Хелпер: установка cask, если ещё нет
cask_install() {
  if brew list --cask "$1" &>/dev/null; then
    skip "$2 (уже установлен)"
  else
    brew install --cask "$1" >/dev/null 2>&1 && ok "$2" || err "$2 — ошибка установки"
  fi
}

# ============================================================================
#  3. Nerd Font (иконки для eza/p10k/neovim)
# ============================================================================
step "Шрифт с глифами (JetBrains Mono Nerd Font)"
cask_install "font-jetbrains-mono-nerd-font" "JetBrains Mono Nerd Font"

# ============================================================================
#  4. CLI: база, Rust-альтернативы, SRE-инструменты
# ============================================================================
step "CLI-утилиты: база + современные альтернативы"
# ВАЖНО: node НЕ ставим через brew — он конфликтует с nvm (см. ниже).
for pkg in git gh tmux btop neovim wget curl jq; do brew_install "$pkg"; done

step "Быстрый поиск и навигация (нужны для Neovim/fzf)"
for pkg in ripgrep fd eza bat fzf zoxide; do brew_install "$pkg"; done

step "SRE-инструменты"
# kubectl ставим как кask (официальный) или formula — formula проще
for pkg in kubectl k9s kubectx helm stern; do brew_install "$pkg"; done

# ============================================================================
#  5. Языковые рантаймы
# ============================================================================
step "Языковые рантаймы"
for pkg in go python nvm; do brew_install "$pkg"; done
# Каталог для nvm (без него nvm.sh ругается)
mkdir -p ~/.nvm

# ============================================================================
#  6. Swift-инструменты (по выбору из меню)
# ============================================================================
step "Swift-инструменты"
case "$SWIFT_CHOICE" in
  1) for pkg in swiftlint swiftformat xcbeautify; do brew_install "$pkg"; done ;;
  2) brew_install "swiftlint" ;;
  3) skip "Пропущено по выбору" ;;
  *) for pkg in swiftlint swiftformat xcbeautify; do brew_install "$pkg"; done ;;
esac

# ============================================================================
#  7. Docker (по выбору из меню)
# ============================================================================
step "Docker / контейнеры"
case "$DOCKER_CHOICE" in
  1)
    for pkg in colima docker docker-compose docker-buildx docker-credential-helper; do brew_install "$pkg"; done
    # Запускаем Colima (создаёт VM и docker socket), если ещё не запущена
    if command -v colima &>/dev/null; then
      if ! colima status &>/dev/null; then
        echo "  Запускаю Colima VM (первый старт может занять минуту)..."
        colima start >/dev/null 2>&1 && ok "Colima запущена" || warn "Colima не стартовала — запусти вручную: colima start"
      else
        skip "Colima уже запущена"
      fi
    fi
    ;;
  2) cask_install "docker" "Docker Desktop" ;;
  3) skip "Docker пропущен по выбору" ;;
  *) for pkg in colima docker docker-compose; do brew_install "$pkg"; done; colima start >/dev/null 2>&1 || true ;;
esac

# ============================================================================
#  8. SSH-ключ + подпись коммитов
# ============================================================================
step "SSH-ключ и подпись коммитов"
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -C "$(whoami)@$(hostname)-$(date +%Y%m%d)" >/dev/null
  ok "SSH-ключ ed25519 создан"
else
  skip "SSH-ключ уже существует"
fi

# Добавляем ключ в ssh-agent + keychain
eval "$(ssh-agent -s)" >/dev/null 2>&1
# Конфиг ssh-agent для автозагрузки ключа из keychain
if ! grep -q "UseKeychain" ~/.ssh/config 2>/dev/null; then
  cat >> ~/.ssh/config << 'SSHCFG'

Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
SSHCFG
fi
ssh-add --apple-use-keychain ~/.ssh/id_ed25519 >/dev/null 2>&1 || ssh-add ~/.ssh/id_ed25519 >/dev/null 2>&1
ok "Ключ добавлен в agent + Keychain"

# ============================================================================
#  9. Git-конфигурация
# ============================================================================
step "Конфигурация Git"
# Спрашиваем имя/почту только если ещё не настроено
CURRENT_NAME="$(git config --global user.name || true)"
CURRENT_MAIL="$(git config --global user.email || true)"

if [[ -z "$CURRENT_NAME" ]]; then
  read -r -p "  Имя для коммитов (Имя Фамилия): " GIT_NAME
  git config --global user.name "$GIT_NAME"
else
  GIT_NAME="$CURRENT_NAME"; skip "user.name уже задан: $GIT_NAME"
fi

if [[ -z "$CURRENT_MAIL" ]]; then
  read -r -p "  Email для коммитов: " GIT_MAIL
  git config --global user.email "$GIT_MAIL"
else
  GIT_MAIL="$CURRENT_MAIL"; skip "user.email уже задан: $GIT_MAIL"
fi

# Подпись коммитов через SSH-ключ
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global init.defaultBranch main
git config --global core.pager "less -F -X"
git config --global pull.rebase true
git config --global fetch.prune true

# allowed_signers — БЕЗ него git log --show-signature выдаёт ошибку
mkdir -p ~/.config/git
ALLOWED="$HOME/.config/git/allowed_signers"
PUBKEY="$(cat ~/.ssh/id_ed25519.pub)"
if ! grep -qF "$PUBKEY" "$ALLOWED" 2>/dev/null; then
  echo "$GIT_MAIL namespaces=\"git\" $PUBKEY" >> "$ALLOWED"
fi
git config --global gpg.ssh.allowedSignersFile "$ALLOWED"
ok "Git настроен, коммиты подписываются и проверяются локально"

# ============================================================================
#  10. Регистрация SSH-ключа на GitHub
# ============================================================================
step "Регистрация ключа на GitHub"
echo
echo "  ${BOLD}Скопируй этот публичный ключ:${RESET}"
echo "  ${DIM}────────────────────────────────────────────${RESET}"
echo "  ${CYAN}$PUBKEY${RESET}"
echo "  ${DIM}────────────────────────────────────────────${RESET}"
# Сразу кладём в буфер обмена
echo "$PUBKEY" | pbcopy && ok "Ключ уже скопирован в буфер обмена (Cmd+V)"
echo
echo "  ${YELLOW}ВАЖНО:${RESET} на GitHub добавь ключ ДВАЖДЫ — как ${BOLD}Authentication Key${RESET}"
echo "  и как ${BOLD}Signing Key${RESET} (тип выбирается при добавлении)."
open "https://github.com/settings/ssh/new" 2>/dev/null || true
read -r -p "  Нажми [Enter], когда добавишь ключ на GitHub... "

# ============================================================================
#  11. Oh-My-Zsh + Powerlevel10k + плагины
# ============================================================================
step "Zsh: Oh-My-Zsh + Powerlevel10k"
export RUNZSH=no  # не уходить в zsh посреди скрипта
if [[ ! -d ~/.oh-my-zsh ]]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >/dev/null 2>&1
  ok "Oh-My-Zsh установлен"
else
  skip "Oh-My-Zsh уже есть"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Powerlevel10k
if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" >/dev/null 2>&1
  ok "Powerlevel10k склонирован"
else
  skip "Powerlevel10k уже есть"
fi

# Плагины
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  if [[ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]]; then
    git clone --depth=1 "https://github.com/zsh-users/$plugin.git" "$ZSH_CUSTOM/plugins/$plugin" >/dev/null 2>&1
    ok "Плагин $plugin"
  else
    skip "Плагин $plugin уже есть"
  fi
done

# Тема в .zshrc
if grep -q 'ZSH_THEME=' ~/.zshrc; then
  sed -i '' 's|ZSH_THEME=".*"|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
fi
# Плагины в .zshrc
sed -i '' 's|^plugins=(.*)|plugins=(git zsh-autosuggestions zsh-syntax-highlighting docker kubectl)|' ~/.zshrc

# ============================================================================
#  12. Алиасы и инициализация инструментов
# ============================================================================
step "Алиасы и интеграции shell"
if ! grep -q "### DEV-SETUP-BLOCK ###" ~/.zshrc; then
  cat >> ~/.zshrc << 'ZRC'

### DEV-SETUP-BLOCK ###
# Современные алиасы
alias ls="eza --icons -a --group-directories-first"
alias ll="eza --icons -la --group-directories-first --git"
alias lt="eza --icons --tree --level=2"
alias cat="bat --style=plain"
# rg/fd оставляем под своими именами, чтобы не ломать скрипты,
# но даём короткие алиасы:
alias rgi="rg -i"
alias k="kubectl"

# zoxide (умный cd)
eval "$(zoxide init zsh)"

# fzf (key-bindings + completion)
if command -v fzf &>/dev/null; then
  source <(fzf --zsh) 2>/dev/null || { [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh; }
fi

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && \. "$(brew --prefix)/opt/nvm/nvm.sh"
[ -s "$(brew --prefix)/opt/nvm/etc/bash_completion.d/nvm" ] && \. "$(brew --prefix)/opt/nvm/etc/bash_completion.d/nvm"
### END-DEV-SETUP-BLOCK ###
ZRC
  ok "Блок алиасов добавлен в .zshrc"
else
  skip "Блок алиасов уже есть"
fi

# ============================================================================
#  13. Установка GUI-приложений (по выбору из меню)
# ============================================================================
step "GUI-приложения"
ANY_APP=false
for i in "${!APP_CASKS[@]}"; do
  if [[ "${APP_PICK[$i]}" == "on" ]]; then
    cask_install "${APP_CASKS[$i]}" "${APP_NAMES[$i]}"
    ANY_APP=true
  fi
done
$ANY_APP || skip "Приложения не выбраны"

# --- Deck (изолированный no-quarantine, только для него) ---
if [[ "$DECK_CHOICE" == "1" ]]; then
  step "Deck (менеджер буфера обмена)"
  if brew list --cask deckclip &>/dev/null; then
    skip "Deck уже установлен"
  else
    brew tap yuzeguitarist/deck >/dev/null 2>&1 && ok "tap yuzeguitarist/deck добавлен"
    # КЛЮЧЕВОЕ: --no-quarantine передаём как опцию ОДНОЙ команды,
    # а не через глобальный export HOMEBREW_CASK_OPTS — чтобы карантин
    # не снимался с остальных приложений.
    if brew install --cask --no-quarantine deckclip >/dev/null 2>&1; then
      ok "Deck установлен"
      warn "Не забудь: Settings → выключи Upload analytics; для AI используй Ollama локально"
    else
      err "Deck — ошибка установки (проверь вручную: brew install --cask --no-quarantine deckclip)"
    fi
  fi
fi

# ============================================================================
#  14. Установка LTS Node через nvm
# ============================================================================
step "Node.js LTS через nvm"
export NVM_DIR="$HOME/.nvm"
if [ -s "$BREW_PREFIX/opt/nvm/nvm.sh" ]; then
  \. "$BREW_PREFIX/opt/nvm/nvm.sh"
  if ! nvm ls --no-colors 2>/dev/null | grep -q "lts"; then
    nvm install --lts >/dev/null 2>&1 && ok "Node LTS установлен" || warn "Node LTS — установи вручную: nvm install --lts"
  else
    skip "Node LTS уже установлен"
  fi
fi

# ============================================================================
#  15. Системные твики macOS
# ============================================================================
step "Системные твики macOS"

# Finder
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Отключение автозамен
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Раскрытые панели сохранения/печати
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Клавиатура: быстрый повтор
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Dock: быстрый автоскрытие (ИСПРАВЛЕНА опечатка autide -> autohide)
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.15
defaults write com.apple.dock show-recents -bool false

# Скриншоты (расположение задаётся ниже, в секции структуры папок →
# ~/Pictures/Screenshots; здесь только формат и тень)
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture disable-shadow -bool true

# .DS_Store на сетевых/USB
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
ok "Твики применены"

# ============================================================================
#  16. Структура папок (организация по источнику/жизненному циклу)
# ============================================================================
step "Создание файловой структуры"
# Принцип: верхний уровень делится по ИСТОЧНИКУ файла (личное/работа/бизнес),
# а не по абстрактным категориям. 00_Inbox — свалка по умолчанию (сверху),
# _Archive — для законченного (снизу). Имена латиницей — стабильнее для путей.

# хелпер: создаёт папку, если её нет, и сообщает
mkfolder() {
  if [[ -d "$1" ]]; then skip "${1/#$HOME/~} (уже есть)"
  else mkdir -p "$1" && ok "${1/#$HOME/~}"; fi
}

# --- Документы ---
DOCS="$HOME/Documents"
mkfolder "$DOCS/00_Inbox"
mkfolder "$DOCS/Personal"          # паспорт, медицина, личные документы
mkfolder "$DOCS/Personal/IDs"      # документы, удостоверяющие личность
mkfolder "$DOCS/Personal/Medical"
mkfolder "$DOCS/Finances"          # счета, налоги, выписки
mkfolder "$DOCS/Work"              # трудовой договор, рабочие бумаги
mkfolder "$DOCS/Business"          # своё дело
mkfolder "$DOCS/_Archive"

# --- Изображения ---
PICS="$HOME/Pictures"
mkfolder "$PICS/00_Inbox"
mkfolder "$PICS/Screenshots"       # совпадает с местом сохранения скриншотов (см. твик выше)
mkfolder "$PICS/Wallpapers"
mkfolder "$PICS/_Archive"

# Перецелим скриншоты сюда (в твиках они шли в ~/Screenshots — объединяем логику)
defaults write com.apple.screencapture location -string "$PICS/Screenshots" 2>/dev/null
killall SystemUIServer 2>/dev/null || true
ok "скриншоты теперь сохраняются в ~/Pictures/Screenshots"

# --- Developer (проекты не дробим — папка проекта уже единица) ---
DEV="$HOME/Developer"
mkfolder "$DEV"
mkfolder "$DEV/00_Inbox"           # быстрый клон/эксперимент перед раскладкой
mkfolder "$DEV/_Archive"          # завершённые/замороженные проекты
# Примеры-плейсхолдеры можно создать по желанию — но не навязываем структуру.
# Просто кладём README с принципом, чтобы будущий ты помнил логику.
if [[ ! -f "$DEV/README.md" ]]; then
  cat > "$DEV/README.md" << 'DEVREADME'
# Developer

Каждая папка верхнего уровня = один проект (это и есть разграничение).
Не создавай категории-обёртки (Projects/Personal/...) — проект атомарен.

- 00_Inbox/  — временное: быстрый клон, эксперимент перед раскладкой
- <project>/ — сам проект (git-репозиторий)
- _Archive/  — завершённое или замороженное, чтобы не мешалось

Принцип: делим по источнику и жизненному циклу, а не по абстрактным темам.
DEVREADME
  ok "~/Developer/README.md (памятка о принципе)"
fi

# ============================================================================
#  17. Финал
# ============================================================================
brew cleanup >/dev/null 2>&1

clear
printf "${BOLD}${GREEN}"
cat << 'DONE'
   ╔══════════════════════════════════════════════╗
   ║             Готово! Mac настроен              ║
   ╚══════════════════════════════════════════════╝
DONE
printf "${RESET}"
printf "                    🎉\n\n"

echo "${BOLD}Что осталось сделать руками:${RESET}"
echo "  ${YELLOW}1.${RESET} Перезапусти терминал (или: ${CYAN}source ~/.zshrc${RESET})"
echo "  ${YELLOW}2.${RESET} В iTerm2 → Settings → Profiles → Text → шрифт"
echo "       выбери ${BOLD}JetBrainsMono Nerd Font${RESET}"
echo "  ${YELLOW}3.${RESET} При первом старте zsh запустится мастер Powerlevel10k —"
echo "       пройди его, или запусти позже: ${CYAN}p10k configure${RESET}"
echo "  ${YELLOW}4.${RESET} Проверь подпись: сделай тестовый коммит и ${CYAN}git log --show-signature${RESET}"
[[ "$DOCKER_CHOICE" == "1" ]] && echo "  ${YELLOW}5.${RESET} Docker: Colima автозапускается командой ${CYAN}colima start${RESET}"
[[ "$DOCKER_CHOICE" == "2" ]] && echo "  ${YELLOW}5.${RESET} Docker Desktop: запусти его из /Applications один раз —"
[[ "$DOCKER_CHOICE" == "2" ]] && echo "       он попросит подтвердить привилегии и поднимет движок (значок-кит в меню-баре)"
if [[ -e /usr/lib/pam/pam_tid.so.2 ]]; then
  echo "  ${YELLOW}6.${RESET} Touch ID для sudo включён. Проверь: открой новый таб и набери ${CYAN}sudo -k; sudo echo ok${RESET}"
  echo "       ${DIM}Для iTerm2: Settings → Advanced → найди \"survive logging out\" → No,${RESET}"
  echo "       ${DIM}иначе палец не всплывёт. Apple Watch нативно не поддерживается${RESET}"
  echo "       ${DIM}(только сторонний pam-модуль — ненадёжен, в скрипт не добавлял).${RESET}"
fi
if [[ "$DECK_CHOICE" == "1" ]]; then
  echo "  ${YELLOW}7.${RESET} Deck не нотаризован: при первом запуске macOS его заблокирует."
  echo "       ${DIM}System Settings → Privacy & Security → найди сообщение про Deck → Open Anyway (разово).${RESET}"
  echo "       ${DIM}Затем сразу выключи авто-выгрузку диагностики в настройках Deck.${RESET}"
fi
echo
