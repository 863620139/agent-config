# agent-config

个人的 AI agent 配置仓库：通用 skills + 按 agent 划分的 rules。

## 结构

```
agent-config/
├── skills/                  # 通用 skill，Cursor / Claude Code / Codex 共用
│   ├── commit-and-push/     # rebase upstream/dev → commit（类型前缀）→ push origin dev
│   ├── debug-parametric/    # do_dimension 调试流程
│   └── publish-package/     # dodimension 发包流程（手动指定版本号）
├── rules/
│   ├── cursor/              # Cursor rules（.mdc），链接到 ~/.cursor/rules/
│   ├── claude/              # Claude Code 全局指令（CLAUDE.md），链接到 ~/.claude/CLAUDE.md
│   └── codex/               # Codex 全局指令（AGENTS.md），链接到 ~/.codex/AGENTS.md
└── install.sh               # 一键创建所有软链接
```

## 安装

```bash
git clone git@github.com:<你的用户名>/agent-config.git ~/agent-config
cd ~/agent-config && ./install.sh
```

`install.sh` 会把 `skills/` 下每个 skill 软链到三个工具的 skills 目录，把 `rules/` 下的文件软链到对应工具的 rules 位置。仓库是唯一数据源，改完 `git push` 即可，换机器 clone + install 一次搞定。

## 新增 skill

```bash
mkdir skills/my-skill
# 编写 skills/my-skill/SKILL.md（含 name/description frontmatter）
./install.sh   # 重新链接
```
