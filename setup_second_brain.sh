#!/usr/bin/env bash
# =============================================================================
# WSL2 Second Brain Setup — Módulo 14
# Autor: Germano Silva | 2026
#
# Complementa o setup_wsl2_analista.sh com:
#   - Estrutura do vault Obsidian
#   - OpenRouter (API key + aliases + script de chat)
#   - CLAUDE.md e contexto para agentes
#   - Workflow diário automatizado
#   - Integração com ~/data-projects (já criado pelo módulo 11)
#
# USO:
#   bash setup_second_brain.sh
#   bash setup_second_brain.sh --openrouter-key sk-or-xxxx
# =============================================================================

set -uo pipefail

# ── Cores (mesmo padrão do setup_wsl2_analista.sh) ───────────────────────────
RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';  CYAN='\033[0;36m';  MAGENTA='\033[0;35m'
BOLD='\033[1m';     DIM='\033[2m';       NC='\033[0m'
TICK="${GREEN}✔${NC}"; CROSS="${RED}✘${NC}"; WARN="${YELLOW}⚠${NC}"

# ── Estado global ─────────────────────────────────────────────────────────────
FAILED_STEPS=()
SKIPPED_STEPS=()
INSTALLED_ITEMS=()
LOG_FILE="$HOME/.second_brain_setup_$(date +%Y%m%d_%H%M%S).log"
STEP_TIMER=0

VAULT="$HOME/Docs/vault"
SCRIPTS_DIR="$HOME/Dev/scripts"
CONFIG_DIR="$HOME/.config/second-brain"

# ── Parse args ───────────────────────────────────────────────────────────────
OR_KEY=""
for arg in "$@"; do
  case "$arg" in
    --openrouter-key=*) OR_KEY="${arg#*=}" ;;
    --openrouter-key)   shift; OR_KEY="${1:-}" ;;
  esac
done

# ── Helpers (mesmo padrão visual do script principal) ────────────────────────
_log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info()   { echo -e "  ${CYAN}[INFO]${NC}  $*"; _log "INFO  $*"; }
ok()     { echo -e "  ${TICK} ${GREEN}$*${NC}"; _log "OK    $*"; }
warn()   { echo -e "  ${WARN} ${YELLOW}$*${NC}"; _log "WARN  $*"; }
err()    { echo -e "  ${CROSS} ${RED}$*${NC}"; _log "ERROR $*"; }
detail() { echo -e "    ${DIM}$*${NC}"; _log "      $*"; }

step() {
  local num="$1"; shift
  echo ""
  echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────────────────────────────┐${NC}"
  printf "${BOLD}${BLUE}│${NC} ${BOLD}%s. %-61s${BLUE}│${NC}\n" "$num" "$*"
  echo -e "${BOLD}${BLUE}└─────────────────────────────────────────────────────────────────┘${NC}"
  STEP_TIMER=$SECONDS
  _log "=== STEP $num: $* ==="
}

end_step() {
  local elapsed=$(( SECONDS - STEP_TIMER ))
  echo -e "  ${DIM}⏱  Concluído em ${elapsed}s${NC}"
}

