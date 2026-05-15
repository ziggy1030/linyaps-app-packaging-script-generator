#!/bin/bash

set -x

ll_id="${package_id}"

# 默認 base/runtime 配置（可通過命令行參數覆蓋）
DEFAULT_BASE_ID="org.deepin.base"
DEFAULT_BASE_VERSION="25.2.2"
DEFAULT_RUNTIME_ID="org.deepin.runtime.dtk"
DEFAULT_RUNTIME_VERSION="25.2.2"

base_id="${DEFAULT_BASE_ID}"
base_version="${DEFAULT_BASE_VERSION}"
runtime_id="${DEFAULT_RUNTIME_ID}"
runtime_version="${DEFAULT_RUNTIME_VERSION}"

# Options
## Auto cleaning, default blank value means "true/TRUE"
auto_clean=""
## Auto push to specified repo, if success. Default blank value means "false/FALSE"
auto_push="${push}"

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

	COMMANDLINE="$@"
	for COMMAND in $COMMANDLINE; do
		key=$(echo $COMMAND | awk -F"=" '{print $1}')
		val=$(echo $COMMAND | awk -F"=" '{print $2}')

		case $key in
		--linyaps_arch)
			linyaps_arch="$val"
			;;
		--origin_version)
			origin_version="$val"
			;;
		--ll_version)
			ll_version="$val"
			;;
		--src_path)
			src_path="$val"
			;;
		--output_dir)
			output_dir="$val"
			;;
		--build_tmp_dir)
			build_tmp_dir="$val"
			;;
		--base_id)
			base_id="$val"
			;;
		--base_version)
			base_version="$val"
			;;
		--runtime_id)
			runtime_id="$val"
			;;
		--runtime_version)
			runtime_version="$val"
			;;
		esac
	done

	# 初始化構建緩存目錄
	if [ -n "${build_tmp_dir}" ]; then
		# 用戶指定了目錄，轉換為絕對路徑
		build_tmp_dir=$(readlink -f "${build_tmp_dir}")
	else
		# 未指定時使用臨時目錄
		build_tmp_dir=$(mktemp -d)
	fi

	# 確保目錄存在
	mkdir -p "${build_tmp_dir}" || {
		echo "錯誤: 無法創建構建緩存目錄: ${build_tmp_dir}" >&2
		exit 1
	}

	case "${linyaps_arch}" in
	"x86_64")
		binary_arch="amd64"
		;;
	"arm64")
		binary_arch="arm64"
		;;
	*)
		echo "Unsupported architecture: ${linyaps_arch}"
		exit 1
		;;
	esac

	# 驗證 base/runtime 配置
	validate_base_runtime
}

