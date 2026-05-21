#!/bin/bash

#=============================================================================
# pak_linyaps.sh - Tar Binary Package to Linglong Converter
#=============================================================================
# 基於 deb-linglong-packer 的 pak_linyaps.sh 模板，專門處理 tar 歸檔二進制包
# 差異於 deb 版：
#   - 使用 --src_path 替代 --deb_path 接受 tar 解压根目
#   - 使用 tar -xf 解壓而非 dpkg -x
#   - 調用 handle_special_paths.sh 處理路徑轉換（與 deb 版一致）
#=============================================================================

set -x

ll_id="${package_id}"

# 默認 base/runtime 配置
DEFAULT_BASE_ID="org.deepin.base"
DEFAULT_BASE_VERSION="25.2.2"
DEFAULT_RUNTIME_ID="org.deepin.runtime.dtk"
DEFAULT_RUNTIME_VERSION="25.2.2"

base_id="${DEFAULT_BASE_ID}"
base_version="${DEFAULT_BASE_VERSION}"
runtime_id="${DEFAULT_RUNTIME_ID}"
runtime_version="${DEFAULT_RUNTIME_VERSION}"

# 白名單配置文件路徑
whitelist_file=""

# Options
auto_clean=""
auto_push="${push}"
repo_name="nightly"
repo_url="https://repo-dev.cicd.getdeepin.org"
push_account_user=""
push_account_passwd=""

# Tar 專用參數
src_path=""
binary_name=""

init_global_data() {
	ARCH=$(uname -m)

	origin_version=""
	ll_version=""
	binary_arch=""
	linyaps_arch=""
	output_dir=""
	build_tmp_dir=""

	project_root="$(dirname "$(readlink -f "$0")")"
	default_output_dir="${project_root}/bins"

	COMMANDLINE="$@"
	for COMMAND in $COMMANDLINE; do
		key=$(echo $COMMAND | awk -F= '{print $1}')
		val=$(echo $COMMAND | awk -F= '{print $2}')

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
		--whitelist)
			whitelist_file="$val"
			;;
		--binary_name)
			binary_name="$val"
			;;
		--package_id)
			package_id="$val"
			;;
		--app_name)
			app_name="$val"
			;;
		--app_version)
			app_version="$val"
			;;
		--icon_path)
			icon_path="$val"
			;;
		esac
	done

	# 初始化構建緩存目錄
	if [ -n "${build_tmp_dir}" ]; then
		build_tmp_dir=$(readlink -f "${build_tmp_dir}")
	else
		build_tmp_dir=$(mktemp -d)
	fi

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

	validate_base_runtime
}

