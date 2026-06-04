# appimage-linyaps 技能实现方案

## 项目概述

### 目标
创建 `appimage-linyaps` 技能，用于将 AppImage 应用程序转换为玲珑（Linyaps）包格式。该技能基于现有的 `tar-linyaps` 技能架构，但专门针对 AppImage 的特性进行优化。

### 核心价值
1. **AppImage 专用处理**：专门处理 AppImage 的解压、元数据提取和 Exec 命令解析
2. **Wrapper 机制**：采用 Go 版本 ll-pica 的 wrapper 方式，保留 AppImage 原始目录结构
3. **智能 Exec 提取**：从 desktop 文件中准确提取 Exec 命令，支持多种 AppImage 变体
4. **版本号自动提取**：从文件名中智能提取版本号，支持多种版本号格式

### 技术架构
- **基于**：`tar-linyaps` 技能架构（850 行 pak_linyaps.sh 脚本）
- **参考**：`ll-pica` Go 版本的 AppImage 转换逻辑
- **核心机制**：Wrapper 方式，保留 squashfs-root 完整结构

## 已完成的工作

### 1. 脚本文件（4个）

#### `scripts/extract_appimage.sh`（76 行）
- **功能**：解压 AppImage 文件
- **方法**：`chmod +x` + `--appimage-extract`
- **输出**：在指定目录生成 `squashfs-root/` 目录
- **验证**：检查 ELF 格式、AppRun 存在性

#### `scripts/resolve_exec_command.sh`（108 行）
- **功能**：从 desktop 文件中准确提取 Exec 命令
- **支持模式**：
  - AppRun 直接调用：`Exec=AppRun %U`
  - AppRun.wrapped：`Exec=AppRun.wrapped`
  - 直接二进制：`Exec=myapp --gui`
  - 带 `${HERE}` 变量：`Exec=${HERE}/usr/bin/myapp`
  - 带引号：`Exec="/path/to/AppRun" %U`
- **输出**：解析后的 binary name（供 wrapper 使用）

#### `scripts/parse_appimage_metadata.sh`（143 行）
- **功能**：从 AppImage 文件和 desktop 文件中提取元数据
- **提取内容**：
  - `app_name`：应用名称（从 desktop Name= 提取）
  - `package_id`：玲珑包 ID（从 desktop 文件名推导）
  - `description`：应用描述（从 desktop Comment= 提取）
  - `exec_command`：Exec 命令（从 desktop Exec= 提取）
  - `icon_name`：图标名称（从 desktop Icon= 提取）
  - `version`：版本号（从文件名正则提取）
- **输出格式**：`key=value` 格式，可直接 `eval` 载入

#### `scripts/parse_build_config.sh`（~390 行）
- **功能**：解析并验证构建配置 JSON 文件
- **依赖**：jq
- **验证**：必填字段检查、可选字段默认值
- **输出**：扁平化的 `key=value` 格式

### 2. 模板文件

#### `templates/linglong.yaml`（21 行）
- **模板变量**：`${package_id}`, `${app_name}`, `${ll_version}`, `${ll_architecture}`, `${description}`
- **构建命令**：`cp -rf /project/binary/* ${prefix}/`
- **特殊处理**：保留 AppImage 原始结构到 `lib/${APP_PREFIX}/`

### 3. 示例文件

#### `examples/build_config.example.json`（22 行）
- **结构**：分组 JSON（main 必填，optional 可选）
- **主要字段**：
  - `appimage_file` 或 `appimage_url`（二选一）
  - `app_name`, `package_id`, `description`
  - `exec_command`（可选覆盖）
  - `icon_url`（可选）

### 4. 目录结构
```
skills/appimage-linyaps/
├── config/                    # 配置文件（待填充）
├── examples/
│   └── build_config.example.json
├── scripts/
│   ├── extract_appimage.sh
│   ├── resolve_exec_command.sh
│   ├── parse_appimage_metadata.sh
│   └── parse_build_config.sh
├── templates/
│   ├── files_res/            # 资源文件目录（空）
│   └── linglong.yaml
└── IMPLEMENTATION.md         # 本文档
```

## 待完成的工作

### 1. 核心构建脚本（最高优先级）

