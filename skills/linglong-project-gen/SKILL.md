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
  mkdir -p ${prefix}/share/
  cp -rf /project/files_res/* ${prefix}/
  # 注意：bin目录和二进制软链由 pak_linyaps.sh 在构建时处理
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

  project_root="$(dirname "$(readlink -f "$0")")"
  build_tmp_dir=$(mktemp -d)
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
      esac
  done

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
  
  # 创建binary目录
  mkdir -p "${binary_dir}"
  
  # 复制应用文件（根据实际deb结构调整路径）
  rsync -avrP "${binary_tmp_dir}/${binary_path}/" "${binary_dir}/"
  
  # 创建bin目录并处理二进制软链（使用相对路径）
  mkdir -p "${binary_dir}/bin"
  
  # 进入bin目录，创建相对路径软链
  cd "${binary_dir}/bin"
  
  # 查找可执行文件并创建相对路径软链
  if [ -f "${binary_dir}/${binary_name}" ]; then
    rel_path="../${binary_name}"
    ln -sf "${rel_path}" "${binary_name}"
  fi
  
  cd "${build_tmp_dir}"

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

**注意：**
- `${command}` 应为相对路径的二进制名称（如 `code`），而非绝对路径
- 二进制文件由 `pak_linyaps.sh` 在构建时处理软链到 `${prefix}/bin/`

## 输出目录结构

```
CI_ll_<package_id>/
├── pak_linyaps.sh          # 打包脚本
└── templates/
    ├── linglong.yaml       # 玲珑配置模板
    └── files_res/          # 资源文件目录
        └── share/
            ├── applications/
            ├── icons/
            ├── appdata/
            └── ...
```

**注意：工程初始化时不包含任何源文件（deb包），deb路径由用户执行脚本时通过 `--src_path` 参数指定。**

## 二进制软链处理

`pak_linyaps.sh` 在构建时需要处理二进制软链，**使用相对路径**：

```bash
build_pak() {
  binary_tmp_dir="${build_tmp_dir}/tmp"
  binary_dir="${build_tmp_dir}/binary/"

  # 解压deb包
  dpkg -x "${src_path}" "${binary_tmp_dir}/"
  
  # 创建binary目录
  mkdir -p "${binary_dir}"
  
  # 复制应用文件（根据实际deb结构调整路径）
  rsync -avrP "${binary_tmp_dir}/${binary_path}/" "${binary_dir}/"
  
  # 创建bin目录并处理二进制软链（使用相对路径）
  # 参考 dependency_fixer.py 的实现：进入目标目录后创建相对路径软链
  mkdir -p "${binary_dir}/bin"
  
  # 进入bin目录，创建相对路径软链
  cd "${binary_dir}/bin"
  
  # 查找可执行文件并创建相对路径软链
  # 例如：将 ../code 软链到 bin/code
  if [ -f "${binary_dir}/${binary_name}" ]; then
    # 计算相对路径（从 bin/ 目录到上级目录的可执行文件）
    rel_path="../${binary_name}"
    ln -sf "${rel_path}" "${binary_name}"
  fi
  
  cd "${build_tmp_dir}"
}
```

**关键点：**
- 进入目标目录 (`cd "${binary_dir}/bin"`) 后创建软链
- 使用相对路径（如 `../${binary_name}`）而非绝对路径
- 这样确保软链在玲珑容器内仍然有效
```

## 注意事项

1. 工程目录命名必须遵循 `CI_ll_<package_id>` 格式
2. `linglong.yaml` 中的变量使用 `${var}` 格式，由 `envsubst` 替换
3. `pak_linyaps.sh` 需要可执行权限 (`chmod +x`)
4. 多架构支持通过 `--linyaps_arch` 参数指定
5. base/runtime 从CSV配置读取，支持不同架构使用不同版本
6. **deb文件路径由用户执行时指定，不存储在工程目录内**
7. **二进制命令使用相对路径，由 `pak_linyaps.sh` 处理软链**
8. 解压后可能目录命名方式不符合Linux规范，存在空格等需要额外转译的类型，需要在pak_linux设定修改为不需要转译的路径格式