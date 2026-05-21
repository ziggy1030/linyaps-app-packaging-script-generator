# tar-linyaps Skill

## 功能說明

將 Linux binary release tar 歸檔包轉換為玲瓏（ Linglong）應用便捷打包腳本。

## 觸發詞

```
convert tar, tar binary, tar package, 轉換 tar, tar 打包
```

## 必要參數

| 參數 | 說明 | 範例 |
|------|------|------|
| `tar_path` | tar 歸檔路徑（必填）| `/path/to/app.tar.zst` |
| `binary_name` | 可執行檔案名（可選）| `app.bin` |
| `app_name` | 應用名稱（必填）| `My Application` |
| `app_version` | 版本號（可選）| `1.0.0` |
| `icon_url` | icon 下載 URL（可選）| `https://example.com/icon.png` |

## 工作流程

### Step 1: 驗證並解壓 tar 歸檔

```bash
# 驗證 tar 文件格式
file "${tar_path}"

# 在臨時目錄解壓
extract_dir=$(mktemp -d)
tar -xf "${tar_path}" -C "${extract_dir}"
```

### Step 2: 檢測源碼包

解壓後立即檢查是否存在以下文件，判斷是否為源碼包：

- `CMakeLists.txt`
- `Makefile`
- `configure.ac`
- `*.spec`（RPM spec）
- `meson.build`
- `setup.py`

**若為源碼包**：終止並提示用戶這是源碼包，不適用此工具。

**若為二進制包**：繼續 Step 3。

### Step 3: 收集用戶參數

- 若用戶提供了 `binary_name`，直接進入 Step 6
- 若用戶未提供 `binary_name`，進入 Step 4 掃描 desktop

### Step 4: 掃描 desktop 文件

```bash
desktop_files=$(find "${extract_dir}" -name "*.desktop" -type f 2>/dev/null)
```

- **有 desktop 文件且 `Exec=` 有值**：
  - 提取 `Exec=` 中的 binary name（**優先級高於自動掃描**）
  - 提取 `Icon=` 欄位中的 icon 路徑
  - 複製 desktop 到 `files_res/share/applications/`
  - 直接進入 Step 6（跳過 Step 5 自動掃描）
- **有 desktop 文件但 `Exec=` 無值**：
  - 提取 `Icon=` 欄位中的 icon 路徑
  - 複製 desktop 到 `files_res/share/applications/`
  - 進入 Step 5 自動掃描 binary name
- **無 desktop 文件**：
  - 進入 Step 5 自動掃描 binary name
  - 後續根據 `app_name`、`binary_name`、`app_version` 生成 desktop 文件
  - 驗證 `binary_name` 是否存在並可執行
  - 調用 `desktop-file-validate` 驗證合規性

### Step 5: 掃描可執行檔（當無 desktop Exec 時）

```bash
"${skill_root}/scripts/scan_executables.sh" "${extract_dir}"
```

- 掃描解压根目所有可執行非 `*.so` 文件
- 通過 `file` 命令檢測 ELF 二進制架構，與 `uname -m` 比較，架構不匹配的自動跳過
- 每個 binary timeout 15s 運行測試
- 能長期運行者判定為候選 binary name
- 輸出候選列表，讓用戶確認

### Step 6: Icon 處理（XDG 規範）

參考 `linglong-fix` 技能的 `fix_icon_directory_structure` 和 `fix_desktop_icon` 邏輯，
確保圖標目錄結構和 desktop `Icon=` 欄位符合 XDG 圖標主題規範。

#### 6a. 定位圖標文件

**優先級**：

1. **從 desktop `Icon=` 欄位提取**：解析 Icon 值，在 tar 解壓目錄中查找對應文件
2. **在 tar 包整個解壓目錄中查找**：`find "${extract_dir}" -type f \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \)`
3. **用戶提供 `--icon-url`**：下載圖標文件

**失敗處理**：以上均未找到有效 icon → **任務終止並報錯**

#### 6b. 按 XDG 規範放置圖標

將找到的圖標文件放置到符合 XDG 圖標主題規範的目錄結構中：

```
files_res/share/icons/hicolor/
├── scalable/apps/        ← SVG 圖標
├── 128x128/apps/         ← PNG 圖標（默認尺寸）
├── 256x256/apps/
└── ...
```

**放置規則**（參考 `linglong-fix` 的 `fix_icon_directory_structure`）：

| 格式 | 目標目錄 | 說明 |
|------|---------|------|
| `.svg` | `hicolor/scalable/apps/` | 矢量圖標統一放入 scalable |
| `.png` | `hicolor/<size>/apps/` | 根據實際尺寸或文件名判斷 |
| `.xpm` | `hicolor/<size>/apps/` | 同 PNG 處理 |

**尺寸判斷**：
- 優先使用 `file` 命令讀取實際尺寸（如 `file icon.png` → `PNG image data, 256 x 256`）
- 其次用 `identify`（ImageMagick）讀取尺寸
- 無法判斷時默認放入 `128x128/apps/`

