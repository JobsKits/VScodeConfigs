#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏬下载配置当前Git子模块.command
# - 核心用途：执行“⏬下载配置当前Git子模块”对应的 Git / Sourcetree 自动化操作。
# - 影响范围：可能修改当前仓库、工作区、分支、菜单配置或 Git 索引。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

# 双击 .command 时 PATH 经常不完整；先补齐 macOS 基础路径和 Homebrew 路径。
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-zh_CN.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-UTF-8}"

# ============================== 用户只需要改这里：目标子 Git 列表 ==============================
# 只允许写“浏览器页面地址”，不要写 .git，也不要写 SSH 地址。
#
# ✅ 正确：
#   "https://github.com/JobsKits/xxx"
#
# ❌ 不要写：
#   "https://github.com/JobsKits/xxx.git"
#   "git@github.com:JobsKits/xxx.git"
#
# 脚本会自动把页面地址转成两种固定下载地址：
#   HTTPS clone: https://github.com/JobsKits/xxx.git
#   SSH clone:   git@github.com:JobsKits/xxx.git
#
# 默认行为：
#   只写页面 URL              -> 本地目录自动使用仓库名，例如 JobsOCBaseConfigDemo
#   写成 页面 URL|本地目录     -> 使用自定义本地目录，例如 🔽JobsSoftware.MacOS
#
# 新增子仓：往 SUBMODULE_REPO_URLS 里加一行浏览器页面地址。
# 删除子仓：从 SUBMODULE_REPO_URLS 里删掉对应页面地址；默认只查漏补缺，不删除 .gitmodules 旧配置。
SUBMODULE_REPO_URLS=(
  "https://github.com/JobsKits/VScodeConfigByFlutter|🐦VScodeConfigByFlutter"
  # 以后新增仓库，只写浏览器页面地址即可。
  # "https://github.com/JobsKits/xxx"
)

# ============================== 脚本配置 ==============================
SUBMODULE_BRANCH="${SUBMODULE_BRANCH:-main}"          # 优先同步的子模块分支；远端没有该分支时自动使用远端默认分支
REMOTE_NAME="${REMOTE_NAME:-origin}"                  # 父仓远端名
DRY_RUN="${DRY_RUN:-0}"                                # 1=只打印动作，不执行
FORCE_DELETE="${FORCE_DELETE:-0}"                      # 1=允许删除非 Git 且非空的冲突目录；默认拒绝，避免误删
AUTO_PARENT_COMMIT="${AUTO_PARENT_COMMIT:-1}"          # 1=自动提交 .gitmodules/gitlink 变化
AUTO_PARENT_PUSH="${AUTO_PARENT_PUSH:-0}"              # 1=自动推送父仓；默认不推送，避免跨机器误推
GIT_URL_STYLE="${GIT_URL_STYLE:-auto}"                  # auto/https/ssh；默认自动继承父仓 origin 协议
PRUNE_STALE_GITMODULES="${PRUNE_STALE_GITMODULES:-0}"  # 1=删除 .gitmodules 中已经不在 SUBMODULE_REPO_URLS 的旧子模块；默认只查漏补缺
SUBMODULE_SHALLOW_CLONE="${SUBMODULE_SHALLOW_CLONE:-1}"    # 1=子仓浅克隆，只拿最新必要历史；0=完整克隆
SUBMODULE_DEPTH="${SUBMODULE_DEPTH:-1}"                    # 浅克隆深度；默认 1，只锚定最新一层提交
SUBMODULE_FETCH_TAGS="${SUBMODULE_FETCH_TAGS:-0}"          # 1=同步 tags；默认 0，软件大包仓库不拉 tags 更快

# ============================== 脚本路径定位 ==============================
SCRIPT_FILE="${(%):-%x}"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_FILE")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
SCRIPT_BASENAME="$(basename "$SCRIPT_FILE" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

