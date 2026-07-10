---
name: hotfix-do-dimension
description: do_dimension 火线修复标准流程：从 service_auto_dimension 最新 tag 读取 do_dimension 版本，在 do_dimension 基于该 tag 创建 hotfix 分支，展示与 upstream/dev 的差异 commit 供用户挑选 cherry-pick，更新版本号并推送到 origin 和 upstream。当用户说 hotfix、火线修复、紧急修复、基于 tag 修复时使用。
---

# Hotfix do_dimension

火线修复流程：查 service 最新 tag → 定位 do_dimension tag → 建 hotfix 分支 → 挑选 cherry-pick commit → 改版本号 → 推送。

## 前置约定

- `service_auto_dimension` 路径：与 `do_dimension` 同级目录（`../service_auto_dimension`）
- do_dimension remote：`origin`（个人 fork）和 `upstream`（主库）
- do_dimension 版本文件：`pyproject.toml` 和 `dodimension/__init__.py`

---

## 流程

按顺序执行，任何一步失败则停下报告。

### 1. 找 service_auto_dimension 最新 tag 对应的 do_dimension 版本

```bash
cd ../service_auto_dimension
git fetch --tags upstream 2>/dev/null || git fetch --tags origin
# 列出最新 tag（格式 vX.Y.Z，按版本降序，取第一个）
LATEST_TAG=$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "最新 tag: $LATEST_TAG"

# 切换到该 tag，读 requirements.txt 里的 do_dimension 版本
git checkout "$LATEST_TAG"
grep "dodimension" requirements.txt
```

记录读到的版本号，格式通常为 `dodimension==X.Y.Z.W`，提取版本 `X.Y.Z.W`。

切回 service 默认分支：

```bash
git checkout -   # 回到上一分支
```

### 2. 在 do_dimension 找到对应 tag 并建 hotfix 分支

回到 do_dimension 目录：

```bash
cd ../do_dimension   # 或直接到 do_dimension 的绝对路径
git fetch --tags upstream
git fetch --tags origin
```

查找与版本号匹配的 tag（tag 可能带 `v` 前缀）：

```bash
DO_VERSION="X.Y.Z.W"   # 用上一步读到的版本
git tag --sort=-version:refname | grep "$DO_VERSION"
```

确认找到 tag（例如 `v0.3.0.5` 或 `0.3.0.5`），记为 `$DO_TAG`。

创建 hotfix 分支（命名：`hotfix/<do_tag>`）：

```bash
git checkout -b "hotfix/$DO_TAG" "$DO_TAG"
```

### 3. 展示 tag 与 upstream/dev 的差异 commit

列出 dev 上有、但 hotfix 基准（tag）里没有的 commit：

```bash
git log --oneline "hotfix/$DO_TAG".."upstream/dev" --no-merges
```

把这些 commit 列表展示给用户，格式：

```
序号  commit hash  commit 信息
1.   abc1234  fix: 修复 XXX
2.   def5678  feat: 新增 YYY
...
```

### 4. 让用户挑选要 cherry-pick 的 commit

使用 `AskQuestion` 工具（或直接提问）让用户从列表中选择：

> 请选择要 cherry-pick 到 hotfix 分支的 commit（可多选）。

按用户选定的顺序（从最早到最新，即列表**倒序**）依次执行：

```bash
git cherry-pick <hash>
```

如果 cherry-pick 出现冲突：停止并报告冲突文件，等待用户解决，不要自行处理。

### 5. 更新版本号

询问用户新版本号的末尾修订号：

> 当前 tag 版本是 `X.Y.Z.W`，hotfix 版本号格式为 `X.Y.Z.W.<修订号>`，请问修订号是几？（例如填 `1` → 版本变为 `X.Y.Z.W.1`）

收到用户回答后，构造新版本 `NEW_VERSION="X.Y.Z.W.<修订号>"`，更新以下两处：

**pyproject.toml**（修改 `version = "..."` 行）

**dodimension/__init__.py**（修改 `__version__ = "..."` 行）

用 StrReplace 工具精确替换，不要用 sed。

### 6. Commit 版本变更

```bash
git add pyproject.toml dodimension/__init__.py
git commit -m "version: hotfix $NEW_VERSION"
```

### 7. 推送到 origin 和 upstream

```bash
git push origin "hotfix/$DO_TAG"
git push upstream "hotfix/$DO_TAG"
```

如果推送被拒绝（非 fast-forward），向用户确认后再 `--force-with-lease`，绝不直接 `--force`。

---

## 完成后汇报

向用户汇报：
- 基于哪个 tag 创建了 hotfix 分支
- cherry-pick 了哪些 commit（hash + 信息）
- 新版本号
- 推送结果（origin / upstream）