SPINNER_PID=""
spinner_start() {
  local msg="${1:-Aguarde...}"
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  ( i=0
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
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  printf "\r%-70s\r" " "
  [[ "${1:-0}" == "0" ]] && ok "$2" || warn "$2"
}

confirm() {
  echo -e "${YELLOW}$1${NC}"
  read -rp "  [s/N]: " ans
  [[ "${ans,,}" == "s" ]]
}

banner() {
  echo -e "${BOLD}${MAGENTA}"
  cat << 'EOF'
  ███████╗███████╗ ██████╗██╗   ██╗███╗   ██╗██████╗
  ██╔════╝██╔════╝██╔════╝██║   ██║████╗  ██║██╔══██╗
  ███████╗█████╗  ██║     ██║   ██║██╔██╗ ██║██║  ██║
  ╚════██║██╔══╝  ██║     ██║   ██║██║╚██╗██║██║  ██║
  ███████║███████╗╚██████╗╚██████╔╝██║ ╚████║██████╔╝
  ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝
  ██████╗ ██████╗  █████╗ ██╗███╗   ██╗
  ██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║
  ██████╔╝██████╔╝███████║██║██╔██╗ ██║
  ██╔══██╗██╔══██╗██╔══██║██║██║╚██╗██║
  ██████╔╝██║  ██║██║  ██║██║██║ ╚████║
  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝
EOF
  echo -e "${NC}  ${BOLD}Módulo 14 — Second Brain + OpenRouter${NC}  ${DIM}[complemento do wsl2-data-lab]${NC}"
  echo -e "  ${DIM}Log em: $LOG_FILE${NC}"
}

# =============================================================================
# 14.1 — VERIFICAÇÕES PRÉ-REQUISITOS
# =============================================================================
check_requirements() {
  step "14.1" "Verificando pré-requisitos"

  # Verifica se o setup_wsl2_analista.sh já correu (módulo 11 cria ~/data-projects)
  if [ -d "$HOME/data-projects" ]; then
    ok "wsl2-data-lab detectado (~/data-projects existe)"
  else
    warn "~/data-projects não encontrado — o setup_wsl2_analista.sh foi executado?"
    warn "Continuando mesmo assim. Algumas integrações podem não funcionar."
  fi

  # Python
  if command -v python3 &>/dev/null; then
    ok "Python $(python3 --version 2>&1 | awk '{print $2}')"
  else
    err "Python3 não encontrado. Execute setup_wsl2_analista.sh primeiro."
    exit 1
  fi

  # jq (para parse de JSON da API)
  if ! command -v jq &>/dev/null; then
    spinner_start "Instalando jq..."
    sudo apt-get install -y -qq jq >> "$LOG_FILE" 2>&1
    spinner_stop 0 "jq instalado"
  else
    ok "jq já disponível"
  fi

  # curl
  if command -v curl &>/dev/null; then
    ok "curl disponível"
  else
    err "curl não encontrado."
    exit 1
  fi

  # Verifica internet
  spinner_start "Verificando acesso ao OpenRouter..."
  if curl -fsSL --connect-timeout 5 https://openrouter.ai > /dev/null 2>&1; then
    spinner_stop 0 "OpenRouter acessível"
  else
    spinner_stop 1 "Sem acesso ao OpenRouter (verifica a ligação)"
  fi

  end_step
}

# =============================================================================
# 14.2 — ESTRUTURA DE PASTAS
# =============================================================================
setup_folders() {
  step "14.2" "Criando estrutura do vault e pastas de suporte"

  # Vault do Obsidian
  local folders=(
    "$VAULT/00-inbox"
    "$VAULT/10-projects"
    "$VAULT/20-areas/dados"
    "$VAULT/20-areas/aprendizagem"
    "$VAULT/20-areas/pessoal"
    "$VAULT/30-resources/python"
    "$VAULT/30-resources/sql"
    "$VAULT/30-resources/ferramentas"
    "$VAULT/40-archive"
    "$VAULT/daily"
    "$VAULT/templates"
    "$VAULT/.attachments"
  )

  local total=${#folders[@]}
  for i in "${!folders[@]}"; do
    local folder="${folders[$i]}"
    printf "\r  ${CYAN}⠋${NC}  ${DIM}Criando pastas... (%d/%d)${NC}   " "$(( i+1 ))" "$total"
    mkdir -p "$folder"
  done
  printf "\r%-70s\r" " "
  ok "${total} pastas do vault criadas em $VAULT"

  # Pastas de suporte (Dev já criado pelo módulo 11 do script principal)
  mkdir -p "$SCRIPTS_DIR"
  mkdir -p "$CONFIG_DIR"
  ok "Pastas de suporte criadas"

  # Integração com data-projects (link simbólico para acesso rápido do vault)
  if [ -d "$HOME/data-projects" ] && [ ! -L "$HOME/data-projects/vault-link" ]; then
    ln -sf "$VAULT" "$HOME/data-projects/vault-link"
    ok "Link simbólico criado: ~/data-projects/vault-link → vault"
  fi

  end_step
}

# =============================================================================
# 14.3 — CONTEÚDO BASE DO VAULT
# =============================================================================
setup_vault_content() {
  step "14.3" "Populando vault com estrutura base"

  # README do vault
  cat > "$VAULT/README.md" << 'EOF'
# Vault do Germano

Segundo cérebro pessoal — notas, projectos, recursos e arquivo.

## Estrutura

| Pasta | Para quê |
|---|---|
| `00-inbox/` | Tudo que entra — processar 1x por semana |
| `10-projects/` | Projectos activos (GitHub e pessoais) |
| `20-areas/` | Responsabilidades contínuas (dados, aprendizagem, pessoal) |
| `30-resources/` | Referências técnicas e artigos |
| `40-archive/` | Material inactivo mas preservado |
| `daily/` | Notas diárias |
| `templates/` | Templates reutilizáveis |

## Agentes disponíveis

```bash
orchat "pergunta"              # Chat geral (modelo automático gratuito)
orchat --vault "pergunta"      # Com contexto do vault
orcode "pergunta"              # Qwen3 Coder — para código
orthink "pergunta"             # DeepSeek R1 — para raciocínio
orday                          # Abre/cria nota do dia
```

## Modelos gratuitos (OpenRouter)

- `openrouter/auto` — selecciona automaticamente o melhor
- `deepseek/deepseek-r1:free` — raciocínio e análise
- `deepseek/deepseek-chat-v3-0324:free` — uso geral
- `meta-llama/llama-4-maverick:free` — contexto longo (1M tokens)
- `qwen/qwen3-235b-a22b:free` — geral, seguimento de instruções
- `qwen/qwen3-coder-480b-a35b:free` — código e scripts

Limite gratuito: **200 pedidos/dia · 20/minuto**
EOF
  ok "README.md do vault criado"

  # README do inbox
  cat > "$VAULT/00-inbox/README.md" << 'EOF'
# Inbox

Tudo que entra vai aqui primeiro. Processar uma vez por semana.

## Como processar

1. Lê a nota
2. Decide: é um projecto, área ou recurso?
3. Move para a pasta certa
4. Elimina daqui

## Regra

Se depois de 2 semanas ainda não moveste — apaga ou arquiva.
EOF

  # Template de nota diária
  cat > "$VAULT/templates/daily.md" << 'EOF'
# {{date}}

## 🎯 Foco do dia
-

## 📊 Dados / Análise
-

## 💻 Código
-

## 📝 Notas soltas
-

## ✅ Feito hoje
-

## 🔗 Notas criadas hoje
-

## 💭 Para amanhã
-

---
*Gerado por: `orday`*
EOF

  # Template de nota de projecto
  cat > "$VAULT/templates/project.md" << 'EOF'
# {{project_name}}

**Status:** activo
**Repositório:** [[link-github]]
**Criado:** {{date}}

## Objectivo

## Stack

## Notas de progresso

### {{date}}
-

## Próximos passos
- [ ]

## Links relacionados
-
EOF

  # Template de recurso/referência
  cat > "$VAULT/templates/resource.md" << 'EOF'
# {{title}}

**Fonte:** 
**Tags:** #recurso
**Data:** {{date}}

## Resumo

## Pontos-chave
-

## Aplicação prática

## Links
-
EOF

  # CLAUDE.md — contexto para agentes (Claude Code, OpenRouter)
  cat > "$VAULT/CLAUDE.md" << 'EOF'
# Germano's Second Brain — Contexto para Agentes

## Quem sou

Germano Silva — analista/engenheiro de dados. Trabalho com Python, SQL, dbt,
JupyterLab, PostgreSQL, DuckDB, Docker. Os meus projectos estão no GitHub
e no WSL2 em ~/Dev/projects/.

## Este vault

Segundo cérebro em Markdown. Estrutura PARA (Projects, Areas, Resources, Archive).

```
00-inbox/     → notas novas, ainda não organizadas
10-projects/  → projectos GitHub e pessoais activos
20-areas/     → dados, aprendizagem, pessoal
30-resources/ → referências técnicas (Python, SQL, ferramentas)
40-archive/   → material inactivo
daily/        → notas diárias (YYYY-MM-DD.md)
templates/    → templates reutilizáveis
```

## Sessão de abertura

Ao iniciar uma sessão, lê (se existirem):
1. `daily/$(date +%Y-%m-%d).md` — nota de hoje
2. `00-inbox/` — o que está por processar
3. `10-projects/` — projectos activos

## Sessão de fecho

Ao terminar, actualiza:
1. `daily/$(date +%Y-%m-%d).md` com resumo da sessão
2. Ficheiros de projecto relevantes modificados

## Integração com data-projects

Os notebooks e scripts de dados estão em ~/data-projects/.
O vault tem um link simbólico: ~/data-projects/vault-link → este vault.

## Idioma

Responde sempre em português europeu.

## Formato das notas

- Markdown puro
- Links entre notas: [[nome-da-nota]]
- Tags: #tag no fim do ficheiro
- Datas: YYYY-MM-DD
EOF
  ok "CLAUDE.md criado no vault"

  # GEMINI.md (para Gemini CLI, se usado no futuro)
  cp "$VAULT/CLAUDE.md" "$VAULT/GEMINI.md"
  sed -i 's/CLAUDE.md/GEMINI.md/' "$VAULT/GEMINI.md"
  ok "GEMINI.md criado (cópia do CLAUDE.md)"

  # Nota de hoje como ponto de partida
  local today
  today=$(date +%Y-%m-%d)
  if [ ! -f "$VAULT/daily/${today}.md" ]; then
    cat > "$VAULT/daily/${today}.md" << EOF
# ${today}

## 🎯 Foco do dia
- Configurar o segundo cérebro no WSL2

## 📝 Notas
- Vault criado com setup_second_brain.sh
- OpenRouter configurado como LLM principal

## ✅ Feito hoje
- [ ] Instalar e configurar vault
- [ ] Testar orchat, orcode, orthink
- [ ] Abrir vault no Obsidian (Windows)

## 💭 Para amanhã
-
EOF
    ok "Nota de hoje criada: daily/${today}.md"
  fi

  end_step
}

# =============================================================================
# 14.4 — OPENROUTER: API KEY E CONFIGURAÇÃO
# =============================================================================
setup_openrouter() {
  step "14.4" "Configurando OpenRouter"

  mkdir -p "$CONFIG_DIR"

  # Pede a key se não foi passada como argumento
  if [ -z "$OR_KEY" ]; then
    # Verifica se já existe configurada
    if [ -f "$CONFIG_DIR/env" ] && grep -q "OPENROUTER_API_KEY=sk-or-" "$CONFIG_DIR/env" 2>/dev/null; then
      ok "API key já configurada em $CONFIG_DIR/env"
      SKIPPED_STEPS+=("openrouter-key")
      source "$CONFIG_DIR/env"
    else
      echo ""
      echo -e "  ${CYAN}Precisas da tua API key do OpenRouter.${NC}"
      echo -e "  ${DIM}Encontra em: https://openrouter.ai/keys${NC}"
      echo ""
      read -rp "  Cola aqui a tua OpenRouter API key (sk-or-...): " OR_KEY
      echo ""
    fi
  fi

  # Guarda a key
  if [ -n "$OR_KEY" ]; then
    cat > "$CONFIG_DIR/env" << EOF
# OpenRouter — gerado por setup_second_brain.sh
# NÃO commitar este ficheiro!
export OPENROUTER_API_KEY="${OR_KEY}"
EOF
    chmod 600 "$CONFIG_DIR/env"
    ok "API key guardada em $CONFIG_DIR/env (chmod 600)"

    # Adiciona ao .bashrc e .zshrc se ainda não estiver
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      if [ -f "$rc" ] && ! grep -q "second-brain/env" "$rc"; then
        cat >> "$rc" << 'EOF'

# Second Brain — OpenRouter
[ -f "$HOME/.config/second-brain/env" ] && source "$HOME/.config/second-brain/env"
EOF
        ok "Adicionado source ao $(basename $rc)"
      fi
    done

    source "$CONFIG_DIR/env"
    INSTALLED_ITEMS+=("OpenRouter API key configurada")
  fi

  # Adiciona .gitignore para nunca commitar a key
  cat >> "$HOME/.gitignore_global" << 'EOF'

# Second Brain — nunca commitar
.config/second-brain/env
OPENROUTER_API_KEY
EOF
  ok ".gitignore_global actualizado (key nunca será commitada)"

  # Testa a ligação
  if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    spinner_start "Testando conexão com OpenRouter..."
    local response
    response=$(curl -s --max-time 15 \
      "https://openrouter.ai/api/v1/chat/completions" \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{"model":"openrouter/auto","messages":[{"role":"user","content":"Responde só com: OK"}],"max_tokens":5}' \
      2>> "$LOG_FILE")

    if echo "$response" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
      local reply
      reply=$(echo "$response" | jq -r '.choices[0].message.content')
      spinner_stop 0 "OpenRouter OK — resposta: \"${reply}\""
    else
      spinner_stop 1 "Teste falhou (verifica a API key e o saldo)"
      FAILED_STEPS+=("openrouter-test")
      _log "Resposta: $response"
    fi
  fi

  end_step
}

# =============================================================================
# 14.5 — SCRIPT DE CHAT (vault-chat.py)
# =============================================================================
setup_chat_script() {
  step "14.5" "Criando script de chat com OpenRouter"

  mkdir -p "$SCRIPTS_DIR"

  cat > "$SCRIPTS_DIR/vault-chat.py" << 'PYEOF'
#!/usr/bin/env python3
"""
vault-chat.py — Chat com OpenRouter usando o vault como contexto opcional.

Uso:
  python3 vault-chat.py "pergunta"
  python3 vault-chat.py --vault "o que tenho em aberto?"
  python3 vault-chat.py --model deepseek/deepseek-r1:free "analisa isto"
  python3 vault-chat.py --model qwen/qwen3-coder-480b-a35b:free "cria um script"
  python3 vault-chat.py --models   # lista modelos gratuitos
"""

import os, sys, json, argparse
from pathlib import Path
from urllib import request, error

# ── Configuração ──────────────────────────────────────────────────────────────
API_KEY   = os.environ.get("OPENROUTER_API_KEY", "")
API_URL   = "https://openrouter.ai/api/v1/chat/completions"
VAULT     = Path.home() / "Docs/vault"
DATA_LAB  = Path.home() / "data-projects"

DEFAULT_MODEL  = "openrouter/auto"
CODING_MODEL   = "qwen/qwen3-coder-480b-a35b:free"
THINKING_MODEL = "deepseek/deepseek-r1:free"
CHAT_MODEL     = "meta-llama/llama-4-maverick:free"

FREE_MODELS = {
  "auto":     ("openrouter/auto",                    "Selecciona automaticamente o melhor gratuito"),
  "chat":     ("meta-llama/llama-4-maverick:free",   "Llama 4 Maverick — contexto 1M tokens"),
  "think":    ("deepseek/deepseek-r1:free",          "DeepSeek R1 — raciocínio e análise"),
  "code":     ("qwen/qwen3-coder-480b-a35b:free",   "Qwen3 Coder 480B — código e scripts"),
  "general":  ("qwen/qwen3-235b-a22b:free",          "Qwen3 235B — geral e instruções"),
  "deepseek": ("deepseek/deepseek-chat-v3-0324:free","DeepSeek Chat V3 — uso geral"),
}

def load_vault_context(max_notes: int = 12, max_chars: int = 600) -> str:
    """Carrega as notas mais recentes do vault como contexto."""
    if not VAULT.exists():
        return ""

    files = []
    for f in VAULT.rglob("*.md"):
        skip_patterns = [".trash", "CLAUDE.md", "GEMINI.md", "templates/"]
        if any(p in str(f) for p in skip_patterns):
            continue
        files.append(f)

    files.sort(key=lambda x: x.stat().st_mtime, reverse=True)

    context_parts = []
    # Nota de hoje tem prioridade
    today = __import__("datetime").date.today().isoformat()
    today_note = VAULT / "daily" / f"{today}.md"
    if today_note.exists():
        content = today_note.read_text(encoding="utf-8", errors="ignore")[:800]
        context_parts.append(f"## Nota de hoje ({today})\n{content}")
        files = [f for f in files if f != today_note]

    for f in files[:max_notes]:
        try:
            content = f.read_text(encoding="utf-8", errors="ignore")[:max_chars]
            rel = f.relative_to(VAULT)
            context_parts.append(f"## {rel}\n{content}")
        except Exception:
            pass

    return "\n\n---\n\n".join(context_parts)

def resolve_model(model_str: str) -> str:
    """Resolve alias curto para model ID completo."""
    if model_str in FREE_MODELS:
        return FREE_MODELS[model_str][0]
    return model_str

def chat(prompt: str, model: str = DEFAULT_MODEL, use_vault: bool = False,
         system_extra: str = "") -> str:
    if not API_KEY:
        print("❌ OPENROUTER_API_KEY não definida.")
        print("   Corre: source ~/.config/second-brain/env")
        sys.exit(1)

    model = resolve_model(model)
    messages = []

    system_parts = [
        "És o assistente pessoal do Germano Silva.",
        "Germano é analista/engenheiro de dados — usa Python, SQL, dbt, Docker, PostgreSQL, DuckDB.",
        "Responde sempre em português europeu, de forma directa e técnica.",
    ]

    if use_vault:
        ctx = load_vault_context()
        if ctx:
            system_parts.append(
                f"\nTens acesso ao vault de notas do Germano:\n\n{ctx}\n\n"
                "Usa este contexto para responder de forma personalizada."
            )
        else:
            system_parts.append("\n(Vault vazio ou não encontrado — responde sem contexto específico.)")

    if system_extra:
        system_parts.append(system_extra)

    messages.append({"role": "system", "content": "\n".join(system_parts)})
    messages.append({"role": "user", "content": prompt})

    payload = json.dumps({
        "model": model,
        "messages": messages,
        "max_tokens": 2048,
    }).encode()

    req = request.Request(
        API_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/Germano-Silva/wsl2-data-lab",
            "X-Title": "WSL2 Second Brain",
        }
    )

    try:
        with request.urlopen(req, timeout=60) as r:
            result = json.loads(r.read())
            if "choices" not in result:
                return f"❌ Resposta inesperada: {result}"
            return result["choices"][0]["message"]["content"]
    except error.HTTPError as e:
        body = e.read().decode(errors="ignore")
        return f"❌ HTTP {e.code}: {body}"
    except error.URLError as e:
        return f"❌ Erro de rede: {e.reason}"
    except Exception as e:
        return f"❌ Erro: {e}"

def list_models():
    print(f"\n{'Alias':<12} {'Model ID':<45} Descrição")
    print("─" * 90)
    for alias, (mid, desc) in FREE_MODELS.items():
        print(f"  {alias:<10} {mid:<45} {desc}")
    print("\nUso: orchat --model <alias ou model ID> \"pergunta\"\n")

def main():
    parser = argparse.ArgumentParser(
        description="Chat com OpenRouter + vault do Obsidian",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  orchat "resume o que tenho em aberto"
  orchat --vault "o que devo focar hoje?"
  orchat --model code "cria um script Python para limpar CSVs"
  orchat --model think "analisa os prós e contras de migrar para Polars"
  orchat --models
        """
    )
    parser.add_argument("prompt", nargs="?", help="Pergunta ou pedido")
    parser.add_argument("--model", "-m", default=DEFAULT_MODEL,
                        help="Modelo a usar (alias ou ID completo)")
    parser.add_argument("--vault", "-v", action="store_true",
                        help="Incluir contexto do vault na pergunta")
    parser.add_argument("--models", action="store_true",
                        help="Listar modelos gratuitos disponíveis")
    parser.add_argument("--system", "-s", default="",
                        help="Instrução extra para o system prompt")

    args = parser.parse_args()

    if args.models:
        list_models()
        sys.exit(0)

    if not args.prompt:
        parser.print_help()
        sys.exit(1)

    model_display = args.model if args.model not in FREE_MODELS else FREE_MODELS[args.model][0]
    if args.vault:
        print(f"  🔍 Vault: ligado  |  Modelo: {model_display}\n", file=sys.stderr)

    result = chat(args.prompt, args.model, args.vault, args.system)
    print(result)

if __name__ == "__main__":
    main()
PYEOF

  chmod +x "$SCRIPTS_DIR/vault-chat.py"
  ok "vault-chat.py criado em $SCRIPTS_DIR"

  # Script de nota diária
  cat > "$SCRIPTS_DIR/daily-note.sh" << 'DAILY'
#!/usr/bin/env bash
# daily-note.sh — Abre ou cria a nota do dia no vault
VAULT="$HOME/Docs/vault"
TODAY=$(date +%Y-%m-%d)
NOTE="$VAULT/daily/${TODAY}.md"

if [ ! -f "$NOTE" ]; then
  cat > "$NOTE" << EOF
# ${TODAY}

## 🎯 Foco do dia
-

## 📊 Dados / Análise
-

## 💻 Código
-

## 📝 Notas
-

## ✅ Feito hoje
-

## 💭 Para amanhã
-
EOF
  echo "✅ Nota criada: $NOTE"
fi

# Abre no editor disponível
if command -v code &>/dev/null; then
  code "$NOTE"
elif command -v nano &>/dev/null; then
  nano "$NOTE"
else
  echo "Nota: $NOTE"
  cat "$NOTE"
fi
DAILY

  chmod +x "$SCRIPTS_DIR/daily-note.sh"
  ok "daily-note.sh criado em $SCRIPTS_DIR"

  INSTALLED_ITEMS+=("vault-chat.py" "daily-note.sh")
  end_step
}

# =============================================================================
# 14.6 — ALIASES E INTEGRAÇÕES NO SHELL
# =============================================================================
setup_aliases() {
  step "14.6" "Configurando aliases no shell"

  local ALIAS_BLOCK
  ALIAS_BLOCK=$(cat << 'ALIASES'

# ── Second Brain + OpenRouter ──────────────────────────────────────────────
# Chat geral (modelo automático gratuito)
alias orchat='python3 ~/Dev/scripts/vault-chat.py'

# Com contexto do vault
alias orvault='python3 ~/Dev/scripts/vault-chat.py --vault'

# Para código — Qwen3 Coder 480B
alias orcode='python3 ~/Dev/scripts/vault-chat.py --model code'

# Para raciocínio — DeepSeek R1
alias orthink='python3 ~/Dev/scripts/vault-chat.py --model think'

# Para contexto longo — Llama 4 Maverick (1M tokens)
alias orchat-long='python3 ~/Dev/scripts/vault-chat.py --model chat'

# Nota do dia
alias orday='bash ~/Dev/scripts/daily-note.sh'

# Abrir vault no VS Code
alias orvs='code ~/Docs/vault'

# Listar modelos gratuitos
alias ormodels='python3 ~/Dev/scripts/vault-chat.py --models'

# Nota rápida no inbox
ornote() {
  local note="$HOME/Docs/vault/00-inbox/$(date +%s).md"
  echo "# $(date +%Y-%m-%d) — nota rápida" > "$note"
  echo "" >> "$note"
  echo "$*" >> "$note"
  echo "✅ Nota criada: $note"
}

# Resumo do dia com IA
orsummary() {
  local today
  today=$(date +%Y-%m-%d)
  local note="$HOME/Docs/vault/daily/${today}.md"
  if [ -f "$note" ]; then
    python3 ~/Dev/scripts/vault-chat.py --vault \
      "Com base na nota de hoje ($today) e no vault, faz um resumo do que foi feito e sugere prioridades para amanhã."
  else
    echo "Nota de hoje não encontrada. Corre: orday"
  fi
}
ALIASES
)

  # Adiciona aos ficheiros rc sem duplicar
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -q "Second Brain + OpenRouter" "$rc"; then
      echo "$ALIAS_BLOCK" >> "$rc"
      ok "Aliases adicionados ao $(basename $rc)"
    elif [ -f "$rc" ]; then
      ok "Aliases já presentes no $(basename $rc)"
      SKIPPED_STEPS+=("aliases-$(basename $rc)")
    fi
  done

  INSTALLED_ITEMS+=("orchat" "orcode" "orthink" "orday" "ornote" "orsummary")
  end_step
}

# =============================================================================
# 14.7 — INTEGRAÇÃO COM data-projects (módulo 11)
# =============================================================================
setup_datalab_integration() {
  step "14.7" "Integrando com o wsl2-data-lab (~/data-projects)"

  if [ ! -d "$HOME/data-projects" ]; then
    warn "~/data-projects não existe — a integração será parcial"
    end_step
    return
  fi

  # Notebook de análise com IA integrada
  cat > "$HOME/data-projects/notebooks/ai_assisted_analysis.ipynb" << 'NB'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# 🤖 Análise Assistida por IA\n\n",
    "Notebook para análise de dados com OpenRouter como assistente.\n\n",
    "**Pré-requisito:** `OPENROUTER_API_KEY` definida no ambiente.\n"
   ]
  },
  {
   "cell_type": "code",
   "metadata": {},
   "source": [
    "import os, json, subprocess\n",
    "import pandas as pd\n",
    "import numpy as np\n",
    "from urllib import request\n",
    "\n",
    "API_KEY = os.environ.get('OPENROUTER_API_KEY', '')\n",
    "if not API_KEY:\n",
    "    print('⚠️  OPENROUTER_API_KEY não definida.')\n",
    "    print('   No terminal: source ~/.config/second-brain/env')\n",
    "else:\n",
    "    print('✅ API key carregada')"
   ],
   "outputs": [],
   "execution_count": null
  },
  {
   "cell_type": "code",
   "metadata": {},
   "source": [
    "def ask_ai(prompt: str, model: str = 'openrouter/auto', context_df=None) -> str:\n",
    "    \"\"\"Faz uma pergunta ao OpenRouter, opcionalmente com contexto de um DataFrame.\"\"\"\n",
    "    full_prompt = prompt\n",
    "    if context_df is not None:\n",
    "        summary = f'Shape: {context_df.shape}\\nColunas: {list(context_df.columns)}\\n'\n",
    "        summary += f'Tipos:\\n{context_df.dtypes.to_string()}\\n'\n",
    "        summary += f'Primeiras 3 linhas:\\n{context_df.head(3).to_string()}'\n",
    "        full_prompt = f'{prompt}\\n\\nContexto do DataFrame:\\n{summary}'\n",
    "    \n",
    "    payload = json.dumps({\n",
    "        'model': model,\n",
    "        'messages': [\n",
    "            {'role': 'system', 'content': 'És um especialista em análise de dados. Responde em português europeu.'},\n",
    "            {'role': 'user', 'content': full_prompt}\n",
    "        ],\n",
    "        'max_tokens': 1024\n",
    "    }).encode()\n",
    "    \n",
    "    req = request.Request(\n",
    "        'https://openrouter.ai/api/v1/chat/completions',\n",
    "        data=payload,\n",
    "        headers={'Authorization': f'Bearer {API_KEY}', 'Content-Type': 'application/json'}\n",
    "    )\n",
    "    with request.urlopen(req, timeout=30) as r:\n",
    "        return json.loads(r.read())['choices'][0]['message']['content']\n",
    "\n",
    "print('✅ Função ask_ai() pronta')"
   ],
   "outputs": [],
   "execution_count": null
  },
  {
   "cell_type": "code",
   "metadata": {},
   "source": [
    "# Exemplo: carregar dados e pedir análise à IA\n",
    "# df = pd.read_csv('data/raw/meus_dados.csv')\n",
    "# resposta = ask_ai('Que análises exploratórias devo fazer neste dataset?', context_df=df)\n",
    "# print(resposta)\n",
    "\n",
    "# Teste simples\n",
    "if API_KEY:\n",
    "    r = ask_ai('Em duas frases: qual é a diferença entre pandas e polars?')\n",
    "    print(r)"
   ],
   "outputs": [],
   "execution_count": null
  }
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python 3 (pyenv)", "language": "python", "name": "python3"},
  "language_info": {"name": "python", "version": "3.12.3"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
NB
  ok "Notebook ai_assisted_analysis.ipynb criado em ~/data-projects/notebooks/"

  # Script de sincronização vault → Google Drive (opcional)
  cat > "$SCRIPTS_DIR/sync-vault.sh" << 'SYNC'
#!/usr/bin/env bash
# sync-vault.sh — Copia o vault para uma pasta acessível no Windows
# (para usar com NotebookLM / Google Drive)
VAULT="$HOME/Docs/vault"
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "devel")
WIN_EXPORT="/mnt/c/Users/${WIN_USER}/Documents/vault-export"

echo "📦 Sincronizando vault → $WIN_EXPORT"
mkdir -p "$WIN_EXPORT"
rsync -av --delete \
  --exclude=".trash/" \
  --exclude=".obsidian/" \
  --exclude=".attachments/" \
  "$VAULT/" "$WIN_EXPORT/" \
  && echo "✅ Vault sincronizado com sucesso" \
  || echo "❌ Erro na sincronização"

echo ""
echo "Abre o NotebookLM e importa a pasta:"
echo "  C:\\Users\\${WIN_USER}\\Documents\\vault-export"
SYNC

  chmod +x "$SCRIPTS_DIR/sync-vault.sh"
  ok "sync-vault.sh criado (para NotebookLM / Google Drive)"

  end_step
}

# =============================================================================
# 14.8 — TESTE FINAL
# =============================================================================
run_smoke_tests() {
  step "14.8" "Smoke tests"

  echo ""
  local pass=0
  local fail=0

  # Teste 1: vault existe
  if [ -d "$VAULT" ]; then
    detail "Vault existe em $VAULT  ${TICK}"
    (( pass++ )) || true
  else
    detail "Vault não encontrado  ${CROSS}"
    (( fail++ )) || true
    FAILED_STEPS+=("smoke:vault")
  fi

  # Teste 2: CLAUDE.md existe
  if [ -f "$VAULT/CLAUDE.md" ]; then
    detail "CLAUDE.md presente  ${TICK}"
    (( pass++ )) || true
  else
    detail "CLAUDE.md ausente  ${CROSS}"
    (( fail++ )) || true
    FAILED_STEPS+=("smoke:claude-md")
  fi

  # Teste 3: vault-chat.py executável
  if [ -x "$SCRIPTS_DIR/vault-chat.py" ]; then
    detail "vault-chat.py executável  ${TICK}"
    (( pass++ )) || true
  else
    detail "vault-chat.py não encontrado  ${CROSS}"
    (( fail++ )) || true
    FAILED_STEPS+=("smoke:vault-chat")
  fi

  # Teste 4: API key carregada
  source "$CONFIG_DIR/env" 2>/dev/null || true
  if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    detail "OPENROUTER_API_KEY carregada  ${TICK}"
    (( pass++ )) || true
  else
    detail "OPENROUTER_API_KEY não carregada  ${WARN}"
    warn "Corre: source ~/.config/second-brain/env"
    (( fail++ )) || true
    FAILED_STEPS+=("smoke:api-key")
  fi

  # Teste 5: Python importa urllib (necessário para vault-chat.py)
  if python3 -c "from urllib import request; import json, pathlib" 2>/dev/null; then
    detail "Dependências Python OK  ${TICK}"
    (( pass++ )) || true
  else
    detail "Dependências Python em falta  ${CROSS}"
    (( fail++ )) || true
    FAILED_STEPS+=("smoke:python-deps")
  fi

  echo ""
  if [[ $fail -eq 0 ]]; then
    ok "Todos os testes passaram ($pass/$pass)"
  else
    warn "$pass passaram | $fail falharam"
  fi

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
  echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════════╗"
  echo -e "║        🧠  SECOND BRAIN CONFIGURADO!                            ║"
  printf  "║   ⏱  Tempo total: %-44s║\n" "${mins}m ${secs}s"
  echo -e "╚══════════════════════════════════════════════════════════════════╝${NC}"

  if [[ ${#INSTALLED_ITEMS[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}Instalado:${NC}"
    for item in "${INSTALLED_ITEMS[@]}"; do
      echo -e "  ${TICK} $item"
    done
  fi

  if [[ ${#SKIPPED_STEPS[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${DIM}Ignorados (já existiam):${NC}"
    for s in "${SKIPPED_STEPS[@]}"; do
      echo -e "  ${DIM}⏭  $s${NC}"
    done
  fi

  if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${YELLOW}Avisos:${NC}"
    for f in "${FAILED_STEPS[@]}"; do
      echo -e "  ${WARN} $f"
    done
  fi

  echo -e "\n${BOLD}Próximos passos:${NC}"
  echo -e "  1. ${CYAN}source ~/.zshrc${NC}                        — recarregar aliases"
  echo -e "  2. ${CYAN}orchat \"olá, estás a funcionar?\"${NC}       — testar chat"
  echo -e "  3. ${CYAN}orchat --vault \"o que devo fazer hoje?\"${NC} — testar com vault"
  echo -e "  4. ${CYAN}orcode \"cria um script para ler CSVs\"${NC}   — testar código"
  echo -e "  5. ${CYAN}orday${NC}                                   — abrir nota de hoje"
  echo -e "  6. ${CYAN}ormodels${NC}                                — listar modelos gratuitos"

  echo -e "\n${BOLD}Abrir o vault no Obsidian (Windows):${NC}"
  local WIN_USER
  WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "devel")
  echo -e "  ${DIM}Caminho: \\\\\\\\wsl\$\\\\Ubuntu-24.04\\\\home\\\\${WIN_USER}\\\\Docs\\\\vault${NC}"

  echo -e "\n${BOLD}Sincronizar vault para NotebookLM:${NC}"
  echo -e "  ${CYAN}bash ~/Dev/scripts/sync-vault.sh${NC}"

  echo -e "\n  ${DIM}Log completo: $LOG_FILE${NC}"
  echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  banner
  echo ""

  echo -e "${BOLD}Este script configura o Segundo Cérebro como complemento do wsl2-data-lab.${NC}"
  echo -e "Não altera nada do que já foi instalado pelo ${CYAN}setup_wsl2_analista.sh${NC}."
  echo ""

  if ! confirm "Deseja continuar?"; then
    echo "Cancelado."; exit 0
  fi

  check_requirements
  setup_folders
  setup_vault_content
  setup_openrouter
  setup_chat_script
  setup_aliases
  setup_datalab_integration
  run_smoke_tests

  print_summary
}

main "$@"
