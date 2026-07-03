---
name: commit-and-push
description: 提交并推送代码的标准流程：先 rebase upstream/dev，再按规定的提交类型前缀（feat/fix/version/update/refactor/style/docs/test/chore）生成 commit，最后 push 到 origin dev。当用户要求提交代码、推送代码、commit、push、同步 upstream 时使用。
---

# Commit and Push

标准提交推送流程：rebase upstream/dev → commit（带类型前缀）→ push origin dev。

## 流程

按顺序执行，任何一步失败则停下并报告，不要跳过。

### 1. 检查状态

```bash
git status
git diff
git log --oneline -5
```

确认当前分支（通常应为 dev）和本次要提交的修改内容。

### 2. Rebase upstream/dev

```bash
git fetch upstream
git stash --include-untracked   # 仅当有未提交修改时
git rebase upstream/dev
git stash pop                   # 仅当上一步 stash 过
```

- 若 rebase 出现冲突：停止操作，向用户报告冲突文件，等待用户决定，不要自行解决或 `git rebase --abort`（除非用户要求）。
- 若 `git stash pop` 出现冲突：同样停止并报告。

### 3. Commit

分析改动内容，选择正确的类型前缀，生成简洁的中文提交信息：

```bash
git add <相关文件>
git commit -m "<前缀>: <描述>"
```

commit 的前缀必须满足提交类型前缀：

| 前缀 | 含义 |
|------|------|
| feat | 新增功能 |
| fix | BUG修复 |
| version | 版本发布 |
| update | 配置、脚本、资源等更新 |
| refactor | 重构，不属于新增功能，也不属于问题修复的代码变动 |
| style | 代码格式，代码风格格式的变动 |
| docs | 文档更新，说明、注释、README等 |
| test | 测试用例、测试脚本更新 |
| chore | 构建过程或辅助工具的变动，e.g. setup.py更新 |

注意事项：

- 只 add 与本次修改相关的文件，不要 `git add -A` 把无关的未跟踪文件带进来。
- 不要提交可能包含密钥的文件（.env、credentials 等）。
- 若改动横跨多种类型，以最主要的改动选择前缀；必要时可拆成多个 commit。

示例：

```
feat: 剖视图新增孔深度标注支持
fix: 修复视图锚点可见性计算错误
docs: 更新剖视图管线说明文档
```

### 4. Push 到 origin dev

```bash
git push origin dev
```

- 若因 rebase 改写了已推送的历史导致被拒绝，先向用户确认后再使用 `git push --force-with-lease origin dev`，绝不直接 `--force`。

### 5. 确认结果

```bash
git status
git log --oneline -3
```

向用户报告：commit 信息、推送结果。
