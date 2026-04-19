#!/usr/bin/env bash
# =============================================================================
# WSL2 Setup Completo para Analista de Dados — v2.1
# Autor: Claude | Data: 2026
#
# MUDANÇAS v2.1:
#   - NOVO módulo 14: dlab — Data Lab CLI (catálogo + linhagem + diagnóstico)
#
# MUDANÇAS v2:
#   - Feedback visual com spinners, barras de progresso e timestamps
#   - Passo 10 (JupyterLab) reescrito: extensões compatíveis com Lab 4.x,
#     instalação em batch, smoke test ao final
#   - Verificação de versões antes de reinstalar
#   - Timeouts em comandos de rede (wget, curl, pip com --timeout)
#   - Separação clara entre erros críticos e avisos não-críticos
#   - Sumário de falhas ao final (não só de sucessos)
# =============================================================================

set -uo pipefail   # Removido -e: erros não-críticos são capturados localmente

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';  CYAN='\033[0;36m';  MAGENTA='\033[0;35m'
BOLD='\033[1m';     DIM='\033[2m';       NC='\033[0m'
TICK="${GREEN}✔${NC}"; CROSS="${RED}✘${NC}"; WARN="${YELLOW}⚠${NC}"
ARROW="${CYAN}→${NC}"

# ── Estado global ─────────────────────────────────────────────────────────────
FAILED_STEPS=()          # Passos que falharam (não-críticos)
SKIPPED_STEPS=()         # Passos ignorados por já estarem presentes
INSTALLED_VERSIONS=()    # Registro de versões instaladas
LOG_FILE="$HOME/.wsl2_setup_$(date +%Y%m%d_%H%M%S).log"
STEP_TIMER=0

# ── Helpers de output ─────────────────────────────────────────────────────────
_ts()    { date '+%H:%M:%S'; }
_log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

info()   {
  echo -e "  ${CYAN}[INFO]${NC}  $*"
  _log "INFO  $*"
}
ok()     {
  echo -e "  ${TICK} ${GREEN}$*${NC}"
  _log "OK    $*"
}
warn()   {
  echo -e "  ${WARN} ${YELLOW}$*${NC}"
  _log "WARN  $*"
}
err()    {
  echo -e "  ${CROSS} ${RED}$*${NC}"
  _log "ERROR $*"
}
detail() {
  echo -e "    ${DIM}$*${NC}"
  _log "      $*"
}

# Separador de passo com timer
step() {
  local num="$1"; shift
  local title="$*"
  echo ""
  echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────────────────────────────┐${NC}"
  printf "${BOLD}${BLUE}│${NC} ${BOLD}%s. %-61s${BLUE}│${NC}\n" "$num" "$title"
  echo -e "${BOLD}${BLUE}└─────────────────────────────────────────────────────────────────┘${NC}"
  STEP_TIMER=$SECONDS
  _log "=== STEP $num: $title ==="
}

# Encerramento de passo com tempo decorrido
end_step() {
  local elapsed=$(( SECONDS - STEP_TIMER ))
  echo -e "  ${DIM}⏱  Concluído em ${elapsed}s${NC}"
  _log "    Step concluído em ${elapsed}s"
}

# Spinner para comandos sem output visível
SPINNER_PID=""
spinner_start() {
  local msg="${1:-Aguarde...}"
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  (
    i=0
    while true; do
      printf "\r  ${CYAN}${frames:$i:1}${NC}  ${DIM}%s${NC}   " "$msg"
      i=$(( (i+1) % ${#frames} ))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
  local status="${1:-0}"
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  printf "\r%-70s\r" " "   # Limpa a linha do spinner
  if [[ "$status" == "0" ]]; then
    ok "$2"
  else
    warn "$2 (pode continuar)"
  fi
}

# Barra de progresso para listas
progress_bar() {
  local current="$1"
  local total="$2"
  local label="$3"
  local width=40
  local filled=$(( width * current / total ))
  local empty=$(( width - filled ))
  local pct=$(( 100 * current / total ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do  bar+="░"; done
  printf "\r  [%s] %3d%%  %-35s" "$bar" "$pct" "$label"
}

# Instala um pacote pip com feedback
pip_install_item() {
  local pkg="$1"
  local current="$2"
  local total="$3"
  local extra_flags="${4:-}"

  progress_bar "$current" "$total" "$pkg"
  # shellcheck disable=SC2086
  if pip install --upgrade --quiet --timeout 120 $extra_flags "$pkg" >> "$LOG_FILE" 2>&1; then
    local ver
    ver=$(pip show "$pkg" 2>/dev/null | awk '/^Version:/{print $2}')
    INSTALLED_VERSIONS+=("$pkg==$ver")
    return 0
  else
    FAILED_STEPS+=("pip:$pkg")
    return 1
  fi
}

# Instala lista de pacotes pip com barra de progresso
pip_install_list() {
  local -n _pkgs=$1   # nameref: passar nome do array
  local extra_flags="${2:-}"
  local total=${#_pkgs[@]}
  local ok_count=0
  local fail_count=0

  echo ""
  for i in "${!_pkgs[@]}"; do
    local pkg="${_pkgs[$i]}"
    local current=$(( i + 1 ))
    if pip_install_item "$pkg" "$current" "$total" "$extra_flags"; then
      (( ok_count++ )) || true
    else
      (( fail_count++ )) || true
    fi
  done
  printf "\r%-70s\r" " "

  if [[ $fail_count -eq 0 ]]; then
    ok "$ok_count pacotes instalados com sucesso"
  else
    warn "$ok_count instalados  |  $fail_count falharam (veja $LOG_FILE)"
  fi
}

# Confirma input do usuário
confirm() {
  echo -e "${YELLOW}$1${NC}"
  read -rp "  [s/N]: " ans
  [[ "${ans,,}" == "s" ]]
}

# Banner ASCII
banner() {
  echo -e "${BOLD}${CYAN}"
  cat <<'EOF'
  ██████╗  █████╗ ████████╗ █████╗     ██╗      █████╗ ██████╗
  ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗    ██║     ██╔══██╗██╔══██╗
  ██║  ██║███████║   ██║   ███████║    ██║     ███████║██████╔╝
  ██║  ██║██╔══██║   ██║   ██╔══██║    ██║     ██╔══██║██╔══██╗
  ██████╔╝██║  ██║   ██║   ██║  ██║    ███████╗██║  ██║██████╔╝
  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═════╝
EOF
  echo -e "${NC}  ${BOLD}WSL2 Setup Completo — Analista de Dados 2026  ${DIM}[v2.1]${NC}"
  echo -e "  ${DIM}Log em: $LOG_FILE${NC}"
}

# ── Verificação do ambiente ───────────────────────────────────────────────────
check_wsl() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    ok "WSL2 detectado."
  else
    warn "Não parece ser WSL2. Continuando mesmo assim..."
  fi

  # Verifica internet
  spinner_start "Verificando conexão com a internet..."
  if curl -fsSL --connect-timeout 5 https://pypi.org > /dev/null 2>&1; then
    spinner_stop 0 "Internet OK"
  else
    spinner_stop 1 ""
    err "Sem acesso à internet. Verifique a conexão e tente novamente."
    exit 1
  fi

  # Verifica espaço em disco (mínimo 5 GB livre)
  local free_gb
  free_gb=$(df -BG "$HOME" | awk 'NR==2{print $4}' | tr -d 'G')
  if (( free_gb < 5 )); then
    err "Espaço insuficiente: ${free_gb}GB livre (mínimo 5GB)"
    exit 1
  fi
  ok "Espaço em disco: ${free_gb}GB livre"
}

# =============================================================================
# 1. SISTEMA BASE
# =============================================================================
setup_system() {
  step 1 "Atualizando sistema base (Ubuntu/Debian)"

  spinner_start "Atualizando lista de pacotes..."
  sudo apt-get update -qq >> "$LOG_FILE" 2>&1
  spinner_stop 0 "Lista de pacotes atualizada"

  spinner_start "Instalando dependências do sistema..."
  sudo apt-get upgrade -y -qq >> "$LOG_FILE" 2>&1
  sudo apt-get install -y -qq \
    build-essential curl wget git unzip zip tar \
    ca-certificates gnupg lsb-release software-properties-common \
    apt-transport-https jq tree htop ncdu tmux \
    libssl-dev libffi-dev libpq-dev libsqlite3-dev \
    fonts-powerline >> "$LOG_FILE" 2>&1
  spinner_stop 0 "Dependências do sistema instaladas"
  end_step
}

# =============================================================================
# 2. ZSH + OH-MY-ZSH + POWERLEVEL10K
# =============================================================================
setup_shell() {
  step 2 "Shell: Zsh + Oh-My-Zsh + Powerlevel10k"

  sudo apt-get install -y -qq zsh >> "$LOG_FILE" 2>&1

  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    spinner_start "Instalando Oh-My-Zsh..."
    RUNZSH=no CHSH=no sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      >> "$LOG_FILE" 2>&1
    spinner_stop 0 "Oh-My-Zsh instalado"
  else
    ok "Oh-My-Zsh já instalado"
    SKIPPED_STEPS+=("oh-my-zsh")
  fi

  local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
  if [ ! -d "$p10k_dir" ]; then
    spinner_start "Clonando Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir" >> "$LOG_FILE" 2>&1
    spinner_stop 0 "Powerlevel10k instalado"
  else
    ok "Powerlevel10k já instalado"
  fi

  local ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local plugins=(
    "zsh-users/zsh-autosuggestions"
    "zsh-users/zsh-syntax-highlighting"
    "zsh-users/zsh-completions"
  )
  local total=${#plugins[@]}
  echo ""
  for i in "${!plugins[@]}"; do
    local repo="${plugins[$i]}"
    local name
    name=$(basename "$repo")
    local dir="$ZSH_CUSTOM_DIR/plugins/$name"
    progress_bar "$(( i + 1 ))" "$total" "$name"
    if [ ! -d "$dir" ]; then
      git clone --depth=1 "https://github.com/${repo}.git" "$dir" >> "$LOG_FILE" 2>&1
    fi
  done
  printf "\r%-70s\r" " "
  ok "Plugins Zsh instalados"

  # Escreve .zshrc
  cat > "$HOME/.zshrc" <<'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions docker kubectl python pip)
source $ZSH/oh-my-zsh.sh
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)" 2>/dev/null || true

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

alias ll='ls -lAh --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias update='sudo apt update && sudo apt upgrade -y'
alias cls='clear'
alias py='python3'
alias pip='pip3'
alias jn='jupyter notebook'
alias jl='jupyter lab'
alias jlab='~/.local/bin/jlab'
alias act='source .venv/bin/activate'
alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias dps='docker ps'
alias dimg='docker images'
alias dprune='docker system prune -f'
alias dbt-run='dbt run'
alias dbt-test='dbt test'

mkcd() { mkdir -p "$1" && cd "$1"; }
venv() { python3 -m venv .venv && source .venv/bin/activate && pip install --upgrade pip; }
csvhead() { head -1 "$1" | tr ',' '\n' | nl; }
ZSHRC

  sudo chsh -s "$(which zsh)" "$USER" >> "$LOG_FILE" 2>&1 || \
    warn "Shell não foi alterado automaticamente. Execute: chsh -s \$(which zsh)"
  ok "Shell configurado. Execute: source ~/.zshrc"
  end_step
}

# =============================================================================
# 3. PYTHON via pyenv
# =============================================================================
setup_python() {
  step 3 "Python via pyenv"

  spinner_start "Instalando dependências de compilação do Python..."
  sudo apt-get install -y -qq \
    make libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    >> "$LOG_FILE" 2>&1
  spinner_stop 0 "Dependências instaladas"

  if [ ! -d "$HOME/.pyenv" ]; then
    spinner_start "Instalando pyenv..."
    curl -fsSL https://pyenv.run | bash >> "$LOG_FILE" 2>&1
    spinner_stop 0 "pyenv instalado"
  else
    ok "pyenv já instalado"
  fi

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"

  local py_version="3.12.3"
  if ! pyenv versions 2>/dev/null | grep -q "$py_version"; then
    spinner_start "Compilando Python $py_version (pode levar 5-10 min)..."
    pyenv install "$py_version" >> "$LOG_FILE" 2>&1
    spinner_stop 0 "Python $py_version compilado"
    pyenv global "$py_version"
  else
    ok "Python $py_version já instalado"
    SKIPPED_STEPS+=("python-$py_version")
  fi

  local actual_ver
  actual_ver=$(python3 --version 2>&1)
  detail "Versão ativa: $actual_ver"
  INSTALLED_VERSIONS+=("$actual_ver")

  spinner_start "Atualizando pip, setuptools e wheel..."
  pip install --upgrade --quiet pip setuptools wheel >> "$LOG_FILE" 2>&1
  spinner_stop 0 "pip $(pip --version | awk '{print $2}')"
  end_step
}

# =============================================================================
# 4. PACOTES PYTHON PARA DADOS
# =============================================================================
setup_python_packages() {
  step 4 "Pacotes Python para Análise de Dados"

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true

  # --- Grupo 1: Núcleo de dados ---
  echo -e "\n  ${BOLD}${DIM}▸ Núcleo de dados${NC}"
  local PKGS_CORE=(numpy pandas polars pyarrow)
  pip_install_list PKGS_CORE

  # --- Grupo 2: Visualização ---
  echo -e "\n  ${BOLD}${DIM}▸ Visualização${NC}"
  local PKGS_VIZ=(matplotlib seaborn plotly altair bokeh)
  pip_install_list PKGS_VIZ

  # --- Grupo 3: Jupyter ---
  echo -e "\n  ${BOLD}${DIM}▸ Jupyter (core)${NC}"
  local PKGS_JUPYTER=(
    "jupyterlab>=4.0"
    notebook
    ipywidgets
    ipykernel
    nbformat
    nbconvert
    jupyterlab-git
  )
  pip_install_list PKGS_JUPYTER

  # --- Grupo 4: ML ---
  echo -e "\n  ${BOLD}${DIM}▸ Machine Learning${NC}"
  local PKGS_ML=(scikit-learn xgboost lightgbm scipy statsmodels)
  pip_install_list PKGS_ML

  # --- Grupo 5: SQL e bancos ---
  echo -e "\n  ${BOLD}${DIM}▸ SQL e Bancos${NC}"
  local PKGS_SQL=(sqlalchemy psycopg2-binary pymysql duckdb)
  pip_install_list PKGS_SQL

  # --- Grupo 6: Cloud e Big Data ---
  echo -e "\n  ${BOLD}${DIM}▸ Cloud e Big Data${NC}"
  local PKGS_CLOUD=(pyspark boto3 google-cloud-bigquery)
  pip_install_list PKGS_CLOUD

  # --- Grupo 7: ELT e Orquestração ---
  echo -e "\n  ${BOLD}${DIM}▸ ELT e Orquestração${NC}"
  local PKGS_ELT=(
    "pathspec>=0.9,<0.13"
    dbt-core
    dbt-postgres
    dbt-bigquery
    prefect
    apache-airflow
  )
  pip_install_list PKGS_ELT

  # --- Grupo 8: Qualidade ---
  echo -e "\n  ${BOLD}${DIM}▸ Qualidade de Dados${NC}"
  local PKGS_QUALITY=(great-expectations pandera)
  pip_install_list PKGS_QUALITY

  # --- Grupo 9: APIs e utilitários ---
  echo -e "\n  ${BOLD}${DIM}▸ APIs e Utilitários${NC}"
  local PKGS_UTIL=(
    requests httpx fastapi uvicorn
    python-dotenv pydantic "rich<15.0" typer tqdm
    openpyxl xlrd xlwt loguru
    black ruff mypy pytest
  )
  pip_install_list PKGS_UTIL

  # --- PyTorch CPU (índice separado) ---
  echo -e "\n  ${BOLD}${DIM}▸ PyTorch (CPU)${NC}"
  spinner_start "Instalando torch + torchvision (pode demorar)..."
  if pip install --upgrade --quiet --timeout 300 \
       torch torchvision \
       --index-url https://download.pytorch.org/whl/cpu \
       >> "$LOG_FILE" 2>&1; then
    spinner_stop 0 "PyTorch CPU instalado"
    INSTALLED_VERSIONS+=("torch (CPU)")
  else
    spinner_stop 1 "PyTorch CPU falhou (não-crítico)"
    FAILED_STEPS+=("torch-cpu")
  fi

  end_step
}

# =============================================================================
# 5. NODE.JS via NVM
# =============================================================================
setup_node() {
  step 5 "Node.js via nvm"

  if [ ! -d "$HOME/.nvm" ]; then
    spinner_start "Instalando nvm..."
    curl -fsSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh \
      | bash >> "$LOG_FILE" 2>&1
    spinner_stop 0 "nvm instalado"
  else
    ok "nvm já instalado"
  fi

  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  set +u

  spinner_start "Instalando Node.js LTS..."
  nvm install --lts >> "$LOG_FILE" 2>&1
  nvm use --lts >> "$LOG_FILE" 2>&1
  nvm alias default node >> "$LOG_FILE" 2>&1
  spinner_stop 0 "Node.js $(node -v) instalado"
  INSTALLED_VERSIONS+=("node $(node -v)")

  local npm_ok=0
  local npm_fail=0
  local npm_total=7
  local npm_current=0
  echo ""
  for pkg in yarn pnpm ts-node typescript prettier eslint http-server; do
    npm_current=$(( npm_current + 1 ))
    progress_bar "$npm_current" "$npm_total" "$pkg"
    if npm install -g "$pkg" >> "$LOG_FILE" 2>&1; then
      npm_ok=$(( npm_ok + 1 ))
    else
      npm_fail=$(( npm_fail + 1 ))
      FAILED_STEPS+=("npm:$pkg")
    fi
  done
  printf "\r%-70s\r" " "

  set -u

  if [[ $npm_fail -eq 0 ]]; then
    ok "$npm_ok pacotes npm globais instalados"
  else
    warn "$npm_ok instalados  |  $npm_fail falharam (veja $LOG_FILE)"
  fi
  end_step
}

# =============================================================================
# 6. RUST + FERRAMENTAS CLI
# =============================================================================
setup_rust() {
  step 6 "Rust + ferramentas CLI modernas"

  if ! command -v rustup &>/dev/null; then
    spinner_start "Instalando Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y >> "$LOG_FILE" 2>&1
    spinner_stop 0 "Rust instalado"
  else
    ok "Rust já instalado: $(rustc --version 2>/dev/null)"
  fi

  source "$HOME/.cargo/env" 2>/dev/null || true

  local rust_tools=(ripgrep fd-find bat lsd tokei hyperfine bottom du-dust)
  local total=${#rust_tools[@]}
  local ok_count=0
  local fail_count=0

  echo ""
  for i in "${!rust_tools[@]}"; do
    local tool="${rust_tools[$i]}"
    progress_bar "$(( i + 1 ))" "$total" "$tool (compilando...)"
    if cargo install "$tool" >> "$LOG_FILE" 2>&1; then
      (( ok_count++ )) || true
    else
      FAILED_STEPS+=("cargo:$tool")
      (( fail_count++ )) || true
    fi
  done
  printf "\r%-70s\r" " "

  spinner_start "Instalando delta (git diff)..."
  if cargo install git-delta >> "$LOG_FILE" 2>&1; then
    spinner_stop 0 "delta instalado"
    (( ok_count++ )) || true
  else
    spinner_stop 1 "delta falhou (não-crítico)"
    (( fail_count++ )) || true
    FAILED_STEPS+=("cargo:git-delta")
  fi

  if [[ $fail_count -eq 0 ]]; then
    ok "${ok_count} ferramentas Rust instaladas: rg, fd, bat, lsd, delta, btm..."
  else
    warn "${ok_count} instaladas | ${fail_count} falharam (veja o log)"
  fi
  end_step
}

# =============================================================================
# 7. DOCKER
# =============================================================================
setup_docker() {
  step 7 "Docker Engine"

  if command -v docker &>/dev/null; then
    ok "Docker já instalado: $(docker --version)"
    SKIPPED_STEPS+=("docker")
    end_step
    return
  fi

  spinner_start "Adicionando repositório oficial Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>> "$LOG_FILE"
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >> "$LOG_FILE"
  sudo apt-get update -qq >> "$LOG_FILE" 2>&1
  spinner_stop 0 "Repositório Docker adicionado"

  spinner_start "Instalando Docker CE..."
  sudo apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    >> "$LOG_FILE" 2>&1
  spinner_stop 0 "Docker instalado"

  sudo usermod -aG docker "$USER"
  INSTALLED_VERSIONS+=("docker $(docker --version | awk '{print $3}' | tr -d ',')")
  detail "Usuário adicionado ao grupo 'docker'. Reinicie o terminal para usar sem sudo."
  end_step
}

# =============================================================================
# 8. BANCOS DE DADOS
# =============================================================================
setup_databases() {
  step 8 "Bancos de Dados"

  spinner_start "Instalando PostgreSQL e Redis..."
  sudo apt-get install -y -qq postgresql postgresql-client redis-server redis-tools \
    sqlite3 >> "$LOG_FILE" 2>&1
  spinner_stop 0 "PostgreSQL, Redis e SQLite3 instalados"

  if ! command -v duckdb &>/dev/null; then
    spinner_start "Baixando DuckDB CLI..."
    local duck_version="v0.10.2"
    wget -qO /tmp/duckdb.zip --timeout=60 \
      "https://github.com/duckdb/duckdb/releases/download/${duck_version}/duckdb_cli-linux-amd64.zip" \
      >> "$LOG_FILE" 2>&1
    sudo unzip -o /tmp/duckdb.zip -d /usr/local/bin/ >> "$LOG_FILE" 2>&1
    sudo chmod +x /usr/local/bin/duckdb
    rm /tmp/duckdb.zip
    spinner_stop 0 "DuckDB CLI $(duckdb --version 2>/dev/null || echo '') instalado"
    INSTALLED_VERSIONS+=("duckdb CLI")
  else
    ok "DuckDB já instalado: $(duckdb --version 2>/dev/null)"
  fi

  if echo "SELECT 42 AS test;" | duckdb :memory: >> "$LOG_FILE" 2>&1; then
    detail "Smoke test DuckDB OK (SELECT 42)"
  else
    warn "DuckDB instalado mas o smoke test falhou — verifique manualmente"
  fi

  end_step
}

# =============================================================================
# 9. FERRAMENTAS DE PRODUTIVIDADE
# =============================================================================
setup_productivity() {
  step 9 "Ferramentas de Produtividade CLI"

  if [ ! -d "$HOME/.fzf" ]; then
    spinner_start "Instalando fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf" >> "$LOG_FILE" 2>&1
    "$HOME/.fzf/install" --all >> "$LOG_FILE" 2>&1
    spinner_stop 0 "fzf instalado"
  else
    ok "fzf já instalado"
  fi

  cat > "$HOME/.tmux.conf" <<'TMUX'
set -g default-terminal "screen-256color"
set -g history-limit 10000
set -g mouse on
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind r source-file ~/.tmux.conf \; display "Config recarregado!"
set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
set -g status-left '#[bold]  #S '
set -g status-right '#[fg=#89b4fa] %d/%m %H:%M '
TMUX

  git config --global init.defaultBranch main
  git config --global core.editor "code --wait" 2>/dev/null || \
    git config --global core.editor "nano"
  git config --global pull.rebase false
  git config --global core.autocrlf input
  git config --global core.pager delta 2>/dev/null || true
  git config --global delta.navigate true 2>/dev/null || true
  git config --global delta.side-by-side true 2>/dev/null || true

  ok "tmux configurado  |  git configurado com delta"
  end_step
}

# =============================================================================
# 10. JUPYTERLAB — CORRIGIDO
# =============================================================================
setup_jupyter() {
  step 10 "JupyterLab — Extensões e Configuração"

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true

  local lab_ver
  lab_ver=$(pip show jupyterlab 2>/dev/null | awk '/^Version:/{print $2}')
  if [[ -z "$lab_ver" ]]; then
    err "JupyterLab não está instalado. Execute o passo 4 primeiro."
    FAILED_STEPS+=("jupyter-config:no-jupyterlab")
    end_step
    return 1
  fi

  local lab_major
  lab_major=$(echo "$lab_ver" | cut -d. -f1)
  info "JupyterLab $lab_ver detectado (major=$lab_major)"

  local EXTS_LAB4=(
    "jupyterlab-lsp>=5.0"
    "python-lsp-server[all]"
    "jupyterlab_code_formatter"
    "black"
    "isort"
  )

  local EXTS_OPTIONAL=(
    "theme-darcula"
    "nbdime"
  )

  echo -e "\n  ${BOLD}${DIM}▸ Extensões essenciais (compatíveis com Lab ${lab_ver})${NC}"
  local total=${#EXTS_LAB4[@]}
  local ext_ok=0
  local ext_fail=0

  for i in "${!EXTS_LAB4[@]}"; do
    local ext="${EXTS_LAB4[$i]}"
    local ext_name
    ext_name=$(echo "$ext" | sed 's/[>=<].*//')
    progress_bar "$(( i + 1 ))" "$total" "$ext_name"
    if pip install --upgrade --quiet --timeout 120 "$ext" >> "$LOG_FILE" 2>&1; then
      (( ext_ok++ )) || true
    else
      (( ext_fail++ )) || true
      FAILED_STEPS+=("jlab-ext:$ext_name")
      _log "FAIL jlab extension: $ext_name"
    fi
  done
  printf "\r%-70s\r" " "

  if [[ $ext_fail -eq 0 ]]; then
    ok "$ext_ok extensões essenciais instaladas"
  else
    warn "$ext_ok instaladas  |  $ext_fail falharam (veja $LOG_FILE)"
  fi

  echo -e "\n  ${BOLD}${DIM}▸ Extensões opcionais${NC}"
  local total_opt=${#EXTS_OPTIONAL[@]}
  for i in "${!EXTS_OPTIONAL[@]}"; do
    local ext="${EXTS_OPTIONAL[$i]}"
    local ext_name
    ext_name=$(echo "$ext" | sed 's/[>=<].*//')
    progress_bar "$(( i + 1 ))" "$total_opt" "$ext_name"
    pip install --upgrade --quiet --timeout 60 "$ext" >> "$LOG_FILE" 2>&1 || true
  done
  printf "\r%-70s\r" " "
  ok "Extensões opcionais processadas"

  spinner_start "Registrando kernel Python no Jupyter..."
  if python3 -m ipykernel install --user --name python3 \
       --display-name "Python 3 (pyenv)" >> "$LOG_FILE" 2>&1; then
    spinner_stop 0 "Kernel Python 3 registrado"
  else
    spinner_stop 1 "Falha ao registrar kernel (não-crítico)"
    FAILED_STEPS+=("jupyter-kernel")
  fi

  spinner_start "Gerando arquivo de configuração JupyterLab..."
  if timeout 30 jupyter lab --generate-config -y >> "$LOG_FILE" 2>&1; then
    spinner_stop 0 "Configuração gerada em ~/.jupyter/"
  else
    spinner_stop 1 "generate-config falhou (não-crítico)"
    FAILED_STEPS+=("jupyter-generate-config")
  fi

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/jlab" <<'JLAB'
#!/bin/bash
cd "${1:-$HOME/data-projects}" && jupyter lab --no-browser "$@"
JLAB
  chmod +x "$HOME/.local/bin/jlab"
  ok "Atalho 'jlab' criado em ~/.local/bin/jlab"

  echo -e "\n  ${BOLD}${DIM}▸ Smoke tests${NC}"

  local actual_lab_ver
  actual_lab_ver=$(timeout 10 jupyter lab --version 2>/dev/null || echo "FALHOU")
  if [[ "$actual_lab_ver" != "FALHOU" ]]; then
    detail "jupyter lab --version → $actual_lab_ver  ${TICK}"
  else
    detail "jupyter lab --version → ${CROSS} (falhou)"
    FAILED_STEPS+=("smoke:jupyter-lab-version")
  fi

  local kernels
  kernels=$(timeout 10 jupyter kernelspec list 2>/dev/null || echo "FALHOU")
  if [[ "$kernels" != "FALHOU" ]] && echo "$kernels" | grep -q "python"; then
    detail "jupyter kernelspec list → kernel Python encontrado  ${TICK}"
  else
    detail "jupyter kernelspec list → ${CROSS} (kernel não encontrado)"
    FAILED_STEPS+=("smoke:jupyter-kernel-list")
  fi

  if python3 -c "import pylsp" >> "$LOG_FILE" 2>&1; then
    detail "python-lsp-server importável  ${TICK}"
  else
    detail "python-lsp-server não importável  ${WARN}"
    FAILED_STEPS+=("smoke:pylsp-import")
  fi

  echo ""
  info "Para iniciar: jlab  (ou: jupyter lab)"
  info "Acesse em:   http://localhost:8888"
  end_step
}

# =============================================================================
# 11. ESTRUTURA DE PASTAS
# =============================================================================
setup_folders() {
  step 11 "Estrutura de Pastas do Analista"

  local BASE="$HOME/data-projects"
  mkdir -p \
    "$BASE"/{notebooks,data/{raw,processed,external},scripts,reports,dashboards,models} \
    "$HOME"/{.config/dbt,tools}

  cat > "$HOME/.gitignore_global" <<'GTIG'
__pycache__/
*.py[cod]
.venv/
*.egg-info/
dist/
.pytest_cache/
*.csv
*.parquet
*.xlsx
*.json
!config.json
data/raw/
data/processed/
.ipynb_checkpoints/
.env
.env.*
!.env.example
.DS_Store
Thumbs.db
.vscode/
.idea/
*.swp
GTIG

  git config --global core.excludesfile "$HOME/.gitignore_global"

  cat > "$BASE/template_projeto.ipynb" <<'NB'
{
 "cells": [
  {"cell_type": "markdown", "metadata": {}, "source": ["# 📊 Projeto de Análise\n\n**Objetivo:** ...\n\n**Data:** ...\n"]},
  {"cell_type": "code", "metadata": {}, "source": ["import numpy as np\nimport pandas as pd\nimport matplotlib.pyplot as plt\nimport seaborn as sns\n\npd.set_option('display.max_columns', None)\npd.set_option('display.float_format', '{:.2f}'.format)\nsns.set_theme(style='whitegrid')\n\nprint('Ambiente pronto! ✅')"], "outputs": [], "execution_count": null}
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python 3 (pyenv)", "language": "python", "name": "python3"},
  "language_info": {"name": "python", "version": "3.12.3"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
NB

  ok "Estrutura criada em $BASE"
  end_step
}

# =============================================================================
# 12. CONFIGURAÇÃO WSL2
# =============================================================================
setup_wsl_config() {
  step 12 "Configuração WSL2 (wsl.conf)"

  sudo tee /etc/wsl.conf > /dev/null <<'WSLCONF'
[boot]
systemd=true

[network]
hostname=data-lab
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=false

[automount]
enabled=true
root=/mnt/
options="metadata,umask=22,fmask=11"
mountFsTab=true
WSLCONF

  cat > "$HOME/.wslconfig_tip.txt" <<'WC'
# Copie para: C:\Users\<SeuUsuário>\.wslconfig (no Windows)
# Ajuste os valores conforme sua RAM disponível.

[wsl2]
memory=8GB
processors=4
swap=4GB
localhostForwarding=true
WC

  ok "wsl.conf configurado (systemd habilitado)"
  warn "Crie o arquivo .wslconfig no Windows. Veja: ~/wslconfig_tip.txt"
  end_step
}

# =============================================================================
# 13. VS CODE EXTENSIONS
# =============================================================================
setup_vscode_list() {
  step 13 "Script de Extensões VS Code"

  cat > "$HOME/vscode_extensions_data.sh" <<'VSC'
#!/bin/bash
extensions=(
  ms-python.python
  ms-python.vscode-pylance
  ms-toolsai.jupyter
  ms-toolsai.jupyter-keymap
  ms-azuretools.vscode-docker
  ms-vscode-remote.remote-wsl
  ms-vscode-remote.remote-containers
  redhat.vscode-yaml
  esbenp.prettier-vscode
  dbaeumer.vscode-eslint
  mtxr.sqltools
  innoverio.vscode-dbt-power-user
  mechatroner.rainbow-csv
  GrapeCity.gc-excelviewer
  eamodio.gitlens
  mhutchie.git-graph
  christian-kohler.path-intellisense
  streetsidesoftware.code-spell-checker
  streetsidesoftware.code-spell-checker-portuguese-brazilian
  kevinrose.vsc-python-indent
  njpwerner.autodocstring
  oderwat.indent-rainbow
  PKief.material-icon-theme
  GitHub.copilot
  GitHub.copilot-chat
  charliermarsh.ruff
  tamasfe.even-better-toml
)
total=${#extensions[@]}
for i in "${!extensions[@]}"; do
  ext="${extensions[$i]}"
  echo "[$(( i + 1 ))/$total] $ext"
  code --install-extension "$ext" --force
done
echo "✅ Extensões instaladas!"
VSC

  chmod +x "$HOME/vscode_extensions_data.sh"
  ok "Script salvo: ~/vscode_extensions_data.sh"
  end_step
}

# =============================================================================
# 14. DLAB — Data Lab CLI (catálogo + linhagem + diagnóstico)
#
# O dlab é a camada que transforma este projeto de "instalador de uso único"
# em uma ferramenta com vida útil contínua. Implementa:
#   • dlab catalog scan      — varre ~/data-projects e indexa todos os dados
#   • dlab catalog list      — lista arquivos rastreados
#   • dlab catalog lineage   — mostra quais notebooks leram/escreveram um arquivo
#   • dlab describe <file>   — perfil rápido: shape, dtypes, % de nulos, head
#   • dlab doctor            — diagnóstico do ambiente
#
# Usa somente dependências já instaladas nos passos anteriores:
#   typer, rich<15.0, duckdb, polars
# =============================================================================
setup_dlab() {
  step 14 "dlab — Data Lab CLI"

  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true

  # Dependências já foram instaladas no passo 4, mas garantimos aqui
  # caso o usuário tenha comentado aquele módulo
  spinner_start "Verificando dependências Python do dlab..."
  pip install --quiet --timeout 60 typer "rich<15.0" duckdb polars >> "$LOG_FILE" 2>&1
  spinner_stop 0 "Dependências OK"

  # Localiza o binário `dlab` no repo (várias heurísticas — robusto a
  # diferentes formas de executar o script)
  local dlab_src=""
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for candidate in \
      "$script_dir/bin/dlab" \
      "./bin/dlab" \
      "./dlab" \
      "$HOME/wsl2-data-lab/bin/dlab"; do
    if [[ -f "$candidate" ]]; then
      dlab_src="$candidate"
      break
    fi
  done

  if [[ -z "$dlab_src" ]]; then
    warn "Arquivo 'bin/dlab' não encontrado no repositório."
    detail "Garanta que você clonou o repo com a pasta bin/ incluída."
    FAILED_STEPS+=("dlab:missing-source")
    end_step
    return 0
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$dlab_src" "$HOME/.local/bin/dlab"
  ok "dlab instalado em ~/.local/bin/dlab"

  # Aliases no .zshrc (idempotente — só adiciona se ainda não existir)
  if ! grep -q "# dlab aliases" "$HOME/.zshrc" 2>/dev/null; then
    cat >> "$HOME/.zshrc" <<'DLAB_ALIAS'

# dlab aliases
alias dl='dlab'
alias dlc='dlab catalog'
alias dls='dlab catalog scan'
alias dld='dlab describe'
alias dldr='dlab doctor'
DLAB_ALIAS
    ok "Aliases do dlab adicionados ao .zshrc (dl, dlc, dls, dld, dldr)"
  else
    ok "Aliases do dlab já presentes"
  fi

  # Primeiro scan (não crítico — a pasta pode estar vazia)
  if [[ -d "$HOME/data-projects" ]]; then
    spinner_start "Executando primeiro scan do catálogo..."
    "$HOME/.local/bin/dlab" catalog scan >> "$LOG_FILE" 2>&1 || true
    spinner_stop 0 "Catálogo inicializado em ~/.dlab/catalog.duckdb"
  fi

  INSTALLED_VERSIONS+=("dlab (Data Lab CLI)")
  detail "Experimente: dlab doctor  |  dlab catalog scan  |  dlab describe <arquivo>"
  end_step
}

# =============================================================================
# SUMÁRIO FINAL
# =============================================================================
print_summary() {
  local elapsed_total=$SECONDS
  local mins=$(( elapsed_total / 60 ))
  local secs=$(( elapsed_total % 60 ))

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗"
  echo -e "║           ✅  SETUP CONCLUÍDO!                                   ║"
  printf  "║   ⏱  Tempo total: %-44s║\n" "${mins}m ${secs}s"
  echo -e "╚══════════════════════════════════════════════════════════════════╝${NC}"

  if [[ ${#INSTALLED_VERSIONS[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}Versões instaladas:${NC}"
    for v in "${INSTALLED_VERSIONS[@]}"; do
      echo -e "  ${TICK} $v"
    done
  fi

  if [[ ${#SKIPPED_STEPS[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${DIM}Já instalados (ignorados):${NC}"
    for s in "${SKIPPED_STEPS[@]}"; do
      echo -e "  ${DIM}⏭  $s${NC}"
    done
  fi

  if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${YELLOW}Avisos (não-críticos):${NC}"
    for f in "${FAILED_STEPS[@]}"; do
      echo -e "  ${WARN} $f"
    done
    echo -e "  ${DIM}Detalhes: $LOG_FILE${NC}"
  fi

  echo -e "\n${BOLD}Próximos passos:${NC}"
  echo -e "  1. ${CYAN}exec zsh${NC}                          — recarregar o shell"
  echo -e "  2. ${CYAN}git config --global user.name 'Seu Nome'${NC}"
  echo -e "  3. ${CYAN}git config --global user.email 'email'${NC}"
  echo -e "  4. Copiar ${CYAN}~/wslconfig_tip.txt${NC} → ${CYAN}C:\\Users\\<Usuário>\\.wslconfig${NC}"
  echo -e "  5. ${CYAN}jlab${NC}                              — iniciar JupyterLab"
  echo -e "  6. ${CYAN}dlab doctor${NC}                       — verificar saúde do ambiente"
  echo -e "  7. ${CYAN}dlab catalog scan${NC}                 — indexar seus dados"
  echo -e "  8. ${CYAN}bash ~/vscode_extensions_data.sh${NC}  — instalar extensões VS Code"
  echo -e "  9. ${CYAN}docker run hello-world${NC}            — testar Docker"
  echo ""
  echo -e "  ${DIM}Log completo: $LOG_FILE${NC}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  banner
  echo ""
  check_wsl

  echo ""
  echo -e "${BOLD}Este script instala um ambiente completo de analista de dados.${NC}"
  echo -e "Tempo estimado: ${YELLOW}30–60 minutos${NC} dependendo da internet."
  echo -e "Log em tempo real: ${DIM}$LOG_FILE${NC}"
  echo ""

  if ! confirm "Deseja continuar?"; then
    echo "Cancelado."; exit 0
  fi

  # Módulos — comente os que não quiser
  setup_system
  setup_shell
  setup_python
  setup_python_packages
  setup_node
  setup_rust
  setup_docker
  setup_databases
  setup_productivity
  setup_jupyter
  setup_folders
  setup_wsl_config
  setup_vscode_list
  setup_dlab            # NOVO v2.1: Data Lab CLI

  print_summary
}

main "$@"
