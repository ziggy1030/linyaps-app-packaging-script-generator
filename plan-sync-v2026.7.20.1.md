# 同步计划：将 v2026.7.20.1 仓库的 commits 同步到本仓库

## 一、仓库关系

| 项目 | 本仓库 (`.github`) | 目标仓库 (`.v2026.7.20.1`) |
|------|-------------------|----------------------------|
| 路径 | `linyaps-app-packaging-script-generator.github` | `linyaps-app-packaging-script-generator.v2026.7.20.1` |
| Remote 名 | `v2026-temp` | — |
| 主分支 | `master` (ziggy1030 重写历史, 60 commits) | `master` (luzijie 原始历史, 80 commits) |
| 额外分支 | 无 | `deb-faker` (不同步) |
| 当前 HEAD | `6168584` (ziggy1030) | `1cb121d` (luzijie, tag `v2026.7.20.1`) |
| 共同 tag | 15 个 tag，指向相同 commit SHA | 15 个 tag |

**关键事实**：两个仓库的 commit DAG 完全不同（ziggy1030 重写了全部历史），没有共享的 git parent 关系。但 tag 指向相同的 commit 对象（已通过 `v2026-temp` remote fetch）。

---

## 二、约束条件

1. **排除 `for-multica/` 目录**：该目录是隐私内容，不同步到本仓库
2. **Author/Committer 统一为当前用户**：新 commit 的 author 和 committer 使用 `ZiggyLuk <ziggy16603042386@163.com>`（当前 git config 值），不保留原始 luzijie 的署名
3. **每个 tag 作为一个 PR 节点**：每个 tag 区间创建一个 PR，等待手动合并后再处理下一个
4. **只同步 master 分支**：`deb-faker` 分支及其 tag 不同步
5. **遵循 skill 规范**：使用 `git format-patch` + `git am` 方式，默认不传 `--preserve-author`

---

## 三、核心方法

### 3.1 技术路线

遵循 skill (`ut-git-migrate-skill`) 的默认行为（`--preserve-author=false`）：

```
1. git format-patch tag_{i-1}..tag_i      # 在目标仓库生成 patch
2. 过滤 patch 文件                          # 排除 for-multica/ 路径
3. git am 到当前 master 分支               # 设置 author/committer = ZiggyLuk
4. git commit --amend --author="ZiggyLuk"  # 确保 author 正确
5. git branch pr/<tag>                     # 创建 PR 分支
6. git reset --hard ORIG_HEAD              # 回到 patch 前状态
7. 创建 PR: pr/<tag> → master             # 等待手动合并
```

### 3.2 Author/Committer 设置

```bash
# git am 时环境变量
GIT_AUTHOR_NAME="ZiggyLuk"
GIT_AUTHOR_EMAIL="ziggy16603042386@163.com"
GIT_COMMITTER_NAME="ZiggyLuk"
GIT_COMMITTER_EMAIL="ziggy16603042386@163.com"

# am 后 amend 确保 author
git commit --amend --author="ZiggyLuk <ziggy16603042386@163.com>" --no-edit
```

时间戳：保留原始 commit 时间戳（`--interval 0` 行为）

### 3.3 for-multica/ 过滤策略

根据 commit 内容分类处理：

| 类型 | 定义 | 处理方式 |
|------|------|---------|
| **纯 multica commit** | 所有变更文件都在 `for-multica/` 下 | 跳过该 commit，不生成 patch |
| **混合 commit** | 同时变更了 `for-multica/` 和其他文件 | 生成 patch 后，用 `filterdiff` 或 `sed` 移除 patch 中 `for-multica/` 的 diff 块 |
| **无关 commit** | 不涉及 `for-multica/` | 正常处理 |

---

## 四、PR 列表（按顺序执行）

### 4.1 各 tag 区间的 commit 分布

