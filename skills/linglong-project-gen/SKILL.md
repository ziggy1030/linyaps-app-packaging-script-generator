---
name: linglong-project-gen
description: '生成玲珑打包工程文件(linglong.yaml、pak_linyaps.sh)。Use when: 需要创建新的玲珑打包工程、生成linglong.yaml配置、生成打包脚本。'
argument-hint: '包ID和配置信息'
---

# 玲珑工程生成

## 功能说明

根据deb包信息和CSV配置，生成完整的玲珑打包工程，包括 `linglong.yaml` 配置文件和 `pak_linyaps.sh` 打包脚本。

## 触发场景

- 需要为deb包创建玲珑打包工程
- 需要生成linglong.yaml配置文件
- 需要生成自动化打包脚本
- 批量创建多个应用的打包工程

## 工作流程

### 1. 准备工程目录

工程目录命名规范：`CI_ll_<package_id>`

```bash
# 例如: com.visualstudio.code -> CI_ll_com.visualstudio.code
project_dir="CI_ll_${package_id}"
mkdir -p "${project_dir}/templates/files_res"
mkdir -p "${project_dir}/scripts"

# 拷贝辅助脚本
cp "scripts/handle_special_paths.sh" "${project_dir}/scripts/"
chmod +x "${project_dir}/scripts/handle_special_paths.sh"
# 注意：不创建 src/ 目录，deb文件路径由用户执行脚本时指定
```

### 2. 生成 linglong.yaml

基于 `scripts/templates/` 目录下的模板生成，使用变量替换：

```bash
# 模板目录结构
# scripts/templates/
#   ├── linglong.yaml
#   └── files_res/
#       ├── share/applications/
#       ├── share/icons/
#       └── ...
```

```yaml
# templates/linglong.yaml
version: "${ll_version}"

package:
  id: ${package_id}
  name: "${app_name}"
  version: ${ll_version}
  kind: app
  architecture: ${ll_architecture}
  description: |
    ${description}

base: ${base}
runtime: ${runtime}

buildext:
  apt:
    depends:
      - ${depends}

command:
  - "${command}"

build: |
  # files/ 映射到 /usr/ 目录
  # files/bin/ -> /usr/bin/
  # files/share/ -> /usr/share/
  # files/lib/ -> /usr/lib/
  # 非 /usr 标准路径（如 /opt/uTools/）直接放到 files/ 下作为未归类目录
  mkdir -p ${prefix}/bin/ ${prefix}/share/ ${prefix}/lib/
  
  # 复制应用文件到 ${prefix}/ (files/) 根目录
  # pak_linyaps.sh 已处理路径转换：/opt/uTools/ -> files/uTools/
  cp -rf /project/binary/* ${prefix}/
  
  # 复制桌面文件、图标等资源
  cp -rf /project/files_res/* ${prefix}/
```

### 3. 生成 pak_linyaps.sh

参考 `CI_ll_com.visualstudio.code/pak_linyaps.sh` 模板：

