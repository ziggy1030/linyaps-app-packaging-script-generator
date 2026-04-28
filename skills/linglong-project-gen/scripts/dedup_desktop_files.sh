#!/bin/bash
# Desktop 文件去重脚本
# 用于去除 files_res/share/applications/ 目录下相同内容的 desktop 文件
#
# 功能：
# 1. 扫描指定目录下的所有 .desktop 文件
# 2. 计算每个文件的 MD5 哈希值
# 3. 按哈希值分组，相同内容的文件只保留一份
# 4. 删除重复文件，输出去重报告
#
# 用法：
#   dedup_desktop_files.sh <files_res_dir> [--verbose]
#
# 参数：
#   files_res_dir - files_res 目录路径（如 /project/files_res）
#   --verbose     - 可选，显示详细日志
#
# 示例：
#   dedup_desktop_files.sh /project/files_res
#   dedup_desktop_files.sh /project/files_res --verbose

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
VERBOSE=false
FILES_RES_DIR=""
STAT_TOTAL_FILES=0
STAT_UNIQUE_FILES=0
STAT_DUPLICATE_FILES=0

# 日志函数
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
	echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 显示使用说明
usage() {
	echo "用法: $0 <files_res_dir> [--verbose]"
	echo ""
	echo "参数:"
	echo "  files_res_dir - files_res 目录路径"
	echo "  --verbose     - 显示详细日志"
	echo ""
	echo "示例:"
	echo "  $0 /project/files_res"
	echo "  $0 /project/files_res --verbose"
}

# 解析参数
parse_args() {
	if [ $# -lt 1 ]; then
		usage
		exit 1
	fi

	FILES_RES_DIR="$1"

	if [ "$2" = "--verbose" ]; then
		VERBOSE=true
	fi

	# 验证目录存在
	if [ ! -d "${FILES_RES_DIR}" ]; then
		log_error "目录不存在: ${FILES_RES_DIR}"
		exit 1
	fi
}

# 去重函数
dedup_desktop_files() {
	local apps_dir="${FILES_RES_DIR}/share/applications"

	# 检查 applications 目录是否存在
	if [ ! -d "${apps_dir}" ]; then
		log_info "applications 目录不存在，跳过去重"
		return 0
	fi

	# 查找所有 desktop 文件
	local desktop_files
	desktop_files=$(find "${apps_dir}" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null || true)

	if [ -z "${desktop_files}" ]; then
		log_info "未找到 desktop 文件，跳过去重"
		return 0
	fi

	# 转换为数组
	local -a files_array
	readarray -t files_array <<<"${desktop_files}"
	STAT_TOTAL_FILES=${#files_array[@]}

	if [ ${STAT_TOTAL_FILES} -eq 0 ]; then
		log_info "未找到 desktop 文件，跳过去重"
		return 0
	fi

	log_info "扫描到 ${STAT_TOTAL_FILES} 个 desktop 文件"

	# 关联数组：哈希值 -> 第一个文件路径
	local -A hash_to_file
	# 数组：需要删除的文件
	local -a files_to_delete

	# 遍历所有 desktop 文件
	for desktop_file in "${files_array[@]}"; do
		# 计算 MD5 哈希（忽略末尾空白符）
		local file_hash
		file_hash=$(md5sum "${desktop_file}" | awk '{print $1}')

		if [ -z "${file_hash}" ]; then
			log_warning "无法计算文件哈希: ${desktop_file}"
			continue
		fi

		if [ "${VERBOSE}" = "true" ]; then
			log_info "处理: $(basename "${desktop_file}") -> ${file_hash}"
		fi

		# 检查是否已存在相同哈希的文件
		if [ -z "${hash_to_file[${file_hash}]}" ]; then
			# 首次遇到此哈希，保留
			hash_to_file[${file_hash}]="${desktop_file}"
			STAT_UNIQUE_FILES=$((STAT_UNIQUE_FILES + 1))
			if [ "${VERBOSE}" = "true" ]; then
				log_info "  保留 (新): $(basename "${desktop_file}")"
			fi
		else
			# 重复文件，记录待删除
			files_to_delete+=("${desktop_file}")
			STAT_DUPLICATE_FILES=$((STAT_DUPLICATE_FILES + 1))
			log_warning "发现重复内容: $(basename "${desktop_file}") 与 $(basename "${hash_to_file[${file_hash}]}") 相同"
			if [ "${VERBOSE}" = "true" ]; then
				log_info "  将删除: $(basename "${desktop_file}")"
			fi
		fi
	done

	# 删除重复文件
	if [ ${#files_to_delete[@]} -gt 0 ]; then
		log_info "开始删除 ${#files_to_delete[@]} 个重复文件..."
		for file_to_delete in "${files_to_delete[@]}"; do
			rm -f "${file_to_delete}"
			if [ "${VERBOSE}" = "true" ]; then
				log_info "  已删除: $(basename "${file_to_delete}")"
			fi
		done
	fi

	# 输出统计
	echo ""
	log_success "Desktop 文件去重完成"
	log_info "  总文件数: ${STAT_TOTAL_FILES}"
	log_info "  唯一文件: ${STAT_UNIQUE_FILES}"
	log_info "  删除重复: ${STAT_DUPLICATE_FILES}"

	if [ ${STAT_DUPLICATE_FILES} -gt 0 ]; then
		log_warning "已去除 ${STAT_DUPLICATE_FILES} 个重复 desktop 文件"
	fi
}

# 主函数
main() {
	parse_args "$@"
	dedup_desktop_files
}

# 执行主函数
main "$@"