**XDG 標準尺寸**：`16x16`, `22x22`, `24x24`, `32x32`, `48x48`, `64x64`, `128x128`, `256x256`, `512x512`, `scalable`

#### 6c. 修正 desktop Icon= 欄位

參考 `linglong-fix` 的 `fix_desktop_icon`，將 desktop 文件的 `Icon=` 欄位統一改為 **XDG 規範名稱**：

- **去除路徑前綴**：無論是絕對路徑還是相對路徑
- **去除擴展名**：只保留圖標名稱（stem）

| 原始值 | 修正後 | 說明 |
|--------|--------|------|
| `Icon=/usr/share/icons/hicolor/256x256/apps/myapp.png` | `Icon=myapp` | 絕對路徑 → 名稱 |
| `Icon=./icons/myapp.svg` | `Icon=myapp` | 相對路徑 → 名稱 |
| `Icon=myapp` | `Icon=myapp` | 已符合規範，不變 |

**注意**：此步驟在 Step 4 複製 desktop 文件之後執行，確保 desktop 文件中的 Icon 欄位與實際圖標文件名一致。

### Step 7: 生成玲瓏工程

調用 `linglong-project-gen` 子技能創建工程：

```bash
# 工程目錄命名
project_dir="CI_ll_${package_id}"
mkdir -p "${project_dir}/templates/files_res"
mkdir -p "${project_dir}/scripts"
mkdir -p "${project_dir}/config"

# 拷貝模板
cp "${skill_root}/templates/pak_linyaps.sh" "${project_dir}/"
chmod +x "${project_dir}/pak_linyaps.sh"
cp "${skill_root}/templates/linglong.yaml" "${project_dir}/templates/"

# 拷貝掃描腳本
cp "${skill_root}/scripts/scan_executables.sh" "${project_dir}/scripts/"
chmod +x "${project_dir}/scripts/scan_executables.sh"

# 拷貝路徑處理腳本（與 deb 版共用，處理 /usr/、/opt/ 等路徑轉換 + 特殊字符標準化）
cp "${skill_root}/../linglong-project-gen/templates/scripts/handle_special_paths.sh" "${project_dir}/scripts/"
chmod +x "${project_dir}/scripts/handle_special_paths.sh"

# 拷貝白名單配置
cp "${skill_root}/../config/base_runtime_whitelist.conf" "${project_dir}/config/"

# 拷貝 desktop 文件
cp "${desktop_file}" "${project_dir}/templates/files_res/share/applications/"

# 拷貝 icon 文件
if [ -n "${icon_file}" ] && [ -f "${icon_file}" ]; then
  mkdir -p "${project_dir}/templates/files_res/share/icons/hicolor/"
  cp "${icon_file}" "${project_dir}/templates/files_res/share/icons/hicolor/"
fi
```

**注意**：
- `package_id` 從 `app_name` 推導（反向域名格式，如 `com.example.app`）
- `command` 欄位占位符由 `pak_linyaps.sh` 在構建時自動處理
- **禁止**在資源收集階段手動修改 desktop 文件的 `Exec=` 欄位

---

## 職責邊界

| 階段 | 負責方 | 操作 |
|------|--------|------|
| Step 2: 源碼包檢測 | tar-linyaps skill | 解壓後立即檢測，源碼包則終止 |
| Step 4: Desktop 掃描 | tar-linyaps skill | 提取 Exec= binary name（優先級高於自動掃描） |
| Step 5: 自動掃描 | tar-linyaps skill | 僅在無 desktop Exec 時掃描可執行檔 |
| Step 4/5: 資源收集 | tar-linyaps skill | 只修復 Icon 路徑，**不修改** Exec 欄位 |
| 構建時 | pak_linyaps.sh | 創建 wrapper 腳本 |
| 構建時 | pak_linyaps.sh | 更新 linglong.yaml 的 command |
| 構建時 | pak_linyaps.sh | 更新 desktop 的 Exec |

---

## 約束條件

1. **不要過度分析結構**：只需定位 binary name，pak_linyaps.sh 會處理路徑解析
2. **Icon 嚴格驗證**：從 desktop Icon 欄位提取，支持 URL 導入，無有效 icon 時終止
3. **Wrapper 機制**：Exec 和 command 由 pak_linyaps.sh 在構建時自動處理
4. **源碼包檢測**：發現 CMakeLists.txt/Makefile 等時明確終止並提示
5. **禁止手動修改 Exec**：資源收集階段不得修改 desktop Exec 欄位

---

## 依賴

- `scan_executables.sh`：可執行檔掃描腳本
- `handle_special_paths.sh`：路徑轉換腳本（處理 `/usr/`、`/opt/` 等路徑層級剝離 + 特殊字符標準化 + 軟鏈修復），與 deb 版共用
- `linglong-project-gen` 子技能：工程生成
- `desktop-file-validate`：desktop 文件驗證工具
- `base_runtime_whitelist.conf`：base/runtime 白名單配置
