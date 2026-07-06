---
name: jenkins-service-release
description: 通过 Jenkins 触发算法服务镜像构建与 K8s 部署。与 git 发版分开。当用户说 Jenkins 发版、发布到预生产/算法重构、投图服务发版、数据处理服务发版、/jenkins-service-release 时使用。
---

# Jenkins Service Release

通过 Jenkins Job `build_general_service_image` 触发构建与 K8s 部署。与 `algorithm-service-release`（git tag）**分开**，不操作 git。

## 用户意图解析

从用户输入提取 **服务类型** 和 **目标环境**，映射为 Jenkins 参数：

| 用户说法（服务） | 触发的 `serviceName`（可能多个） |
|-----------------|--------------------------------|
| 投图服务 | `ai-python-auto-dimension`、`ai-python-auto-dimension-part`（两个都发） |
| 数据处理服务 | `ai-algorithm-stp-convert` |

| 用户说法（环境） | `profile` | `branch` |
|-----------------|-----------|----------|
| 预生产 / 生产环境 | `production` | `release` |
| 算法重构 | `suanfa` | `dev` |

`collection` 固定为 `python-ai`，不可改。

用户未明确服务或环境时**必须询问**，不要猜测。

示例：
- 「帮我把投图服务发布到预生产」→ 并行两次构建：`production` + `release`，两个 serviceName
- 「数据处理服务发布到算法重构」→ 一次构建：`suanfa` + `dev`，`ai-algorithm-stp-convert`

## 固定参数（勾选框）

每次构建使用以下默认值，除非用户明确要求修改：

| 参数 | 默认值 |
|------|--------|
| `collection` | `python-ai` |
| `CleanWorkSpace` | `false` |
| `DeployToK8S` | `true` |
| `Rsync` | `false` |
| `Reverse` | `true` |

`Reverse` 说明：profile 为 `production` 时，勾选表示仅发预发布生产、不发正式生产。

## 凭证

从本地读取，**不要在回复中输出 token**：

- 用户名：`/Users/jackson/secret/jenkins/username`
- Token：`/Users/jackson/secret/jenkins/api_token`

```bash
JENKINS_USER=$(cat /Users/jackson/secret/jenkins/username)
JENKINS_TOKEN=$(cat /Users/jackson/secret/jenkins/api_token)
JENKINS_URL="https://jenkins.designorder.cn"
JOB="build_general_service_image"
```

## 触发与轮询原则

1. **每个 `serviceName` 只触发一次**，禁止重复 POST。
2. **禁止用 `lastBuild` 识别本次构建**——并发时 `lastBuild` 会指向别人的构建，导致误判或重复触发。
3. **投图服务的多个 `serviceName` 并行触发、并行等待**，不要串行「等第一个完成再触发第二个」。
4. 触发后从响应头 `Location` 取 queue id，再轮询 queue item 拿到 build 号，最后轮询 build 状态。

## 流程

需要 `full_network` 权限。推荐用 [scripts/release.sh](scripts/release.sh) 执行，避免手写 curl 出错。

### 1. 获取 CSRF Crumb（全程只用一次）

```bash
CRUMB_JSON=$(curl -sS -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])")
CRUMB_FIELD=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])")
```

### 2. 并行触发所有 serviceName

对每个 `<SERVICE>` 各 POST **一次**，保存 `service → queue_id` 映射：

```bash
HTTP_CODE=$(curl -sS -D /tmp/jenkins_hdr.txt -o /dev/null -w '%{http_code}' -X POST \
  -u "$JENKINS_USER:$JENKINS_TOKEN" \
  -H "$CRUMB_FIELD: $CRUMB" \
  "$JENKINS_URL/job/$JOB/buildWithParameters" \
  --data-urlencode "collection=python-ai" \
  --data-urlencode "serviceName=<SERVICE>" \
  --data-urlencode "profile=<PROFILE>" \
  --data-urlencode "branch=<BRANCH>" \
  --data-urlencode "CleanWorkSpace=false" \
  --data-urlencode "DeployToK8S=true" \
  --data-urlencode "Rsync=false" \
  --data-urlencode "Reverse=true")

# 从 Location 头解析 queue id，例如 .../queue/item/13598/
QUEUE_ID=$(grep -i '^location:' /tmp/jenkins_hdr.txt | sed 's|.*/queue/item/||;s|/.*||' | tr -d '\r')
```

- 成功：HTTP **201**（偶发 302）
- 失败：立即停止，报告 HTTP 码和响应体，**不要 retry 同一个 serviceName**

投图服务：对两个 serviceName **连续触发两次**（中间不等待），得到两个 queue_id。

### 3. 从 queue 解析 build 号

对每个 queue_id 轮询，直到 `executable.number` 出现（最多等 60 秒）：

```bash
curl -sS -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/queue/item/<QUEUE_ID>/api/json" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('executable'); print(e.get('number','') if e else '')"
```

得到 `service → build_no` 映射后再开始等构建完成。

### 4. 并行轮询所有 build

所有 build 号就绪后，**在一个循环里同时检查**每个 build，每 30 秒一轮，超时 30 分钟：

```bash
# 对每个 BUILD_NO 查 building/result/displayName
curl -sS -u "$JENKINS_USER:$JENKINS_TOKEN" \
  "$JENKINS_URL/job/$JOB/<BUILD_NO>/api/json?tree=building,result,displayName,url"
```

- 全部 `result=SUCCESS` → 完成报告
- 任一 `FAILURE` / `ABORTED` → 报告失败项及 console 链接，**但不取消已在跑的其它 build**
- 超时 → 报告各 build 当前状态

Console 链接：`$JENKINS_URL/job/$JOB/<BUILD_NO>/console`

## 脚本用法

```bash
# 投图 → 算法重构（并行触发两个 serviceName）
bash scripts/release.sh --service projection --env refactor

# 投图 → 预生产
bash scripts/release.sh --service projection --env preprod

# 数据处理 → 算法重构
bash scripts/release.sh --service dataproc --env refactor
```

## 完成后报告

向用户报告：

- 服务类型、目标环境（profile / branch）
- 每个 `serviceName` 的 queue id、build 号、镜像 displayName、构建结果
- Jenkins console 链接
- 若失败：失败阶段（可查 console 末尾）

## 注意事项

- **不要**修改 git config，**不要**操作 git 分支或 tag。
- **不要**在对话中打印 token 或凭证文件内容。
- **不要**用 `lastBuild`；**不要**对同一 serviceName 触发两次。
- 投图服务 = 两个 serviceName **并行**构建，不是串行。
- 用户要求修改 `CleanWorkSpace`、`DeployToK8S`、`Rsync`、`Reverse` 时按用户指定覆盖默认值。
- 本 skill 不负责 Python 包发包；git 发版走 `algorithm-service-release`。
