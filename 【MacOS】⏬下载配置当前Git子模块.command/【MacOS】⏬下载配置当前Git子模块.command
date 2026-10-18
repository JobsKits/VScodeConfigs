#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏬下载配置当前Git子模块.command
# - 来源日志：克隆 / 拉取前突出平台与完整地址，完成时带来源，保留递归来源核对。
# - 下载协议：Gitee 标准 SSH 地址在本次进程改走 HTTPS，递归子模块继承，不写全局配置。
# - 核心用途：按各仓独立清单下载、更新和登记 Git 子模块，支持根目录或直属同名脚本目录。
# - 影响范围：父仓登记、索引与提交，子仓工作区和分支；全量模式仅删除清单目标及对应旧仓名目录。
# - 运行提示：先阅读内置自述并回车确认；全量重建另需 YES；Ctrl+C 取消，默认提交父仓但不推送。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}

# ============================== 用户只需要改这里：目标子 Git 列表 ==============================
# 支持任意托管站点的 HTTPS、git@host:namespace/repo.git、ssh://git@host:端口/namespace/repo.git。
# 使用 地址|本地目录 指定本地名称；未指定时使用真实地址中的仓库名。
# 已有 .gitmodules 的 URL、分支和扩展字段优先保留；相对 URL 随 REMOTE_NAME 的平台、namespace 和协议解析。
# 新条目依据所选父 remote 与真实子 remote 生成 ../仓名.git；跨平台映射无法确认时停止，须在 .gitmodules 明确地址。
# 跨组织或不同仓名可在 .gitmodules 填写完整地址，不会把 GitHub 主机/owner 机械替换。
# 删除清单项目默认不会删除 .gitmodules 旧配置。
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
GIT_URL_STYLE="${GIT_URL_STYLE:-auto}"                  # auto/https/ssh；默认继承所选父 remote 的完整地址
PRUNE_STALE_GITMODULES="${PRUNE_STALE_GITMODULES:-0}"  # 1=删除 .gitmodules 中已经不在 SUBMODULE_REPO_URLS 的旧子模块；默认只查漏补缺
SUBMODULE_SHALLOW_CLONE="${SUBMODULE_SHALLOW_CLONE:-1}"    # 1=子仓浅克隆，只拿最新必要历史；0=完整克隆
SUBMODULE_DEPTH="${SUBMODULE_DEPTH:-1}"                    # 浅克隆深度；默认 1，只锚定最新一层提交
SUBMODULE_FETCH_TAGS="${SUBMODULE_FETCH_TAGS:-0}"          # 1=同步 tags；默认 0，软件大包仓库不拉 tags 更快

# ============================== 脚本路径定位 ==============================
SCRIPT_FILE="${(%):-%x}"
SCRIPT_DIR=""
REPO_ROOT=""
SCRIPT_BASENAME="【MacOS】⏬下载配置当前Git子模块"
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
PREVIEW_FILE=""

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
# 同步显示终端输出并记录本轮日志。
log()          { printf '%s\n' "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()    { log "ℹ️  $*"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo() { log "✅ $*"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()    { log "⚠️  $*"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()   { printf '%s\n' "❌ $*" >&2; printf '%s\n' "❌ $*" >> "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()    { log "📝 $*"; }

# 来源重点只在交互终端着色，日志始终保存可直接搜索的纯文本。
source_highlight_echo() {
  local message="$1"
  printf '%s\n' "$message" >> "$LOG_FILE"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" &&
        "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
    printf '\033[1;36m%s\033[0m\n' "$message"
  else
    printf '%s\n' "$message"
  fi
}
# 只处理日志展示，不改变 Git 实际使用的地址。
safe_git_source_url() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | sed -E \
    -e 's#(https?://)[^/@]*@#\1[凭据已隐藏]@#' \
    -e 's#(://)[^/@]*:[^/@]*@#\1[凭据已隐藏]@#' \
    -e 's#[?#].*$#[参数已隐藏]#'
}
# --get-url 仅展开本地 insteadOf；在与该次 Git 操作相同的仓库作用域读取。
effective_git_source_url() {
  local repo_root="$1" url="$2" scope="${3:-repository}" effective_url=""
  if [[ "$scope" == clone ]]; then
    # clone 不读取父仓 local 配置，保留全局、系统和进程级规则。
    effective_url="$(GIT_DIR=/dev/null git -C "$repo_root" ls-remote --get-url -- "$url" 2>/dev/null)" || effective_url="$url"
  else
    effective_url="$(git -C "$repo_root" ls-remote --get-url -- "$url" 2>/dev/null)" || effective_url="$url"
  fi
  printf '%s\n' "$effective_url"
}
# 平台名称只用于展示；其它托管服务直接显示真实主机和端口。
git_source_platform() {
  local url="$1" host=""
  case "$url" in
    file://*) printf '%s\n' '本地文件'; return 0 ;;
    *://*) host="${url#*://}"; host="${host%%/*}"; host="${host##*@}" ;;
    *@*:*) host="${url%%:*}"; host="${host##*@}" ;;
    *) printf '%s\n' '本地路径'; return 0 ;;
  esac
  case "${(L)host}" in
    github.com|github.com:443|github.com:22) printf 'GitHub（%s）\n' "$host" ;;
    gitee.com|gitee.com:443|gitee.com:22) printf 'Gitee（%s）\n' "$host" ;;
    gitlab.com|gitlab.com:443|gitlab.com:22) printf 'GitLab（%s）\n' "$host" ;;
    *) safe_git_source_url "$host"; printf '\n' ;;
  esac
}
# 联网前突出本次来源，重写地址与解析地址不同时同时展示。
print_git_source() {
  local action="$1" repo_label="$2" repo_root="$3" url="$4" scope="${5:-repository}" effective_url=""
  effective_url="$(effective_git_source_url "$repo_root" "$url" "$scope")"
  source_highlight_echo "━━━━━━━━━━ Git 来源｜$action ━━━━━━━━━━"
  source_highlight_echo "📦 仓库：$repo_label"
  source_highlight_echo "🌐 平台 / 主机：$(git_source_platform "$effective_url")"
  if [[ "$effective_url" != "$url" ]]; then
    source_highlight_echo "🔎 解析地址：$(safe_git_source_url "$url")"
  fi
  source_highlight_echo "📥 拉取地址：$(safe_git_source_url "$effective_url")"
  source_highlight_echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
}

