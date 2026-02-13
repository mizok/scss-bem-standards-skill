#!/bin/bash

# SCSS BEM Standards Skill Installer
# Compatible with Claude Code, Codex CLI, Gemini CLI, and Antigravity

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "${HOME:-}" ]; then
  HOME="$(cd ~ && pwd)"
fi

SKILL_NAME="angular-scss-bem-standards"
REPO_URL="https://github.com/mizok/angular-scss-bem-standards-skill.git"

TARGET_AGENT=""
AUTO_YES="false"
INSTALL_SCOPE="global"
PROJECT_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  install.sh [--agent claude|codex|gemini|antigravity] [--scope global|project] [--project-root <path>] [--yes]

Options:
  --agent <name>        Install for a specific agent only
  --scope <scope>       Installation scope: global (default) or project
  --project-root <path> Project root when --scope project (default: current directory)
  --yes                 Auto-update when already installed
  -h, --help            Show help
EOF
}

is_valid_agent() {
  case "$1" in
    claude|codex|gemini|antigravity) return 0 ;;
    *) return 1 ;;
  esac
}

is_valid_scope() {
  case "$1" in
    global|project) return 0 ;;
    *) return 1 ;;
  esac
}

skills_dir_for_agent() {
  local agent="$1"
  local scope="$2"
  local project_root="$3"

  if [ "$scope" = "project" ]; then
    case "$agent" in
      claude) echo "$project_root/.claude/skills" ;;
      codex) echo "$project_root/.agents/skills" ;;
      gemini) echo "$project_root/.gemini/skills" ;;
      antigravity) echo "$project_root/.gemini/antigravity/global_skills" ;;
      *) return 1 ;;
    esac
    return 0
  fi

  case "$agent" in
    claude) echo "$HOME/.claude/skills" ;;
    codex) echo "$HOME/.agents/skills" ;;
    gemini) echo "$HOME/.gemini/skills" ;;
    antigravity) echo "$HOME/.gemini/antigravity/global_skills" ;;
    *) return 1 ;;
  esac
}

agent_detected() {
  local agent="$1"

  if [ "$INSTALL_SCOPE" = "project" ]; then
    case "$agent" in
      claude) command -v claude >/dev/null 2>&1 || [ -d "$PROJECT_ROOT/.claude" ] ;;
      codex) command -v codex >/dev/null 2>&1 || [ -d "$PROJECT_ROOT/.codex" ] || [ -d "$PROJECT_ROOT/.agents" ] ;;
      gemini) command -v gemini >/dev/null 2>&1 || [ -d "$PROJECT_ROOT/.gemini" ] ;;
      antigravity) command -v antigravity >/dev/null 2>&1 || [ -d "$PROJECT_ROOT/.gemini/antigravity" ] ;;
      *) return 1 ;;
    esac
    return 0
  fi

  case "$agent" in
    claude) command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
    codex) command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ] || [ -d "$HOME/.agents" ] ;;
    gemini) command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
    antigravity) command -v antigravity >/dev/null 2>&1 || [ -d "$HOME/.gemini/antigravity" ] ;;
    *) return 1 ;;
  esac
}

sync_project_codex_alias() {
  local agent="$1"
  local legacy_skills_dir=""
  local legacy_link=""
  local relative_target="../../.agents/skills/$SKILL_NAME"

  if [ "$INSTALL_SCOPE" != "project" ] || [ "$agent" != "codex" ]; then
    return 0
  fi

  legacy_skills_dir="$PROJECT_ROOT/.agent/skills"
  legacy_link="$legacy_skills_dir/$SKILL_NAME"

  # Optional compatibility bridge for tools that still read <project>/.agent/skills.
  if [ ! -d "$legacy_skills_dir" ]; then
    return 0
  fi

  if [ -L "$legacy_link" ]; then
    if [ "$(readlink "$legacy_link")" = "$relative_target" ]; then
      return 0
    fi
    rm -f "$legacy_link"
  elif [ -e "$legacy_link" ]; then
    echo -e "${YELLOW}[codex] .agent alias exists and is not a symlink: $legacy_link${NC}"
    echo "[codex] Skipping .agent alias sync."
    return 0
  fi

  if ln -s "$relative_target" "$legacy_link"; then
    echo "[codex] Synced .agent alias: $legacy_link -> $relative_target"
  else
    echo -e "${YELLOW}[codex] Failed to sync .agent alias: $legacy_link${NC}"
  fi
}