```bash
#!/bin/bash
set -x

ll_id="${package_id}"

# Options
auto_clean=""
auto_push="${push}"  # 从CSV配置读取

repo_name="nightly"
repo_url="https://repo-dev.cicd.getdeepin.org"
push_account_user=""
push_account_passwd=""

init_global_data() {
  ARCH=$(uname -m)
  origin_version=""
  ll_version=""
  binary_arch=""
  linyaps_arch=""
  src_path=""
  output_dir=""
  build_tmp_dir=""

  project_root="$(dirname "$(readlink -f "$0")")"
  default_output_dir="${project_root}/bins"

  # 解析命令行参数
  COMMANDLINE="$@"
  for COMMAND in $COMMANDLINE; do
      key=$(echo $COMMAND | awk -F"=" '{print $1}')
      val=$(echo $COMMAND | awk -F"=" '{print $2}')
      case $key in
          --linyaps_arch) linyaps_arch="$val" ;;
          --origin_version) origin_version="$val" ;;
          --ll_version) ll_version="$val" ;;
          --src_path) src_path="$val" ;;
          --output_dir) output_dir="$val" ;;
          --build_tmp_dir) build_tmp_dir="$val" ;;
      esac
  done
  
  # 初始化构建缓存目录
  if [ -z "${build_tmp_dir}" ]; then
    # 未指定时使用临时目录
    build_tmp_dir=$(mktemp -d)
  else
    # 用户指定了目录，转换为绝对路径并创建（如不存在）
    build_tmp_dir=$(readlink -f "${build_tmp_dir}")
    if [ ! -d "${build_tmp_dir}" ]; then
      mkdir -p "${build_tmp_dir}" || {
        echo "错误: 无法创建构建缓存目录: ${build_tmp_dir}" >&2
        exit 1
      }
    fi
  fi

  # 架构映射
  case "${linyaps_arch}" in
    "x86_64")
      binary_arch="amd64"
      base_id="${base_id}"
      base_version="${base_version}"
      runtime_id="${runtime_id}"
      runtime_version="${runtime_version}"
      ;;
    "arm64")
      binary_arch="arm64"
      base_id="${base_id}"
      base_version="${base_version}"
      runtime_id="${runtime_id}"
      runtime_version="${runtime_version}"
      ;;
    *)
      echo "Unsupported architecture: ${linyaps_arch}"
      exit 1
      ;;
  esac
}

# ... 其他函数 (validate_version_format, generate_version_from_origin, etc.)

build_dir_init() {
  mkdir -p "${build_tmp_dir}/binary"
  cd "${build_tmp_dir}"
  cp -rf "${project_root}/templates/files_res" "${build_tmp_dir}"

  export prefix="\$PREFIX"
  export ll_version=${ll_version}
  export base_id=${base_id}
  export base_version=${base_version}
  export runtime_id=${runtime_id}
  export runtime_version=${runtime_version}
  export linyaps_arch=${linyaps_arch}

  cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"
}

build_pak() {
  binary_tmp_dir="${build_tmp_dir}/tmp"
  binary_dir="${build_tmp_dir}/binary/"

  # 解压deb包
  dpkg -x "${src_path}" "${binary_tmp_dir}/"
  
  # 创建binary目录结构
  # binary/ 目录的内容会复制到 files/ 根目录
  # files/ 映射到 /usr/，所以 files/bin/ -> /usr/bin/
  mkdir -p "${binary_dir}"
  
  # 调用特殊路径处理脚本
  # 处理 deb 中的文件路径转换，包括：
  # 1. /usr/ 下的内容直接复制到 binary/ (对应 files/)
  # 2. 非 /usr 标准路径（如 /opt/uTools/）直接放到 binary/ 下作为未归类目录
  #    例如：/opt/uTools/ -> binary/uTools/ (去掉 opt/ 层级)
  # 3. 支持包含空格、括号、中文、&、@、#、$ 等特殊字符的路径
  # 注意：此操作必须在所有软链动作之前完成，否则软链关系将被破坏
  "${project_root}/scripts/handle_special_paths.sh" "${binary_tmp_dir}" "${binary_dir}"
  
  # 创建 bin/ 目录用于存放可执行文件软链
  # 注意：此操作必须在特殊路径处理完成之后进行
  mkdir -p "${binary_dir}/bin"
  
  # 处理二进制文件软链
  # 在 files/bin/ 创建软链，指向实际二进制文件
  # 注意：此操作必须在所有文件复制和路径处理完成之后进行
  if [ -n "${binary_name}" ]; then
    # 在 binary/ 目录下查找二进制文件
    actual_binary=$(find "${binary_dir}" -type f -name "${binary_name}" -executable 2>/dev/null | head -n 1)
    
    if [ -n "${actual_binary}" ]; then
      rel_binary="${actual_binary#${binary_dir}}"
      
      cd "${binary_dir}/bin"
      ln -sf "../${rel_binary}" "${binary_name}"
      cd "${build_tmp_dir}"
    fi
  fi

  ll-builder build --skip-output-check
  building_status=$?
  if [ "${building_status}" = "0" ]; then
    echo "Building success!"
  else
    echo "Building failed!"
    exit 1
  fi
  ll-builder export --no-develop --layer

  binary_layer=$(find "${build_tmp_dir}" -type f -name "*binary.layer")
  if [ -z ${binary_layer} ]; then
    echo "Failed to build paks!"
    exit 1
  else
    mv "${binary_layer}" "${output_dir}"
  fi
}

main() {
    init_global_data "$@"
    data_regroup_check
    build_dir_init
    build_pak

    if [[ -n "${auto_push}" && ("${auto_push}" =~ ^[Tt][Rr][Uu][Ee]$) ]]; then
      push_dev
    fi

    if [ -z "${auto_clean}" ] || [ "${auto_clean}" = "TRUE" ]; then
      rm -rf "${build_tmp_dir}"
    fi
}

main "$@"
exit 0
```

### 4. CSV配置填充

从CSV读取配置并填充到模板：

```python
import csv

with open('config/packages.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        config = {
            'package_name': row['package_name'],
            'deb_path': row['deb_path'],
            'architecture': row['architecture'],
            'base': row['base'],
            'runtime': row['runtime'],
            'push': row['push']
        }
        # 使用config填充模板
```

## 模板变量说明