#### `templates/pak_linyaps.sh`（预计 600-800 行）
- **功能**：主构建编排脚本
- **核心逻辑**：
  1. 初始化全局数据（参数解析、验证）
  2. 解压 AppImage（使用 `extract_appimage.sh`）
  3. 提取元数据（使用 `parse_appimage_metadata.sh`）
  4. 解析 Exec 命令（使用 `resolve_exec_command.sh`）
  5. 构建目录初始化（wrapper 机制）
  6. 生成 desktop 文件和图标
  7. 执行 ll-builder build 和 export
  8. 推送到开发仓库（可选）

- **关键设计决策**：
  - `srcType="appimage"`
  - 保留 `squashfs-root` 完整结构在 `lib/${APP_PREFIX}/`
  - Wrapper 脚本：`cd lib/${APP_PREFIX} && ./AppRun $@`
  - **不修改** AppImage 内部路径结构
  - **不手动设置** Exec 路径，由 wrapper 自动处理

- **CLI 参数**：
  ```
  --src_path          # AppImage 文件路径
  --package_id        # 玲珑包 ID
  --app_name          # 应用名称
  --description       # 应用描述
  --exec_command      # 显式指定 Exec 命令（可选覆盖）
  --icon_path         # 图标路径
  --origin_version    # 原始版本号
  --ll_version        # 玲珑版本号
  --linyaps_arch      # 目标架构
  --output_dir        # 输出目录
  --build_tmp_dir     # 构建临时目录
  --base_id/version   # base 层配置
  --runtime_id/version # runtime 层配置
  --whitelist         # 白名单配置
  ```

### 2. 技能定义文档

#### `SKILL.md`
- **功能**：技能定义和使用说明
- **内容**：
  - 技能描述和触发条件
  - 工作流程步骤
  - 职责边界说明
  - 约束条件
  - 示例用法

### 3. 共享脚本复制

从 `tar-linyaps` 复制以下脚本：
- `scripts/dedup_desktop_files.sh` - 去重 desktop 文件
- `scripts/validate_bin_nesting.sh` - 验证二进制嵌套
- `scripts/scan_executables.sh` - 扫描可执行文件（作为备用）

### 4. 配置文件复制

从 `linglong-project-gen` 复制：
- `config/base_runtime_whitelist.conf` - base/runtime 白名单配置

### 5. 权限设置

对所有脚本文件执行 `chmod +x`

## 设计决策

### 1. Wrapper 机制 vs 路径扁平化

**选择**：Wrapper 机制（保留原始结构）

**理由**：
- AppImage 解压后可能包含复杂的相对路径关系
- 修改路径可能导致应用程序无法正常运行
- Wrapper 方式更安全，保持 AppImage 原有执行逻辑
- Go 版本 ll-pica 验证了此方案的可行性

**实现**：
```bash
# Wrapper 脚本内容
#!/bin/bash
cd "$(dirname "$0")/lib/${APP_PREFIX}"
exec ./AppRun "$@"
```

### 2. Exec 命令处理

**策略**：智能提取 + 显式覆盖

**流程**：
1. 优先使用用户通过 `--exec_command` 显式指定的命令
2. 如果未指定，使用 `resolve_exec_command.sh` 从 desktop 文件提取
3. 提取失败时，使用 `scan_executables.sh` 扫描可执行文件作为备用

**关键约束**：
- **不修改** desktop 文件的 Exec 字段
- **不手动设置** linglong.yaml 的 command 字段
- **让** pak_linyaps.sh 通过 wrapper 机制自动处理

### 3. 版本号处理

**策略**：多模式正则提取 + 格式标准化

**支持格式**：
- `-v1.2.3` 或 `-V1.2.3`
- `-1.2.3-` 或 `_1.2.3_`
- `1.2.3` 在文件名开头
- 任何位置的 `1.2.3.4` 格式

**标准化**：确保版本号为 `X.Y.Z.W` 格式（ll-builder 要求）

### 4. 目录结构设计

**原则**：
- `binary/` 对应 `$prefix/`（files/）
- `squashfs-root` 保持原始结构，安装到 `lib/${APP_PREFIX}/`
- `files_res/` 存放 desktop 文件、图标等资源

## 实现流程

### 阶段 1：创建核心脚本（已完成）
1. ✅ `extract_appimage.sh` - AppImage 解压
2. ✅ `resolve_exec_command.sh` - Exec 命令解析
3. ✅ `parse_appimage_metadata.sh` - 元数据提取
4. ✅ `parse_build_config.sh` - 配置解析