# ============================== 全局缓存 ==============================
# entry 格式：local_path|page_url|https_clone_url|ssh_clone_url|repo_name
typeset -ga SUBMODULE_ENTRIES
typeset -ga CONFIG_PATHS
typeset -ga CONFIG_REPO_NAMES
SUBMODULE_ENTRIES=()
CONFIG_PATHS=()
CONFIG_REPO_NAMES=()
GITMODULES_RECONCILED=0
# ============================== 输出工具 ==============================
log()          { printf '%s\n' "$1" | tee -a "$LOG_FILE"; }
# 输出 info echo 对应级别的日志信息。
info_echo()    { log "ℹ️  $*"; }
# 输出 success echo 对应级别的日志信息。
success_echo() { log "✅ $*"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()    { log "⚠️  $*"; }
# 输出 error echo 对应级别的日志信息。
error_echo()   { printf '%s\n' "❌ $*" >&2; printf '%s\n' "❌ $*" >> "$LOG_FILE"; }
# 输出 note echo 对应级别的日志信息。
note_echo()    { log "📝 $*"; }
# 执行 run cmd 对应的独立业务步骤。
run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}
# 封装 trim string 对应的独立处理逻辑。
trim_string() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
# 封装 preview safe text 对应的独立处理逻辑。
preview_safe_text() {
  # 只处理 fzf preview 展示层：去掉 U+FE0F，避免 macOS Terminal/fzf 对 emoji 宽度重绘错位。
  # 不改变真实目录名、.gitmodules、Git 子模块路径。
  local s="$1"
  if command -v perl >/dev/null 2>&1; then
    printf '%s\n' "$s" | perl -CSDA -pe 's/\x{FE0F}//g' 2>/dev/null || printf '%s\n' "$s"
  else
    printf '%s\n' "$s"
  fi
}
# 解析并返回 get ncpu 所需信息。
get_ncpu() {
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null || echo 1
  else
    echo 1
  fi
}
# 解析并返回 get cpu arch 所需信息。
get_cpu_arch() {
  uname -m
}
# 封装 cd to script dir 对应的独立处理逻辑。
cd_to_script_dir() {
  cd "$REPO_ROOT"
  info_echo "当前工作目录已切换到目标仓库根目录：$(pwd)"
}
# 判断 contains item 对应条件是否成立。
contains_item() {
  local needle="$1"
  shift || true
  local item=""
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}
# ============================== Git URL 解析 ==============================
# 输出：page_url|https_clone_url|ssh_clone_url|repo_name
normalize_git_url() {
  local raw=""
  raw="$(trim_string "$1")"
  raw="${raw%/}"

  local rest=""
  local owner=""
  local repo=""

  if [[ "$raw" == https://github.com/* ]]; then
    rest="${raw#https://github.com/}"
    rest="${rest%.git}"
  elif [[ "$raw" == git@github.com:* ]]; then
    rest="${raw#git@github.com:}"
    rest="${rest%.git}"
  else
    return 1
  fi

  owner="${rest%%/*}"
  repo="${rest#*/}"

  if [[ -z "$owner" || -z "$repo" || "$owner" == "$repo" || "$repo" == */* || "$owner" == *[[:space:]]* || "$repo" == *[[:space:]]* ]]; then
    return 1
  fi

  printf 'https://github.com/%s/%s|https://github.com/%s/%s.git|git@github.com:%s/%s.git|%s\n' \
    "$owner" "$repo" \
    "$owner" "$repo" \
    "$owner" "$repo" \
    "$repo"
}
# 封装 entry path 对应的独立处理逻辑。
entry_path() {
  local entry="$1"
  printf '%s\n' "${entry%%|*}"
}
# 封装 entry page 对应的独立处理逻辑。
entry_page() {
  local entry="$1"
  local rest="${entry#*|}"
  printf '%s\n' "${rest%%|*}"
}
# 封装 entry https 对应的独立处理逻辑。
entry_https() {
  local entry="$1"
  local rest="${entry#*|}"
  rest="${rest#*|}"
  printf '%s\n' "${rest%%|*}"
}
# 封装 entry ssh 对应的独立处理逻辑。
entry_ssh() {
  local entry="$1"
  local rest="${entry#*|}"
  rest="${rest#*|}"
  rest="${rest#*|}"
  printf '%s\n' "${rest%%|*}"
}
# 封装 entry repo 对应的独立处理逻辑。
entry_repo() {
  local entry="$1"
  local rest="${entry#*|}"
  rest="${rest#*|}"
  rest="${rest#*|}"
  rest="${rest#*|}"
  printf '%s\n' "$rest"
}
# 解析并返回 get entry by path 所需信息。
get_entry_by_path() {
  local target="$1"
  local entry=""

  for entry in "${SUBMODULE_ENTRIES[@]}"; do
    if [[ "$(entry_path "$entry")" == "$target" ]]; then
      printf '%s\n' "$entry"
      return 0
    fi
  done

  return 1
}
# 封装 repo page by path 对应的独立处理逻辑。
repo_page_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_page "$entry"
}
# 封装 repo https by path 对应的独立处理逻辑。
repo_https_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_https "$entry"
}
# 封装 repo ssh by path 对应的独立处理逻辑。
repo_ssh_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_ssh "$entry"
}
# 封装 repo name by path 对应的独立处理逻辑。
repo_name_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_repo "$entry"
}
# 检查 validate local path 所需条件，不满足时阻止继续执行。
validate_local_path() {
  local local_path="$1"

  if [[ -z "$local_path" || "$local_path" == . || "$local_path" == .. || "$local_path" == */* || "$local_path" == *"|"* ]]; then
    return 1
  fi

  return 0
}
# 解析并返回 load configured submodules 所需信息。
load_configured_submodules() {
  SUBMODULE_ENTRIES=()
  CONFIG_PATHS=()
  CONFIG_REPO_NAMES=()
  GITMODULES_RECONCILED=0

  local spec=""
  for spec in "${SUBMODULE_REPO_URLS[@]}"; do
    local url_part="$spec"
    local local_path=""

    if [[ "$spec" == *"|"* ]]; then
      url_part="${spec%%|*}"
      local_path="${spec#*|}"
    fi

    url_part="$(trim_string "$url_part")"
    local_path="$(trim_string "$local_path")"

    if [[ "$url_part" == *.git || "$url_part" == git@github.com:* ]]; then
      error_echo "SUBMODULE_REPO_URLS 只能写浏览器页面地址，当前非法：$url_part"
      exit 1
    fi

    local normalized=""
    if ! normalized="$(normalize_git_url "$url_part")"; then
      error_echo "SUBMODULE_REPO_URLS 存在无法识别的 GitHub 页面地址：$url_part"
      exit 1
    fi

    local page_url="${normalized%%|*}"
    local rest1="${normalized#*|}"
    local https_url="${rest1%%|*}"
    local rest2="${rest1#*|}"
    local ssh_url="${rest2%%|*}"
    local repo_name="${rest2#*|}"

    [[ -z "$local_path" ]] && local_path="$repo_name"

    if ! validate_local_path "$local_path"; then
      error_echo "本地目录名非法：$local_path"
      exit 1
    fi

    if contains_item "$local_path" "${CONFIG_PATHS[@]}"; then
      error_echo "SUBMODULE_REPO_URLS 本地目录重复：$local_path"
      exit 1
    fi

    SUBMODULE_ENTRIES+=("$local_path|$page_url|$https_url|$ssh_url|$repo_name")
    CONFIG_PATHS+=("$local_path")
    CONFIG_REPO_NAMES+=("$repo_name")
  done
}
# 封装 append runtime submodule 对应的独立处理逻辑。
append_runtime_submodule() {
  local page_url="$1"
  local https_url="$2"
  local ssh_url="$3"
  local repo_name="$4"
  local local_path="$5"

  if ! validate_local_path "$local_path"; then
    error_echo "本地目录名非法：$local_path"
    return 1
  fi

  if ! get_entry_by_path "$local_path" >/dev/null 2>&1; then
    SUBMODULE_ENTRIES+=("$local_path|$page_url|$https_url|$ssh_url|$repo_name")
    CONFIG_PATHS+=("$local_path")
  fi

  if ! contains_item "$repo_name" "${CONFIG_REPO_NAMES[@]}"; then
    CONFIG_REPO_NAMES+=("$repo_name")
  fi

  GITMODULES_RECONCILED=0
}
# ============================== Homebrew / fzf 自检 ==============================
find_brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    printf '%s\n' "/opt/homebrew/bin/brew"
    return 0
  fi

  if [[ -x "/usr/local/bin/brew" ]]; then
    printf '%s\n' "/usr/local/bin/brew"
    return 0
  fi

  return 1
}
# 封装 inject shellenv block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv="$2"
  local id="homebrew_env"
  local header="# >>> ${id} 环境变量 >>>"
  local footer="# <<< ${id} 环境变量 <<<"

  if [[ -z "$profile_file" || -z "$shellenv" ]]; then
    error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv>"
    return 1
  fi

  run_cmd mkdir -p "$(dirname "$profile_file")"
  [[ -f "$profile_file" ]] || run_cmd touch "$profile_file"

  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY-RUN] 写入 $profile_file：$shellenv"
  elif grep -Fq "$shellenv" "$profile_file"; then
    info_echo "Homebrew shellenv 已存在：$profile_file"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv"
      echo "$footer"
    } >> "$profile_file"
    success_echo "已写入 Homebrew shellenv：$profile_file"
  fi

  if [[ "$DRY_RUN" == "0" ]]; then
    eval "$shellenv"
  fi
}
# 准备并配置 install homebrew 对应的运行条件。
install_homebrew() {
  local arch=""
  arch="$(get_cpu_arch)"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  warn_echo "未检测到可用 Homebrew，开始安装（架构：$arch）"

  if [[ "$arch" == "arm64" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
    if [[ "$DRY_RUN" == "1" ]]; then
      note_echo '[DRY-RUN] /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  else
    brew_bin="/usr/local/bin/brew"
    if [[ "$DRY_RUN" == "1" ]]; then
      note_echo '[DRY-RUN] arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    elif command -v arch >/dev/null 2>&1; then
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  fi

  # macOS 默认 shell 是 zsh；该脚本也使用 zsh。
  profile_file="$HOME/.zprofile"
  shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
  inject_shellenv_block "$profile_file" "$shellenv_cmd"
  success_echo "Homebrew 安装完成"
}
# 检查 ensure homebrew healthy 所需条件，不满足时阻止继续执行。
ensure_homebrew_healthy() {
  local brew_bin=""

  if ! brew_bin="$(find_brew_bin)"; then
    install_homebrew
    brew_bin="$(find_brew_bin)" || {
      error_echo "Homebrew 安装后仍不可用"
      exit 1
    }
  fi

  if [[ "$brew_bin" == "/opt/homebrew/bin/brew" ]]; then
    inject_shellenv_block "$HOME/.zprofile" 'eval "$(/opt/homebrew/bin/brew shellenv)"'
  elif [[ "$brew_bin" == "/usr/local/bin/brew" ]]; then
    inject_shellenv_block "$HOME/.zprofile" 'eval "$(/usr/local/bin/brew shellenv)"'
  fi

  if ! "$brew_bin" --version >/dev/null 2>&1; then
    error_echo "Homebrew 已存在但不能正常响应：$brew_bin"
    exit 1
  fi

  success_echo "Homebrew 自检通过：$($brew_bin --version | head -n 1)"

  info_echo "是否更新 Homebrew？"
  echo "👉 按 [Enter]：执行 brew update && brew upgrade && brew cleanup && brew doctor && brew -v"
  echo "👉 输入任意字符后回车：跳过更新"

  local confirm=""
  IFS= read -r confirm
  if [[ -z "$confirm" ]]; then
    run_cmd "$brew_bin" update
    run_cmd "$brew_bin" upgrade
    run_cmd "$brew_bin" cleanup
    "$brew_bin" doctor || warn_echo "brew doctor 有警告/错误，请按提示处理"
    "$brew_bin" -v || warn_echo "打印 brew 版本失败，可忽略"
    success_echo "Homebrew 更新流程完成"
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}
# 检查 ensure fzf healthy 所需条件，不满足时阻止继续执行。
ensure_fzf_healthy() {
  if command -v fzf >/dev/null 2>&1 && fzf --version >/dev/null 2>&1; then
    success_echo "fzf 自检通过：$(fzf --version | head -n 1)"
    return 0
  fi

  warn_echo "fzf 未安装或不能正常响应，准备通过 Homebrew 安装/修复"
  ensure_homebrew_healthy

  local brew_bin=""
  brew_bin="$(find_brew_bin)" || {
    error_echo "未找到 Homebrew，无法安装 fzf"
    exit 1
  }

  if "$brew_bin" list fzf >/dev/null 2>&1; then
    run_cmd "$brew_bin" reinstall fzf
  else
    run_cmd "$brew_bin" install fzf
  fi

  if command -v fzf >/dev/null 2>&1 && fzf --version >/dev/null 2>&1; then
    success_echo "fzf 安装/修复完成：$(fzf --version | head -n 1)"
  else
    error_echo "fzf 安装后仍不能正常响应"
    exit 1
  fi
}
# ============================== 父仓协议与基础操作 ==============================
ensure_repo_initialized() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    info_echo "已位于 Git 仓库内"
  else
    run_cmd git init
    success_echo "已初始化父 Git 仓库"
  fi

  run_cmd git config core.quotepath false || true
  git -c core.quotepath=false status >/dev/null
}
# 检查 ensure git remote 所需条件，不满足时阻止继续执行。
ensure_git_remote() {
  local remote_name="${1:-$REMOTE_NAME}"

  if git remote get-url "$remote_name" >/dev/null 2>&1; then
    info_echo "父仓远端 [$remote_name] -> $(git remote get-url "$remote_name")"
    return 0
  fi

  local remote_url=""
  while true; do
    printf '请输入父仓 Git 远端地址（用于 %s）：' "$remote_name"
    IFS= read -r remote_url
    remote_url="$(trim_string "$remote_url")"

    if [[ -z "$remote_url" ]]; then
      warn_echo "远端地址不能为空"
      continue
    fi

    if git ls-remote "$remote_url" >/dev/null 2>&1; then
      run_cmd git remote add "$remote_name" "$remote_url"
      success_echo "已添加父仓远端：$remote_name -> $remote_url"
      return 0
    fi

    error_echo "无法访问父仓远端：$remote_url"
  done
}
# 解析并返回 detect git url style 所需信息。
detect_git_url_style() {
  if [[ "$GIT_URL_STYLE" == "ssh" || "$GIT_URL_STYLE" == "https" ]]; then
    printf '%s\n' "$GIT_URL_STYLE"
    return 0
  fi

  local parent_url=""
  parent_url="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"

  case "$parent_url" in
    git@*|ssh://*) printf '%s\n' "ssh" ;;
    http://*|https://*) printf '%s\n' "https" ;;
    *) printf '%s\n' "https" ;;
  esac
}
# 封装 clone url for path 对应的独立处理逻辑。
clone_url_for_path() {
  local submodule_path="$1"
  local style=""
  style="$(detect_git_url_style)"

  if [[ "$style" == "ssh" ]]; then
    repo_ssh_by_path "$submodule_path"
  else
    repo_https_by_path "$submodule_path"
  fi
}
# 封装 parent has uncommitted changes 对应的独立处理逻辑。
parent_has_uncommitted_changes() {
  [[ -n "$(git -c core.quotepath=false status --porcelain)" ]]
}
# 检查 ensure parent branch 所需条件，不满足时阻止继续执行。
ensure_parent_branch() {
  local b="$SUBMODULE_BRANCH"
  local current=""
  current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  if [[ "$current" == "$b" ]]; then
    info_echo "父仓已在分支：$b"
    return 0
  fi

  if git rev-parse --verify "$b" >/dev/null 2>&1; then
    run_cmd git -c core.quotepath=false checkout "$b"
    return 0
  fi

  if git ls-remote --exit-code --heads "$REMOTE_NAME" "$b" >/dev/null 2>&1; then
    run_cmd git -c core.quotepath=false checkout -B "$b" --track "$REMOTE_NAME/$b"
  else
    run_cmd git -c core.quotepath=false checkout -B "$b"
  fi
}
# 封装 parent pull rebase 对应的独立处理逻辑。
parent_pull_rebase() {
  local b=""
  b="$(git rev-parse --abbrev-ref HEAD)"

  if parent_has_uncommitted_changes; then
    warn_echo "父仓存在未提交变更，已跳过 pull --rebase，避免触发冲突。当前未提交文件如下："
    git -c core.quotepath=false status --short || true
    return 0
  fi

  run_cmd git fetch "$REMOTE_NAME" || true
  if git ls-remote --exit-code --heads "$REMOTE_NAME" "$b" >/dev/null 2>&1; then
    run_cmd git pull --rebase "$REMOTE_NAME" "$b" || warn_echo "父仓 pull --rebase 未完成，请检查是否存在冲突；本次继续处理子模块"
  fi
}
# 封装 parent push if needed 对应的独立处理逻辑。
parent_push_if_needed() {
  if [[ "$AUTO_PARENT_PUSH" != "1" ]]; then
    note_echo "AUTO_PARENT_PUSH=0，已跳过父仓 push"
    return 0
  fi

  local b=""
  b="$(git rev-parse --abbrev-ref HEAD)"
  run_cmd git push -u "$REMOTE_NAME" "$b"
}
# ============================== 分支探测 ==============================
remote_default_branch_by_url() {
  local url="$1"
  local branch=""

  branch="$(git ls-remote --symref "$url" HEAD 2>/dev/null | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }' || true)"
  [[ -n "$branch" ]] && printf '%s\n' "$branch"
}
# 封装 remote branch exists 对应的独立处理逻辑。
remote_branch_exists() {
  local url="$1"
  local branch="$2"
  git ls-remote --exit-code --heads "$url" "$branch" >/dev/null 2>&1
}
# 封装 remote branch for url 对应的独立处理逻辑。
remote_branch_for_url() {
  local url="$1"
  local preferred="$2"
  local branch=""

  if remote_branch_exists "$url" "$preferred"; then
    printf '%s\n' "$preferred"
    return 0
  fi

  branch="$(remote_default_branch_by_url "$url")"
  if [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return 0
  fi

  printf '%s\n' "$preferred"
}
# ============================== 子模块状态判断 ==============================
is_git_worktree() {
  local submodule_path="$1"
  [[ -e "$submodule_path/.git" ]] || return 1
  git -C "$submodule_path" rev-parse --is-inside-work-tree >/dev/null 2>&1
}
# 判断 is gitlink registered 对应条件是否成立。
is_gitlink_registered() {
  local submodule_path="$1"
  git ls-files --stage -- "$submodule_path" 2>/dev/null | awk '{ if ($1 == "160000") found=1 } END { exit found ? 0 : 1 }'
}
# 判断 is dir empty 对应条件是否成立。
is_dir_empty() {
  local submodule_path="$1"
  [[ -d "$submodule_path" ]] || return 1
  local -a entries
  entries=("$submodule_path"/*(DN))
  [[ ${#entries} -eq 0 ]]
}
# 检查 assert clean submodule 所需条件，不满足时阻止继续执行。
assert_clean_submodule() {
  local submodule_path="$1"
  local action="$2"

  if ! is_git_worktree "$submodule_path"; then
    return 0
  fi

  local dirty=""
  dirty="$(git -C "$submodule_path" -c core.quotepath=false status --porcelain --untracked-files=normal)"
  if [[ -n "$dirty" ]]; then
    error_echo "子 Git 存在尚未提交内容，已终止${action}：$submodule_path"
    printf '%s\n' "$dirty"
    return 1
  fi

  return 0
}
# ============================== .gitmodules 查漏补缺 ==============================
ensure_gitmodules_file_exists() {
  if [[ -f .gitmodules ]]; then
    return 0
  fi

  run_cmd touch .gitmodules
  warn_echo ".gitmodules 当前不存在，已按 SUBMODULE_REPO_URLS 重建空文件，后续会逐项查漏补缺"
}
# 解析并返回 find gitmodules section by path 所需信息。
find_gitmodules_section_by_path() {
  local target_path="$1"
  [[ -f .gitmodules ]] || return 1

  local key=""
  while IFS= read -r key; do
    local value=""
    value="$(git config -f .gitmodules --get "$key" 2>/dev/null || true)"
    if [[ "$value" == "$target_path" ]]; then
      local section="$key"
      section="${section#submodule.}"
      section="${section%.path}"
      printf '%s\n' "$section"
      return 0
    fi
  done < <(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  return 1
}
# 解析并返回 collect gitmodules paths 所需信息。
collect_gitmodules_paths() {
  [[ -f .gitmodules ]] || return 0

  local key=""
  while IFS= read -r key; do
    git config -f .gitmodules --get "$key" 2>/dev/null || true
  done < <(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}
# 封装 gitmodules preferred style 对应的独立处理逻辑。
gitmodules_preferred_style() {
  if [[ -f .gitmodules ]]; then
    local key=""
    while IFS= read -r key; do
      local url=""
      url="$(git config -f .gitmodules --get "$key" 2>/dev/null || true)"
      case "$url" in
        git@*|ssh://*) printf '%s\n' "ssh"; return 0 ;;
        http://*|https://*) printf '%s\n' "https"; return 0 ;;
      esac
    done < <(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.url$' 2>/dev/null || true)
  fi

  # .gitmodules 作为跨机器配置文件，默认保持 HTTPS；实际下载/同步仍按父仓 origin 自动改用 HTTPS/SSH。
  printf '%s\n' "https"
}
# 封装 gitmodules url for path 对应的独立处理逻辑。
gitmodules_url_for_path() {
  local submodule_path="$1"
  local style=""
  style="$(gitmodules_preferred_style)"

  if [[ "$style" == "ssh" ]]; then
    repo_ssh_by_path "$submodule_path"
  else
    repo_https_by_path "$submodule_path"
  fi
}
# 封装 gitmodules url points to config repo 对应的独立处理逻辑。
gitmodules_url_points_to_config_repo() {
  local actual_url="$1"
  local submodule_path="$2"
  local normalized=""
  normalized="$(normalize_git_url "$actual_url" 2>/dev/null || true)"
  [[ -n "$normalized" ]] || return 1

  local actual_page="${normalized%%|*}"
  local expected_page=""
  expected_page="$(repo_page_by_path "$submodule_path")" || return 1

  [[ "$actual_page" == "$expected_page" ]]
}
# 清理 remove gitmodules entry by path 对应的目标内容。
remove_gitmodules_entry_by_path() {
  local submodule_path="$1"
  local section=""
  section="$(find_gitmodules_section_by_path "$submodule_path" 2>/dev/null || true)"

  if [[ -n "$section" ]]; then
    run_cmd git config -f .gitmodules --remove-section "submodule.$section" || true
    run_cmd git config --remove-section "submodule.$section" >/dev/null 2>&1 || true
    note_echo "已移除 .gitmodules 旧配置段：submodule.$section"
  fi
}
# 检查 ensure gitmodules entry 所需条件，不满足时阻止继续执行。
ensure_gitmodules_entry() {
  local submodule_path="$1"
  ensure_gitmodules_file_exists

  local desired_url=""
  desired_url="$(gitmodules_url_for_path "$submodule_path")"

  local section=""
  section="$(find_gitmodules_section_by_path "$submodule_path" 2>/dev/null || true)"
  [[ -z "$section" ]] && section="$submodule_path"

  local changed=0
  local cur_path=""
  local cur_url=""
  local cur_branch=""

  cur_path="$(git config -f .gitmodules --get "submodule.$section.path" 2>/dev/null || true)"
  cur_url="$(git config -f .gitmodules --get "submodule.$section.url" 2>/dev/null || true)"
  cur_branch="$(git config -f .gitmodules --get "submodule.$section.branch" 2>/dev/null || true)"

  if [[ "$cur_path" != "$submodule_path" ]]; then
    run_cmd git config -f .gitmodules "submodule.$section.path" "$submodule_path"
    changed=1
  fi

  # 关键：现有 .gitmodules 只要 URL 指向同一个 GitHub 仓库，就不强行改协议。
  # 例如你上传的 .gitmodules 全部是 https，这是合法的；父仓是 ssh 时，实际同步阶段会单独把子仓 origin 改成 ssh。
  if [[ -z "$cur_url" ]]; then
    run_cmd git config -f .gitmodules "submodule.$section.url" "$desired_url"
    changed=1
  elif ! gitmodules_url_points_to_config_repo "$cur_url" "$submodule_path"; then
    warn_echo ".gitmodules 中 $submodule_path 的 url 指向了非配置仓库，已修正"
    run_cmd git config -f .gitmodules "submodule.$section.url" "$desired_url"
    changed=1
  fi

  if [[ "$cur_branch" != "$SUBMODULE_BRANCH" ]]; then
    run_cmd git config -f .gitmodules "submodule.$section.branch" "$SUBMODULE_BRANCH"
    changed=1
  fi

  if [[ "$changed" == "1" ]]; then
    note_echo ".gitmodules 已查漏补缺/修复：$submodule_path"
  else
    info_echo ".gitmodules 已存在且合法，保持不动：$submodule_path"
  fi
}
# 封装 prune unconfigured gitmodules 对应的独立处理逻辑。
prune_unconfigured_gitmodules() {
  [[ "$PRUNE_STALE_GITMODULES" == "1" ]] || return 0
  [[ -f .gitmodules ]] || return 0

  local existing_path=""
  while IFS= read -r existing_path; do
    [[ -z "$existing_path" ]] && continue

    if ! contains_item "$existing_path" "${CONFIG_PATHS[@]}"; then
      warn_echo "发现 .gitmodules 中不再属于 SUBMODULE_REPO_URLS 的旧子模块：$existing_path"
      assert_clean_submodule "$existing_path" "移除旧子模块配置" || return 1

      if is_gitlink_registered "$existing_path"; then
        run_cmd git rm -f --cached -- "$existing_path" >/dev/null 2>&1 || true
      fi

      remove_gitmodules_entry_by_path "$existing_path"

      if [[ -d "$existing_path" ]]; then
        if is_git_worktree "$existing_path" || is_dir_empty "$existing_path" || [[ "$FORCE_DELETE" == "1" ]]; then
          run_cmd rm -rf "$existing_path"
          warn_echo "已删除旧子模块目录：$existing_path"
        else
          error_echo "旧子模块目录不是 Git 且非空，默认拒绝删除：$existing_path；确认要删可设置 FORCE_DELETE=1"
          return 1
        fi
      fi
    fi
  done < <(collect_gitmodules_paths)
}
# 封装 reconcile gitmodules with config once 对应的独立处理逻辑。
reconcile_gitmodules_with_config_once() {
  if [[ "$GITMODULES_RECONCILED" == "1" ]]; then
    info_echo ".gitmodules 本轮已完成查漏补缺，跳过重复自检"
    return 0
  fi

  ensure_gitmodules_file_exists

  local p=""
  for p in "${CONFIG_PATHS[@]}"; do
    ensure_gitmodules_entry "$p"
  done

  prune_unconfigured_gitmodules
  GITMODULES_RECONCILED=1
  success_echo ".gitmodules 查漏补缺完成"
}
# ============================== 子模块目录清理/添加/同步 ==============================
unique_paths_from_stdin() {
  local -a result
  result=()
  local line=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! contains_item "$line" "${result[@]}"; then
      result+=("$line")
    fi
  done

  local p=""
  for p in "${result[@]}"; do
    printf '%s\n' "$p"
  done
}
# 解析并返回 collect existing child git dirs 所需信息。
collect_existing_child_git_dirs() {
  local d=""
  for d in ./*(N/); do
    d="${d#./}"
    [[ -z "$d" || "$d" == ".git" ]] && continue
    if is_git_worktree "$d"; then
      printf '%s\n' "$d"
    fi
  done
}
# 解析并返回 collect full delete targets 所需信息。
collect_full_delete_targets() {
  {
    local p=""
    for p in "${CONFIG_PATHS[@]}"; do
      printf '%s\n' "$p"
      repo_name_by_path "$p" 2>/dev/null || true
    done

    collect_existing_child_git_dirs
  } | unique_paths_from_stdin
}
# 清理 remove worktree dir safely 对应的目标内容。
remove_worktree_dir_safely() {
  local submodule_path="$1"

  if [[ -z "$submodule_path" || "$submodule_path" == "." || "$submodule_path" == "/" || "$submodule_path" == ".." ]]; then
    error_echo "拒绝删除危险路径：$submodule_path"
    return 1
  fi

  assert_clean_submodule "$submodule_path" "删除目录" || return 1

  if is_gitlink_registered "$submodule_path"; then
    run_cmd git submodule deinit -f -- "$submodule_path" >/dev/null 2>&1 || true
  fi

  if [[ -d ".git/modules/$submodule_path" ]]; then
    run_cmd rm -rf ".git/modules/$submodule_path"
    note_echo "已清理旧子模块缓存：.git/modules/$submodule_path"
  fi

  if [[ -e "$submodule_path" ]]; then
    if is_git_worktree "$submodule_path" || is_dir_empty "$submodule_path" || [[ "$FORCE_DELETE" == "1" ]]; then
      run_cmd rm -rf "$submodule_path"
      warn_echo "已删除目标目录：$submodule_path"
    else
      error_echo "发现非 Git 且非空目录，默认拒绝删除：$submodule_path；确认要删可设置 FORCE_DELETE=1"
      return 1
    fi
  fi

  # 注意：这里故意不删除 .gitmodules 段、不 git rm --cached。
  # 全量同步只是刷新工作区目录；.gitmodules 由 reconcile_gitmodules_with_config_once 负责查漏补缺。
}
# 封装 clone submodule worktree 对应的独立处理逻辑。
clone_submodule_worktree() {
  local submodule_path="$1"
  local url=""
  url="$(clone_url_for_path "$submodule_path")"
  local branch=""
  branch="$(remote_branch_for_url "$url" "$SUBMODULE_BRANCH")"

  local -a clone_args
  clone_args=()

  if [[ "$SUBMODULE_SHALLOW_CLONE" == "1" ]]; then
    clone_args+=(--depth "$SUBMODULE_DEPTH" --single-branch --shallow-submodules)
  fi

  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    clone_args+=(--no-tags)
  fi

  if remote_branch_exists "$url" "$branch"; then
    run_cmd git clone "${clone_args[@]}" --branch "$branch" --recurse-submodules --jobs="$(get_ncpu)" "$url" "$submodule_path"
  else
    warn_echo "远端未确认存在分支 $branch，将按远端默认分支 clone：$submodule_path"
    run_cmd git clone "${clone_args[@]}" --recurse-submodules --jobs="$(get_ncpu)" "$url" "$submodule_path"
  fi

  run_cmd git -C "$submodule_path" config core.quotepath false || true
  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    run_cmd git -C "$submodule_path" config remote.origin.tagOpt --no-tags || true
  fi
}
# 检查 ensure submodule worktree present 所需条件，不满足时阻止继续执行。
ensure_submodule_worktree_present() {
  local submodule_path="$1"

  # 不走 git submodule update 做首次下载，因为它会严格使用 .gitmodules 的 url。
  # 这里直接按父仓 origin 推导出的 HTTPS/SSH 克隆地址下载，满足“父仓什么协议，子仓同步就用什么协议”。
  if [[ -e "$submodule_path" ]]; then
    if is_git_worktree "$submodule_path"; then
      assert_clean_submodule "$submodule_path" "纳入子模块" || return 1
    elif is_dir_empty "$submodule_path"; then
      run_cmd rm -rf "$submodule_path"
    else
      error_echo "目标目录已存在且不是 Git 空目录，拒绝覆盖：$submodule_path"
      return 1
    fi
  fi

  if [[ ! -e "$submodule_path" ]]; then
    clone_submodule_worktree "$submodule_path"
  fi

  # 不使用 git submodule add，避免 .gitmodules 被 Git 自动重写；手动 add 会把内部 Git 仓登记为 gitlink。
  run_cmd git add -- .gitmodules "$submodule_path"

  # 标准子模块形态：子仓目录里保留 .git 单文件，真正 Git 数据放到父仓 .git/modules 下。
  # 这一步不决定是否浅克隆；浅克隆由 --depth 控制。这里负责把 .git 文件夹吸收到父仓管理。
  run_cmd git submodule absorbgitdirs -- "$submodule_path" >/dev/null 2>&1 || true
  run_cmd git add -- .gitmodules "$submodule_path"

  if [[ -f "$submodule_path/.git" ]]; then
    success_echo "已登记标准子模块 gitlink：$submodule_path（子仓 .git 为单文件）"
  else
    warn_echo "已登记子模块 gitlink：$submodule_path；但 .git 仍不是单文件，后续可再次执行 git submodule absorbgitdirs 修复"
  fi
}
# 解析并返回 resolve remote branch for submodule 所需信息。
resolve_remote_branch_for_submodule() {
  local submodule_path="$1"
  local preferred="$SUBMODULE_BRANCH"

  if git -C "$submodule_path" ls-remote --exit-code --heads origin "$preferred" >/dev/null 2>&1; then
    printf '%s\n' "$preferred"
    return 0
  fi

  local head_branch=""
  head_branch="$(git -C "$submodule_path" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}' || true)"
  if [[ -n "$head_branch" && "$head_branch" != "(unknown)" ]]; then
    printf '%s\n' "$head_branch"
    return 0
  fi

  return 1
}
# 更新并同步 sync one submodule to latest 对应的目标状态。
sync_one_submodule_to_latest() {
  local submodule_path="$1"
  local url=""
  url="$(clone_url_for_path "$submodule_path")"

  if [[ ! -e "$submodule_path" ]]; then
    warn_echo "本地目录不存在，跳过：$submodule_path"
    return 0
  fi

  if ! is_git_worktree "$submodule_path"; then
    warn_echo "不是 Git 子目录，跳过：$submodule_path"
    return 0
  fi

  assert_clean_submodule "$submodule_path" "更新" || return 1

  run_cmd git -C "$submodule_path" config core.quotepath false || true
  run_cmd git -C "$submodule_path" remote set-url origin "$url"
  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    run_cmd git -C "$submodule_path" config remote.origin.tagOpt --no-tags || true
  fi

  local branch=""
  if ! branch="$(resolve_remote_branch_for_submodule "$submodule_path")"; then
    error_echo "无法确定远端可同步分支：$submodule_path"
    return 1
  fi

  local -a fetch_args
  fetch_args=()
  if [[ "$SUBMODULE_SHALLOW_CLONE" == "1" ]]; then
    fetch_args+=(--depth "$SUBMODULE_DEPTH")
  fi
  if [[ "$SUBMODULE_FETCH_TAGS" == "1" ]]; then
    fetch_args+=(--tags)
  else
    fetch_args+=(--no-tags)
  fi

  run_cmd git -C "$submodule_path" fetch "${fetch_args[@]}" origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" --prune
  run_cmd git -C "$submodule_path" -c core.quotepath=false checkout -B "$branch" "origin/$branch"
  run_cmd git -C "$submodule_path" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null 2>&1 || true
  run_cmd git -C "$submodule_path" reset --hard "origin/$branch"

  local -a submodule_update_args
  submodule_update_args=(submodule update --init --recursive --jobs="$(get_ncpu)")
  if [[ "$SUBMODULE_SHALLOW_CLONE" == "1" ]]; then
    submodule_update_args+=(--depth "$SUBMODULE_DEPTH" --recommend-shallow)
  fi
  run_cmd git -C "$submodule_path" "${submodule_update_args[@]}" || true

  # 再次确保子仓是标准 submodule 形态：工作目录下 .git 为单文件，Git 数据由父仓 .git/modules 托管。
  run_cmd git submodule absorbgitdirs -- "$submodule_path" >/dev/null 2>&1 || true

  success_echo "$submodule_path 已浅同步到 origin/$branch：$(git -C "$submodule_path" rev-parse --short HEAD)"
}
# 更新并同步 sync selected submodules to latest 对应的目标状态。
sync_selected_submodules_to_latest() {
  local -a paths
  paths=("$@")
  local p=""

  if [[ ${#paths} -eq 0 ]]; then
    warn_echo "没有需要同步的子模块"
    return 0
  fi

  for p in "${paths[@]}"; do
    ensure_submodule_worktree_present "$p"
    sync_one_submodule_to_latest "$p"
  done
}
# 封装 stage and commit parent changes 对应的独立处理逻辑。
stage_and_commit_parent_changes() {
  if [[ "$AUTO_PARENT_COMMIT" != "1" ]]; then
    note_echo "AUTO_PARENT_COMMIT=0，已跳过父仓提交"
    return 0
  fi

  local -a paths
  paths=("$@")
  local -a add_targets
  add_targets=()

  [[ -f .gitmodules ]] && add_targets+=(".gitmodules")

  local p=""
  for p in "${paths[@]}"; do
    add_targets+=("$p")
  done

  if [[ ${#add_targets} -eq 0 ]]; then
    info_echo "无父仓文件需要 add，跳过提交"
    return 0
  fi

  run_cmd git add -A -- "${add_targets[@]}" >/dev/null 2>&1 || true

  if git diff --cached --quiet -- "${add_targets[@]}"; then
    info_echo "父仓 .gitmodules/gitlink 无变化，跳过提交"
    return 0
  fi

  local style=""
  style="$(detect_git_url_style)"
  run_cmd git -c core.quotepath=false commit -m "chore: sync git submodules (${style})"
  success_echo "父仓已提交 .gitmodules/gitlink 变化"
}
# ============================== 三种菜单动作 ==============================
full_sync_to_latest() {
  info_echo "开始全量同步：先对 .gitmodules 做一次查漏补缺；再删除目标子 Git 工作目录/目标空目录；最后按 SUBMODULE_REPO_URLS 重建"

  reconcile_gitmodules_with_config_once

  local -a delete_targets
  delete_targets=()
  local p=""
  while IFS= read -r p; do
    [[ -n "$p" ]] && delete_targets+=("$p")
  done < <(collect_full_delete_targets)

  for p in "${delete_targets[@]}"; do
    remove_worktree_dir_safely "$p"
  done

  local -a synced_paths
  synced_paths=()
  for p in "${CONFIG_PATHS[@]}"; do
    synced_paths+=("$p")
  done

  sync_selected_submodules_to_latest "${synced_paths[@]}"
  run_cmd git submodule sync --recursive || true
  stage_and_commit_parent_changes "${synced_paths[@]}"
  parent_push_if_needed
  success_echo "全量同步完成"
}
# 解析并返回 collect existing configured git paths 所需信息。
collect_existing_configured_git_paths() {
  local p=""
  for p in "${CONFIG_PATHS[@]}"; do
    if is_git_worktree "$p"; then
      printf '%s\n' "$p"
    fi
  done
}
# 更新并同步 update existing to latest 对应的目标状态。
update_existing_to_latest() {
  local -a existing_paths
  existing_paths=()
  local p=""

  while IFS= read -r p; do
    [[ -n "$p" ]] && existing_paths+=("$p")
  done < <(collect_existing_configured_git_paths)

  if [[ ${#existing_paths} -eq 0 ]]; then
    warn_echo "当前不存在任何已配置的本地 Git 子目录，自动切换为全量同步"
    full_sync_to_latest
    return 0
  fi

  reconcile_gitmodules_with_config_once
  info_echo "只同步当前已有的子 Git 目录：${existing_paths[*]}"
  sync_selected_submodules_to_latest "${existing_paths[@]}"
  run_cmd git submodule sync --recursive || true
  stage_and_commit_parent_changes "${existing_paths[@]}"
  parent_push_if_needed
  success_echo "已有子模块同步完成"
}
# 检查 validate remote access or loop continue 所需条件，不满足时阻止继续执行。
validate_remote_access_or_loop_continue() {
  local url="$1"
  if git ls-remote "$url" >/dev/null 2>&1; then
    return 0
  fi

  error_echo "Git 地址格式正确，但当前无法访问：$url"
  return 1
}
# 封装 add new git url interactive 对应的独立处理逻辑。
add_new_git_url_interactive() {
  while true; do
    echo ""
    echo "请输入新的 GitHub 仓库地址："
    echo "  支持：https://github.com/JobsKits/JobsGenesis"
    echo "  支持：https://github.com/JobsKits/JobsGenesis.git"
    echo "  支持：git@github.com:JobsKits/JobsGenesis.git"
    echo "  输入一个空格后回车：返回上一页"
    printf 'Git 地址：'

    local input=""
    IFS= read -r input

    if [[ "$input" == " " ]]; then
      note_echo "返回上一页"
      return 0
    fi

    local normalized=""
    if ! normalized="$(normalize_git_url "$input")"; then
      error_echo "地址不合法，请重新输入"
      continue
    fi

    local page_url="${normalized%%|*}"
    local rest1="${normalized#*|}"
    local https_url="${rest1%%|*}"
    local rest2="${rest1#*|}"
    local ssh_url="${rest2%%|*}"
    local repo_name="${rest2#*|}"
    local local_path="$repo_name"

    local style=""
    style="$(detect_git_url_style)"
    local clone_url="$https_url"
    [[ "$style" == "ssh" ]] && clone_url="$ssh_url"

    validate_remote_access_or_loop_continue "$clone_url" || continue

    append_runtime_submodule "$page_url" "$https_url" "$ssh_url" "$repo_name" "$local_path"
    ensure_gitmodules_entry "$local_path"
    GITMODULES_RECONCILED=1
    sync_selected_submodules_to_latest "$local_path"
    run_cmd git submodule sync --recursive || true
    stage_and_commit_parent_changes "$local_path"
    parent_push_if_needed

    success_echo "已添加并同步新子模块：$local_path -> $clone_url"
    echo ""
    echo "如果希望以后固定保留，请把下面这一行加入脚本顶部 SUBMODULE_REPO_URLS："
    echo "  \"$page_url\""
    echo ""
    echo "按 [Enter] 返回菜单"
    local dummy=""
    IFS= read -r dummy
    return 0
  done
}
# 执行 build submodule picker content 对应的独立业务步骤。
build_submodule_picker_content() {
  local style=""
  style="$(detect_git_url_style 2>/dev/null || echo https)"

  cat <<EOF2
📦 选择指定子模块同步（OpenClaw 键盘版，非 fzf 多选页）
------------------------------------------------------------
操作说明：
  - 按 ↑ / ↓ 移动光标
  - 按 [Enter] 勾选 / 取消勾选当前项目
  - 按 [Space] 确认当前勾选并开始同步
  - 第一项“全选”会一次勾选 / 取消全部 SUBMODULE_REPO_URLS 项目
  - 按 ← 返回上一页

子模块同步 URL 模式: $style（auto 时继承父仓 origin）
子模块分支优先级: $SUBMODULE_BRANCH
子仓浅克隆: $SUBMODULE_SHALLOW_CLONE
浅克隆深度: $SUBMODULE_DEPTH
同步 tags: $SUBMODULE_FETCH_TAGS

当前配置项目数: ${#CONFIG_PATHS}
------------------------------------------------------------
EOF2
}
# 封装 submodule picker all selected 对应的独立处理逻辑。
submodule_picker_all_selected() {
  local p=""

  [[ ${#CONFIG_PATHS[@]} -gt 0 ]] || return 1

  for p in "${CONFIG_PATHS[@]}"; do
    [[ -n "${SUBMODULE_PICKED[$p]:-}" ]] || return 1
  done

  return 0
}
# 输出 render submodule keyboard picker 对应的说明与结果。
render_submodule_keyboard_picker() {
  local cursor="$1"
  local message="${2:-}"
  local total=$(( ${#CONFIG_PATHS[@]} + 1 ))
  local i=1
  local pointer=""
  local mark=""
  local p=""
  local display_path=""
  local page_url=""

  command clear 2>/dev/null || printf '\033[2J\033[H'
  build_submodule_picker_content

  if [[ -n "$message" ]]; then
    printf '%s\n' "$message"
    printf '%s\n' '------------------------------------------------------------'
  fi

  while [[ $i -le $total ]]; do
    if [[ $i -eq $cursor ]]; then
      pointer="👉"
    else
      pointer="  "
    fi

    if [[ $i -eq 1 ]]; then
      if submodule_picker_all_selected; then
        mark="✅"
      else
        mark="⬜️"
      fi
      printf '%s %s %s\n' "$pointer" "$mark" "全选：同步 SUBMODULE_REPO_URLS 中全部项目"
    else
      p="${CONFIG_PATHS[$(( i - 1 ))]}"
      display_path="$(preview_safe_text "$p")"
      page_url="$(repo_page_by_path "$p" 2>/dev/null || true)"
      if [[ -n "${SUBMODULE_PICKED[$p]:-}" ]]; then
        mark="✅"
      else
        mark="⬜️"
      fi
      printf '%s %s %s    %s\n' "$pointer" "$mark" "$display_path" "$page_url"
    fi

    (( i++ ))
  done

  printf '%s\n' '------------------------------------------------------------'
  printf '已勾选：%s / %s\n' "${#SUBMODULE_PICKED[@]}" "${#CONFIG_PATHS[@]}"
}
# 解析并返回 read submodule picker key 所需信息。
read_submodule_picker_key() {
  local key=""
  local rest=""
  local ch=""
  local guard=0

  SUBMODULE_PICKER_KEY=""
  IFS= read -rs -k 1 key || return 1

  # 方向键是 ESC 开头的转义序列。不能只读固定 2 个字符，
  # 否则某些终端发出的扩展序列会被截断，导致 ← 识别失败。
  if [[ "$key" == $'\e' ]]; then
    rest=""
    while IFS= read -rs -t 0.03 -k 1 ch; do
      rest+="$ch"
      (( guard++ ))
      [[ $guard -ge 8 ]] && break
    done
    key+="$rest"
  fi

  SUBMODULE_PICKER_KEY="$key"
}
# 封装 select configured submodules interactive 对应的独立处理逻辑。
select_configured_submodules_interactive() {
  local preview_file="$1"

  if [[ ${#CONFIG_PATHS[@]} -eq 0 ]]; then
    warn_echo "SUBMODULE_REPO_URLS 当前没有配置任何项目"
    return 2
  fi

  typeset -gA SUBMODULE_PICKED
  SUBMODULE_PICKED=()
  local cursor=1
  local total=$(( ${#CONFIG_PATHS[@]} + 1 ))
  local message=""
  local key=""
  local p=""

  while true; do
    render_submodule_keyboard_picker "$cursor" "$message"
    message=""

    if ! read_submodule_picker_key; then
      note_echo "已取消选择，返回上一页"
      return 2
    fi
    key="$SUBMODULE_PICKER_KEY"

    case "$key" in
      $'\e[A'|k)
        (( cursor-- ))
        [[ $cursor -lt 1 ]] && cursor=$total
        ;;
      $'\e[B'|j)
        (( cursor++ ))
        [[ $cursor -gt $total ]] && cursor=1
        ;;
      $'\r'|$'\n')
        if [[ $cursor -eq 1 ]]; then
          if submodule_picker_all_selected; then
            SUBMODULE_PICKED=()
            message="已取消全选"
          else
            SUBMODULE_PICKED=()
            for p in "${CONFIG_PATHS[@]}"; do
              SUBMODULE_PICKED[$p]=1
            done
            message="已全选 ${#CONFIG_PATHS[@]} 个项目"
          fi
        else
          p="${CONFIG_PATHS[$(( cursor - 1 ))]}"
          if [[ -n "${SUBMODULE_PICKED[$p]:-}" ]]; then
            unset "SUBMODULE_PICKED[$p]"
            message="已取消：$(preview_safe_text "$p")"
          else
            SUBMODULE_PICKED[$p]=1
            message="已勾选：$(preview_safe_text "$p")"
          fi
        fi
        ;;
      ' ')
        local -a selected_paths
        selected_paths=()
        for p in "${CONFIG_PATHS[@]}"; do
          if [[ -n "${SUBMODULE_PICKED[$p]:-}" ]]; then
            selected_paths+=("$p")
          fi
        done

        if [[ ${#selected_paths[@]} -eq 0 ]]; then
          message="⚠️  还没有勾选任何子模块：请先用 Enter 勾选，再按 Space 确认"
          continue
        fi

        command clear 2>/dev/null || printf '\033[2J\033[H'
        reconcile_gitmodules_with_config_once
        info_echo "开始同步已选择的子模块：${selected_paths[*]}"
        sync_selected_submodules_to_latest "${selected_paths[@]}"
        run_cmd git submodule sync --recursive || true
        stage_and_commit_parent_changes "${selected_paths[@]}"
        parent_push_if_needed
        success_echo "已选择子模块同步完成"
        return 0
        ;;
      $'\e[D'|$'\eOD'|$'\e[1D'|$'\e[1;2D'|$'\e[1;3D'|$'\e[1;4D'|$'\e[1;5D'|h|H)
        note_echo "已返回上一页"
        return 2
        ;;
      $'\e')
        note_echo "已停止脚本"
        return 130
        ;;
      *)
        message="提示：↑/↓ 移动，Enter 勾选/取消，Space 确认，← 返回上一页"
        ;;
    esac
  done
}
# ============================== fzf 菜单 ==============================
select_menu_action() {
  local preview_file="$1"
  local selected=""

  selected="$(printf '%s\n' \
    "全量同步更新下载到最新" \
    "选择指定子模块同步（可多选）" \
    "只更新目前已有的" \
    "添加并同步一个新的 Git 地址" \
    "退出" \
    | FZF_CONFIG_PREVIEW_FILE="$preview_file" fzf \
        --prompt='请选择操作 > ' \
        --height=100% \
        --border \
        --reverse \
        --preview='cat "$FZF_CONFIG_PREVIEW_FILE"' \
        --preview-window='up,70%,border-bottom,nowrap' \
        --header=$'上方是配置预览区；内容超出时可鼠标滚动，或用 Ctrl+K/J 单行滚动、Ctrl+U/D 翻页。' \
        --bind='ctrl-k:preview-up,ctrl-j:preview-down,ctrl-u:preview-page-up,ctrl-d:preview-page-down')" || return 1

  printf '%s\n' "$selected"
}
# 执行 build intro content 对应的独立业务步骤。
build_intro_content() {
  local style=""
  style="$(detect_git_url_style 2>/dev/null || echo https)"
  local gm_style=""
  gm_style="$(gitmodules_preferred_style 2>/dev/null || echo "$style")"

  cat <<EOF2
📘 Git 子模块批量管理脚本
------------------------------------------------------------
脚本目录: $SCRIPT_DIR
当前目录: $(pwd)
父仓远端: $REMOTE_NAME
子模块分支优先级: $SUBMODULE_BRANCH
子模块同步 URL 模式: $style（auto 时继承父仓 origin）
.gitmodules 补缺 URL 模式: $gm_style（已有合法条目不改，只补缺）
干跑: $DRY_RUN
自动提交父仓: $AUTO_PARENT_COMMIT
自动推送父仓: $AUTO_PARENT_PUSH
子仓浅克隆: $SUBMODULE_SHALLOW_CLONE
浅克隆深度: $SUBMODULE_DEPTH
同步 tags: $SUBMODULE_FETCH_TAGS

当前配置的目标子 Git：
EOF2

  local p=""
  local display_path=""
  local page_url=""
  local https_url=""
  local ssh_url=""
  local gm_section=""
  local gm_status=""

  for p in "${CONFIG_PATHS[@]}"; do
    display_path="$(preview_safe_text "$p")"
    page_url="$(repo_page_by_path "$p")"
    https_url="$(repo_https_by_path "$p")"
    ssh_url="$(repo_ssh_by_path "$p")"
    gm_section="$(find_gitmodules_section_by_path "$p" 2>/dev/null || true)"
    if [[ -n "$gm_section" ]]; then
      gm_status="已存在"
    else
      gm_status="缺失，执行同步时会补齐"
    fi

    printf '  - %s\n' "$display_path"
    printf '      page       : %s\n' "$page_url"
    printf '      https      : %s\n' "$https_url"
    printf '      ssh        : %s\n' "$ssh_url"
    printf '      .gitmodules: %s\n' "$gm_status"
  done

  cat <<EOF2
------------------------------------------------------------
EOF2
}
# 封装 main menu loop 对应的独立处理逻辑。
main_menu_loop() {
  local preview_file="$1"

  while true; do
    build_intro_content > "$preview_file"

    local action=""
    if ! action="$(select_menu_action "$preview_file")"; then
      note_echo "已取消选择，退出"
      return 0
    fi

    case "$action" in
      "全量同步更新下载到最新")
        full_sync_to_latest
        return 0
        ;;
      "选择指定子模块同步（可多选）")
        select_configured_submodules_interactive "$preview_file"
        local result="$?"
        if [[ "$result" == "0" ]]; then
          return 0
        elif [[ "$result" == "2" ]]; then
          continue
        else
          return "$result"
        fi
        ;;
      "只更新目前已有的")
        update_existing_to_latest
        return 0
        ;;
      "添加并同步一个新的 Git 地址")
        add_new_git_url_interactive
        ;;
      "退出")
        note_echo "已退出"
        return 0
        ;;
      *)
        warn_echo "未知选项：$action"
        ;;
    esac
  done
}
# 展示同目录 README，并等待用户确认后执行。
show_readme_and_wait() {
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】⏬下载配置当前Git子模块.command'
  print -r -- '核心用途：执行“⏬下载配置当前Git子模块”对应的 Git 自动化操作。'
  print -r -- '影响范围：可能修改当前仓库、工作区、分支或 Git 索引。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  local readme_path="${SCRIPT_DIR}/README.md"
  [[ -f "$readme_path" ]] || { error_echo "未找到配套 README.md：$readme_path"; return 1; }
  cat "$readme_path" | tee -a "$LOG_FILE"
  echo ""
  read -r "?👉 已阅读 README，按回车继续；按 Ctrl+C 取消：" _
}
# 编排脚本的高层业务流程。
# 初始化本次运行的日志文件。
initialize_execution_log() {
  : > "$LOG_FILE"
}
# 创建交互预览文件并注册退出清理。
prepare_preview_runtime() {
  PREVIEW_FILE="$(mktemp "/tmp/${SCRIPT_BASENAME}.preview.XXXXXX")"
  trap '[[ -n "${PREVIEW_FILE:-}" ]] && rm -f "$PREVIEW_FILE"' EXIT
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  if [[ "$SCRIPT_FILE" != /* ]]; then
    SCRIPT_FILE="$PWD/$SCRIPT_FILE"
  fi
}
# 编排脚本的高层业务流程。
main() {
  # 展示配套 README，确认子模块同步范围后继续。
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 清空当前脚本旧日志，确保本次记录独立可查。
  initialize_execution_log
  # 切换到脚本所在仓库，避免相对路径指向错误位置。
  cd_to_script_dir
  # 加载脚本中维护的目标子模块配置。
  load_configured_submodules

  # 确认当前目录已经初始化为 Git 仓库。
  ensure_repo_initialized
  # 检查并修复父仓库远程地址配置。
  ensure_git_remote "$REMOTE_NAME"
  # 确保父仓库处于可同步的目标分支。
  ensure_parent_branch
  # 在处理子模块前同步父仓库最新提交。
  parent_pull_rebase

  # fzf 必须在第一次使用前完成自检；缺失时自动检查/安装 Homebrew，再安装 fzf。
  ensure_fzf_healthy

  # 创建 fzf 预览文件并注册退出清理。
  prepare_preview_runtime
  # 进入交互菜单，按用户选择执行子模块同步动作。
  main_menu_loop "$PREVIEW_FILE"

  # 输出全部流程的完成状态。
  success_echo "全部完成 ✅"
  # 输出日志文件位置，方便后续排查。
  note_echo "日志文件：$LOG_FILE"
}

main "$@"