| 变量 | 来源 | 说明 |
|-----|------|------|
| `${package_id}` | deb包名转换 | 玲珑包ID，如 com.visualstudio.code |
| `${app_name}` | deb Description | 应用名称 |
| `${ll_version}` | 版本转换 | 玲珑格式版本 (x.x.x.x) |
| `${ll_architecture}` | 架构映射 | x86_64/aarch64 |
| `${base}` | CSV配置 | 基础运行时 |
| `${runtime}` | CSV配置 | 应用运行时 |
| `${push}` | CSV配置 | 是否自动推送 |
| `${command}` | desktop Exec | 启动命令（相对路径，如 `code`） |
| `${depends}` | deb Depends | 运行时依赖 |
| `${binary_name}` | CSV配置 | 二进制文件名（如 `utools`），用于创建软链 |

**binary_path 最佳实践：**
- `binary_path` 已废弃，新版本自动保持 deb 原有目录结构
- deb 中的 `/opt/uTools/` → `files/opt/uTools/`
- deb 中的 `/usr/share/code/` → `files/usr/share/code/`
- 二进制软链自动创建在 `files/bin/`，指向实际二进制文件

## 命令行参数说明

| 参数 | 必填 | 说明 |
|-----|------|------|
| `--src_path` | 是 | deb包完整路径 |
| `--output_dir` | 是 | 输出目录 |
| `--ll_version` | 二选一 | 玲珑格式版本 (x.x.x.x) |
| `--origin_version` | 二选一 | 原始版本号（自动转换为玲珑格式） |
| `--linyaps_arch` | 否 | 目标架构 (x86_64/arm64)，默认当前系统架构 |
| `--build_tmp_dir` | 否 | 构建缓存目录，未指定时使用临时目录 |

**注意：**
- `${command}` 应为相对路径的二进制名称（如 `code`），而非绝对路径
- 二进制文件由 `pak_linyaps.sh` 在构建时处理软链到 `${prefix}/bin/`

## 输出目录结构

```
CI_ll_<package_id>/
├── pak_linyaps.sh              # 打包脚本
├── scripts/                    # 辅助脚本目录
│   └── handle_special_paths.sh # 特殊路径处理脚本
└── templates/
    ├── linglong.yaml           # 玲珑配置模板
    └── files_res/              # 资源文件目录
        └── share/
            ├── applications/
            ├── icons/
            ├── appdata/
            └── ...
```

**注意：工程初始化时不包含任何源文件（deb包），deb路径由用户执行脚本时通过 `--src_path` 参数指定。**

## 二进制软链处理

`pak_linyaps.sh` 在构建时需要处理二进制软链，**使用相对路径**。

**目录结构说明：**
- `files/` 映射到玲瓏容器内的 `/usr/` 目录
- `files/bin/` → `/usr/bin/` (存放可执行文件软链)
- `files/share/` → `/usr/share/` (存放桌面文件、图标等)
- `files/lib/` → `/usr/lib/` (存放库文件)
- deb 中的非标准路径（如 `/opt/uTools/`）直接放到 `files/` 下作为未归类目录

**路径转换示例：**
```
deb 结构                    binary/ 结构              files/ 结构 (容器内 /usr/)
/opt/uTools/utools    →    uTools/utools       →    /usr/uTools/utools
/opt/uTools/resources →    uTools/resources    →    /usr/uTools/resources
/usr/bin/code         →    bin/code            →    /usr/bin/code
/usr/share/code/      →    share/code/         →    /usr/share/code/
```

**最终目录结构：**
```
files/
├── bin/
│   └── utools -> ../uTools/utools  # 软链指向实际二进制
├── share/
│   ├── applications/
│   └── icons/
├── lib/
└── uTools/          # 原 /opt/uTools/ 直接放到 files/ 下
    ├── utools       # 实际二进制文件
    └── resources/
```

