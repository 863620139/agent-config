#!/bin/bash
# 把本仓库的 skills 和 rules 软链到 Cursor / Claude Code / Codex 的配置目录
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- skills：三个工具共用 ----
SKILL_TARGETS=("$HOME/.cursor/skills" "$HOME/.claude/skills" "$HOME/.codex/skills")

for target in "${SKILL_TARGETS[@]}"; do
    mkdir -p "$target"
done

for skill in "$REPO_DIR"/skills/*/; do
    name="$(basename "$skill")"
    for target in "${SKILL_TARGETS[@]}"; do
        ln -sfn "$REPO_DIR/skills/$name" "$target/$name"
        echo "link: $target/$name -> skills/$name"
    done
done

# ---- rules：按 agent 分发 ----
# Cursor: rules/cursor/*.mdc -> ~/.cursor/rules/
mkdir -p "$HOME/.cursor/rules"
for rule in "$REPO_DIR"/rules/cursor/*.mdc; do
    [ -e "$rule" ] || continue
    name="$(basename "$rule")"
    ln -sfn "$rule" "$HOME/.cursor/rules/$name"
    echo "link: ~/.cursor/rules/$name -> rules/cursor/$name"
done

# Claude Code: rules/claude/CLAUDE.md -> ~/.claude/CLAUDE.md
if [ -f "$REPO_DIR/rules/claude/CLAUDE.md" ]; then
    mkdir -p "$HOME/.claude"
    ln -sfn "$REPO_DIR/rules/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    echo "link: ~/.claude/CLAUDE.md -> rules/claude/CLAUDE.md"
fi

# Codex: rules/codex/AGENTS.md -> ~/.codex/AGENTS.md
if [ -f "$REPO_DIR/rules/codex/AGENTS.md" ]; then
    mkdir -p "$HOME/.codex"
    ln -sfn "$REPO_DIR/rules/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
    echo "link: ~/.codex/AGENTS.md -> rules/codex/AGENTS.md"
fi

echo "done."
