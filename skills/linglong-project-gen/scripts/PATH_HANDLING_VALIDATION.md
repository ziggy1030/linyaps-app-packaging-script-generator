# 路徑處理驗證工具

## 概述

本目錄包含兩個相關的腳本：

1. **`handle_special_paths.sh`** - 獨立的特殊路徑處理腳本，用於處理 deb 包解壓後包含特殊字符路徑的轉換邏輯
2. **`validate_path_handling.sh`** - 驗證工具，用於測試特殊路徑處理邏輯的正確性

### 腳本關係

```
pak_linyaps.sh (主構建腳本)
    └── 調用 handle_special_paths.sh (路徑處理)
            └── 被 validate_path_handling.sh 測試
```

## handle_special_paths.sh

### 功能

處理 deb 包解壓後的文件路徑轉換，包括：

1. 處理 `/usr/` 下的標準目錄
2. 處理 `/opt/`、`/var/`、`/srv/` 等非標準路徑
3. 支持包含空格、括號、中文、&、@、#、$ 等特殊字符的路徑

### 用法

```bash
# 基本用法
./handle_special_paths.sh <src_dir> <dest_dir>

# 顯示詳細日誌
./handle_special_paths.sh <src_dir> <dest_dir> --verbose
```

### 參數說明

| 參數 | 說明 |
|------|------|
| `src_dir` | deb 包解壓後的源目錄 |
| `dest_dir` | 目標目錄 |
| `--verbose` | 可選，顯示詳細日誌 |

### 集成方式

在 `pak_linyaps.sh` 中，解壓 deb 包後自動調用：

```bash
# 解压deb包
dpkg -x "${src_path}" "${binary_tmp_dir}/"

# 调用特殊路径处理脚本
"${project_root}/scripts/handle_special_paths.sh" "${binary_tmp_dir}" "${binary_dir}"
```

## validate_path_handling.sh

該腳本用於驗證玲瓏打包腳本中特殊格式路徑處理邏輯的正確性。它調用 `handle_special_paths.sh` 進行實際處理，並驗證結果。

## 測試場景

腳本涵蓋了以下特殊字符路徑的測試場景：

### 1. 空格字符
- **目錄名包含空格**: `My App`
- **文件名包含空格**: `my binary`
- **多個連續空格**: `App  With  Spaces`

### 2. 特殊符號
- **括號**: `App (x86_64)`
- **& 符號**: `App&Co`
- **@ 符號**: `app@latest`
- **# 符號**: `app-v1.0#stable`
- **$ 符號**: `app$special`

### 3. Unicode 字符
- **中文目錄名**: `我的應用`

## 使用方法

### 基本用法

```bash
# 使用自動創建的臨時目錄
./validate_path_handling.sh

# 指定臨時目錄
./validate_path_handling.sh /tmp/my_test_dir

# 保留測試目錄（用於調試）
./validate_path_handling.sh /tmp/my_test_dir --keep
```

### 參數說明

| 參數 | 說明 |
|------|------|
| `臨時目錄` | 可選，指定測試用的臨時目錄，默認自動創建 |
| `--keep` | 保留測試目錄，不自動清理 |

## 測試流程

腳本執行以下測試步驟：

1. **創建測試結構** - 模擬 deb 包解壓後的目錄結構
2. **檢測潛在問題** - 掃描並報告包含特殊字符的路徑
3. **路徑處理** - 模擬 `pak_linyaps.sh` 的路徑轉換邏輯
4. **驗證結果** - 檢查目標目錄結構是否正確
5. **軟鏈測試** - 驗證二進制文件軟鏈的創建
6. **生成報告** - 輸出測試統計信息

## 測試結果示例

```
=========================================
           測試報告
=========================================
總測試數: 11
通過: 11
失敗: 0
通過率: 100.00%
=========================================
所有測試通過！
```

## 路徑處理邏輯

### 標準路徑處理

- `/usr/` 下的內容直接複製到 `binary/` 目錄
- 例如：`/usr/bin/code` → `binary/bin/code`

### 非標準路徑處理

- `/opt/`、`/var/`、`/srv/` 等非標準路徑的內容直接放到 `binary/` 根目錄
- 例如：`/opt/uTools/` → `binary/uTools/`

### 特殊字符處理

`handle_special_paths.sh` 使用以下技術處理特殊字符：

1. **使用 `find` 命令** - 正確處理包含特殊字符的文件名
2. **使用 `IFS=` 和 `-r` 選項** - 防止 shell 對特殊字符進行解釋
3. **使用引號保護** - 確保路徑中的空格和特殊字符被正確傳遞

```bash
# 正確的處理方式（在 handle_special_paths.sh 中）
find "${src_dir}/${non_std_dir}" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r subdir; do
    subdir_name=$(basename "${subdir}")
    mkdir -p "${dest_dir}/${subdir_name}"
    cp -r "${subdir}/." "${dest_dir}/${subdir_name}/"
done
```

## 軟鏈處理

對於包含特殊字符的目錄中的二進制文件，腳本會創建相對路徑的軟鏈：

```bash
# 創建軟鏈
cd "${binary_dir}/bin"
ln -sf "../My App/myapp" "myapp"
```

這確保了在玲瓏容器內，軟鏈能夠正確指向實際的二進制文件。

## 已知問題與解決方案

### 問題 1: rsync 不可用

**症狀**: 系統提示 `rsync: command not found`

**解決方案**: 腳本已改用 `cp -r` 命令作為備選方案

### 問題 2: 特殊字符導致腳本失敗

**症狀**: 包含 `$`、`(`、`)` 等字符的路徑導致腳本執行失敗

**解決方案**: 
- 使用 `find` 命令配合 `IFS= read -r` 處理文件名
- 所有路徑變量使用雙引號保護
- 使用 `basename` 命令提取文件名，避免路徑解析問題

## 最佳實踐

1. **總是使用引號** - 包含路徑的變量應該始終用雙引號包裹
2. **使用 find 而非 glob** - 對於包含特殊字符的文件名，使用 `find` 比 `*` 更可靠
3. **使用相對路徑軟鏈** - 確保軟鏈在不同環境下都能正確解析
4. **測試極端情況** - 包括空格、中文、特殊符號等各種情況

## 相關文件

- `handle_special_paths.sh` - 獨立的特殊路徑處理腳本
- `pak_linyaps.sh` - 主構建腳本，自動調用 `handle_special_paths.sh`
- `validate_path_handling.sh` - 測試驗證腳本
- `SKILL.md` - 玲瓏工程生成技能文檔
- `linglong.yaml` - 玲瓏配置文件模板

## 更新日誌

### 2026-04-27 (v2)
- **重構**: 將路徑處理邏輯提取為獨立的 `handle_special_paths.sh` 腳本
- **集成**: `pak_linyaps.sh` 現在自動調用 `handle_special_paths.sh`
- **優化**: 避免智能體忽略路徑處理步驟的問題
- **改進**: 確保軟鏈創建在路徑處理完成後執行

### 2026-04-27 (v1)
- 創建初始版本
- 支持 10 種特殊字符路徑測試場景
- 添加軟鏈創建測試
- 所有測試通過率 100%