# 执行已经拆分完成的独立业务步骤。
run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}
# 封装 trim_string 对应的独立处理逻辑。
trim_string() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
# 封装 preview_safe_text 对应的独立处理逻辑。
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
# 解析并返回后续流程需要的目标信息。
get_ncpu() {
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null || echo 1
  else
    echo 1
  fi
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  uname -m
}
# 封装 cd_to_script_dir 对应的独立处理逻辑。
cd_to_script_dir() {
  cd "$REPO_ROOT"
  info_echo "当前工作目录已切换到目标仓库根目录：$(pwd)"
}
# 封装 contains_item 对应的独立处理逻辑。
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
# 解析任意托管站点地址，保留协议、SSH 用户/端口和完整 namespace。
parse_git_remote_url() {
  local raw="$(trim_string "$1")" prefix="" repo_path="" authority="" repo="" namespace=""
  raw="${raw%/}"
  [[ -n "$raw" && "$raw" != *[[:space:]]* && "$raw" != *[\|\?\#]* ]] || return 1
  case "$raw" in
    https://*|http://*|ssh://*|git://*)
      authority="${raw#*://}"
      [[ "$authority" == */* ]] || return 1
      repo_path="${authority#*/}"
      authority="${authority%%/*}"
      [[ -n "$authority" ]] || return 1
      case "$raw" in
        http://*|https://*) [[ "$authority" != *@* ]] || return 1 ;;
        ssh://*) [[ "${authority%%@*}" != *:* || "$authority" != *@* ]] || return 1 ;;
      esac
      prefix="${raw%%://*}://$authority/"
      ;;
    *@*:*)
      prefix="${raw%%:*}:"
      repo_path="${raw#*:}"
      [[ "$prefix" != */* && "$prefix" == *@*: ]] || return 1
      ;;
    *) return 1 ;;
  esac
  repo_path="${repo_path%.git}"
  [[ -n "$repo_path" && "$repo_path" != /* && "$repo_path" != */ && "$repo_path" != *//* ]] || return 1
  local component=""
  for component in "${(@s:/:)repo_path}"; do
    [[ "$component" != . && "$component" != .. && -n "$component" ]] || return 1
  done
  repo="${repo_path##*/}"
  namespace=""
  [[ "$repo_path" != */* ]] || namespace="${repo_path%/*}"
  [[ -n "$repo" ]] || return 1
  printf '%s|%s|%s\n' "$prefix" "$namespace" "$repo"
}
# 返回可对照真实 remote 的主机与 namespace，不推测跨平台 owner 映射。
git_remote_scope() {
  local parsed=""
  parsed="$(parse_git_remote_url "$1")" || return 1
  local prefix="${parsed%%|*}" rest="${parsed#*|}" host=""
  host="${prefix#*://}"
  host="${host%/}"
  host="${host%:}"
  host="${host##*@}"
  printf '%s|%s\n' "${(L)host}" "${rest%%|*}"
}
# 输出展示及常用协议地址；实际下载仍保留配置原地址和端口。
normalize_git_url() {
  local parsed=""
  parsed="$(parse_git_remote_url "$1")" || return 1
  local prefix="${parsed%%|*}" rest="${parsed#*|}" namespace="" repo="" host="" https_url="" ssh_url=""
  namespace="${rest%%|*}"
  repo="${rest#*|}"
  host="${prefix#*://}"
  host="${host%/}"
  host="${host%:}"
  host="${host##*@}"
  https_url="https://$host/${namespace:+$namespace/}$repo.git"
  ssh_url="git@$host:${namespace:+$namespace/}$repo.git"
  local page_url=""
  case "$prefix" in
    http://*|https://*)
      https_url="$prefix${namespace:+$namespace/}$repo.git"
      [[ "$host" != *:* ]] || ssh_url=""
      page_url="${https_url%.git}"
      ;;
    *)
      ssh_url="$prefix${namespace:+$namespace/}$repo.git"
      [[ "$host" != *:* ]] || https_url=""
      page_url="${https_url%.git}"
      [[ -n "$page_url" ]] || page_url="${ssh_url%.git}"
      ;;
  esac
  printf '%s|%s|%s|%s\n' "$page_url" "$https_url" "$ssh_url" "$repo"
}
# 按 Git 的仓库目录语义解析 ./ 与 ../，保留父 remote 的完整连接信息。
resolve_relative_git_url() {
  local parent_url="$1" relative_url="$2" parsed="" prefix="" rest="" component=""
  [[ "$relative_url" == ./* || "$relative_url" == ../* ]] || return 1
  [[ "$relative_url" != *[[:space:]\|\?\#]* ]] || return 1
  parsed="$(parse_git_remote_url "$parent_url")" || return 1
  prefix="${parsed%%|*}"
  rest="${parsed#*|}"
  local -a components resolved
  local parent_repo="${rest#*|}"
  [[ "${parent_url%/}" != *.git ]] || parent_repo+=".git"
  components=("${(@s:/:)${rest%%|*}}" "$parent_repo" "${(@s:/:)relative_url}")
  resolved=()
  for component in "${components[@]}"; do
    case "$component" in
      ''|.) ;;
      ..)
        (( ${#resolved[@]} > 0 )) || return 1
        resolved[-1]=()
        ;;
      *) resolved+=("$component") ;;
    esac
  done
  (( ${#resolved[@]} > 0 )) || return 1
  printf '%s%s\n' "$prefix" "${(j:/:)resolved}"
}
# Gitee 标准 SSH 地址使用已确认的 HTTPS 入口，不改仓名或推断自定义端口。
normalize_gitee_https_url() {
  local url="$1"
  case "$url" in
    git@gitee.com:*) printf 'https://gitee.com/%s\n' "${url#git@gitee.com:}" ;;
    ssh://git@gitee.com/*) printf 'https://gitee.com/%s\n' "${url#ssh://git@gitee.com/}" ;;
    ssh://git@gitee.com:22/*) printf 'https://gitee.com/%s\n' "${url#ssh://git@gitee.com:22/}" ;;
    *) printf '%s\n' "$url" ;;
  esac
}
# 追加本次进程的 Git 规则，让首次递归克隆也走 HTTPS，不写全局配置。
configure_gitee_https_transport() {
  [[ "${JOBS_GITEE_HTTPS_CONFIGURED:-0}" != 1 ]] || return 0
  local config_count="${GIT_CONFIG_COUNT:-0}" prefix=""
  if [[ "$config_count" != <-> || ${#config_count} -gt 9 ]]; then
    error_echo "GIT_CONFIG_COUNT 无效或过大，未修改 Git 下载环境。"
    return 1
  fi
  local -i config_index=$(( 10#$config_count ))
  local -a ssh_prefixes
  ssh_prefixes=('git@gitee.com:' 'ssh://git@gitee.com/' 'ssh://git@gitee.com:22/')
  for prefix in "${ssh_prefixes[@]}"; do
    typeset -gx "GIT_CONFIG_KEY_${config_index}=url.https://gitee.com/.insteadOf"
    typeset -gx "GIT_CONFIG_VALUE_${config_index}=$prefix"
    (( config_index += 1 ))
  done
  export GIT_CONFIG_COUNT="$config_index"
  typeset -g JOBS_GITEE_HTTPS_CONFIGURED=1
  info_echo "Gitee 标准 SSH 地址在本次进程改走 HTTPS，首次克隆和递归子模块均继承。"
}
# 仅在用户显式指定协议时转换；Gitee 标准地址固定 HTTPS，自定义端口保持边界。
git_url_with_style() {
  local url="$1" style="${GIT_URL_STYLE:-auto}" parsed="" prefix="" rest="" host="" repo_path=""
  url="$(normalize_gitee_https_url "$url")"
  if [[ "$url" == https://gitee.com/* ]]; then
    printf '%s\n' "$url"
    return 0
  fi
  [[ "$style" == auto ]] && { printf '%s\n' "$url"; return 0; }
  parsed="$(parse_git_remote_url "$url")" || return 1
  prefix="${parsed%%|*}"
  rest="${parsed#*|}"
  case "$style:$prefix" in
    https:http://*|https:https://*|ssh:ssh://*|ssh:*@*:)
      printf '%s\n' "$url"
      return 0
      ;;
  esac
  host="${prefix#*://}"
  host="${host%/}"
  host="${host%:}"
  host="${host##*@}"
  if [[ "$host" == *:* ]]; then
    error_echo "无法推测跨协议端口，请使用 GIT_URL_STYLE=auto 或为子模块配置完整目标地址：$url"
    return 1
  fi
  case "$style" in
    https) repo_path="${rest%%|*}"; printf 'https://%s/%s%s.git\n' "$host" "${repo_path:+$repo_path/}" "${rest#*|}" ;;
    ssh) repo_path="${rest%%|*}"; printf 'git@%s:%s%s.git\n' "$host" "${repo_path:+$repo_path/}" "${rest#*|}" ;;
    *) error_echo "GIT_URL_STYLE 只支持 auto/https/ssh：$style"; return 1 ;;
  esac
}
# 从清单提取原始地址，避免 SSH 自定义端口被展示用地址替代。
configured_git_url_by_path() {
  local target="$1" spec="" raw="" local_path="" parsed=""
  for spec in "${SUBMODULE_REPO_URLS[@]}"; do
    raw="$(trim_string "${spec%%|*}")"
    if [[ "$spec" == *'|'* ]]; then
      local_path="$(trim_string "${spec#*|}")"
    else
      parsed="$(parse_git_remote_url "$raw")" || continue
      local_path="${parsed##*|}"
    fi
    [[ "$local_path" == "$target" ]] || continue
    printf '%s\n' "$raw"
    return 0
  done
  repo_https_by_path "$target"
}
# 封装 entry_path 对应的独立处理逻辑。
entry_path() {
  local entry="$1"
  printf '%s\n' "${entry%%|*}"
}
# 封装 entry_page 对应的独立处理逻辑。
entry_page() {
  local entry="$1"
  local rest="${entry#*|}"
  printf '%s\n' "${rest%%|*}"
}
# 封装 entry_https 对应的独立处理逻辑。
entry_https() {
  local entry="$1"
  local rest="${entry#*|}"
  rest="${rest#*|}"
  printf '%s\n' "${rest%%|*}"
}
# 封装 entry_ssh 对应的独立处理逻辑。
entry_ssh() {
  local entry="$1"
  local rest="${entry#*|}"
  rest="${rest#*|}"
  rest="${rest#*|}"
  printf '%s\n' "${rest%%|*}"
}
# 封装 entry_repo 对应的独立处理逻辑。
entry_repo() {
  local entry="$1"
  local rest="${entry#*|}"
  rest="${rest#*|}"
  rest="${rest#*|}"
  rest="${rest#*|}"
  printf '%s\n' "$rest"
}
# 解析并返回后续流程需要的目标信息。
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
# 封装 repo_page_by_path 对应的独立处理逻辑。
repo_page_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_page "$entry"
}
# 封装 repo_https_by_path 对应的独立处理逻辑。
repo_https_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_https "$entry"
}
# 封装 repo_ssh_by_path 对应的独立处理逻辑。
repo_ssh_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_ssh "$entry"
}
# 封装 repo_name_by_path 对应的独立处理逻辑。
repo_name_by_path() {
  local entry=""
  entry="$(get_entry_by_path "$1")" || return 1
  entry_repo "$entry"
}
# 检查当前运行条件是否满足后续流程要求。
validate_local_path() {
  local local_path="$1"

  if [[ -z "$local_path" || "$local_path" == . || "$local_path" == .. || "$local_path" == */* || "$local_path" == *"|"* ]]; then
    return 1
  fi

  return 0
}
# 封装 load_configured_submodules 对应的独立处理逻辑。
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

    local normalized=""
    if ! normalized="$(normalize_git_url "$url_part")"; then
      error_echo "SUBMODULE_REPO_URLS 存在无法识别的 Git 仓库地址：$url_part"
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
# 封装 append_runtime_submodule 对应的独立处理逻辑。
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
# 查找已验证可运行的 Homebrew，避免重复安装。
find_brew_bin() {
  jobs_brew_find
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
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
# 执行对应的环境配置或同步处理。
install_homebrew() {
  jobs_brew_install_or_exit # 只在真正安装时选择路径；演练模式不安装。
}
# 检查当前运行条件是否满足后续流程要求。
ensure_homebrew_healthy() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || exit 1
  fi
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
# 检查当前运行条件是否满足后续流程要求。
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
# 验证当前目录就是父仓根目录，拒绝错误层级和隐式初始化。
ensure_repo_initialized() {
  local git_root=""
  local current_root=""

  current_root="$(pwd -P)"
  if ! git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    error_echo "当前目录不是父 Git 仓库：$current_root"
    return 1
  fi

  git_root="$(cd "$git_root" && pwd -P)"
  if [[ "$git_root" != "$current_root" ]]; then
    error_echo "脚本必须在父 Git 根目录运行：$current_root；当前 Git 根目录：$git_root"
    return 1
  fi

  info_echo "已位于父 Git 仓库根目录：$current_root"
  run_cmd git config core.quotepath false || true
  git -c core.quotepath=false status >/dev/null
}
# 检查当前运行条件是否满足后续流程要求。
ensure_git_remote() {
  local remote_name="${1:-$REMOTE_NAME}"

  if git remote get-url "$remote_name" >/dev/null 2>&1; then
    local source_url=""
    source_url="$(git config --get-all "remote.$remote_name.url" 2>/dev/null || git remote get-url "$remote_name")"
    source_url="${source_url%%$'\n'*}"
    print_git_source "父仓线路 [$remote_name]" "$remote_name" "$PWD" "$source_url"
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
      success_echo "已添加父仓远端：$remote_name -> $(safe_git_source_url "$remote_url")"
      print_git_source "父仓线路 [$remote_name]" "$remote_name" "$PWD" "$remote_url"
      return 0
    fi

    error_echo "无法访问父仓远端：$remote_url"
  done
}
# 解析并返回后续流程需要的目标信息。
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
# 相对 URL 完整跟随所选父 remote，明确绝对 URL 保留其平台和 namespace。
clone_url_for_path() {
  local submodule_path="$1" url="" parent_url=""
  url="$(gitmodules_url_for_path "$submodule_path")" || return 1
  if [[ "$url" == ./* || "$url" == ../* ]]; then
    parent_url="$(git remote get-url "$REMOTE_NAME" 2>/dev/null)" || return 1
    url="$(resolve_relative_git_url "$parent_url" "$url")" || {
      error_echo "无法相对父远端解析子模块地址：$submodule_path -> $url"
      return 1
    }
  fi
  git_url_with_style "$url"
}
# 逐层同步已初始化子仓的真实地址，避免命令行覆盖被递归继承。
# 拒绝越界路径和指向仓外的符号链接，再确认已有子仓的独立根目录。
validate_submodule_url_path() {
  local repo_root="$1" submodule_path="$2" component="" child_root="" child_git_root=""
  [[ -n "$submodule_path" && "$submodule_path" != /* && "$submodule_path" != *$'\n'* && "$submodule_path" != *$'\r'* ]] || return 1
  for component in "${(@s:/:)submodule_path}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
  done
  repo_root="${repo_root:A}"
  child_root="$repo_root/$submodule_path"
  child_root="${child_root:A}"
  [[ "$child_root" == "$repo_root"/* ]] || return 1
  if [[ -e "$child_root/.git" ]]; then
    child_git_root="$(git -C "$child_root" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ "${child_git_root:A}" == "$child_root" ]] || return 1
  fi
}
# 逐层解析实际下载地址，同步本地配置并按需核对来源。
sync_submodule_urls_at_repo() {
  local repo_root="$1" parent_url="$2" key="" section="" submodule_path="" url="" child_root=""
  local show_sources="${3:-0}" source_repo="" source_scope=""
  [[ -f "$repo_root/.gitmodules" ]] || return 0
  while IFS= read -r key; do
    section="${key#submodule.}"
    section="${section%.path}"
    submodule_path="$(git config -f "$repo_root/.gitmodules" --get "$key")" || return 1
    validate_submodule_url_path "$repo_root" "$submodule_path" || {
      error_echo "拒绝同步仓外或非独立子仓路径：$submodule_path"
      return 1
    }
    child_root="$repo_root/$submodule_path"
    url="$(git config -f "$repo_root/.gitmodules" --get "submodule.$section.url")" || return 1
    if [[ "$url" == ./* || "$url" == ../* ]]; then
      url="$(resolve_relative_git_url "$parent_url" "$url")" || return 1
    fi
    url="$(git_url_with_style "$url")" || return 1
    if [[ "$show_sources" == 1 ]]; then
      source_repo="$repo_root"
      source_scope=clone
      if [[ -e "$child_root/.git" ]]; then
        source_repo="$child_root"
        source_scope=repository
      fi
      print_git_source "递归来源核对" "${child_root#"$PWD"/}" "$source_repo" "$url" "$source_scope"
    fi
    run_cmd git -C "$repo_root" config "submodule.$section.url" "$url" || return 1
    [[ -e "$child_root/.git" ]] || continue
    run_cmd git -C "$child_root" remote set-url origin "$url" || return 1
    sync_submodule_urls_at_repo "$child_root" "$url" "$show_sources" || return 1
  done < <(git config -f "$repo_root/.gitmodules" --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}
# 从显式选择的父 remote 开始，各层只使用自身解析后的地址。
sync_submodule_urls_for_remote() {
  local parent_url="" repo_root=""
  parent_url="$(git remote get-url "$REMOTE_NAME" 2>/dev/null)" || return 1
  repo_root="$(git rev-parse --show-toplevel)" || return 1
  sync_submodule_urls_at_repo "$repo_root" "$parent_url"
}
# 封装 parent_has_uncommitted_changes 对应的独立处理逻辑。
parent_has_uncommitted_changes() {
  [[ -n "$(git -c core.quotepath=false status --porcelain)" ]]
}
# 检查当前运行条件是否满足后续流程要求。
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
# 封装 parent_pull_rebase 对应的独立处理逻辑。
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
# 封装 parent_push_if_needed 对应的独立处理逻辑。
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
# 从远端 HEAD 读取默认分支，不创建或改名本地分支。
remote_default_branch_by_url() {
  local url="$1"
  local branch=""

  branch="$(git ls-remote --symref "$url" HEAD 2>/dev/null | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }' || true)"
  [[ -n "$branch" ]] && printf '%s\n' "$branch"
}
# 封装 remote_branch_exists 对应的独立处理逻辑。
remote_branch_exists() {
  local url="$1"
  local branch="$2"
  git ls-remote --exit-code --heads "$url" "$branch" >/dev/null 2>&1
}
# 封装 remote_branch_for_url 对应的独立处理逻辑。
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
# 判断目标是否为可用的 Git 工作区。
is_git_worktree() {
  local submodule_path="$1"
  [[ -e "$submodule_path/.git" ]] || return 1
  git -C "$submodule_path" rev-parse --is-inside-work-tree >/dev/null 2>&1
}
# 检查当前运行条件是否满足后续流程要求。
is_gitlink_registered() {
  local submodule_path="$1"
  git ls-files --stage -- "$submodule_path" 2>/dev/null | awk '{ if ($1 == "160000") found=1 } END { exit found ? 0 : 1 }'
}
# 检查当前运行条件是否满足后续流程要求。
is_dir_empty() {
  local submodule_path="$1"
  [[ -d "$submodule_path" ]] || return 1
  local -a entries
  entries=("$submodule_path"/*(DN))
  [[ ${#entries} -eq 0 ]]
}
# 封装 assert_clean_submodule 对应的独立处理逻辑。
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
# 保留已有共享登记文件，缺失时才建立空文件。
ensure_gitmodules_file_exists() {
  if [[ -f .gitmodules ]]; then
    return 0
  fi

  run_cmd touch .gitmodules
  warn_echo ".gitmodules 当前不存在，已按 SUBMODULE_REPO_URLS 重建空文件，后续会逐项查漏补缺"
}
# 解析并返回后续流程需要的目标信息。
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
# 封装 collect_gitmodules_paths 对应的独立处理逻辑。
collect_gitmodules_paths() {
  [[ -f .gitmodules ]] || return 0

  local key=""
  while IFS= read -r key; do
    git config -f .gitmodules --get "$key" 2>/dev/null || true
  done < <(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}
# 已知镜像仓名不同时保留明确绝对地址，不把当前平台仓名传播到其它平台。
submodule_has_consistent_remote_names() {
  local submodule_path="$1" expected_name="$2" remote_name="" remote_url="" remote_repo=""
  [[ -e "$submodule_path/.git" ]] || return 0
  while IFS= read -r remote_name; do
    remote_url="$(git -C "$submodule_path" remote get-url "$remote_name" 2>/dev/null)" || continue
    remote_repo="$(repo_name_from_git_url "$remote_url")" || continue
    [[ "$remote_repo" == "$expected_name" ]] || return 1
  done < <(git -C "$submodule_path" remote 2>/dev/null)
}
# 保留已有清单 URL；新增条目只依据真实 remote 或同 namespace 配置生成。
gitmodules_url_for_path() {
  local submodule_path="$1" section="" current_url="" parent_url="" parent_scope="" source_url="" source_scope=""
  section="$(find_gitmodules_section_by_path "$submodule_path" 2>/dev/null || true)"
  if [[ -n "$section" ]]; then
    current_url="$(git config -f .gitmodules --get "submodule.$section.url" 2>/dev/null || true)"
    [[ -z "$current_url" ]] || { printf '%s\n' "$current_url"; return 0; }
  fi
  parent_url="$(git remote get-url "$REMOTE_NAME" 2>/dev/null)" || {
    error_echo "父仓远端不存在：$REMOTE_NAME；无法确定子模块来源：$submodule_path"
    return 1
  }
  parent_scope="$(git_remote_scope "$parent_url")" || return 1
  source_url="$(configured_git_url_by_path "$submodule_path")" || return 1
  source_scope="$(git_remote_scope "$source_url")" || return 1

  local remote_name="" child_url="" child_scope="" child_identity="" selected_url="" selected_identity=""
  if [[ -e "$submodule_path/.git" ]]; then
    while IFS= read -r remote_name; do
      child_url="$(git -C "$submodule_path" remote get-url "$remote_name" 2>/dev/null)" || continue
      child_scope="$(git_remote_scope "$child_url")" || continue
      [[ "${child_scope%%|*}" == "${parent_scope%%|*}" ]] || continue
      child_identity="$child_scope|$(repo_name_from_git_url "$child_url")"
      if [[ -n "$selected_identity" && "$selected_identity" != "$child_identity" ]]; then
        error_echo "子仓在所选平台有多个不同地址，请先在 .gitmodules 明确配置：$submodule_path"
        return 1
      fi
      selected_url="$child_url"
      selected_identity="$child_identity"
    done < <(git -C "$submodule_path" remote 2>/dev/null)
  fi
  if [[ -n "$selected_url" ]]; then
    if [[ "$(git_remote_scope "$selected_url")" == "$parent_scope" ]] &&
       submodule_has_consistent_remote_names "$submodule_path" "$(repo_name_from_git_url "$selected_url")"; then
      printf '../%s.git\n' "$(repo_name_from_git_url "$selected_url")"
    else
      printf '%s\n' "$selected_url"
    fi
    return 0
  fi
  if [[ "$source_scope" == "$parent_scope" ]] &&
     submodule_has_consistent_remote_names "$submodule_path" "$(repo_name_from_git_url "$source_url")"; then
    printf '../%s.git\n' "$(repo_name_from_git_url "$source_url")"
    return 0
  fi

  if [[ "${source_scope%%|*}" == "${parent_scope%%|*}" ]]; then
    printf '%s\n' "$source_url"
    return 0
  fi
  error_echo "无法确认 $submodule_path 在远端 $REMOTE_NAME 的对应地址；请在 .gitmodules 明确配置目标 URL，或为本地子仓添加已核实的对应 remote。"
  return 1
}
# 提取远端真实仓名，不从本地目录名推断。
repo_name_from_git_url() {
  local parsed=""
  parsed="$(parse_git_remote_url "$1")" || return 1
  printf '%s\n' "${parsed##*|}"
}
# 执行对应的清理操作，并保留必要的安全检查。
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
# 检查当前运行条件是否满足后续流程要求。
# 增量补齐缺项，保留已有 URL、分支与扩展字段。
ensure_gitmodules_entry() {
  local submodule_path="$1" section="" desired_url="${2:-}" new_section=0
  ensure_gitmodules_file_exists || return 1
  section="$(find_gitmodules_section_by_path "$submodule_path" 2>/dev/null || true)"
  if [[ -z "$section" ]]; then
    section="$submodule_path"
    new_section=1
  fi
  local changed=0 cur_path="" cur_url="" cur_branch=""
  cur_path="$(git config -f .gitmodules --get "submodule.$section.path" 2>/dev/null || true)"
  cur_url="$(git config -f .gitmodules --get "submodule.$section.url" 2>/dev/null || true)"
  cur_branch="$(git config -f .gitmodules --get "submodule.$section.branch" 2>/dev/null || true)"
  if [[ -z "$cur_url" ]]; then
    [[ -n "$desired_url" ]] || desired_url="$(gitmodules_url_for_path "$submodule_path")" || return 1
    if [[ "$desired_url" == ./* || "$desired_url" == ../* ]]; then
      resolve_relative_git_url "$(git remote get-url "$REMOTE_NAME")" "$desired_url" >/dev/null || return 1
    elif ! parse_git_remote_url "$desired_url" >/dev/null; then
      error_echo "子模块目标地址无效或含凭据，未写入 .gitmodules：$submodule_path"
      return 1
    fi
  fi
  if [[ "$cur_path" != "$submodule_path" ]]; then
    run_cmd git config -f .gitmodules "submodule.$section.path" "$submodule_path" || return 1
    changed=1
  fi
  if [[ -z "$cur_url" ]]; then
    run_cmd git config -f .gitmodules "submodule.$section.url" "$desired_url" || return 1
    changed=1
  fi
  if [[ "$new_section" == 1 && -z "$cur_branch" ]]; then
    run_cmd git config -f .gitmodules "submodule.$section.branch" "$SUBMODULE_BRANCH" || return 1
    changed=1
  fi
  if [[ "$changed" == 1 ]]; then
    note_echo ".gitmodules 已查漏补缺：$submodule_path"
  else
    info_echo ".gitmodules 已存在，保留 URL、分支与扩展字段：$submodule_path"
  fi
}
# 封装 prune_unconfigured_gitmodules 对应的独立处理逻辑。
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
          run_cmd rm -rf "$existing_path" || return 1
          warn_echo "已删除旧子模块目录：$existing_path"
        else
          error_echo "旧子模块目录不是 Git 且非空，默认拒绝删除：$existing_path；确认要删可设置 FORCE_DELETE=1"
          return 1
        fi
      fi
    fi
  done < <(collect_gitmodules_paths)
}
# 封装 reconcile_gitmodules_with_config_once 对应的独立处理逻辑。
reconcile_gitmodules_with_config_once() {
  if [[ "$GITMODULES_RECONCILED" == "1" ]]; then
    info_echo ".gitmodules 本轮已完成查漏补缺，跳过重复自检"
    return 0
  fi

  ensure_gitmodules_file_exists || return 1

  local p=""
  for p in "${CONFIG_PATHS[@]}"; do
    ensure_gitmodules_entry "$p" || return 1
  done

  prune_unconfigured_gitmodules || return 1
  GITMODULES_RECONCILED=1
  success_echo ".gitmodules 查漏补缺完成"
}
# ============================== 子模块目录清理/添加/同步 ==============================
# 按输入顺序去重目录，避免重复处理目标。
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
# 封装 collect_full_delete_targets 对应的独立处理逻辑。
collect_full_delete_targets() {
  {
    local p=""
    for p in "${CONFIG_PATHS[@]}"; do
      printf '%s\n' "$p"
      repo_name_by_path "$p" 2>/dev/null || true
    done
  } | unique_paths_from_stdin
}
# 按真实 section 定位目标缓存，删除前核验边界、工作区归属和独立引用。
submodule_cache_for_removal() {
  local submodule_path="$1" section="" parent_git_dir="" modules_root="" cache_dir=""
  local worktree="" expected_worktree="" actual_git_dir="" key="" other_section="" other_path=""
  section="$(find_gitmodules_section_by_path "$submodule_path" || true)"
  if [[ -z "$section" ]]; then
    if [[ -f "$submodule_path/.git" ]] || is_gitlink_registered "$submodule_path"; then
      error_echo "缺少明确的子模块登记，无法安全定位 Git 缓存：$submodule_path"
      return 1
    fi
    return 0
  fi
  if [[ "$section" == /* || "$section" == */ || "$section" == *//* || "$section" == *$'\n'* || "$section" == *$'\r'* ]]; then
    error_echo "子模块 section 不是安全的相对缓存路径：$section"
    return 1
  fi
  local component=""
  for component in "${(@s:/:)section}"; do
    if [[ -z "$component" || "$component" == . || "$component" == .. ]]; then
      error_echo "子模块 section 包含越界路径：$section"
      return 1
    fi
  done
  parent_git_dir="$(git rev-parse --absolute-git-dir)" || return 1
  parent_git_dir="${parent_git_dir:A}"
  modules_root="$parent_git_dir/modules"
  cache_dir="$modules_root/$section"
  [[ -e "$cache_dir" || -L "$cache_dir" ]] || return 0
  if [[ ! -d "$cache_dir" || -L "$modules_root" || "${cache_dir:A}" != "$cache_dir" ]]; then
    error_echo "子模块缓存不是父仓 modules 下的普通目录，拒绝删除：$cache_dir"
    return 1
  fi
  while IFS= read -r key; do
    other_section="${key#submodule.}"
    other_section="${other_section%.path}"
    other_path="$(git config -f .gitmodules --get "$key")" || return 1
    if [[ "$other_section" != "$section" && ( "$other_section" == "$section/"* || "$other_path" == "$submodule_path" ) ]]; then
      error_echo "目标缓存与其它子模块登记重叠，拒绝删除：$section / $other_section"
      return 1
    fi
  done < <(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$')
  worktree="$(git config --file "$cache_dir/config" --get core.worktree)" || {
    error_echo "缓存缺少可核验的 core.worktree，拒绝删除：$cache_dir"
    return 1
  }
  [[ "$worktree" == /* ]] || worktree="$cache_dir/$worktree"
  expected_worktree="$PWD/$submodule_path"
  if [[ "${worktree:A}" != "${expected_worktree:A}" ]]; then
    error_echo "缓存属于其它工作目录，拒绝删除：$cache_dir"
    return 1
  fi
  if [[ -e "$submodule_path/.git" ]]; then
    actual_git_dir="$(git -C "$submodule_path" rev-parse --absolute-git-dir)" || return 1
    if [[ "${actual_git_dir:A}" != "$cache_dir" ]]; then
      error_echo "当前子仓与候选缓存指向不同元数据，拒绝删除：$submodule_path"
      return 1
    fi
  fi
  if [[ -d "$cache_dir/worktrees" && -n "$(ls -A "$cache_dir/worktrees")" ]]; then
    error_echo "子模块缓存仍登记其它 worktree，拒绝删除：$cache_dir"
    return 1
  fi
  printf '%s\n' "$cache_dir"
}
# 只删除已核验属于目标子仓的工作目录和真实 Git 缓存。
remove_worktree_dir_safely() {
  local submodule_path="$1" submodule_cache=""

  if ! validate_local_path "$submodule_path" || [[ "$submodule_path" == .git || -L "$submodule_path" ]]; then
    error_echo "拒绝删除危险路径或符号链接：$submodule_path"
    return 1
  fi

  assert_clean_submodule "$submodule_path" "删除目录" || return 1
  submodule_cache="$(submodule_cache_for_removal "$submodule_path")" || return 1

  if is_gitlink_registered "$submodule_path"; then
    run_cmd git submodule deinit -f -- "$submodule_path" || return 1
  fi

  if [[ -n "$submodule_cache" ]]; then
    run_cmd rm -rf -- "$submodule_cache" || return 1
    note_echo "已清理目标子模块缓存：$submodule_cache"
  fi

  if [[ -e "$submodule_path" ]]; then
    if is_git_worktree "$submodule_path" || is_dir_empty "$submodule_path" || [[ "$FORCE_DELETE" == "1" ]]; then
      run_cmd rm -rf "$submodule_path" || return 1
      warn_echo "已删除目标目录：$submodule_path"
    else
      error_echo "发现非 Git 且非空目录，默认拒绝删除：$submodule_path；确认要删可设置 FORCE_DELETE=1"
      return 1
    fi
  fi

  # 注意：这里故意不删除 .gitmodules 段、不 git rm --cached。
  # 全量同步只是刷新工作区目录；.gitmodules 由 reconcile_gitmodules_with_config_once 负责查漏补缺。
}
# 封装 clone_submodule_worktree 对应的独立处理逻辑。
clone_submodule_worktree() {
  local submodule_path="$1"
  local url=""
  url="$(clone_url_for_path "$submodule_path")" || return 1
  print_git_source "首次克隆" "$submodule_path" "$PWD" "$url" clone
  local branch=""
  branch="$(remote_branch_for_url "$url" "$SUBMODULE_BRANCH")" || return 1

  local -a clone_args
  clone_args=()

  if [[ "$SUBMODULE_SHALLOW_CLONE" == "1" ]]; then
    clone_args+=(--depth "$SUBMODULE_DEPTH" --single-branch --shallow-submodules)
  fi

  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    clone_args+=(--no-tags)
  fi

  if remote_branch_exists "$url" "$branch"; then
    info_echo "克隆分支：$branch"
    run_cmd git clone "${clone_args[@]}" --branch "$branch" --recurse-submodules --jobs="$(get_ncpu)" "$url" "$submodule_path" || return 1
  else
    warn_echo "远端未确认存在分支 $branch，将按远端默认分支 clone：$submodule_path"
    run_cmd git clone "${clone_args[@]}" --recurse-submodules --jobs="$(get_ncpu)" "$url" "$submodule_path" || return 1
  fi

  run_cmd git -C "$submodule_path" config core.quotepath false || true
  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    run_cmd git -C "$submodule_path" config remote.origin.tagOpt --no-tags || true
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_submodule_worktree_present() {
  local submodule_path="$1"

  # 不走 git submodule update 做首次下载，因为它会严格使用 .gitmodules 的 url。
  # 这里按 .gitmodules 与所选父 remote 的完整地址解析下载，保留绝对 URL 例外。
  if [[ -e "$submodule_path" ]]; then
    if is_git_worktree "$submodule_path"; then
      assert_clean_submodule "$submodule_path" "纳入子模块" || return 1
    elif is_dir_empty "$submodule_path"; then
      run_cmd rm -rf "$submodule_path" || return 1
    else
      error_echo "目标目录已存在且不是 Git 空目录，拒绝覆盖：$submodule_path"
      return 1
    fi
  fi

  if [[ ! -e "$submodule_path" ]]; then
    clone_submodule_worktree "$submodule_path" || return 1
  fi

  # 不使用 git submodule add，避免 .gitmodules 被 Git 自动重写；手动 add 会把内部 Git 仓登记为 gitlink。
  run_cmd git add -- .gitmodules "$submodule_path" || return 1

  # 标准子模块形态：子仓目录里保留 .git 单文件，真正 Git 数据放到父仓 .git/modules 下。
  # 这一步不决定是否浅克隆；浅克隆由 --depth 控制。这里负责把 .git 文件夹吸收到父仓管理。
  if ! run_cmd git submodule absorbgitdirs -- "$submodule_path"; then
    error_echo "子模块元数据归集失败：$submodule_path；未标记为完成。"
    return 1
  fi
  run_cmd git add -- .gitmodules "$submodule_path" || return 1

  if [[ "$DRY_RUN" == 1 ]]; then
    note_echo "[DRY-RUN] 已计划登记并归集子模块：$submodule_path"
  elif [[ -f "$submodule_path/.git" ]]; then
    success_echo "已登记标准子模块 gitlink：$submodule_path（子仓 .git 为单文件）"
  else
    error_echo "子模块元数据未形成标准 .git 指针：$submodule_path；未标记为完成。"
    return 1
  fi
}
# 解析并返回后续流程需要的目标信息。
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
# 执行对应的环境配置或同步处理。
sync_one_submodule_to_latest() {
  local submodule_path="$1"
  local url=""
  url="$(clone_url_for_path "$submodule_path")" || return 1

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
  run_cmd git -C "$submodule_path" remote set-url origin "$url" || return 1
  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    run_cmd git -C "$submodule_path" config remote.origin.tagOpt --no-tags || true
  fi

  print_git_source "拉取更新" "$submodule_path" "$PWD/$submodule_path" "$url"
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

  info_echo "拉取分支：origin/$branch"
  run_cmd git -C "$submodule_path" fetch "${fetch_args[@]}" origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" --prune || return 1
  run_cmd git -C "$submodule_path" -c core.quotepath=false checkout -B "$branch" "origin/$branch" || return 1
  run_cmd git -C "$submodule_path" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null 2>&1 || true
  run_cmd git -C "$submodule_path" reset --hard "origin/$branch" || return 1

  sync_submodule_urls_at_repo "$PWD/$submodule_path" "$url" 1 || return 1

  local -a submodule_update_args
  submodule_update_args=(submodule update --init --recursive --jobs="$(get_ncpu)")
  if [[ "$SUBMODULE_SHALLOW_CLONE" == "1" ]]; then
    submodule_update_args+=(--depth "$SUBMODULE_DEPTH" --recommend-shallow)
  fi
  if ! run_cmd git -C "$submodule_path" "${submodule_update_args[@]}"; then
    error_echo "递归子模块同步失败：$submodule_path；未标记为同步成功。"
    return 1
  fi

  # 再次确保子仓是标准 submodule 形态：工作目录下 .git 为单文件，Git 数据由父仓 .git/modules 托管。
  if ! run_cmd git submodule absorbgitdirs -- "$submodule_path"; then
    error_echo "子模块元数据归集失败：$submodule_path；未标记为完成。"
    return 1
  fi

  success_echo "$submodule_path 已浅同步到 origin/$branch：$(git -C "$submodule_path" rev-parse --short HEAD)（来源：$(safe_git_source_url "$(effective_git_source_url "$PWD/$submodule_path" "$url")")）"
}
# 执行对应的环境配置或同步处理。
sync_selected_submodules_to_latest() {
  local -a paths
  paths=("$@")
  local p=""

  if [[ ${#paths} -eq 0 ]]; then
    warn_echo "没有需要同步的子模块"
    return 0
  fi

  for p in "${paths[@]}"; do
    ensure_submodule_worktree_present "$p" || return 1
    sync_one_submodule_to_latest "$p" || return 1
  done
}
# 封装 stage_and_commit_parent_changes 对应的独立处理逻辑。
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

  run_cmd git add -A -- "${add_targets[@]}" || return 1

  if git diff --cached --quiet -- "${add_targets[@]}"; then
    info_echo "父仓 .gitmodules/gitlink 无变化，跳过提交"
    return 0
  fi

  local style=""
  style="$(detect_git_url_style)"
  run_cmd git --literal-pathspecs -c core.quotepath=false commit --only -m "chore: sync git submodules (${style})" -- "${add_targets[@]}" || return 1
  success_echo "父仓已提交 .gitmodules/gitlink 变化"
}
# 删除前展示精确清单并要求 YES；演练不触发破坏性确认。
confirm_full_rebuild() {
  [[ "$DRY_RUN" != 1 ]] || return 0
  local target="" answer=""
  warn_echo "全量模式会删除下列目标目录与对应子模块缓存，再按清单重建；本地独有提交可能丢失。"
  while IFS= read -r target; do
    [[ -z "$target" ]] || note_echo "全量重建目标：$target"
  done < <(collect_full_delete_targets)
  if [[ ! -t 0 ]]; then
    error_echo "全量重建需要在交互终端输入 YES，未执行删除。"
    return 1
  fi
  if ! IFS= read -r "answer?确认删除并重建以上目标？输入 YES 后回车执行；其它输入取消："; then
    note_echo "输入已结束，已取消全量重建。"
    return 1
  fi
  if [[ "$answer" != YES ]]; then
    note_echo "未输入 YES，已取消全量重建。"
    return 1
  fi
}
# 确认后只重建脚本清单与对应旧仓名目录。
full_sync_to_latest() {
  if ! confirm_full_rebuild; then
    return 0
  fi
  info_echo "开始全量同步：先对 .gitmodules 做一次查漏补缺；再删除 SUBMODULE_REPO_URLS 配置的目标目录；最后按配置重建"

  reconcile_gitmodules_with_config_once || return 1

  local -a delete_targets
  delete_targets=()
  local p=""
  while IFS= read -r p; do
    [[ -n "$p" ]] && delete_targets+=("$p")
  done < <(collect_full_delete_targets)

  for p in "${delete_targets[@]}"; do
    remove_worktree_dir_safely "$p" || return 1
  done

  local -a synced_paths
  synced_paths=()
  for p in "${CONFIG_PATHS[@]}"; do
    synced_paths+=("$p")
  done

  sync_selected_submodules_to_latest "${synced_paths[@]}" || return 1
  sync_submodule_urls_for_remote || return 1
  stage_and_commit_parent_changes "${synced_paths[@]}" || return 1
  parent_push_if_needed || return 1
  success_echo "全量同步完成"
}
# 封装 collect_existing_configured_git_paths 对应的独立处理逻辑。
collect_existing_configured_git_paths() {
  local p=""
  for p in "${CONFIG_PATHS[@]}"; do
    if is_git_worktree "$p"; then
      printf '%s\n' "$p"
    fi
  done
}
# 执行对应的环境配置或同步处理。
update_existing_to_latest() {
  local -a existing_paths
  existing_paths=()
  local p=""

  while IFS= read -r p; do
    [[ -n "$p" ]] && existing_paths+=("$p")
  done < <(collect_existing_configured_git_paths)

  if [[ ${#existing_paths} -eq 0 ]]; then
    warn_echo "当前不存在任何已配置的本地 Git 子目录，自动切换为全量同步"
    full_sync_to_latest || return 1
    return 0
  fi

  reconcile_gitmodules_with_config_once || return 1
  info_echo "只同步当前已有的子 Git 目录：${existing_paths[*]}"
  sync_selected_submodules_to_latest "${existing_paths[@]}" || return 1
  sync_submodule_urls_for_remote || return 1
  stage_and_commit_parent_changes "${existing_paths[@]}" || return 1
  parent_push_if_needed || return 1
  success_echo "已有子模块同步完成"
}
# 检查当前运行条件是否满足后续流程要求。
validate_remote_access_or_loop_continue() {
  local url="$1"
  if git ls-remote "$url" >/dev/null 2>&1; then
    return 0
  fi

  error_echo "Git 地址格式正确，但当前无法访问：$url"
  return 1
}
# 封装 add_new_git_url_interactive 对应的独立处理逻辑。
add_new_git_url_interactive() {
  while true; do
    echo ""
    echo "请输入新的 Git 仓库地址（任意托管站点）："
    echo "  支持：https://git.example.com/group/project"
    echo "  支持：ssh://git@git.example.com:2222/group/project.git"
    echo "  支持：git@git.example.com:group/project.git"
    echo "  输入一个空格后回车：返回上一页"
    printf 'Git 地址：'

    local input=""
    IFS= read -r input

    if [[ "$input" == " " ]]; then
      note_echo "返回上一页"
      return 0
    fi

    input="$(trim_string "$input")"

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
    local clone_url="$input"
    clone_url="$(git_url_with_style "$clone_url")" || continue

    validate_remote_access_or_loop_continue "$clone_url" || continue

    SUBMODULE_REPO_URLS+=("$input|$local_path")
    append_runtime_submodule "$page_url" "$https_url" "$ssh_url" "$repo_name" "$local_path"
    ensure_gitmodules_entry "$local_path" "$input" || continue
    GITMODULES_RECONCILED=1
    sync_selected_submodules_to_latest "$local_path" || return 1
    sync_submodule_urls_for_remote || return 1
    stage_and_commit_parent_changes "$local_path" || return 1
    parent_push_if_needed || return 1

    success_echo "已添加并同步新子模块：$local_path -> $clone_url"
    echo ""
    echo "如果希望以后固定保留，请把下面这一行加入脚本顶部 SUBMODULE_REPO_URLS："
    echo "  \"$input|$local_path\""
    echo ""
    echo "按 [Enter] 返回菜单"
    local dummy=""
    IFS= read -r dummy
    return 0
  done
}
# 封装 build_submodule_picker_content 对应的独立处理逻辑。
build_submodule_picker_content() {
  local style=""
  style="$(detect_git_url_style 2>/dev/null || echo https)"

  cat <<EOF2
📦 选择指定子模块同步（OpenClaw 键盘版，非 fzf 多选页）
------------------------------------------------------------
操作说明：
  - 按 ↑ / ↓ 移动光标
  - 按 [回车 Enter] 勾选 / 取消勾选当前项目
  - 最后按【空格键 Space】确认当前勾选并开始同步（无需再按回车）
  - 第一项“全选”会一次勾选 / 取消全部 SUBMODULE_REPO_URLS 项目
  - 按 ← 返回上一页

子模块同步 URL 模式: $style（相对地址继承 $REMOTE_NAME；Gitee 标准地址固定 HTTPS）
子模块分支优先级: $SUBMODULE_BRANCH
子仓浅克隆: $SUBMODULE_SHALLOW_CLONE
浅克隆深度: $SUBMODULE_DEPTH
同步 tags: $SUBMODULE_FETCH_TAGS

当前配置项目数: ${#CONFIG_PATHS}
------------------------------------------------------------
EOF2
}
# 封装 submodule_picker_all_selected 对应的独立处理逻辑。
submodule_picker_all_selected() {
  local p=""

  [[ ${#CONFIG_PATHS[@]} -gt 0 ]] || return 1

  for p in "${CONFIG_PATHS[@]}"; do
    [[ -n "${SUBMODULE_PICKED[$p]:-}" ]] || return 1
  done

  return 0
}
# 封装 render_submodule_keyboard_picker 对应的独立处理逻辑。
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
  printf '%s\n' '操作：↑/↓ 移动，回车(Enter) 勾选/取消，← 返回上一页'
  printf '%s\n' '👉 最后按【空格键 Space】确认已勾选项目并开始同步（无需再按回车）。'
}
# 封装 read_submodule_picker_key 对应的独立处理逻辑。
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
# 收集并校验用户输入，决定后续执行路径。
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
          message="⚠️  还没有勾选任何子模块：请先用回车(Enter)勾选，再按空格键(Space)确认"
          continue
        fi

        command clear 2>/dev/null || printf '\033[2J\033[H'
        reconcile_gitmodules_with_config_once || return 1
        info_echo "开始同步已选择的子模块：${selected_paths[*]}"
        sync_selected_submodules_to_latest "${selected_paths[@]}" || return 1
        sync_submodule_urls_for_remote || return 1
        stage_and_commit_parent_changes "${selected_paths[@]}" || return 1
        parent_push_if_needed || return 1
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
        message="提示：↑/↓ 移动，回车(Enter)勾选/取消，空格键(Space)确认并开始同步，← 返回上一页"
        ;;
    esac
  done
}
# ============================== fzf 菜单 ==============================
# 展示主菜单并返回用户选中的同步动作。
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
# 展示脚本用途和影响范围，并在执行前等待用户确认。
build_intro_content() {
  local style=""
  style="$(detect_git_url_style 2>/dev/null || echo https)"
  local gm_style=""
  gm_style="保留已有地址；缺项优先相对，映射不明时停止"

  cat <<EOF2
📘 Git 子模块批量管理脚本
------------------------------------------------------------
脚本目录: $SCRIPT_DIR
当前目录: $(pwd)
父仓远端: $REMOTE_NAME
子模块分支优先级: $SUBMODULE_BRANCH
子模块同步 URL 模式: $style（相对地址继承 $REMOTE_NAME；Gitee 标准地址固定 HTTPS）
.gitmodules 补缺 URL 模式: $gm_style
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
  local resolved_url=""
  local gm_section=""
  local gm_status=""

  for p in "${CONFIG_PATHS[@]}"; do
    display_path="$(preview_safe_text "$p")"
    page_url="$(repo_page_by_path "$p")"
    resolved_url="$(clone_url_for_path "$p" 2>/dev/null || echo "目标地址未确认，请先配置 .gitmodules")"
    gm_section="$(find_gitmodules_section_by_path "$p" 2>/dev/null || true)"
    if [[ -n "$gm_section" ]]; then
      gm_status="已存在"
    else
      gm_status="缺失，执行同步时会补齐"
    fi

    printf '  - %s\n' "$display_path"
    printf '      配置参考   : %s\n' "$page_url"
    printf '      实际下载   : %s\n' "$resolved_url"
    printf '      .gitmodules: %s\n' "$gm_status"
  done

  cat <<EOF2
------------------------------------------------------------
EOF2
}
# 封装 main_menu_loop 对应的独立处理逻辑。
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
        full_sync_to_latest || return 1
        return 0
        ;;
      "选择指定子模块同步（可多选）")
        local result=0
        select_configured_submodules_interactive "$preview_file" || result="$?"
        if [[ "$result" == "0" ]]; then
          return 0
        elif [[ "$result" == "2" ]]; then
          continue
        else
          return "$result"
        fi
        ;;
      "只更新目前已有的")
        update_existing_to_latest || return 1
        return 0
        ;;
      "添加并同步一个新的 Git 地址")
        add_new_git_url_interactive || return 1
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
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】⏬下载配置当前Git子模块.command' | jobs_intro_style title
  print -r -- '核心用途：按脚本清单下载、更新或添加父仓的 Git 子模块。' | jobs_intro_style body
  print -r -- '影响范围：父仓登记和提交指针、子仓代码与分支；默认自动提交父仓，不自动推送。' | jobs_intro_style body
  print -r -- '关键风险：更新会强制对齐远端；全量模式删除清单目标及对应旧仓名目录，必须另输入 YES。' | jobs_intro_style body
  print -r -- "日志文件：$LOG_FILE" | jobs_intro_style body
  print -r -- '取消方式：按 Ctrl+C 终止；自述确认前不执行真实业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  if ! read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _; then
    print -u2 -r -- '输入已结束，未执行后续业务。'
    exit 1
  fi
}
# 兼容仓库根目录裸脚本和直属同名脚本目录，确认后计算实际父仓。
initialize_script_paths() {
  SCRIPT_FILE="${SCRIPT_FILE:A}"
  SCRIPT_DIR="${SCRIPT_FILE:h}"
  SCRIPT_BASENAME="${SCRIPT_FILE:t:r}"
  REPO_ROOT="$SCRIPT_DIR"
  if [[ "${SCRIPT_DIR:t}" == "${SCRIPT_FILE:t}" ]]; then
    REPO_ROOT="${SCRIPT_DIR:h}"
  fi
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
}
# 确认后定位父仓、载入本仓清单并准备实际下载线路。
prepare_parent_repository() {
  cd_to_script_dir || return 1 # 以当前入口推导的父仓根目录作为全部相对路径基准。
  load_configured_submodules || return 1 # 保留各仓独立清单与已有共享登记。
  ensure_repo_initialized || return 1 # 拒绝非仓库或位于错误层级的目录。
  configure_gitee_https_transport || return 1 # 在首次联网前配置当前进程的 Gitee HTTPS 规则。
  ensure_git_remote "$REMOTE_NAME" || return 1 # 检查所选父仓远端并显示实际线路。
}
# 保留既有分支选择及父仓拉取策略。
synchronize_parent_repository() {
  ensure_parent_branch || return 1 # 确认当前父仓分支后再拉取。
  parent_pull_rebase # 父仓有未提交改动时按既有策略跳过拉取。
}
# 创建当前运行的菜单预览文件，并在退出时回收。
prepare_preview_runtime() {
  PREVIEW_FILE="$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.preview.XXXXXX")" || return 1
  trap '[[ -z "${PREVIEW_FILE:-}" ]] || rm -f -- "$PREVIEW_FILE"' EXIT
}
# 仅在菜单流程成功结束后输出完成摘要。
report_completion() {
  success_echo "全部完成 ✅"
  note_echo "日志文件：$LOG_FILE"
}
# 确认后集中初始化环境、路径与日志，函数外不执行真实操作。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  export LANG="${LANG:-zh_CN.UTF-8}"
  export LC_CTYPE="${LC_CTYPE:-UTF-8}"
  initialize_script_paths || return 1
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 首先展示内置自述，确认失败立即停止。
  initialize_script_runtime # 确认后初始化 Shell、入口路径和本轮日志。
  prepare_parent_repository # 验证父仓根目录，载入本仓清单并准备下载线路。
  synchronize_parent_repository # 按既有分支规则先处理父仓更新。
  ensure_fzf_healthy # 复用可用菜单工具，缺失时才处理依赖。
  prepare_preview_runtime # 准备菜单预览及退出清理。
  main_menu_loop "$PREVIEW_FILE" # 根据菜单选择同步，失败立即向入口传播。
  report_completion # 成功后汇总结果与日志位置。
}

main "$@"