| 顺序 | PR 分支 | 区间 | 原始 commits | 过滤后 commits | 过滤说明 |
|------|---------|------|-------------|---------------|---------|
| 1 | `pr/v1.0.0` | `root..v1.0.0` | 26 | 26 | 无 multica 内容 |
| 2 | `pr/v1.1.0` | `v1.0.0..v1.1.0` | 12 | 12 | 无 multica 内容 |
| 3 | `pr/v1.2.0` | `v1.1.0..v1.2.0` | 13 | 13 | 无 multica 内容 |
| 4 | `pr/v1.3.0` | `v1.2.0..v1.3.0` | 3 | 3 | 无 multica 内容 |
| 5 | `pr/v26.6.11.1` | `v1.3.0..v26.6.11.1` | 17 | **14** | 跳过 `d17bcc9`（纯 multica）；`cfbb3da`、`c53e078`、`0ffc113` 为混合 commit，需过滤 patch 中的 multica 路径 |
| 6 | `pr/v26.6.25.1` | `v26.6.11.1..v26.6.25.1` | 1 | **0** | `a0f79b1` 是纯 multica commit，跳过 |
| 7 | `pr/v2026.6.25.2` | `v26.6.25.1..v2026.6.25.2` | 1 | **0** | `a715368` 是纯 multica commit，跳过 |
| 8 | `pr/v2026.7.8.1` | `v2026.6.25.2..v2026.7.8.1` | 1 | **0** | `7e1db9c` 是纯 multica commit，跳过 |
| 9 | `pr/v2026.7.9.1` | `v2026.7.8.1..v2026.7.9.1` | 2 | **1** | `0eaf81f` 纯 multica 跳过；`1f903db` 正常保留 |
| 10 | `pr/v2026.7.9.2` | `v2026.7.9.1..v2026.7.9.2` | 1 | **0** | `5f94eaf` 是纯 multica commit，跳过 |
| 11 | `pr/v2026.7.13.1` | `v2026.7.9.2..v2026.7.13.1` | 1 | **0** | `035c670` 是纯 multica commit，跳过 |
| 12 | `pr/v2026.7.20.1` | `v2026.7.13.1..v2026.7.20.1` | 2 | 2 | 无 multica 内容 |

### 4.2 需要过滤的混合 commit 详情

| Commit | 涉及文件 | 需保留的变更 |
|--------|---------|------------|
| `cfbb3da` (centralize external configs) | `for-multica/agent-config.json` (×2), `agent-config.json`, `agents/deb-linglong-packer.agent.md` | `agent-config.json`, `agents/deb-linglong-packer.agent.md` |
| `c53e078` (standalone agent-config.json) | `for-multica/agent-config.json`, `agent-config.json`, `agents/deb-linglong-packer.agent.md` | `agent-config.json`, `agents/deb-linglong-packer.agent.md` |
| `0ffc113` (add multica agent definition) | `for-multica/agent-config.json`, `for-multica/agent.md`, `README.md` | `README.md` |

### 4.3 PR 合并后的效果

```
合并前:  master ── A ── B ── C (ziggy1030 历史, 60 commits)
         pr/v1.0.0 ── X1 ── ... ── X26 (ZiggyLuk 署名)
         PR#1 显示: 全量 diff (无共同祖先)

合并后:  master ── A ── B ── C ── X1 ── ... ── X26
         pr/v1.1.0 ── X1 ── ... ── X26 ── Y1 ── ... ── Y12
         PR#2 显示: Y1~Y12 增量 diff ✅
```

---

## 五、执行步骤

### 5.1 准备工作

```bash
# 确认当前 git 用户信息
git config user.name     # 应输出: ZiggyLuk
git config user.email    # 应输出: ziggy16603042386@163.com

# 确认 v2026-temp remote 已存在
git remote -v | grep v2026-temp

# 确认目标仓库 master 分支已 fetch
git fetch v2026-temp master
```

### 5.2 单个 tag 区间的处理流程

