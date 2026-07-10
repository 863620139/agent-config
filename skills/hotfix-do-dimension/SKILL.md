---
name: hotfix-do-dimension
description: do_dimension 火线修复标准流程：从 service_auto_dimension 最新 tag 读取 do_dimension 版本，在 do_dimension 基于该 tag 创建 hotfix 分支，展示与 upstream/dev 的差异 commit 供用户挑选 cherry-pick，更新版本号并推送到 origin 和 upstream，可选发包到内部 PyPI。当用户说 hotfix、火线修复、紧急修复、基于 tag 修复时使用。
---

# Hotfix do_dimension

火线修复流程：查 service 最新 tag → 定位 do_dimension 基准 → 建 hotfix 分支 → 挑选 cherry-pick commit → 改版本号 → 推送 → （可选）发包。

## 前置约定

- `service_auto_dimension` 路径：优先 `../service_auto_dimension`；若不存在，尝试 `../../do/service_auto_dimension`
- do_dimension remote：`origin`（个人 fork）和 `upstream`（主库）
- do_dimension 版本文件：`pyproject.toml` 和 `dodimension/__init__.py`
- hotfix 版本号格式：`X.Y.Z.W.<修订号>`（五段式，如 `0.3.6.12.1`）

---

## 流程

按顺序执行，任何一步失败则停下报告。

### 1. 找 service_auto_dimension 最新 tag 对应的 do_dimension 版本

```bash
cd ../service_auto_dimension   # 或 ../../do/service_auto_dimension
git fetch --tags upstream 2>/dev/null || git fetch --tags origin
# 列出最新 tag（格式 vX.Y.Z，按版本降序，取第一个）
LATEST_TAG=$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "最新 tag: $LATEST_TAG"

# 切换到该 tag，读 requirement.txt 里的 do_dimension 版本
git checkout "$LATEST_TAG"
grep "dodimension" requirement.txt
```

记录读到的版本号，格式通常为 `dodimension==X.Y.Z.W`，提取版本 `X.Y.Z.W`。

切回 service 默认分支：

```bash
git checkout -   # 回到上一分支
```

### 2. 在 do_dimension 找到对应基准并建 hotfix 分支

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

**若远程无 tag**：用 version commit 作为基准：

```bash
git log upstream/dev --oneline -S "$DO_VERSION" -- pyproject.toml dodimension/__init__.py | head -1
# 取输出的 commit hash，记为 $BASE_COMMIT
```

确认基准（tag 或 version commit），记为 `$DO_TAG`（用于分支名）和 `$BASE_REF`（tag 名或 commit hash）。

创建 hotfix 分支前，若当前在 dev 且有未提交改动，先 stash：

```bash
git stash push --all -m "hotfix-auto"
```

创建 hotfix 分支（命名：`hotfix/<do_tag>`，去掉 `v` 前缀）：

```bash
git checkout -b "hotfix/$DO_TAG" "$BASE_REF"
```

### 3. 展示 tag 与 upstream/dev 的差异 commit

列出 dev 上有、但 hotfix 基准里没有的 commit：

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

按用户选定的 commit，**从最早到最新**依次执行：

```bash
git cherry-pick <hash>
```

如果 cherry-pick 出现冲突：停止并报告冲突文件，等待用户解决，不要自行处理。

### 5. 更新版本号

询问用户新版本号的末尾修订号：

> 当前基准版本是 `X.Y.Z.W`，hotfix 版本号格式为 `X.Y.Z.W.<修订号>`，请问修订号是几？（例如填 `1` → 版本变为 `X.Y.Z.W.1`）

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

### 8. 发包（用户要求时执行）

hotfix 发包**不走 dev 的 commit-and-push**，直接在 `hotfix/$DO_TAG` 分支上 build + upload。版本号已在步骤 5–6 提交，无需再改。

#### 8.1 清空工作区

若当前不在 hotfix 分支，或工作区有改动（含 build 残留），先处理：

```bash
git checkout "hotfix/$DO_TAG"
git stash push --all -m "hotfix-publish-auto"   # 工作区有任何改动时执行
git status --short                               # 应无输出
```

向用户报告 stash 之后的工作区状态，再继续。

#### 8.2 构建并上传

在 py12 环境、仓库根目录执行：

```bash
conda activate py12 && cd /Users/jackson/python_ws/cursor_ws/do_dimension

python -c "import build, wheel, setuptools, twine, requests"

# zsh 下 *.egg-info 可能 glob 失败，用 find 清理
rm -rf build/ dist/
find . -maxdepth 1 -name '*.egg-info' -exec rm -rf {} + 2>/dev/null

python -m build
twine upload --repository do dist/*
```

上传后核实 dist 文件名与 `$NEW_VERSION` 一致（如 `dodimension-$NEW_VERSION-py3-none-any.whl`）。

#### 8.3 钉钉通知（⚠️ 时机关键）

`notify_dingtalk.py` 通过 `from dodimension import __version__` 读取版本，**必须在 hotfix 分支上、且尚未切回 dev 时执行**：

```bash
# ✅ 正确：仍在 hotfix/$DO_TAG 分支
python notify_dingtalk.py
```

**禁止在以下时机发通知**（会读到 dev 的 `0.3.6.14` 等错误版本）：

- ❌ `git checkout dev` 之后
- ❌ 与 `git checkout dev` 并行执行
- ❌ stash pop 之后（若 pop 带回 dev 版本文件）

正确顺序：

```
build → twine upload → notify_dingtalk（hotfix 分支）→ checkout dev → stash pop
```

#### 8.4 恢复工作区

**发包和通知全部完成后**，再切回 dev 并恢复 stash：

```bash
git checkout dev
git stash pop    # 恢复 hotfix-auto 或 hotfix-publish-auto；若有冲突则停下报告
git status
```

若 stash pop 因 build 残留的 `dodimension.egg-info` 冲突，先 `rm -rf dodimension.egg-info build dist` 再 pop 或 drop stash。

---

## 完成后汇报

向用户汇报：
- 基于哪个 tag / version commit 创建了 hotfix 分支
- cherry-pick 了哪些 commit（hash + 信息）
- 新版本号
- 推送结果（origin / upstream）
- （若发包）PyPI 上传结果、钉钉通知版本号、安装命令：

```bash
pip install dodimension==<NEW_VERSION> --extra-index-url https://hub.designorder.cn/repository/pypi-hosted/simple/
```