# 驗證 base/runtime 配置值
# 檢查項：
# 1. 值不為空
# 2. 值不是變量引用（如 ${var} 或 $var）
# 3. ID 格式符合反向域名規範（如 org.deepin.base）
# 4. Version 格式為 X.Y.Z 或 X.Y.Z.W
validate_base_runtime() {
	local has_error=0

	# 定義需要驗證的字段：名稱、值、ID正則、描述
	local fields=(
		"base_id:${base_id}:org[0-9a-z]*\\.[0-9a-z][0-9a-z.]*:基礎運行時ID"
		"base_version:${base_version}:版本號:基礎運行時版本"
		"runtime_id:${runtime_id}:org[0-9a-z]*\\.[0-9a-z][0-9a-z.]*:應用運行時ID"
		"runtime_version:${runtime_version}:版本號:應用運行時版本"
	)

	for field_def in "${fields[@]}"; do
		IFS=':' read -r field_name field_value _ field_desc <<<"${field_def}"

		# 檢查1：值不為空
		if [ -z "${field_value}" ]; then
			echo "錯誤: ${field_desc} (${field_name}) 為空！" >&2
			echo "  修復建議: 使用 --${field_name} 參數指定，或檢查腳本頂部默認值定義" >&2
			has_error=1
			continue
		fi

		# 檢查2：值不是變量引用（LLM 常見錯誤模式）
		# 檢測 ${var} 或 $var 形式的值
		if [[ "${field_value}" =~ ^\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?$ ]]; then
			echo "錯誤: ${field_desc} (${field_name}) 的值為變量引用 '${field_value}'，而非實際值！" >&2
			echo "  這通常是 LLM 生成時的錯誤，變量自引用會導致值為空。" >&2
			echo "  修復建議: 將 ${field_name} 設置為實際值，例如：" >&2
			case "${field_name}" in
			base_id)
				echo "    ${field_name}=\"org.deepin.base\"" >&2
				;;
			base_version)
				echo "    ${field_name}=\"25.2.2\"" >&2
				;;
			runtime_id)
				echo "    ${field_name}=\"org.deepin.runtime.dtk\"" >&2
				;;
			runtime_version)
				echo "    ${field_name}=\"25.2.2\"" >&2
				;;
			esac
			has_error=1
			continue
		fi

		# 檢查3：ID 格式驗證（僅對 *_id 字段）
		if [[ "${field_name}" == *_id ]]; then
			if [[ ! "${field_value}" =~ ^org[0-9a-z]*\.[0-9a-z][0-9a-z.]*$ ]]; then
				echo "警告: ${field_desc} (${field_name}='${field_value}') 格式可能不正確" >&2
				echo "  期望格式: org.xxx.xxx（反向域名格式）" >&2
				# 格式警告不阻止構建，僅提示
			fi
		fi

		# 檢查4：Version 格式驗證（僅對 *_version 字段）
		if [[ "${field_name}" == *_version ]]; then
			if [[ ! "${field_value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
				echo "錯誤: ${field_desc} (${field_name}='${field_value}') 版本格式不正確" >&2
				echo "  期望格式: X.Y.Z 或 X.Y.Z.W（如 25.2.2 或 23.1.0.1）" >&2
				has_error=1
				continue
			fi
		fi

		echo "驗證通過: ${field_desc} (${field_name}='${field_value}')"
	done

	if [ "${has_error}" -eq 1 ]; then
		echo "" >&2
		echo "========================================" >&2
		echo "base/runtime 配置驗證失敗！" >&2
		echo "請使用以下參數指定正確的值：" >&2
		echo "  --base_id=<值>        基礎運行時ID（如 org.deepin.base）" >&2
		echo "  --base_version=<值>   基礎運行時版本（如 25.2.2）" >&2
		echo "  --runtime_id=<值>     應用運行時ID（如 org.deepin.runtime.dtk）" >&2
		echo "  --runtime_version=<值> 應用運行時版本（如 25.2.2）" >&2
		echo "========================================" >&2
		exit 1
	fi

	echo "base/runtime 配置驗證通過"
	echo "  base: ${base_id}/${base_version}"
	echo "  runtime: ${runtime_id}/${runtime_version}"
}

validate_version_format() {
	local version="$1"
	if [[ -n "${version}" &&
		"${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		return 0
	else
		return 1
	fi
}

# 从 desktop 文件中自动提取 binary_name
# 核心思路：从所有 .desktop 文件的 Exec= 字段中提取二进制名称，
# 统计每个名称出现次数，返回出现次数最多的作为全局 binary_name
extract_binary_name_from_desktop() {
	local desktop_dir="$1"

	# 如果目录不存在，返回空
	if [ ! -d "${desktop_dir}" ]; then
		echo ""
		return 1
	fi

	# 临时文件存储所有提取的二进制名称
	local names_file
	names_file=$(mktemp)

	# 遍历所有 .desktop 文件
	while IFS= read -r file; do
		# 提取所有 Exec= 行
		while IFS= read -r line; do
			# 移除 "Exec=" 前缀
			cmd="${line#*=}"

			# 移除引号包裹的参数，保留第一个参数
			# 处理情况：
			#   Exec="/usr/lib/foo" --args  -> /usr/lib/foo
			#   Exec=/usr/lib/foo --args    -> /usr/lib/foo
			#   Exec="/usr/lib/foo"         -> /usr/lib/foo
			cmd=$(echo "$cmd" | sed 's/"[^"]*"/""/g' | awk '{print $1}')

			# 获取文件名（去掉路径）
			if [ -n "$cmd" ]; then
				basename "$cmd" 2>/dev/null
			fi
		done < <(grep "^Exec=" "$file" 2>/dev/null)
	done < <(find "${desktop_dir}" -name "*.desktop" -type f 2>/dev/null) >"$names_file"

	# 统计出现次数，返回最多的
	# sort -c 检查是否已排序，这里我们直接排序后统计
	local result
	result=$(sort "$names_file" | uniq -c | sort -rn | head -1 | awk '{print $2}')

	rm -f "$names_file"
	echo "$result"
}

generate_version_from_origin() {
	local origin_ver="$1"

	if [[ -z "${origin_ver}" ]]; then
		echo "错误: origin_version 为空" >&2
		return 1
	fi

	local cleaned_version="${origin_ver%%~*}"

	local version_parts=()
	local temp_version="${cleaned_version}"

	while [[ "${temp_version}" =~ ([0-9]+)(.*) ]]; do
		version_parts+=("${BASH_REMATCH[1]}")
		temp_version="${BASH_REMATCH[2]#*[!0-9]}"
	done

	if [[ ${#version_parts[@]} -lt 2 ]]; then
		echo "错误: origin_version 格式不正确，无法提取足够的数字部分" >&2
		return 1
	fi

	local major="${version_parts[0]:-0}"
	local minor="${version_parts[1]:-0}"
	local patch="${version_parts[2]:-0}"
	local build="${version_parts[3]:-0}"

	local generated_version="${major}.${minor}.${patch}.${build}"

	if validate_version_format "${generated_version}"; then
		echo "${generated_version}"
		return 0
	else
		echo "错误: 生成的版本号格式不正确: ${generated_version}" >&2
		return 1
	fi
}

version_check_regroup() {
	if validate_version_format "${ll_version}"; then
		echo "Using existing valid ll_version=${ll_version}"
	else
		echo "ll_version 格式不正确或为空，尝试使用 origin_version 生成"

		local generated_version
		if generated_version=$(generate_version_from_origin "${origin_version}"); then
			ll_version="${generated_version}"
			echo "Using origin_version=${origin_version} to generate ll_version=${ll_version}"
		else
			echo "无法从 origin_version 生成有效的版本号"
			exit 1
		fi
	fi

	echo "Final ll_version=${ll_version}"
}

validate_required_fields() {
	if [ -z "${src_path}" ]; then
		echo "请指定源包完整路径 src_path" >&2
		exit 1
	elif [ ! -f "${src_path}" ]; then
		echo "指定的源包文件不存在: ${src_path}" >&2
		exit 1
	fi

	if [ ! -d "${output_dir}" ]; then
		echo "输出目录不存在，尝试创建: ${output_dir}"
		if mkdir -p "${output_dir}"; then
			echo "成功创建输出目录: ${output_dir}"
		else
			echo "错误: 无法创建输出目录: ${output_dir}" >&2
			exit 1
		fi
	fi

	if [ -z "${ll_version}" ]; then
		echo "请单独指定 ll_version 或 提供正确的 origin_version" >&2
		exit 1
	fi

	if [ -z "${linyaps_arch}" ]; then
		linyaps_arch=$(uname -m)
	fi
}

data_regroup_check() {
	src_path=$(readlink -f "${src_path}")
	output_dir=$(readlink -f "${output_dir}")

	version_check_regroup
	validate_required_fields
}

build_dir_init() {
	## Generate linyaps building dir
	mkdir -p "${build_tmp_dir}/binary"
	cd "${build_tmp_dir}"
	cp -rf "${project_root}/files_res" \
		"${build_tmp_dir}"

	## 复制脚本到构建目录，供 linglong.yaml build 阶段使用
	mkdir -p "${build_tmp_dir}/scripts"
	cp -f "${project_root}/scripts/"*.sh "${build_tmp_dir}/scripts/"

	## Generate linyaps res
	## Envs for linglong.yaml
	export prefix="\$PREFIX"
	export ll_version=${ll_version}
	export base_id=${base_id}
	export base_version=${base_version}
	export runtime_id=${runtime_id}
	export runtime_version=${runtime_version}
	export linyaps_arch=${linyaps_arch}

	cat "${project_root}/linglong.yaml" |
		envsubst >"${build_tmp_dir}/linglong.yaml"
}

build_pak() {
	## Extract the binary package
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

	# 处理二进制文件：创建 wrapper 脚本而非软链
	# 在 files/bin/ 创建 wrapper 脚本，执行实际二进制文件
	# 同时创建 .orig 软链指向原始二进制，供 wrapper 使用
	# 注意：此操作必须在所有文件复制和路径处理完成之后进行
	if [ -z "${binary_name}" ]; then
		# 未指定 binary_name 时，自动从 desktop 文件中提取
		echo "binary_name not specified, auto-detecting from desktop files..."
		binary_name=$(extract_binary_name_from_desktop "${binary_dir}")
		if [ -n "${binary_name}" ]; then
			echo "Auto-detected binary_name: ${binary_name}"
		else
			echo "Warning: Could not auto-detect binary_name"
		fi
	fi

	if [ -n "${binary_name}" ]; then
		# 在 binary/ 目录下查找二进制文件
		actual_binary=$(find "${binary_dir}" -type f -name "${binary_name}" -executable 2>/dev/null | head -n 1)

		if [ -n "${actual_binary}" ]; then
			# 使用 readlink -f 解析实际文件路径，处理软链情况
			real_binary=$(readlink -f "${actual_binary}")

			# 计算相对于 binary/ 的路径
			# real_binary 示例: /path/to/binary/uTools/utools
			# binary_dir 示例: /path/to/binary/
			# rel_binary 示例: uTools/utools
			rel_binary="${real_binary#${binary_dir}}"

			# 创建 wrapper 脚本
			# wrapper 位于 bin/ 目录，使用相对路径直接指向原始二进制
			# 文件名使用 .wrapper 后缀，避免与原始二进制名冲突
			# 例如：bin/utools.wrapper 中的 exec 路径为 ../uTools/utools
			# 注意：使用 \$@ 而非 $@，防止 envsubst 替换
			cat >"${binary_dir}/bin/${binary_name}.wrapper" <<WRAPPER_EOF
#!/bin/bash
# Wrapper script generated by pak_linyaps.sh
# This wrapper ensures scripts using 'dirname \$0' work correctly
# by executing the original binary directly via relative path
# 使用 cd+pwd 解析 wrapper 自身的绝对路径，确保 $PATH 执行时也能正确工作
script_dir="\$(cd "\$(dirname "\$0")" && pwd)"
exec "${script_dir}/../${rel_binary}" "\$@"
WRAPPER_EOF

			chmod +x "${binary_dir}/bin/${binary_name}.wrapper"
			echo "Created wrapper script: bin/${binary_name}.wrapper -> ../${rel_binary}"
			echo "  (wrapper resolves absolute path first, then uses relative path)"

			# 更新 linglong.yaml 的 command 字段
			# 将 command 设置为 wrapper 脚本路径
			if [ -f "${build_tmp_dir}/linglong.yaml" ]; then
				sed -i "s|^\s*command:\s*.*|command: ${binary_name}.wrapper|" "${build_tmp_dir}/linglong.yaml"
				echo "Updated linglong.yaml command to: ${binary_name}.wrapper"
			fi

			# 更新 desktop 文件的 Exec= 字段
			# 将 Exec= 中的二进制路径替换为 wrapper 路径
			# 处理 files_res/ 和 binary/ 中的所有 desktop 文件
			for desktop_file in $(find "${build_tmp_dir}" -name "*.desktop" -type f 2>/dev/null); do
				if grep -q "Exec=.*${binary_name}" "${desktop_file}"; then
					# 替换 Exec= 行中的二进制路径为 wrapper 路径
					# 保留 Exec= 后的参数（如 %F, %U 等）
					sed -i "s|Exec=[^ ]*${binary_name}[^ ]*|Exec=/opt/apps/${ll_id}/files/bin/${binary_name}.wrapper|g" "${desktop_file}"
					echo "Updated Exec= in: ${desktop_file}"
				fi
			done
		else
			echo "Warning: Binary '${binary_name}' not found in ${binary_dir}"
		fi
	fi

	# 第一步去重：删除 binary/ 中与 files_res/ 内容重复的 desktop 文件
	# 在 ll-builder build 之前执行，避免重复文件进入最终包
	# 参数说明：
	#   - 第一个参数：待去重的目标目录 (binary/)
	#   - --reference-dir：参考目录 (files_res/)
	# 效果：删除 binary/ 中与 files_res/ 内容相同的 desktop 文件
	"${project_root}/scripts/dedup_desktop_files.sh" "${build_tmp_dir}/binary" --reference-dir "${build_tmp_dir}/files_res"

	# 第二步去重：对 files_res/ 内部的 desktop 文件进行去重（保底检测）
	# 避免相同内容的 desktop 文件重复打包
	"${project_root}/scripts/dedup_desktop_files.sh" "${build_tmp_dir}/files_res"

	# 验证并修复嵌套 bin/ 路径问题
	# 检测 binary/bin/bin/ 嵌套问题并自动修复
	"${project_root}/scripts/validate_bin_nesting.sh" "${binary_dir}" --fix

	## Building & Exporting
	ll-builder build --skip-output-check
	building_status=$?
	if [ "${building_status}" = "0" ]; then
		echo "Building success ! "
	else
		echo "Building failed ! "
		exit 1
	fi
	ll-builder export --no-develop --layer

	## Check layers
	binary_layer=$(find "${build_tmp_dir}" -type f \
		-name "*binary.layer")
	if [ -z ${binary_layer} ]; then
		echo "Failed to build paks !"
		exit 1
	else
		mv "${binary_layer}" "${output_dir}"
	fi
}

push_dev() {
	## Check data
	export LINGLONG_USERNAME="${LINGLONG_USERNAME:-$push_account_user}"
	export LINGLONG_PASSWORD="${LINGLONG_PASSWORD:-$push_account_passwd}"
	for data in repo_name repo_url LINGLONG_USERNAME LINGLONG_PASSWORD; do
		if [ -z "${!data}" ]; then
			echo "Error: Required '$data' is missing"
			exit 1
		fi
	done
	## Push
	cd "${build_tmp_dir}"
	ll-builder push --repo-name ${repo_name} --repo-url ${repo_url}
}

main() {
	init_global_data "$@"
	data_regroup_check
	build_dir_init
	build_pak

	## Auto push
	if [[ -n "${auto_push}" && ("${auto_push}" =~ ^[Tt][Rr][Uu][Ee]$ ||
		"${auto_push}" =~ ^[Tt]$) ]]; then
		push_dev
	else
		echo "Skip auto push due to empty or false value of auto_push"
	fi

	#Clean up the environment
	rm -fr ${base_name}

	## Clean up
	if [ -z "${auto_clean}" ] || [ "${auto_clean}" = "TRUE" ] || [ "${auto_clean}" = "true" ]; then
		rm -rf "${build_tmp_dir}"
	fi
}

main "$@"
exit 0