```bash
# 参数: TAG_PREV, TAG_CURR
TAG_PREV=v1.0.0    # 前一个 tag
TAG_CURR=v1.1.0    # 当前 tag
TEMP_DIR=$(mktemp -d)

# Step 1: 在目标仓库生成 patch
cd /path/to/target/repo
git format-patch -o "${TEMP_DIR}" "${TAG_PREV}..${TAG_CURR}"

# Step 2: 过滤 for-multica/ 路径
for patch in "${TEMP_DIR}"/*.patch; do
    # 检查 patch 是否只包含 multica 变更 → 跳过
    # 检查 patch 是否包含混合变更 → 过滤 multica 路径
    filterdiff -x 'for-multica/*' -i "${patch}" > "${patch}.filtered" || true
done

# Step 3: 在本仓库应用 patch
cd /path/to/current/repo
export GIT_AUTHOR_NAME="ZiggyLuk"
export GIT_AUTHOR_EMAIL="ziggy16603042386@163.com"
export GIT_COMMITTER_NAME="ZiggyLuk"
export GIT_COMMITTER_EMAIL="ziggy16603042386@163.com"

for patch in "${TEMP_DIR}"/*.filtered; do
    git am "${patch}"
    git commit --amend --author="ZiggyLuk <ziggy16603042386@163.com>" --no-edit
done

# Step 4: 创建 PR 分支
git branch "pr/${TAG_CURR}"

# Step 5: 回退到 patch 前状态
git reset --hard ORIG_HEAD
# 或: git reset --hard HEAD~<commit_count>

# Step 6: 创建 PR
# (在 GitHub 上操作)
```

### 5.3 特殊处理

对于纯 multica commit 的 tag 区间（如 `v26.6.11.1 → v26.6.25.1`，`v26.6.25.1 → v2026.6.25.2` 等）：
- 该区间内没有可同步的 commit
- 但 tag 本身仍然需要同步（标签已存在，无需额外操作）
- 跳过该区间的 PR 创建

### 5.4 混合 commit 的 patch 过滤

使用 `filterdiff`（来自 `patchutils` 包）或 `sed` 移除 patch 中 `for-multica/` 相关的 diff 块：

```bash
# 方式一: filterdiff (推荐)
filterdiff -x 'for-multica/*' original.patch > filtered.patch

# 方式二: 手动移除
# 找到 patch 中 diff --git 开头、路径包含 for-multica/ 的块，整体移除
```

---

## 六、风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| Patch 应用到当前 master 时冲突 | 流程中断 | 人工介入解决冲突，或跳过冲突 commit |
| 混合 commit 的 patch 过滤不干净 | 残留 `for-multica/` 内容 | 在 am 后检查 `git diff HEAD --name-only`，确认无 `for-multica/` |
| 部分 commit 在本仓库已存在 | 重复提交 | `git am --skip` 跳过 |
| PR 合并后状态与预期不符 | 后续 PR 显示异常 | 合并后检查 `git log --oneline` 确认状态正确 |

---

## 七、验证清单

每个 PR 合并后，执行以下验证：

```bash
# 1. 确认 author 为 ZiggyLuk
git log --format="%h %an <%ae> %s" -1

# 2. 确认无 for-multica/ 残留
git ls-tree -r HEAD --name-only | grep for-multica || echo "OK: no multica"

# 3. 确认 commit 数量正确
git log --oneline | wc -l

# 4. 确认 tag 仍然有效
git tag -l | sort
```

---

## 八、附录：完整 tag 列表

| Tag | 指向的 commit | 日期 | 类型 |
|-----|--------------|------|------|
| v1.0.0 | `23afdab` | 2026-05-08 | annotated |
| v1.1.0 | `16409a3` | 2026-05-18 | lightweight |
| v1.2.0 | `e7fae8a` | 2026-06-01 | annotated |
| v1.3.0 | `bd55d56` | 2026-06-02 | annotated |
| v26.6.11.1 | `d4c9e08` | 2026-06-11 | annotated |
| v26.6.11.2 | `d4c9e08` | 2026-06-11 | annotated (同 v26.6.11.1) |
| v26.6.25.1 | `a0f79b1` | 2026-06-25 | annotated |
| v2026.6.25.2 | `a715368` | 2026-06-25 | annotated |
| v2026.7.8.1 | `7e1db9c` | 2026-07-08 | annotated |
| v2026.7.9.1 | `0eaf81f` | 2026-07-09 | annotated |
| v2026.7.9.2 | `5f94eaf` | 2026-07-09 | annotated |
| v2026.7.13.1 | `035c670` | 2026-07-13 | lightweight |
| v2026.7.20.1 | `1cb121d` | 2026-07-20 | lightweight |

> 注意：`v26.6.11.1` 和 `v26.6.11.2` 指向同一个 commit。`v2026.06.02.deb-faker` 和 `v2026.6.25.1.deb-faker` 属于 `deb-faker` 分支，不在同步范围内。