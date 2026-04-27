#!/bin/bash
# 特殊格式路径处理脚本
# 用于处理 deb 包解压后包含特殊字符路径的转换逻辑
#
# 功能：
# 1. 处理 /usr/ 下的标准目录
# 2. 处理 /opt/、/var/、/srv/ 等非标准路径
# 3. 标准化目录名（处理空格、特殊字符等）
# 4. 生成路径映射文件，供软链创建使用
#
# 用法：
#   handle_special_paths.sh <src_dir> <dest_dir> [--verbose]
#
# 参数：
#   src_dir   - deb 包解压后的源目录（如 binary_tmp_dir）
#   dest_dir  - 目标目录（如 binary_dir）
#   --verbose - 可选，显示详细日志
#
# 输出：
#   在 dest_dir 下生成 .path_mapping 文件，记录原始路径到标准化路径的映射
#   格式: 原始目录名|标准化目录名
#
# 示例：
#   handle_special_paths.sh /tmp/build/tmp /tmp/build/binary --verbose

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
VERBOSE=false
SRC_DIR=""
DEST_DIR=""
PATH_MAPPING_FILE=""

# 日志函数
log_info() {
	if [ "${VERBOSE}" = "true" ]; then
		echo -e "${BLUE}[INFO]${NC} $1" >&2
	fi
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
	echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

# 显示使用说明
usage() {
	echo "用法: $0 <src_dir> <dest_dir> [--verbose]"
	echo ""
	echo "参数:"
	echo "  src_dir   - deb 包解压后的源目录"
	echo "  dest_dir  - 目标目录"
	echo "  --verbose - 显示详细日志"
	echo ""
	echo "输出:"
	echo "  在 dest_dir 下生成 .path_mapping 文件"
	echo ""
	echo "示例:"
	echo "  $0 /tmp/build/tmp /tmp/build/binary"
	echo "  $0 /tmp/build/tmp /tmp/build/binary --verbose"
}

# 解析参数
parse_args() {
	if [ $# -lt 2 ]; then
		usage
		exit 1
	fi

	SRC_DIR="$1"
	DEST_DIR="$2"

	if [ "$3" = "--verbose" ]; then
		VERBOSE=true
	fi

	# 验证源目录存在
	if [ ! -d "${SRC_DIR}" ]; then
		log_error "源目录不存在: ${SRC_DIR}"
		exit 1
	fi

	# 创建目标目录
	mkdir -p "${DEST_DIR}"

	# 初始化路径映射文件
	PATH_MAPPING_FILE="${DEST_DIR}/.path_mapping"
	echo "# 原始目录名|标准化目录名" >"${PATH_MAPPING_FILE}"
	echo "# 生成时间: $(date)" >>"${PATH_MAPPING_FILE}"
}

# 标准化目录名
# 将空格和特殊字符替换为安全字符
normalize_dirname() {
	local original_name="$1"
	local normalized_name="${original_name}"

	# 检查是否需要标准化
	local needs_normalization=false

	# 检查空格
	if [[ "${normalized_name}" =~ [[:space:]] ]]; then
		needs_normalization=true
	fi

	# 检查特殊字符: ( ) & @ # $ ' " 等
	if [[ "${normalized_name}" =~ [\(\)\&\@\#\$\'\"] ]]; then
		needs_normalization=true
	fi

	if [ "${needs_normalization}" = "true" ]; then
		# 执行标准化
		# 1. 空格替换为下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/[[:space:]]/_/g')

		# 2. 特殊字符替换
		# ( ) 替换为空（去掉括号）
		normalized_name=$(echo "${normalized_name}" | sed 's/[(\)]//g')

		# & 替换为 _and_
		normalized_name=$(echo "${normalized_name}" | sed 's/&/_and_/g')

		# @ 替换为 _at_
		normalized_name=$(echo "${normalized_name}" | sed 's/@/_at_/g')

		# # 替换为 _hash_
		normalized_name=$(echo "${normalized_name}" | sed 's/#/_hash_/g')

		# $ 替换为 _dollar_
		normalized_name=$(echo "${normalized_name}" | sed 's/\$/_dollar_/g')

		# ' 和 " 替换为空
		normalized_name=$(echo "${normalized_name}" | sed "s/['\"]//g")

		# 清理连续下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/__*/_/g')

		# 清理首尾下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/^_//;s/_$//')

		log_info "  标准化: '${original_name}' -> '${normalized_name}'"
	fi

	echo "${normalized_name}"
}

# 记录路径映射
record_path_mapping() {
	local original_name="$1"
	local normalized_name="$2"

	if [ "${original_name}" != "${normalized_name}" ]; then
		echo "${original_name}|${normalized_name}" >>"${PATH_MAPPING_FILE}"
		log_info "  记录映射: ${original_name} -> ${normalized_name}"
	fi
}

# 处理 /usr/ 下的标准目录
process_usr_paths() {
	log_info "处理 /usr/ 目录..."

	if [ -d "${SRC_DIR}/usr" ]; then
		# 使用 rsync 复制，排除 share 和 lib 目录
		if command -v rsync &>/dev/null; then
			rsync -a "${SRC_DIR}/usr/" "${DEST_DIR}/" --exclude='share' --exclude='lib' 2>/dev/null || true
			log_info "使用 rsync 复制 /usr/ 内容"
		else
			# 如果没有 rsync，使用 cp
			if [ -d "${SRC_DIR}/usr/bin" ]; then
				mkdir -p "${DEST_DIR}/bin"
				cp -r "${SRC_DIR}/usr/bin/"* "${DEST_DIR}/bin/" 2>/dev/null || true
			fi
			if [ -d "${SRC_DIR}/usr/sbin" ]; then
				mkdir -p "${DEST_DIR}/sbin"
				cp -r "${SRC_DIR}/usr/sbin/"* "${DEST_DIR}/sbin/" 2>/dev/null || true
			fi
			if [ -d "${SRC_DIR}/usr/libexec" ]; then
				mkdir -p "${DEST_DIR}/libexec"
				cp -r "${SRC_DIR}/usr/libexec/"* "${DEST_DIR}/libexec/" 2>/dev/null || true
			fi
			log_info "使用 cp 复制 /usr/ 内容"
		fi
	else
		log_info "未找到 /usr/ 目录，跳过"
	fi
}

# 处理非标准路径（/opt、/var、/srv 等）
process_non_standard_paths() {
	log_info "处理非标准路径..."

	for non_std_dir in opt var srv; do
		if [ -d "${SRC_DIR}/${non_std_dir}" ]; then
			log_info "处理 /${non_std_dir}/ 目录..."

			# 使用进程替换避免子 shell 问题
			# find + IFS= read -r 组合可以正确处理空格、括号、中文等特殊字符
			while IFS= read -r subdir; do
				if [ -d "${subdir}" ]; then
					original_name=$(basename "${subdir}")

					# 检查是否包含特殊字符并记录日志
					if [[ "${original_name}" =~ [[:space:]] ]]; then
						log_warning "检测到空格字符: ${original_name}"
					fi
					if [[ "${original_name}" =~ [\(\)\&\@\#\$] ]]; then
						log_warning "检测到特殊字符: ${original_name}"
					fi

					log_info "  处理子目录: ${original_name}"

					# 标准化目录名
					normalized_name=$(normalize_dirname "${original_name}")

					# 记录路径映射
					record_path_mapping "${original_name}" "${normalized_name}"

					# 检查目标目录是否已存在（路径冲突检测）
					if [ -d "${DEST_DIR}/${normalized_name}" ]; then
						log_warning "目标目录已存在，将合并内容: ${normalized_name}"
					fi

					# 使用标准化后的目录名创建目标目录
					mkdir -p "${DEST_DIR}/${normalized_name}"
					cp -r "${subdir}/." "${DEST_DIR}/${normalized_name}/" 2>/dev/null || true

					log_info "  复制完成: ${original_name} -> ${normalized_name}"
				fi
			done < <(find "${SRC_DIR}/${non_std_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
		fi
	done
}

# 检测并报告潜在问题
detect_potential_issues() {
	log_info "检测潜在问题..."

	local issues_found=0

	# 检查目录名是否包含需要特殊处理的字符
	while IFS= read -r dir; do
		dirname=$(basename "${dir}")

		# 检查空格
		if [[ "${dirname}" =~ [[:space:]] ]]; then
			log_warning "目录包含空格: ${dir}"
			((issues_found++)) || true
		fi

		# 检查特殊字符
		if [[ "${dirname}" =~ [\(\)\&\@\#\$\'\"] ]]; then
			log_warning "目录包含特殊字符: ${dir}"
			((issues_found++)) || true
		fi
	done < <(find "${DEST_DIR}" -type d 2>/dev/null)

	# 检查文件名
	while IFS= read -r file; do
		filename=$(basename "${file}")

		if [[ "${filename}" =~ [[:space:]] ]]; then
			log_warning "文件包含空格: ${file}"
			((issues_found++)) || true
		fi

		if [[ "${filename}" =~ [\(\)\&\@\#\$\'\"] ]]; then
			log_warning "文件包含特殊字符: ${file}"
			((issues_found++)) || true
		fi
	done < <(find "${DEST_DIR}" -type f 2>/dev/null)

	if [ ${issues_found} -eq 0 ]; then
		log_info "未检测到潜在问题"
	else
		log_info "检测到 ${issues_found} 个潜在问题（已记录日志）"
	fi
}

# 主函数
main() {
	parse_args "$@"

	log_info "========================================="
	log_info "  特殊格式路径处理脚本"
	log_info "========================================="
	log_info "源目录: ${SRC_DIR}"
	log_info "目标目录: ${DEST_DIR}"
	log_info "========================================="

	# 步骤 1: 处理 /usr/ 标准路径
	process_usr_paths

	# 步骤 2: 处理非标准路径（包含标准化）
	process_non_standard_paths

	# 步骤 3: 检测潜在问题
	detect_potential_issues

	log_success "路径处理完成"

	# 返回统计信息
	local total_dirs=$(find "${DEST_DIR}" -type d 2>/dev/null | wc -l)
	local total_files=$(find "${DEST_DIR}" -type f 2>/dev/null | wc -l)
	log_info "处理结果: ${total_dirs} 个目录, ${total_files} 个文件"

	# 显示路径映射文件位置
	if [ -f "${PATH_MAPPING_FILE}" ]; then
		local mapping_count=$(grep -v "^#" "${PATH_MAPPING_FILE}" | grep -c "|" 2>/dev/null || echo "0")
		if [ "${mapping_count}" -gt 0 ]; then
			log_info "路径映射文件: ${PATH_MAPPING_FILE} (${mapping_count} 个映射)"
		fi
	fi
}

# 执行主函数
main "$@"
