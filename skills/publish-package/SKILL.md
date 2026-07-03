---
name: publish-package
description: 发布 dodimension 包到内部 PyPI 的标准流程：按用户手动指定的版本号更新 pyproject.toml 和 dodimension/__init__.py，走 commit-and-push 流程提交推送，然后 build + twine 上传 + 钉钉通知。当用户要求发包、发版、发布版本、publish 时使用。
---

# Publish Package (dodimension)

发包流程：改版本号 → commit-and-push 提交推送 → build → twine 上传 → 钉钉通知。

版本号**由用户手动指定**，不自动递增。任何一步失败立即停止并报告，绝不带着错误继续上传。

## 1. 确认版本号

- 从用户输入中提取版本号（如"发包，版本号是 0.3.6.9"）。
- 用户没给版本号时，读取当前版本并**询问用户**要发布的版本号，不要自己猜。
- 校验：必须是四段式 `x.y.z.n`，且大于当前版本（当前版本看 `pyproject.toml` 的 `version` 字段）。
- 校验 `pyproject.toml` 和 `dodimension/__init__.py` 两处当前版本一致；不一致先报告用户。

## 2. 更新版本号

两个文件都要改，保持一致：

- `pyproject.toml`：`version = "<新版本>"`
- `dodimension/__init__.py`：`__version__ = "<新版本>"`

## 3. 提交推送

按 `commit-and-push` skill（`~/.agent-skills/commit-and-push/SKILL.md`）的完整流程执行：rebase upstream/dev → commit → push origin dev。

- commit 信息固定用 version 前缀：`version: 0.3.6.9`（替换为实际版本号）。
- 本次 commit 只包含 `pyproject.toml` 和 `dodimension/__init__.py` 两个文件。
- 若工作区还有其他未提交改动，向用户确认是否先单独处理，不要混入发版 commit。

## 4. 构建并上传

在 py12 环境、仓库根目录执行：

```bash
conda activate py12 && cd /Users/jackson/python_ws/cursor_ws/do_dimension

# 检查发版依赖（缺少则 pip install 补齐）
python -c "import build, wheel, setuptools, twine, requests"

# 清理旧构建产物，避免 dist/ 残留导致 twine 报错
rm -rf build/ dist/ *.egg-info

# 构建 sdist + wheel
python -m build

# 上传到内部 PyPI（需要 ~/.pypirc 已配置 [do] 仓库）
twine upload --repository do dist/*
```

## 5. 钉钉通知

上传成功后发送钉钉群通知：

```bash
python notify_dingtalk.py
```

## 6. 报告结果

向用户报告：

- 发布版本号、commit hash、推送结果
- 安装命令：

```bash
pip install dodimension==<版本号> --extra-index-url https://hub.designorder.cn/repository/pypi-hosted/simple/
```