install_or_update() {
  local agent="$1"
  local skills_dir="$2"
  local dest="$skills_dir/$SKILL_NAME"

  mkdir -p "$skills_dir"

  echo ""
  echo "[$agent] Install path: $dest"

  if [ -d "$dest/.git" ]; then
    local do_update="false"
    echo -e "${YELLOW}[$agent] Skill already installed${NC}"
    if [ "$AUTO_YES" = "true" ]; then
      do_update="true"
    else
      read -p "[$agent] Update to latest version? (y/N) " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        do_update="true"
      fi
    fi

    if [ "$do_update" = "true" ]; then
      echo "[$agent] Updating..."
      if ! (
        cd "$dest"
        git pull --ff-only
      ); then
        echo -e "${RED}[$agent] Update failed${NC}"
        return 1
      fi
      echo -e "${GREEN}[$agent] Updated successfully${NC}"
    else
      echo "[$agent] Skipped update."
    fi
    sync_project_codex_alias "$agent"
    return 0
  fi

  if [ -e "$dest" ]; then
    echo -e "${RED}[$agent] Path exists but is not a git checkout: $dest${NC}"
    echo "[$agent] Remove or rename this path, then rerun installer."
    return 1
  fi

  echo "[$agent] Installing..."
  if ! git clone "$REPO_URL" "$dest"; then
    echo -e "${RED}[$agent] Install failed${NC}"
    return 1
  fi
  echo -e "${GREEN}[$agent] Installed successfully${NC}"
  sync_project_codex_alias "$agent"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agent)
      if [ $# -lt 2 ]; then
        echo -e "${RED}Missing value for --agent${NC}"
        usage
        exit 1
      fi
      TARGET_AGENT="$2"
      if ! is_valid_agent "$TARGET_AGENT"; then
        echo -e "${RED}Unsupported agent: $TARGET_AGENT${NC}"
        usage
        exit 1
      fi
      shift 2
      ;;
    --scope)
      if [ $# -lt 2 ]; then
        echo -e "${RED}Missing value for --scope${NC}"
        usage
        exit 1
      fi
      INSTALL_SCOPE="$2"
      if ! is_valid_scope "$INSTALL_SCOPE"; then
        echo -e "${RED}Unsupported scope: $INSTALL_SCOPE${NC}"
        usage
        exit 1
      fi
      shift 2
      ;;
    --project-root)
      if [ $# -lt 2 ]; then
        echo -e "${RED}Missing value for --project-root${NC}"
        usage
        exit 1
      fi
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --yes)
      AUTO_YES="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown argument: $1${NC}"
      usage
      exit 1
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo -e "${RED}Error: git is not installed${NC}"
  echo "Please install git and try again."
  exit 1
fi

if [ "$INSTALL_SCOPE" = "project" ]; then
  if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$PWD"
  fi

  if [ ! -d "$PROJECT_ROOT" ]; then
    echo -e "${RED}Project root does not exist: $PROJECT_ROOT${NC}"
    exit 1
  fi

  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Angular SCSS BEM Standards Skill Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scope: $INSTALL_SCOPE"
if [ "$INSTALL_SCOPE" = "project" ]; then
  echo "Project root: $PROJECT_ROOT"
fi

AGENTS=()
if [ -n "$TARGET_AGENT" ]; then
  AGENTS+=("$TARGET_AGENT")
else
  for candidate in claude codex gemini antigravity; do
    if agent_detected "$candidate"; then
      AGENTS+=("$candidate")
    fi
  done
fi

if [ "${#AGENTS[@]}" -eq 0 ]; then
  if [ "$INSTALL_SCOPE" = "project" ]; then
    echo -e "${YELLOW}No supported agent detected in project. Falling back to Codex project path.${NC}"
    AGENTS=("codex")
  else
    echo -e "${YELLOW}No supported agent detected. Falling back to Claude path.${NC}"
    AGENTS=("claude")
  fi
fi

echo ""
echo "Detected targets: ${AGENTS[*]}"

FAILED=0
for agent in "${AGENTS[@]}"; do
  if ! install_or_update "$agent" "$(skills_dir_for_agent "$agent" "$INSTALL_SCOPE" "$PROJECT_ROOT")"; then
    FAILED=1
  fi
done

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}Installation complete!${NC}"
else
  echo -e "${YELLOW}Installation completed with warnings/errors.${NC}"
fi
echo ""
echo "Next steps:"
echo "1. Restart your AI agent (Claude/Codex/Gemini/Antigravity)."
echo "2. The skill will be available for:"
echo "   • Writing component styles"
echo "   • Reviewing style code"
echo "   • Refactoring SCSS/CSS"
echo ""
echo "Repository: $REPO_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