```bash
build_pak() {
  binary_tmp_dir="${build_tmp_dir}/tmp"
  binary_dir="${build_tmp_dir}/binary/"

  # 解压deb包
  dpkg -x "${src_path}" "${binary_tmp_dir}/"
  
  # 创建binary目录结构
  # binary/ 目录的内容会复制到 files/ 根目录
  # files/ 映射到 /usr/，所以 files/bin/ -> /usr/bin/
  mkdir -p "${binary_dir}"
  
  # 调用特殊路径处理脚本
  # 处理 deb 中的文件路径转换，包括：
  # 1. /usr/ 下的内容直接复制到 binary/ (对应 files/)
  # 2. 非 /usr 标准路径（如 /opt/uTools/）直接放到 binary/ 下作为未归类目录
  #    例如：/opt/uTools/ -> binary/uTools/ (去掉 opt/ 层级)
  # 3. 支持包含空格、括号、中文、&、@、#、$ 等特殊字符的路径
  # 注意：此操作必须在所有软链动作之前完成，否则软链关系将被破坏
  "${project_root}/scripts/handle_special_paths.sh" "${binary_tmp_dir}" "${binary_dir}"
  
  # 创建 bin/ 目录用于存放可执行文件软链
  # 注意：此操作必须在特殊路径处理完成之后进行
  mkdir -p "${binary_dir}/bin"
  
  # 处理二进制文件软链
  # 在 files/bin/ 创建软链，指向实际二进制文件
  # 注意：此操作必须在所有文件复制和路径处理完成之后进行
  if [ -n "${binary_name}" ]; then
    # 在 binary/ 目录下查找二进制文件
    actual_binary=$(find "${binary_dir}" -type f -name "${binary_name}" -executable 2>/dev/null | head -n 1)
    
    if [ -n "${actual_binary}" ]; then
      rel_binary="${actual_binary#${binary_dir}}"
      
      cd "${binary_dir}/bin"
      ln -sf "../${rel_binary}" "${binary_name}"
      echo "Created symlink: bin/${binary_name} -> ../${rel_binary}"
      cd "${build_tmp_dir}"
    fi
  fi
}
```

**关键点：**
- `files/` 映射到 `/usr/`，不包含 `/opt`、`/var` 等目录
- 非 `/usr` 标准路径的内容直接放到 `files/` 根目录下
- `files/bin/` 只存放软链，实际应用文件存放在 `files/` 的其他子目录
- 软链使用相对路径（如 `../uTools/utools`），确保在玲瓏容器内正确解析
```

## 注意事项

1. 工程目录命名必须遵循 `CI_ll_<package_id>` 格式
2. `linglong.yaml` 中的变量使用 `${var}` 格式，由 `envsubst` 替换
3. `pak_linyaps.sh` 需要可执行权限 (`chmod +x`)
4. 多架构支持通过 `--linyaps_arch` 参数指定
5. base/runtime 从CSV配置读取，支持不同架构使用不同版本
6. **deb文件路径由用户执行时指定，不存储在工程目录内**
7. **二进制命令使用相对路径，由 `pak_linyaps.sh` 处理软链**
8. **特殊格式路径处理**：
   - 解压后可能目录命名方式不符合Linux规范，存在空格等需要额外转译的类型
   - `pak_linyaps.sh` 已使用 `find` + `IFS= read -r` 组合正确处理特殊字符路径
   - 支持的特殊字符包括：空格、括号、&、@、#、$、中文字符等
   - 可使用 `scripts/test_special_paths.sh` 验证特殊路径处理逻辑
9. **构建缓存目录可通过 `--build_tmp_dir` 参数指定，未指定时使用系统临时目录**
10. **自定义构建缓存目录时，目录不存在会自动创建；清理行为由 `auto_clean` 参数控制**
11. **files/ 映射到 /usr/**：`files/bin/` → `/usr/bin/`，非标准路径（如 `/opt/`）的内容直接放到 `files/` 根目录下

## 特殊格式路径处理

### 问题背景

deb 包解压后可能包含不符合 Linux 命名规范的路径，例如：
- 包含空格的目录名：`/opt/My App/`
- 包含特殊字符的目录名：`/opt/App (x86_64)/`
- 包含中文字符的目录名：`/opt/我的应用/`

### 解决方案

`pak_linyaps.sh` 使用以下技术正确处理特殊字符路径：

```bash
# 使用 find 命令遍历目录，避免 shell glob 的问题
find "${binary_tmp_dir}/${non_std_dir}" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r subdir; do
    if [ -d "${subdir}" ]; then
        subdir_name=$(basename "${subdir}")
        mkdir -p "${binary_dir}/${subdir_name}"
        cp -r "${subdir}/." "${binary_dir}/${subdir_name}/"
    fi
done
```

**关键技术点：**
1. 使用 `find` 命令而非 `for subdir in */` 遍历目录
2. 使用 `IFS= read -r` 防止 shell 对特殊字符进行解释
3. 所有路径变量使用双引号保护
4. 使用 `basename` 提取文件名，避免路径解析问题

### 验证测试

使用 `scripts/test_special_paths.sh` 验证特殊路径处理逻辑：

```bash
# 运行测试
./scripts/test_special_paths.sh

# 保留测试目录用于调试
./scripts/test_special_paths.sh /tmp/test --keep
```

测试覆盖以下场景：
- 空格字符（单空格、多空格）
- 特殊符号（括号、&、@、#、$）
- Unicode 字符（中文）
- 文件名和目录名中的特殊字符
- 软链创建的正确性

详细说明请参考 `scripts/README_test_special_paths.md`。