# 驗證 base/runtime 配置
validate_base_runtime() {
	local has_error=0
	local has_warning=0

	local fields=(
		"base_id:${base_id}:org[0-9a-z]*\\.[0-9a-z][0-9a-z.]*:基礎運行時ID"
		"base_version:${base_version}:版本號:基礎運行時版本"
		"runtime_id:${runtime_id}:org[0-9a-z]*\\.[0-9a-z][0-9a-z.]*:應用運行時ID"
		"runtime_version:${runtime_version}:版本號:應用運行時版本"
	)

	for field_def in "${fields[@]}"; do
		IFS=: read -r field_name field_value _ field_desc <<<"${field_def}"

		if [ -z "${field_value}" ]; then
			echo "錯誤: ${field_desc} (${field_name}) 為空！" >&2
			has_error=1
			continue
		fi

		if [[ "${field_value}" =~ ^\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?$ ]]; then
			echo "錯誤: ${field_desc} (${field_name}) 的值為變量引用 '${field_value}'" >&2
			has_error=1
			continue
		fi

		if [[ "${field_name}" == *_version ]]; then
			if [[ ! "${field_value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
				echo "錯誤: ${field_desc} (${field_name}='${field_value}') 版本格式不正確" >&2
				has_error=1
				continue
			fi
		fi

		echo "驗證通過: ${field_desc} (${field_name}='${field_value}')"
	done

	if [ "${has_error}" -eq 0 ]; then
		validate_base_runtime_whitelist
	fi
}

validate_base_runtime_whitelist() {
	if [ -z "${whitelist_file}" ]; then
		whitelist_file="${project_root}/config/base_runtime_whitelist.conf"
		if [ ! -f "${whitelist_file}" ]; then
			whitelist_file="${skill_root}/../config/base_runtime_whitelist.conf"
		fi
	fi

	if [ ! -f "${whitelist_file}" ]; then
		echo "警告: 白名單文件不存在: ${whitelist_file}" >&2
		return 0
	fi

	if grep -q "^${base_id}/${base_version}:${runtime_id}/${runtime_version}$" "${whitelist_file}"; then
		echo "白名單驗證通過: ${base_id}/${base_version}:${runtime_id}/${runtime_version}"
		return 0
	else
		echo "錯誤: base/runtime 組合不在白名單中" >&2
		echo "  當前: ${base_id}/${base_version}:${runtime_id}/${runtime_version}" >&2
		echo "  請查看 ${whitelist_file} 获取合規組合" >&2
		return 1
	fi
}

# 驗證 src_path 是否有效
validate_src_path() {
	if [ -z "${src_path}" ]; then
		echo "錯誤: --src_path 參數為空" >&2
		return 1
	fi

	if [ ! -f "${src_path}" ]; then
		echo "錯誤: --src_path 文件不存在: ${src_path}" >&2
		return 1
	fi

	echo "驗證通過: src_path='${src_path}'"
	return 0
}

# 驗證 binary_name 是否存在
validate_binary_name() {
	if [ -z "${binary_name}" ]; then
		echo "錯誤: --binary_name 參數為空" >&2
		return 1
	fi

	local binary_path="${src_path}/${binary_name}"
	if [ ! -f "${binary_path}" ]; then
		echo "錯誤: binary 不存在: ${binary_path}" >&2
		return 1
	fi

	if [ ! -x "${binary_path}" ]; then
		echo "錯誤: binary 不可執行: ${binary_path}" >&2
		return 1
	fi

	echo "驗證通過: binary_name='${binary_name}'"
	return 0
}

# 創建 wrapper 腳本（從 desktop Exec 提取 binary name）
create_wrapper_scripts() {
	local desktop_file="$1"
	local wrapper_dir="${project_root}/wrappers"

	mkdir -p "${wrapper_dir}"

	# 從 desktop Exec 提取 binary name
	local exec_line=$(grep "^Exec=" "${desktop_file}" 2>/dev/null | head -1)
	local exec_cmd="${exec_line#Exec=}"
	# 移除參數，只保留命令
	local main_binary=$(echo "${exec_cmd}" | awk '{print $1}')

	# 創建 wrapper 腳本
	local wrapper_path="${wrapper_dir}/${binary_name}.sh"
	cat > "${wrapper_path}" << 'WRAPPER_EOF'
#!/bin/bash
# Wrapper script for binary execution
# 由 pak_linyaps.sh 自動生成

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_DIR="${SCRIPT_DIR}/../../binary"

exec "${BINARY_DIR}/__BINARY_NAME__" "$@"
WRAPPER_EOF

	# 替換 __BINARY_NAME__ 為實際 binary name
	sed -i "s/__BINARY_NAME__/${binary_name}/g" "${wrapper_path}"
	chmod +x "${wrapper_path}"

	echo "已創建 wrapper: ${wrapper_path}"
}

# 生成 linglong.yaml
generate_linglong_yaml() {
	local output_dir="$1"
	local template_file="${project_root}/templates/linglong.yaml"

	if [ ! -f "${template_file}" ]; then
		echo "錯誤: 模板文件不存在: ${template_file}" >&2
		return 1
	fi

	# 設置默認值
	: "${ll_version:=1.0.0}"
	: "${ll_architecture:=amd64}"
	: "${description:=Binary application packaged with Linglong}"
	: "${base:=${base_id}/${base_version}}"
	: "${runtime:=${runtime_id}/${runtime_version}}"
	: "${extra_apt_deps:=}"

	# 計算 files_res 相對路徑
	local files_res_rel="files_res"
	local wrapper_script_path="./app/${binary_name}"

	# 使用 envsubst 替換變量
	envsubst '${package_id} ${app_name} ${ll_version} ${ll_architecture} ${description} ${base} ${runtime} ${extra_apt_deps} ${files_res_rel} ${wrapper_script_path}' \
		< "${template_file}" \
		> "${output_dir}/linglong.yaml"

	echo "已生成: ${output_dir}/linglong.yaml"
}

# 主構建流程
build_pak() {
	if ! validate_src_path; then
		return 1
	fi

	if ! validate_binary_name; then
		return 1
	fi

	# 創建臨時目錄
	local binary_tmp_dir="${build_tmp_dir}/binary_tmp"
	local binary_dir="${build_tmp_dir}/binary"
	local project_dir="${build_tmp_dir}/project"

	mkdir -p "${binary_tmp_dir}"
	mkdir -p "${binary_dir}"
	mkdir -p "${project_dir}"

	# 解壓 tar 到臨時目錄
	echo "解壓 tar: ${src_path}"
	tar -xf "${src_path}" -C "${binary_tmp_dir}/"

	# 調用特殊路徑處理腳本
	# 處理 tar 中的文件路徑轉換，包括：
	# 1. /usr/ 下的內容直接複製到 binary/ (對應 files/)
	# 2. 非 /usr 標準路徑（如 /opt/uTools/）直接放到 binary/ 下作為未歸類目錄
	#    例如：/opt/uTools/ -> binary/uTools/ (去掉 opt/ 層級)
	# 3. 支持包含空格、括號、中文、&、@、#、$ 等特殊字符的路徑
	# 注意：此操作必須在所有軟鏈動作之前完成，否則軟鏈關係將被破壞
	"${project_root}/scripts/handle_special_paths.sh" "${binary_tmp_dir}" "${binary_dir}"

	# 複製 templates 到項目目錄
	cp -rf "${project_root}/templates/"* "${project_dir}/"

	# 處理 desktop 文件
	local desktop_file=$(find "${binary_dir}" -name "*.desktop" -type f 2>/dev/null | head -1)
	if [ -n "${desktop_file}" ]; then
		# 更新 desktop Exec 指向 wrapper
		local exec_line=$(grep "^Exec=" "${desktop_file}" 2>/dev/null | head -1)
		local exec_cmd="${exec_line#Exec=}"
		local main_binary=$(echo "${exec_cmd}" | awk '{print $1}')

		# 創建 wrapper
		create_wrapper_scripts "${desktop_file}"

		# 更新 desktop Exec 為 wrapper 路徑
		local wrapper_name="${binary_name}.sh"
		sed -i "s|^Exec=.*|Exec=./app/${wrapper_name}|" "${desktop_file}"
	fi

	# 生成 linglong.yaml
	generate_linglong_yaml "${project_dir}"

	# 複製 files_res
	if [ -d "${project_root}/templates/files_res" ]; then
		cp -rf "${project_root}/templates/files_res" "${project_dir}/"
	fi

	# 移動 desktop 文件到 files_res
	if [ -n "${desktop_file}" ] && [ -f "${desktop_file}" ]; then
		mkdir -p "${project_dir}/files_res/share/applications"
		cp "${desktop_file}" "${project_dir}/files_res/share/applications/"
	fi

	# 輸出
	if [ -z "${output_dir}" ]; then
		output_dir="${default_output_dir}"
	fi
	mkdir -p "${output_dir}"

	local final_project_dir="${output_dir}/CI_ll_${package_id}"
	rm -rf "${final_project_dir}"
	mv "${project_dir}" "${final_project_dir}"

	echo "構建完成: ${final_project_dir}"
	echo "下一步: cd ${final_project_dir} && bash pak_linyaps.sh"
}

# 顯示幫助
show_help() {
	cat << 'HELP_EOF'
用法: pak_linyaps.sh [選項]

必填選項:
  --src_path <路徑>           tar 歸檔解压根目
  --package_id <ID>          玲瓏包 ID (如 com.example.app)
  --binary_name <名稱>       可執行檔案名

可選選項:
  --app_name <名稱>          應用顯示名稱
  --app_version <版本>       應用版本
  --icon_path <路徑>         icon 檔案路徑
  --ll_version <版本>        玲瓏包版本 (默認 1.0.0)
  --ll_architecture <架構>   目標架構 (amd64/arm64, 默認 amd64)
  --base_id <ID>             基礎运行时 ID (默認 org.deepin.base)
  --base_version <版本>      基礎運行時版本 (默認 25.2.2)
  --runtime_id <ID>          應用運行時 ID (默認 org.deepin.runtime.dtk)
  --runtime_version <版本>   應用運行時版本 (默認 25.2.2)
  --whitelist <路徑>         base/runtime 白名單配置文件
  --output_dir <路徑>        輸出目錄 (默認 ./bins)
  --build_tmp_dir <路徑>     構建緩存目錄

示例:
  pak_linyaps.sh \
    --src_path /tmp/app-extract \
    --package_id com.example.app \
    --binary_name myapp \
    --app_name "My Application" \
    --ll_version 1.0.0
HELP_EOF
}

# 解析命令行參數
parse_args() {
	if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
		show_help
		exit 0
	fi

	init_global_data "$@"
}

# 入口
main() {
	parse_args "$@"
	build_pak
}

main "$@"