### 阶段 2：创建模板和示例（已完成）
1. ✅ `linglong.yaml` - 玲珑包模板
2. ✅ `build_config.example.json` - 配置示例

### 阶段 3：创建主构建脚本（待完成）
1. ❌ `pak_linyaps.sh` - 主构建编排脚本

### 阶段 4：创建技能文档（待完成）
1. ❌ `SKILL.md` - 技能定义文档

### 阶段 5：复制共享资源（待完成）
1. ❌ 复制共享脚本（dedup_desktop_files.sh, validate_bin_nesting.sh, scan_executables.sh）
2. ❌ 复制配置文件（base_runtime_whitelist.conf）
3. ❌ 设置脚本权限

### 阶段 6：测试验证（待完成）
1. ❌ 单元测试
2. ❌ 集成测试
3. ❌ 端到端测试

## 如何继续实现

### 1. 创建 `pak_linyaps.sh`

**参考**：`tar-linyaps/templates/pak_linyaps.sh`（850 行）

**关键修改点**：
- `srcType` 从 "tar" 改为 "appimage"
- 解压逻辑从 `tar xf` 改为 `--appimage-extract`
- 添加 Exec 命令解析逻辑
- 保留 wrapper 机制
- 移除 tar 特有的处理逻辑

**建议步骤**：
1. 复制 `tar-linyaps/templates/pak_linyaps.sh` 作为基础
2. 修改 `init_global_data` 函数，添加 AppImage 特有参数
3. 修改 `build_pak` 函数，实现 AppImage 解压逻辑
4. 添加 `resolve_exec_command` 调用
5. 保留 wrapper 创建逻辑
6. 测试验证

### 2. 创建 `SKILL.md`

**参考**：`tar-linyaps/SKILL.md`

**关键修改点**：
- 触发条件：AppImage 相关关键词
- 工作流程：AppImage 专用步骤
- 职责边界：明确 Exec 命令处理方式
- 约束条件：禁止手动修改 Exec

### 3. 复制共享脚本

**命令**：
```bash
# 复制共享脚本
cp ../tar-linyaps/scripts/dedup_desktop_files.sh scripts/
cp ../tar-linyaps/scripts/validate_bin_nesting.sh scripts/
cp ../tar-linyaps/scripts/scan_executables.sh scripts/

# 复制配置文件
cp ../linglong-project-gen/config/base_runtime_whitelist.conf config/

# 设置权限
chmod +x scripts/*.sh
```

## 测试策略

### 单元测试
- 测试每个脚本的独立功能
- 验证参数解析、错误处理
- 测试边界条件

### 集成测试
- 测试脚本间的协作
- 验证数据流转
- 测试配置解析和验证

### 端到端测试
- 测试完整的转换流程
- 使用真实的 AppImage 文件
- 验证生成的玲珑包

## 注意事项

### 1. 安全性
- 验证 AppImage 文件格式
- 检查文件权限
- 防止路径遍历攻击

### 2. 兼容性
- 支持多种 AppImage 变体
- 处理不同的 desktop 文件格式
- 兼容各种版本号格式

### 3. 错误处理
- 清晰的错误信息
- 优雅的失败处理
- 详细的日志记录

### 4. 性能
- 避免不必要的文件操作
- 优化解压过程
- 减少磁盘空间使用

## 后续优化

### 1. 功能增强
- 支持 AppImage 更新检测
- 添加依赖关系分析
- 支持多架构构建

### 2. 用户体验
- 图形界面支持
- 进度显示
- 交互式配置

### 3. 生态集成
- 与 CI/CD 集成
- 支持批量转换
- 插件系统支持

## 总结

`appimage-linyaps` 技能已经完成了核心脚本的开发，建立了坚实的基础架构。接下来的工作重点是创建主构建脚本 `pak_linyaps.sh` 和技能文档 `SKILL.md`，然后进行充分的测试验证。

该技能的设计遵循了以下原则：
1. **模块化**：每个脚本负责单一职责
2. **可扩展**：易于添加新功能和支持新的 AppImage 变体
3. **可靠性**：完善的错误处理和验证机制
4. **用户友好**：清晰的配置和详细的文档

通过完成剩余的工作，该技能将能够可靠地将 AppImage 应用程序转换为玲珑包格式，为用户提供更好的应用分发体验。