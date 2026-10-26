#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command
# - 来源日志：克隆 / 拉取前突出平台与完整地址，完成时带来源，保留递归来源核对。
# - 下载协议：Gitee 标准 SSH 地址在本次进程改走 HTTPS，递归子模块继承，不写全局配置。
# - 核心用途：回车默认只拉取明确上游并递归同步子仓分支最新；维护模式保留各仓清单、分支最新和登记流程。
# - 影响范围：只拉取不暂存、不提交、不推送；维护模式沿用父仓登记、索引和提交开关。
# - 文档目录：已配置目录过滤器才执行本仓 restore / verify，无配置跳过，不自动安装。
# - 运行提示：先选择只拉取或维护，再阅读对应自述并回车确认；危险舍弃另需精确 YES，Ctrl+C 取消。

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

# ============================== 脚本配置（仅维护模式） ==============================
SUBMODULE_BRANCH="${SUBMODULE_BRANCH:-main}"          # 维护模式入口父仓分支；子仓读取各层 branch，缺省使用远端默认
REMOTE_NAME="${REMOTE_NAME:-origin}"                  # 父仓远端名
DRY_RUN="${DRY_RUN:-0}"                                # 1=只打印动作，不执行
FORCE_DELETE="${FORCE_DELETE:-0}"                      # 1=显式裁剪时允许删除非 Git 非空旧目录；仍逐仓要求 YES
AUTO_PARENT_COMMIT="${AUTO_PARENT_COMMIT:-1}"          # 1=自动提交 .gitmodules/gitlink 变化
AUTO_PARENT_PUSH="${AUTO_PARENT_PUSH:-0}"              # 1=自动推送父仓；默认不推送，避免跨机器误推
GIT_URL_STYLE="${GIT_URL_STYLE:-auto}"                  # auto/https/ssh；默认继承所选父 remote 的完整地址
PRUNE_STALE_GITMODULES="${PRUNE_STALE_GITMODULES:-0}"  # 1=逐仓 YES 后裁剪清单外旧登记；默认只查漏补缺
SUBMODULE_SHALLOW_CLONE="${SUBMODULE_SHALLOW_CLONE:-1}"    # 1=子仓浅克隆，只拿最新必要历史；0=完整克隆
SUBMODULE_DEPTH="${SUBMODULE_DEPTH:-1}"                    # 浅克隆深度；默认 1，只锚定最新一层提交
SUBMODULE_FETCH_TAGS="${SUBMODULE_FETCH_TAGS:-0}"          # 1=同步 tags；默认 0，软件大包仓库不拉 tags 更快
SUBMODULE_RECURSIVE="${SUBMODULE_RECURSIVE:-1}"            # 1=向下逐层同步最新代码；0=仅同步所选直属子仓，可在菜单切换

# ============================== 脚本路径定位 ==============================
SCRIPT_FILE="${(%):-%x}"
SCRIPT_DIR=""
REPO_ROOT=""
SCRIPT_BASENAME="【MacOS】⏬下载配置当前Git子模块（可向下同步递归）"
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
PREVIEW_FILE=""
DOWNLOAD_OPERATION_MODE=""

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

# 只还原已配置的目录过滤器；无配置不安装，保留当前正文与暂存内容。
restore_configured_markdown_toc() {
  local toc_root="${1:A}" toc_smudge="" toc_process="" toc_node="" toc_result=0
  toc_smudge="$(command git -C "$toc_root" config --get filter.jobs-markdown-toc.smudge)" || toc_result=$?
  if (( toc_result > 1 )); then
    print -u2 -r -- "无法读取 Markdown 目录过滤器，保留现场：${toc_root}"
    return 1
  fi
  toc_result=0
  toc_process="$(command git -C "$toc_root" config --get filter.jobs-markdown-toc.process)" || toc_result=$?
  if (( toc_result > 1 )) || [[ -n "$toc_process" ]]; then
    print -u2 -r -- "Markdown 目录 process 配置冲突或读取失败，保留现场：${toc_root}"
    return 1
  fi
  if [[ -z "$toc_smudge" ]]; then
    print -r -- "Markdown 目录：未配置还原过滤器，跳过：${toc_root}"
    return 0
  fi
  # 还原不跨越未完成的合并、冲突或其它 Git 写操作。
  local toc_marker="" toc_marker_path="" toc_unmerged=""
  for toc_marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START index.lock; do
    toc_marker_path="$(command git -C "$toc_root" rev-parse --git-path "$toc_marker")" || return 1
    [[ "$toc_marker_path" == /* ]] || toc_marker_path="${toc_root}/${toc_marker_path}"
    if [[ -e "$toc_marker_path" ]]; then
      print -u2 -r -- "存在未完成 Git 操作或锁，未还原目录：${toc_root}（${toc_marker}）"
      return 1
    fi
  done
  toc_unmerged="$(command git -C "$toc_root" ls-files --unmerged)" || return 1
  if [[ -n "$toc_unmerged" ]]; then
    print -u2 -r -- "索引存在未解决冲突，未还原目录：${toc_root}"
    return 1
  fi
  local toc_tool="${toc_root}/.jobs-markdown-toc/MarkdownToc.mjs"
  if [[ ! -f "$toc_tool" || -L "$toc_tool" || -L "${toc_tool:h}" ]]; then
    print -u2 -r -- "已配置 Markdown 目录过滤器，但缺少本仓安全还原工具，停止：${toc_tool}"
    return 1
  fi
  # 优先使用过滤器已登记的 Node 路径，不求值或执行配置中的 Shell 文本。
  local -a toc_words
  toc_words=(${(z)toc_smudge})
  toc_node="${(Q)toc_words[1]}"
  if [[ "$toc_node" != /* || "${toc_node:t}" != node || ! -x "$toc_node" ]]; then
    toc_node="$(command -v node 2>/dev/null)" || toc_node=""
  fi
  if [[ -z "$toc_node" || ! -x "$toc_node" ]]; then
    print -u2 -r -- "已配置 Markdown 目录过滤器，但 Node.js 不可用；未安装或改写配置：${toc_root}"
    return 1
  fi
  print -r -- "Markdown 目录：执行已配置过滤器的本仓还原与检查：${toc_root}"
  "$toc_node" "$toc_tool" restore || return 1
  "$toc_node" "$toc_tool" verify
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
  [[ "$local_path" != *"|"* ]] || return 1
  validate_submodule_url_path "$PWD" "$local_path"
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
  [[ -n "$submodule_path" && "$submodule_path" != /* && "$submodule_path" != */ &&
     "$submodule_path" != *//* && "$submodule_path" != *[[:cntrl:]]* && "$submodule_path" != *\\* ]] || return 1
  repo_root="${repo_root:A}"
  child_root="$repo_root"
  for component in "${(@s:/:)submodule_path}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. &&
       "${component:l}" != .git && "$component" != -* ]] || return 1
    child_root="$child_root/$component"
    [[ ! -L "$child_root" && ( ! -e "$child_root" || -d "$child_root" ) ]] || return 1
    # 分类目录不能跨过另一个独立 Git 仓，否则直属父子关系会失真。
    if [[ "$child_root" != "$repo_root/$submodule_path" && ( -e "$child_root/.git" || -L "$child_root/.git" ) ]]; then
      return 1
    fi
  done
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
    run_cmd git -c submodule.recurse=false -c core.quotepath=false checkout --no-recurse-submodules --no-overwrite-ignore "$b"
    return 0
  fi

  if git ls-remote --exit-code --heads "$REMOTE_NAME" "$b" >/dev/null 2>&1; then
    run_cmd git -c submodule.recurse=false -c core.quotepath=false checkout --no-recurse-submodules --no-overwrite-ignore -B "$b" --track "$REMOTE_NAME/$b"
  else
    run_cmd git -c submodule.recurse=false -c core.quotepath=false checkout --no-recurse-submodules --no-overwrite-ignore -B "$b"
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

  run_cmd git -c submodule.recurse=false fetch --recurse-submodules=no "$REMOTE_NAME" || true
  if git ls-remote --exit-code --heads "$REMOTE_NAME" "$b" >/dev/null 2>&1; then
    run_cmd git -c submodule.recurse=false pull --no-recurse-submodules --rebase "$REMOTE_NAME" "$b" || warn_echo "父仓 pull --rebase 未完成，请检查是否存在冲突；本次继续处理子模块"
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
# 严格使用显式分支；缺省才查询远端 HEAD，不能静默切换目标。
remote_branch_for_url() {
  local url="$1"
  local preferred="${2:-}"
  local branch=""

  if [[ -n "$preferred" ]]; then
    git check-ref-format "refs/heads/$preferred" >/dev/null 2>&1 &&
      [[ "$preferred" != -* && "$preferred" != HEAD ]] || return 1
    remote_branch_exists "$url" "$preferred" || return 1
    printf '%s\n' "$preferred"
    return 0
  fi

  branch="$(remote_default_branch_by_url "$url")"
  if [[ -n "$branch" ]]; then
    git check-ref-format "refs/heads/$branch" >/dev/null 2>&1 &&
      [[ "$branch" != -* && "$branch" != HEAD ]] || return 1
    printf '%s\n' "$branch"
    return 0
  fi

  return 1
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
# 高风险提示在终端使用红色粗体，日志保留纯文本。
submodule_risk_echo() {
  local message="$1"
  printf '%s\n' "❌ $message" >> "$LOG_FILE"
  if [[ -t 2 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" &&
        "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
    printf '\033[1;31m❌ %s\033[0m\n' "$message" >&2
  else
    printf '%s\n' "❌ $message" >&2
  fi
}
# 只列当前仓源码和已暂存内容，忽略同步产生的后代 HEAD 漂移。
submodule_own_changes() {
  local submodule_path="$1" dirty="" staged=""
  dirty="$(git -C "$submodule_path" -c core.quotepath=false status --porcelain --untracked-files=all --ignore-submodules=all)" || return 1
  staged="$(git -C "$submodule_path" -c core.quotepath=false diff --cached --name-status --ignore-submodules=none --)" || return 1
  [[ -z "$dirty" ]] || printf '%s\n' "$dirty"
  [[ -z "$staged" ]] || printf '已暂存（含子模块指针）：\n%s\n' "$staged"
  return 0
}
# 循环等待当前仓变干净；YES 仅放弃本仓内容，不递归清理后代。
wait_for_clean_submodule() {
  local submodule_path="$1" action="$2" dirty="" answer="" repo_root=""
  repo_root="${submodule_path:A}"
  while true; do
    if ! is_git_worktree "$repo_root"; then
      error_echo "等待期间子仓已不可用，停止${action}：$repo_root"
      return 1
    fi
    dirty="$(submodule_own_changes "$repo_root")" || return 1
    [[ -n "$dirty" ]] || return 0
    submodule_risk_echo "子 Git 存在尚未提交内容，暂停${action}。仓库：$repo_root"
    submodule_risk_echo "$dirty"
    submodule_risk_echo '输入精确大写 YES：放弃上述仓库自己的已暂存、未暂存和未跟踪内容；忽略文件及嵌套 Git 仓保留，后代有改动会另行确认。'
    if [[ "$DRY_RUN" == 1 || ! -t 0 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
      error_echo "演练或无交互模式不能确认放弃内容，未执行清理：$repo_root"
      return 1
    fi
    if ! IFS= read -r "answer?👉 输入 YES 放弃本仓改动；或在外部处理后按回车重新检查（Ctrl+C 取消）："; then
      error_echo "输入已结束，停止${action}并保留尚未处理的内容：$repo_root"
      return 1
    fi
    if [[ "$answer" == YES ]]; then
      run_cmd git -C "$repo_root" -c submodule.recurse=false reset --hard HEAD || return 1
      run_cmd git -C "$repo_root" -c submodule.recurse=false clean -fd -- || return 1
      note_echo "已按 YES 放弃当前仓未提交内容，重新检查：$repo_root"
    else
      info_echo "未收到 YES，重新检查；仍有改动将继续等待：$repo_root"
    fi
  done
}
# 从索引与 HEAD 收集子仓，防止待放弃的 .gitmodules 改动隐藏已有后代。
submodule_children_for_protection() {
  local repo_root="$1" index_entries="" head_entries="" entry="" child_path=""
  local -a children
  children=()
  index_entries="$(git -C "$repo_root" ls-files --stage -z)" || return 1
  head_entries="$(git -C "$repo_root" ls-tree -rz --full-tree HEAD)" || return 1
  for entry in "${(@0)index_entries}" "${(@0)head_entries}"; do
    [[ "$entry" == '160000 '* ]] || continue
    child_path="${entry#*$'\t'}"
    validate_submodule_url_path "$repo_root" "$child_path" || return 1
    if ! contains_item "$child_path" "${children[@]}"; then
      children+=("$child_path")
    fi
  done
  [[ ${#children} -eq 0 ]] || printf '%s\n' "${children[@]}"
  return 0
}
# 更新祖先前保护已初始化后代；每仓单独等待确认，不将一次 YES 扩大到整棵树。
assert_clean_submodule() {
  local submodule_path="$1" action="$2" children="" current_children="" child_path=""
  is_git_worktree "$submodule_path" || return 0
  if [[ "$action" == 更新 || "$action" == 纳入子模块 ]]; then
    run_cmd restore_configured_markdown_toc "$submodule_path" 2>&1 | tee -a "$LOG_FILE" || return 1
  fi
  if [[ "$SUBMODULE_RECURSIVE" == 1 ]]; then
    children="$(submodule_children_for_protection "$submodule_path")" || return 1
  fi
  wait_for_clean_submodule "$submodule_path" "$action" || return 1
  if [[ "$SUBMODULE_RECURSIVE" == 1 ]]; then
    current_children="$(submodule_children_for_protection "$submodule_path")" || return 1
    local -a checked
    checked=()
    for child_path in "${(@f)children}" "${(@f)current_children}"; do
      [[ -n "$child_path" ]] || continue
      contains_item "$child_path" "${checked[@]}" && continue
      checked+=("$child_path")
      assert_clean_submodule "$submodule_path/$child_path" "$action" || return 1
    done
  fi
  return 0
}
# 校验配置后枚举直属登记，读取失败不能当作没有子模块。
submodule_path_keys() {
  local repo_root="$1" result=0
  [[ -f "$repo_root/.gitmodules" ]] || return 0
  git config -f "$repo_root/.gitmodules" --list >/dev/null || return 1
  git config -f "$repo_root/.gitmodules" --name-only --get-regexp '^submodule\..*\.path$' || result=$?
  [[ "$result" == 0 || "$result" == 1 ]]
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
  local submodule_path="$1" section="" desired_url="${2:-}"
  ensure_gitmodules_file_exists || return 1
  section="$(find_gitmodules_section_by_path "$submodule_path" 2>/dev/null || true)"
  if [[ -z "$section" ]]; then
    section="$submodule_path"
  fi
  local changed=0 cur_path="" cur_url=""
  cur_path="$(git config -f .gitmodules --get "submodule.$section.path" 2>/dev/null || true)"
  cur_url="$(git config -f .gitmodules --get "submodule.$section.url" 2>/dev/null || true)"
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
  if [[ "$changed" == 1 ]]; then
    note_echo ".gitmodules 已查漏补缺：$submodule_path"
  else
    info_echo ".gitmodules 已存在，保留 URL、分支与扩展字段：$submodule_path"
  fi
}
# 显式启用旧登记裁剪时另行确认，不能复用全量同步或脏仓放弃授权。
confirm_stale_submodule_removal() {
  local submodule_path="$1" answer=""
  submodule_risk_echo "PRUNE_STALE_GITMODULES=1：准备移除清单外旧登记及目录：${submodule_path:A}"
  submodule_risk_echo '此项会删除该目录及其后代，本地独有提交可能失去工作区引用；这是显式裁剪，不是正常同步。'
  if [[ "$DRY_RUN" == 1 ]]; then
    note_echo "[DRY-RUN] 仅展示旧登记裁剪，不执行删除：$submodule_path"
    return 0
  fi
  if [[ ! -t 0 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    error_echo "旧登记裁剪必须在交互终端逐仓输入 YES，未执行删除：$submodule_path"
    return 1
  fi
  if ! IFS= read -r "answer?👉 输入 YES 删除上述旧登记及目录；其它输入停止裁剪："; then
    error_echo "输入已结束，未执行旧登记裁剪：$submodule_path"
    return 1
  fi
  if [[ "$answer" != YES ]]; then
    error_echo "未输入 YES，停止旧登记裁剪并保留目标：$submodule_path"
    return 1
  fi
}
# 仅在显式启用并逐仓确认后移除清单外登记。
prune_unconfigured_gitmodules() {
  [[ "$PRUNE_STALE_GITMODULES" == "1" ]] || return 0
  [[ -f .gitmodules ]] || return 0

  local existing_path="" configured_path=""
  while IFS= read -r existing_path; do
    [[ -z "$existing_path" ]] && continue

    if ! contains_item "$existing_path" "${CONFIG_PATHS[@]}"; then
      for configured_path in "${CONFIG_PATHS[@]}"; do
        if [[ "$configured_path" == "$existing_path/"* || "$existing_path" == "$configured_path/"* ]]; then
          error_echo "旧登记与当前清单路径重叠，保留分类目录及子树并停止裁剪：$existing_path / $configured_path"
          return 1
        fi
      done
      if ! validate_submodule_url_path "$PWD" "$existing_path"; then
        error_echo "旧登记路径不是安全的独立子仓目录，停止裁剪：$existing_path"
        return 1
      fi
      warn_echo "发现 .gitmodules 中不再属于 SUBMODULE_REPO_URLS 的旧子模块：$existing_path"
      confirm_stale_submodule_removal "$existing_path" || return 1
      if ! (
        SUBMODULE_RECURSIVE=1
        assert_clean_submodule "$existing_path" "移除旧子模块配置"
      ); then
        return 1
      fi

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
# 按真实 section 定位既有缓存，核验边界、工作区归属和独立引用。
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
    error_echo "子模块缓存不是父仓 modules 下的普通目录，拒绝复用：$cache_dir"
    return 1
  fi
  while IFS= read -r key; do
    other_section="${key#submodule.}"
    other_section="${other_section%.path}"
    other_path="$(git config -f .gitmodules --get "$key")" || return 1
    if [[ "$other_section" != "$section" && ( "$other_section" == "$section/"* || "$other_path" == "$submodule_path" ) ]]; then
      error_echo "目标缓存与其它子模块登记重叠，拒绝复用：$section / $other_section"
      return 1
    fi
  done < <(git config -f .gitmodules --name-only --get-regexp '^submodule\..*\.path$')
  worktree="$(git config --file "$cache_dir/config" --get core.worktree)" || {
    error_echo "缓存缺少可核验的 core.worktree，拒绝复用：$cache_dir"
    return 1
  }
  [[ "$worktree" == /* ]] || worktree="$cache_dir/$worktree"
  expected_worktree="$PWD/$submodule_path"
  if [[ "${worktree:A}" != "${expected_worktree:A}" ]]; then
    error_echo "缓存属于其它工作目录，拒绝复用：$cache_dir"
    return 1
  fi
  if [[ -e "$submodule_path/.git" ]]; then
    actual_git_dir="$(git -C "$submodule_path" rev-parse --absolute-git-dir)" || return 1
    if [[ "${actual_git_dir:A}" != "$cache_dir" ]]; then
      error_echo "当前子仓与候选缓存指向不同元数据，拒绝复用：$submodule_path"
      return 1
    fi
  fi
  if [[ -d "$cache_dir/worktrees" && -n "$(ls -A "$cache_dir/worktrees")" ]]; then
    error_echo "子模块缓存仍登记其它 worktree，拒绝复用：$cache_dir"
    return 1
  fi
  printf '%s\n' "$cache_dir"
}
# 在空工作区重新连接已核验缓存，从索引恢复文件，保留提交、配置和暂存改动。
restore_cached_submodule_worktree() {
  local submodule_path="$1" cached_gitdir="$2" repo_root="${PWD}/$1"
  if [[ -e "$submodule_path" ]] && ! is_dir_empty "$submodule_path"; then
    error_echo "Git 缓存对应目录非空，拒绝覆盖：$repo_root"
    return 1
  fi
  if [[ ! -f "$cached_gitdir/index" ]]; then
    error_echo "子模块缓存缺少索引，保留并停止：$cached_gitdir；请先用 Git 恢复后重试。"
    return 1
  fi
  info_echo "复用已有 Git 缓存恢复空工作区：$repo_root（缓存：$cached_gitdir）"
  if [[ "$DRY_RUN" == 1 ]]; then
    note_echo "[DRY-RUN] 恢复 .git 指针与索引文件，不删除缓存：$repo_root"
    return 0
  fi
  mkdir -p -- "$submodule_path" || return 1
  printf 'gitdir: %s\n' "$cached_gitdir" > "$submodule_path/.git" || return 1
  git -C "$submodule_path" -c submodule.recurse=false checkout-index --all || {
    error_echo "缓存工作区恢复失败，已保留缓存和当前状态：$repo_root"
    return 1
  }
}
# 封装 clone_submodule_worktree 对应的独立处理逻辑。
clone_submodule_worktree() {
  local submodule_path="$1"
  local url="${2:-}" preferred="${3:-}"
  [[ -n "$url" ]] || url="$(clone_url_for_path "$submodule_path")" || return 1
  print_git_source "首次克隆" "$submodule_path" "$PWD" "$url" clone
  local branch=""
  branch="$(remote_branch_for_url "$url" "$preferred")" || {
    error_echo "无法确定或获取目标分支，未克隆：$submodule_path（指定：${preferred:-远端默认}；来源：$(safe_git_source_url "$url")）"
    return 1
  }

  local -a clone_args
  clone_args=()

  if [[ "$SUBMODULE_SHALLOW_CLONE" == "1" ]]; then
    clone_args+=(--depth "$SUBMODULE_DEPTH" --single-branch)
  fi

  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    clone_args+=(--no-tags)
  fi

  validate_submodule_url_path "$PWD" "$submodule_path" || return 1
  run_cmd mkdir -p -- "${submodule_path:h}" || return 1
  info_echo "克隆分支：$branch"
  run_cmd git -c submodule.recurse=false clone "${clone_args[@]}" --branch "$branch" --no-recurse-submodules -- "$url" "$submodule_path" || return 1

  run_cmd git -C "$submodule_path" config core.quotepath false || true
  if [[ "$SUBMODULE_FETCH_TAGS" != "1" ]]; then
    run_cmd git -C "$submodule_path" config remote.origin.tagOpt --no-tags || true
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_submodule_worktree_present() {
  local submodule_path="$1"
  local url="${2:-}" preferred="${3:-}" stage_association="${4:-1}"
  validate_submodule_url_path "$PWD" "$submodule_path" || {
    error_echo "子仓目录不是安全的相对路径，未初始化或覆盖：$submodule_path"
    return 1
  }
  # 已有缓存先核验并恢复空工作区，避免重新克隆或丢失历史。
  if [[ ! -e "$submodule_path/.git" ]]; then
    local cached_gitdir=""
    cached_gitdir="$(submodule_cache_for_removal "$submodule_path")" || return 1
    if [[ -n "$cached_gitdir" ]]; then
      restore_cached_submodule_worktree "$submodule_path" "$cached_gitdir" || return 1
    fi
  fi

  # 不走 git submodule update 做首次下载，因为它会严格使用 .gitmodules 的 url。
  # 这里按 .gitmodules 与所选父 remote 的完整地址解析下载，保留绝对 URL 例外。
  if [[ -e "$submodule_path" ]]; then
    if is_git_worktree "$submodule_path"; then
      assert_clean_submodule "$submodule_path" "纳入子模块" || return 1
    elif is_dir_empty "$submodule_path"; then
      info_echo "首次初始化空子仓目录：$PWD/$submodule_path"
      run_cmd rmdir -- "$submodule_path" || return 1
    else
      error_echo "目标目录已存在且不是 Git 空目录，拒绝覆盖：$submodule_path"
      return 1
    fi
  fi

  if [[ ! -e "$submodule_path" ]]; then
    clone_submodule_worktree "$submodule_path" "$url" "$preferred" || return 1
  fi

  run_cmd restore_configured_markdown_toc "$submodule_path" 2>&1 | tee -a "$LOG_FILE" || return 1

  # 不使用 git submodule add，避免 .gitmodules 被 Git 自动重写；手动 add 会把内部 Git 仓登记为 gitlink。
  if [[ "$stage_association" == 1 ]]; then
    run_cmd git --literal-pathspecs add -- .gitmodules "$submodule_path" || return 1
  fi

  # 标准子模块形态：子仓目录里保留 .git 单文件，真正 Git 数据放到父仓 .git/modules 下。
  # 这一步不决定是否浅克隆；浅克隆由 --depth 控制。这里负责把 .git 文件夹吸收到父仓管理。
  if [[ ! -f "$submodule_path/.git" ]] && ! run_cmd git --literal-pathspecs submodule absorbgitdirs -- "$submodule_path"; then
    error_echo "子模块元数据归集失败：$submodule_path；未标记为完成。"
    return 1
  fi
  if [[ "$stage_association" == 1 ]]; then
    run_cmd git --literal-pathspecs add -- .gitmodules "$submodule_path" || return 1
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    note_echo "[DRY-RUN] 已计划登记并归集子模块：$submodule_path"
  elif [[ -f "$submodule_path/.git" ]]; then
    success_echo "已登记标准子模块 gitlink：$submodule_path（子仓 .git 为单文件）"
  else
    error_echo "子模块元数据未形成标准 .git 指针：$submodule_path；未标记为完成。"
    return 1
  fi
}
# 在子仓自身配置作用域中严格解析目标分支。
resolve_remote_branch_for_submodule() {
  local submodule_path="$1"
  local preferred="${2:-}"
  ( cd "$submodule_path" && remote_branch_for_url origin "$preferred" )
}
# 执行对应的环境配置或同步处理。
sync_one_submodule_to_latest() {
  local submodule_path="$1"
  local url="${2:-}" preferred="${3:-}"
  [[ -n "$url" ]] || url="$(clone_url_for_path "$submodule_path")" || return 1

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
  if ! branch="$(resolve_remote_branch_for_submodule "$submodule_path" "$preferred")"; then
    error_echo "无法确定远端可同步分支：$submodule_path（指定：${preferred:-远端默认}；来源：$(safe_git_source_url "$url")）"
    return 1
  fi

  local -a fetch_args
  fetch_args=()
  if [[ "$SUBMODULE_FETCH_TAGS" == "1" ]]; then
    fetch_args+=(--tags)
  else
    fetch_args+=(--no-tags)
  fi

  info_echo "拉取分支：origin/$branch"
  run_cmd git -C "$submodule_path" -c submodule.recurse=false fetch --recurse-submodules=no "${fetch_args[@]}" origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" --prune || return 1
  # 离开游离态前保留独有提交；父仓已登记的旧 pin 可以安全切回分支。
  if ! git -C "$submodule_path" symbolic-ref --quiet HEAD >/dev/null; then
    local detached_head="" containing_refs="" parent_pin=""
    detached_head="$(git -C "$submodule_path" rev-parse HEAD)" || return 1
    containing_refs="$(git -C "$submodule_path" for-each-ref --contains "$detached_head" --format='%(refname)')" || return 1
    parent_pin="$(git --literal-pathspecs ls-files --stage -- "$submodule_path" | awk '$1 == "160000" { print $2; exit }')" || return 1
    if [[ -z "$containing_refs" && "$detached_head" != "$parent_pin" ]] && ! git -C "$submodule_path" merge-base --is-ancestor "$detached_head" "refs/remotes/origin/$branch"; then
      error_echo "子仓存在未受引用保护的游离提交，保留现场并停止：$submodule_path（$detached_head）"
      return 1
    fi
  fi
  # 远端最新只允许快进，不能用 -B / reset 无提示抹掉同名分支的本地提交。
  if git -C "$submodule_path" show-ref --verify --quiet "refs/heads/$branch"; then
    if ! git -C "$submodule_path" merge-base --is-ancestor "refs/heads/$branch" "refs/remotes/origin/$branch"; then
      error_echo "目标分支存在独有提交或无法快进，保留现场并停止：$submodule_path（$branch）"
      return 1
    fi
    run_cmd git -C "$submodule_path" -c submodule.recurse=false checkout --no-recurse-submodules --no-overwrite-ignore "$branch" || return 1
    run_cmd git -C "$submodule_path" -c submodule.recurse=false -c "branch.$branch.mergeOptions=" merge --ff-only --no-autostash --no-overwrite-ignore --no-edit "refs/remotes/origin/$branch" || return 1
  else
    run_cmd git -C "$submodule_path" -c submodule.recurse=false checkout --no-recurse-submodules --no-overwrite-ignore -b "$branch" "refs/remotes/origin/$branch" || return 1
  fi
  run_cmd git -C "$submodule_path" branch --set-upstream-to="origin/$branch" "$branch" || return 1
  [[ "$(git -C "$submodule_path" symbolic-ref --quiet --short HEAD)" == "$branch" && "$(git -C "$submodule_path" rev-parse HEAD)" == "$(git -C "$submodule_path" rev-parse "refs/remotes/origin/$branch")" ]] || return 1

  run_cmd restore_configured_markdown_toc "$submodule_path" 2>&1 | tee -a "$LOG_FILE" || return 1

  if [[ "$SUBMODULE_RECURSIVE" == 1 ]] && ! sync_descendant_submodules_to_latest "$PWD/$submodule_path" "$url"; then
    error_echo "递归子模块同步失败：$submodule_path；未标记为同步成功。"
    return 1
  fi

  # 再次确保子仓是标准 submodule 形态：工作目录下 .git 为单文件，Git 数据由父仓 .git/modules 托管。
  if [[ ! -f "$submodule_path/.git" ]] && ! run_cmd git --literal-pathspecs submodule absorbgitdirs -- "$submodule_path"; then
    error_echo "子模块元数据归集失败：$submodule_path；未标记为完成。"
    return 1
  fi

  success_echo "$submodule_path 已浅同步到 origin/$branch：$(git -C "$submodule_path" rev-parse --short HEAD)（来源：$(safe_git_source_url "$(effective_git_source_url "$PWD/$submodule_path" "$url")")）"
}
# 每层读取刚取得的 .gitmodules；不调用子仓脚本，不暂存或提交深层指针。
sync_descendant_submodules_to_latest() (
  local repo_root="$1" parent_url="$2" keys="" key="" section="" child_path="" url="" branch=""
  [[ "$SUBMODULE_RECURSIVE" == 1 ]] || return 0
  [[ -d "$repo_root" ]] || return 0
  cd "$repo_root" || return 1
  keys="$(submodule_path_keys .)" || return 1
  local -a inherited_urls
  inherited_urls=("${SUBMODULE_ACTIVE_URLS[@]}")
  local -a SUBMODULE_ACTIVE_URLS
  SUBMODULE_ACTIVE_URLS=("${inherited_urls[@]}" "${parent_url%.git}")
  for key in "${(@f)keys}"; do
    [[ -n "$key" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    child_path="$(git config -f .gitmodules --get "$key")" || return 1
    validate_submodule_url_path "$PWD" "$child_path" || {
      error_echo "拒绝递归仓外或非独立子仓路径：$PWD/$child_path"
      return 1
    }
    if ! git --literal-pathspecs ls-files --stage -- "$child_path" | awk '$1 == "160000" { found=1 } END { exit !found }'; then
      error_echo "递归条目不是已登记的 gitlink：$PWD/$child_path"
      return 1
    fi
    url="$(git config -f .gitmodules --get "submodule.$section.url")" || return 1
    if [[ "$url" == ./* || "$url" == ../* ]]; then
      url="$(resolve_relative_git_url "$parent_url" "$url")" || return 1
    fi
    url="$(git_url_with_style "$url")" || return 1
    if contains_item "${url%.git}" "${SUBMODULE_ACTIVE_URLS[@]}"; then
      error_echo "检测到子模块祖先地址循环，停止递归：$PWD/$child_path"
      return 1
    fi
    branch="$(git config -f .gitmodules --get "submodule.$section.branch" 2>/dev/null || true)"
    if [[ "$branch" == . ]]; then
      branch="$(git symbolic-ref --quiet --short HEAD)" || return 1
    fi
    info_echo "向下递归：${PWD#"$REPO_ROOT"/}/$child_path（目标分支：${branch:-远端默认}）"
    run_cmd git config "submodule.$section.url" "$url" || return 1
    ensure_submodule_worktree_present "$child_path" "$url" "$branch" 0 || return 1
    sync_one_submodule_to_latest "$child_path" "$url" "$branch" || return 1
  done
)
# 执行对应的环境配置或同步处理。
sync_selected_submodules_to_latest() {
  local -a paths
  paths=("$@")
  local p="" section="" url="" branch=""

  if [[ ${#paths} -eq 0 ]]; then
    warn_echo "没有需要同步的子模块"
    return 0
  fi

  for p in "${paths[@]}"; do
    if [[ -L "$p" ]] || ! validate_submodule_url_path "$PWD" "$p"; then
      error_echo "拒绝同步符号链接、仓外或非独立子仓路径：$p"
      return 1
    fi
    section="$(find_gitmodules_section_by_path "$p" 2>/dev/null || true)"
    url="$(clone_url_for_path "$p")" || return 1
    branch=""
    if [[ -n "$section" ]]; then
      branch="$(git config -f .gitmodules --get "submodule.$section.branch" 2>/dev/null || true)"
      run_cmd git config "submodule.$section.url" "$url" || return 1
    fi
    if [[ "$branch" == . ]]; then
      branch="$(git symbolic-ref --quiet --short HEAD)" || return 1
    fi
    ensure_submodule_worktree_present "$p" "$url" "$branch" || return 1
    sync_one_submodule_to_latest "$p" "$url" "$branch" || return 1
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
# 全量遍历清单；已有子仓原地更新，空目录或缺失工作区按实际状态初始化。
full_sync_to_latest() {
  info_echo "开始全量同步：补齐 .gitmodules；已有子仓复用更新，空目录初始化；未提交内容逐仓确认"
  reconcile_gitmodules_with_config_once || return 1
  sync_selected_submodules_to_latest "${CONFIG_PATHS[@]}" || return 1
  stage_and_commit_parent_changes "${CONFIG_PATHS[@]}" || return 1
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

    synchronize_parent_repository || return 1
    SUBMODULE_REPO_URLS+=("$input|$local_path")
    append_runtime_submodule "$page_url" "$https_url" "$ssh_url" "$repo_name" "$local_path"
    ensure_gitmodules_entry "$local_path" "$input" || continue
    GITMODULES_RECONCILED=1
    sync_selected_submodules_to_latest "$local_path" || return 1
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
📦 选择指定子模块同步（fzf 多选）
------------------------------------------------------------
操作说明：
  - 按 ↑ / ↓ 移动光标
  - 按 [回车 Enter] 勾选 / 取消勾选当前项目
  - 最后按【空格键 Space】确认当前勾选并开始同步（无需再按回车）
  - Ctrl+A 全选，Ctrl+D 清空，Esc 取消脚本；空选不会启动同步
  - 按 ← 返回上一页

子模块同步 URL 模式: $style（相对地址继承 $REMOTE_NAME；Gitee 标准地址固定 HTTPS）
子模块分支: 显式 branch；缺省使用远端默认分支
子仓浅克隆: $SUBMODULE_SHALLOW_CLONE
浅克隆深度: $SUBMODULE_DEPTH
同步 tags: $SUBMODULE_FETCH_TAGS

当前配置项目数: ${#CONFIG_PATHS}
------------------------------------------------------------
EOF2
}
# 收集并校验用户输入，决定后续执行路径。
select_configured_submodules_interactive() {
  local preview_file="$1"
  local selected="" picker_result=0 payload="" p=""
  local -a selected_paths
  selected_paths=()

  if [[ ${#CONFIG_PATHS[@]} -eq 0 ]]; then
    warn_echo "SUBMODULE_REPO_URLS 当前没有配置任何项目"
    return 2
  fi

  build_submodule_picker_content > "$preview_file"
  selected="$(printf '%s\n' "${CONFIG_PATHS[@]}" |
    FZF_CONFIG_PREVIEW_FILE="$preview_file" FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
      --multi --height=100% --border --reverse \
      --prompt='选择子模块 > ' --expect=left \
      --preview='cat "$FZF_CONFIG_PREVIEW_FILE"' \
      --preview-window='up,60%,border-bottom,nowrap' \
      --header='回车勾选 / 取消，空格确认，Ctrl+A 全选，Ctrl+D 清空，← 返回主菜单，Esc 取消脚本' \
      --bind='enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all' \
      --bind='space:transform:if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then echo accept; else echo "change-header:请先回车勾选项目；← 返回主菜单，Esc 取消脚本"; fi')" || picker_result=$?
  if [[ "${selected%%$'\n'*}" == left ]]; then
    return 2
  fi
  if (( picker_result != 0 )); then
    [[ "$picker_result" == 130 ]] && return 130
    error_echo "子模块选择器失败（退出码 $picker_result），未开始同步"
    return 1
  fi
  [[ "$selected" == *$'\n'* ]] || return 2
  payload="${selected#*$'\n'}"
  [[ -n "$payload" ]] || return 2
  selected_paths=("${(@f)payload}")
  for p in "${selected_paths[@]}"; do
    if (( ${CONFIG_PATHS[(Ie)$p]} == 0 )); then
      error_echo "选择器返回了清单外的路径，未开始同步：$p"
      return 1
    fi
  done

  synchronize_parent_repository || return 1
  reconcile_gitmodules_with_config_once || return 1
  info_echo "开始同步已选择的子模块：${selected_paths[*]}"
  sync_selected_submodules_to_latest "${selected_paths[@]}" || return 1
  stage_and_commit_parent_changes "${selected_paths[@]}" || return 1
  parent_push_if_needed || return 1
  success_echo "已选择子模块同步完成"
  return 0
}
# ============================== fzf 菜单 ==============================
# 展示主菜单并返回用户选中的同步动作。
select_menu_action() {
  local preview_file="$1" menu_cursor="${2:-1}"
  local selected="" picker_result=0

  selected="$(printf '%s\n' \
    "全量同步更新下载到最新" \
    "选择指定子模块同步（可多选）" \
    "只更新目前已有的" \
    "添加并同步一个新的 Git 地址" \
    "切换同步深度（向下递归 / 仅直属一层）" \
    "退出" \
    | FZF_CONFIG_PREVIEW_FILE="$preview_file" FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
        --prompt='请选择操作 > ' --expect=left \
        --height=100% --border --reverse --sync \
        --preview='cat "$FZF_CONFIG_PREVIEW_FILE"' \
        --preview-window='up,70%,border-bottom,nowrap' \
        --header="当前深度：$(submodule_recursion_label)；← 返回用途选择，Esc 取消。Ctrl+K/J 滚动预览，Ctrl+U/D 翻页。" \
        --bind="start:pos($menu_cursor)" \
        --bind='ctrl-k:preview-up,ctrl-j:preview-down,ctrl-u:preview-page-up,ctrl-d:preview-page-down')" || picker_result=$?
  if [[ "${selected%%$'\n'*}" == left ]]; then
    print -r -- '__JOBS_BACK_MODE__'
    return 0
  fi
  (( picker_result == 0 )) || return "$picker_result"
  [[ "$selected" == *$'\n'* ]] || return 130
  selected="${selected#*$'\n'}"
  [[ -n "$selected" ]] || return 130
  print -r -- "$selected"
}
# 将递归配置转为菜单和日志中的明确范围。
submodule_recursion_label() {
  if [[ "$SUBMODULE_RECURSIVE" == 1 ]]; then
    print -r -- '向下递归（所选子树逐层最新）'
  else
    print -r -- '仅直属一层（不拉取下层）'
  fi
}
# 单独选择深度，取消后保留当前设置并返回主菜单。
select_submodule_recursion_interactive() {
  local selected="" picker_result=0 depth_cursor=1
  [[ "$SUBMODULE_RECURSIVE" == 0 ]] && depth_cursor=2
  selected="$(printf '%s\n' '向下递归（所选子树逐层最新）' '仅直属一层（不拉取下层）' |
    FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
      --prompt='同步深度 > ' --height=40% --border --reverse --expect=left --sync \
      --bind="start:pos($depth_cursor)" \
      --header="当前：$(submodule_recursion_label)；← 返回主菜单，Esc 取消脚本。递归不向上、不扩展未选子树。")" || picker_result=$?
  [[ "${selected%%$'\n'*}" == left ]] && return 0
  if (( picker_result != 0 )); then
    [[ "$picker_result" == 130 ]] && return 130
    error_echo "同步深度选择器失败（退出码 $picker_result），原设置保留"
    return 1
  fi
  [[ "$selected" == *$'\n'* ]] || return 0
  selected="${selected#*$'\n'}"
  case "$selected" in
    '向下递归（所选子树逐层最新）') SUBMODULE_RECURSIVE=1 ;;
    '仅直属一层（不拉取下层）') SUBMODULE_RECURSIVE=0 ;;
    '') return 0 ;;
    *) error_echo "同步深度选择无效，原设置保留"; return 1 ;;
  esac
  info_echo "同步深度已选择：$(submodule_recursion_label)"
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
子模块分支: 显式 branch；缺省使用远端默认分支
子模块同步 URL 模式: $style（相对地址继承 $REMOTE_NAME；Gitee 标准地址固定 HTTPS）
.gitmodules 补缺 URL 模式: $gm_style
干跑: $DRY_RUN
自动提交父仓: $AUTO_PARENT_COMMIT
自动推送父仓: $AUTO_PARENT_PUSH
子仓浅克隆: $SUBMODULE_SHALLOW_CLONE
浅克隆深度: $SUBMODULE_DEPTH
同步 tags: $SUBMODULE_FETCH_TAGS
同步深度: $(submodule_recursion_label)
递归边界: 以当前脚本对应仓库为起点，仅进入所选子仓的 .gitmodules；不向上、不扩展未选子树。
深层指针: 下层跟随各自分支最新，可能与父仓记录的 gitlink 不同；不自动暂存或提交深层指针。

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
  local preview_file="$1" action="" picker_result=0 result=0 menu_cursor=1
  while true; do
    build_intro_content > "$preview_file"
    picker_result=0
    action="$(select_menu_action "$preview_file" "$menu_cursor")" || picker_result=$?
    if (( picker_result != 0 )); then
      note_echo "已停止菜单选择，未开始新的同步"
      return "$picker_result"
    fi
    case "$action" in
      "__JOBS_BACK_MODE__") return 20 ;;
      "全量同步更新下载到最新")
        synchronize_parent_repository || return 1
        full_sync_to_latest || return 1
        return 0
        ;;
      "选择指定子模块同步（可多选）")
        menu_cursor=2
        result=0
        select_configured_submodules_interactive "$preview_file" || result=$?
        if (( result == 0 )); then
          return 0
        elif (( result == 2 )); then
          continue
        fi
        return "$result"
        ;;
      "只更新目前已有的")
        synchronize_parent_repository || return 1
        update_existing_to_latest || return 1
        return 0
        ;;
      "添加并同步一个新的 Git 地址")
        menu_cursor=4
        add_new_git_url_interactive || return 1
        ;;
      "切换同步深度（向下递归 / 仅直属一层）")
        menu_cursor=5
        result=0
        select_submodule_recursion_interactive || result=$?
        (( result == 0 )) || return "$result"
        ;;
      "退出") note_echo "已退出"; return 130 ;;
      *) error_echo "未知菜单选项，未开始同步：$action"; return 1 ;;
    esac
  done
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command' | jobs_intro_style title
  print -r -- '核心用途：按脚本清单下载、更新或添加 Git 子模块；默认向下逐层同步，可在菜单切换为仅直属一层。' | jobs_intro_style body
  print -r -- '递归边界：从运行脚本对应仓库向下，仅处理所选子树，各层读取自己的 .gitmodules；不向上处理。' | jobs_intro_style body
  print -r -- '影响范围：父仓登记和提交指针、子仓代码与分支；默认自动提交父仓，不自动推送。' | jobs_intro_style body
  print -r -- '同步策略：全量按清单逐仓处理；已有子仓复用更新，空目录首次初始化，不删除已有子树或旧仓名目录。' | jobs_intro_style body
  print -r -- '文档目录：有已配置的目录过滤器才执行本仓 restore / verify；无配置跳过，不自动安装。' | jobs_intro_style body
  print -r -- '关键风险：分支会对齐远端最新；未提交内容红字加粗标明仓库，循环等待 YES 放弃当前仓改动，或在外部处理后按回车复检。' | jobs_intro_style body
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
}
# 保留既有分支选择及父仓拉取策略。
synchronize_parent_repository() {
  ensure_git_remote "$REMOTE_NAME" || return 1 # 业务已确认后才允许补建缺失远端。
  ensure_parent_branch || return 1 # 确认当前父仓分支后再拉取。
  parent_pull_rebase || return 1 # 父仓有未提交改动时按既有策略跳过拉取。
  run_cmd restore_configured_markdown_toc "$REPO_ROOT" 2>&1 | tee -a "$LOG_FILE" || return 1 # 无更新拉取也检查已配置的还原流程。
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
  if [[ "$SUBMODULE_RECURSIVE" != 0 && "$SUBMODULE_RECURSIVE" != 1 ]]; then
    print -u2 -r -- 'SUBMODULE_RECURSIVE 只支持 0（仅直属一层）或 1（向下递归）。'
    return 1
  fi
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
run_management_download() {
  show_script_intro_and_wait # 首先展示维护模式内置自述，确认失败立即停止。
  initialize_script_runtime # 确认后初始化 Shell、入口路径和本轮日志。
  prepare_parent_repository # 验证父仓根目录，载入本仓清单并准备下载线路。
  ensure_fzf_healthy # 复用可用菜单工具，缺失时才处理依赖。
  prepare_preview_runtime # 准备菜单预览及退出清理。
  main_menu_loop "$PREVIEW_FILE" # 根据菜单选择同步，失败立即向入口传播。
  report_completion # 成功后汇总结果与日志位置。
}
# 先选择用途，默认只拉取在维护依赖和父仓写操作之前分流。
select_download_operation_mode() {
  initialize_script_paths || return 1
  local selected="" picker_result=0 mode_cursor=1
  [[ "${DOWNLOAD_OPERATION_MODE:-readonly}" == maintenance ]] && mode_cursor=2
  print -r -- '================ Git 子模块下载与同步 ================' | jobs_intro_style title
  print -r -- '同步策略版本：2026.10.25-fzf-navigation（选择支持逐层返回，子仓继续跟随分支最新）' | jobs_intro_style body
  print -r -- '同步策略：只拉取跟随各层目标分支最新；维护模式保留本仓清单及原提交开关。' | jobs_intro_style body
  print -r -- "目标父仓：$REPO_ROOT" | jobs_intro_style body
  print -r -- '只拉取不暂存、不提交、不推送；维护模式会登记子仓，沿用 AUTO_PARENT_*。危险舍弃另需 YES。' | jobs_intro_style body
  print -r -- '先通过 fzf 选择用途，再阅读对应自述并回车确认；← 从维护菜单返回本页，Esc / Ctrl+C 取消。' | jobs_intro_style body
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -u2 -r -- '当前没有可交互终端，未执行任何同步；请在终端重新运行。'
    return 1
  fi
  if ! command -v fzf >/dev/null 2>&1 || ! fzf --version >/dev/null 2>&1; then
    print -u2 -r -- 'fzf 未安装或不可用，未执行同步。请先安装 / 修复 fzf（已有 Homebrew 时可运行 brew install fzf），再重新运行。'
    return 1
  fi
  selected="$(printf '%s\n' '只拉取（默认，不暂存、不提交、不推送）' '维护子模块（使用本仓清单及原提交开关）' |
    FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --height=40% --border --reverse --sync \
      --bind="start:pos($mode_cursor)" \
      --prompt='选择用途 > ' --header='↑↓ 移动，回车确认，Esc / Ctrl+C 取消；选中用途后仍须阅读自述并确认')" || picker_result=$?
  (( picker_result == 0 )) || return "$picker_result"
  case "$selected" in
    '只拉取（默认，不暂存、不提交、不推送）') DOWNLOAD_OPERATION_MODE=readonly ;;
    '维护子模块（使用本仓清单及原提交开关）') DOWNLOAD_OPERATION_MODE=maintenance ;;
    '') return 130 ;;
    *) print -u2 -r -- '用途选择无效，未执行同步。'; return 1 ;;
  esac
}
# 执行内嵌的安全只拉取实现，保留终端输入且不依赖外置脚本。
run_embedded_readonly_pull() {
  local engine_code=""
  engine_code="$(/bin/cat <<'JOBS_READONLY_PULL_ENGINE'
#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】⏬只拉取远程代码.command
# - 核心用途：将当前仓库同步到明确的远程上游，逐层检出子模块目标分支的远端最新提交，不提交、不推送。
# - 影响范围：先 fetch；发现本地改动、未跟踪文件或独有提交时，终端红字列明范围，精确输入 YES 才舍弃。
# - 保护边界：忽略文件保留；游离入口先预检再恢复跟踪分支，独有历史、上游不明确、子仓风险或忽略文件覆盖风险时停止。
# - 运行提示：SourceTree 只打开 Terminal.app；终端先回车确认，危险操作另需 YES，Ctrl+C 取消。

RAW_SCRIPT_PATH="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
IS_SOURCETREE_RUNTIME=0
TERMINAL_RUN=0
PLAIN_OUTPUT=1
REPOSITORY=""
BRANCH=""
REMOTE=""
MERGE_REF=""
TRACKING_REF=""
SOURCE_URL=""
EFFECTIVE_URL=""
ORIGINAL_HEAD=""
ENTRY_DETACHED=0
DETACHED_TARGET_HEAD=""
DETACHED_TARGET_REMOTE_CONFIG=""
DETACHED_TARGET_MERGE_CONFIG=""
DETACHED_PARENT_ROOT=""
DETACHED_PARENT_PATH=""
DETACHED_PARENT_MANIFEST=""
DETACHED_PARENT_PIN=""
DETACHED_PARENT_BRANCH=""
TARGET_HEAD=""
WORKTREE_STATE=""
WORKTREE_FINGERPRINT=""
LOCAL_ONLY_COUNT=0
PREPARE_DIRECTORY=""
SYNC_STARTED=0
PLAN_PATHS=()
PLAN_PARENTS=()
PLAN_SECTIONS=()
PLAN_TARGETS=()
PLAN_URLS=()
PLAN_ORIGINAL_HEADS=()
PLAN_ORIGINAL_BRANCHES=()
PLAN_OBJECT_REPOS=()
PLAN_OLD_PINS=()
PLAN_BRANCHES=()
PLAN_REMOTES=()
PLAN_LOCAL_HEADS=()
LOCK_DIRECTORY=""
LOCK_HELD=0
COLOR_RED=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_RESET=""
# 只读解析入口和展示变量，不在确认前写入文件。
prepare_display_context() {
  local candidate="${RAW_SCRIPT_PATH:A}"
  local filename="${RAW_SCRIPT_PATH:t}"
  local fallback=""
  for fallback in "${HOME}/SourceTree.command/${filename}/${filename}" "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/${filename}/${filename}"; do
    [[ -f "$candidate" ]] && break
    [[ -f "$fallback" ]] && candidate="$fallback"
  done
  SCRIPT_PATH="$candidate"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.$(/bin/date +%Y%m%d-%H%M%S).$$.log"
  [[ "${1:-}" == --terminal-run ]] && TERMINAL_RUN=1
  if (( ! TERMINAL_RUN )); then
    local process_id="$PPID" process_name="" guard=0
    if /usr/bin/env | /usr/bin/grep -Eqi '^(SOURCETREE|SOURCE_TREE)'; then
      IS_SOURCETREE_RUNTIME=1
    fi
    while [[ -n "$process_id" && "$process_id" != 0 && "$guard" -lt 8 ]]; do
      process_name="$(/bin/ps -o comm= -p "$process_id" 2>/dev/null)"
      [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && IS_SOURCETREE_RUNTIME=1
      process_id="$(/bin/ps -o ppid= -p "$process_id" 2>/dev/null | /usr/bin/tr -d ' ')"
      guard=$((guard + 1))
    done
  fi
  configure_output_mode
}
# SourceTree 输出纯文本，独立终端按终端能力显示红字。
configure_output_mode() {
  PLAIN_OUTPUT=1
  if (( ! IS_SOURCETREE_RUNTIME )) && [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=0
    COLOR_RED=$'\033[1;31m'
    COLOR_BLUE=$'\033[0;34m'
    COLOR_GREEN=$'\033[0;32m'
    COLOR_RESET=$'\033[0m'
  else
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 过滤终端控制码和地址凭据，日志只保留可读脱敏文本。
sanitize_stream() {
  /usr/bin/perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g; s{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*@}{$1***@}g; s{((?:https?|ssh|git|file)://[^\s?#]+)[?#][^\s]*}{$1?[REDACTED]}g'
}
# 显示内置自述；SourceTree 转交终端，终端先确认再进入业务。
show_script_intro_and_wait() {
  prepare_display_context "$@"
  print -r -- "${COLOR_RED}================ 只拉取远程代码 ================${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}1、同步当前仓库明确的远程上游，再向下检出各子仓目标分支的远端最新提交；不提交、不推送。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}2、先获取远程；本地改动、未跟踪文件和独有提交须精确输入 YES 才舍弃。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}3、子模块按 .gitmodules 分支（缺省为远端默认分支）更新并保持分支态；子仓源码、暂存指针、分叉和独有游离提交均停止。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}游离入口：先确定分支并获取远端，检查历史与工作区后才恢复本地跟踪分支；独有历史或脏源码停止。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}4、已配置目录过滤器的仓库执行本仓 restore / verify；无配置跳过，不自动安装。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}5、SourceTree 打开独立终端；回车继续，Ctrl+C 取消；日志：${LOG_FILE}${COLOR_RESET}"
  if (( IS_SOURCETREE_RUNTIME )); then
    open_terminal_for_repository "$@"
    exit $?
  fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -u2 -r -- "请在可交互终端运行；非交互输入不能代替回车或 YES 确认。"
    exit 1
  fi
  local answer=""
  IFS= read -r 'answer?👉 已了解用途与风险，按回车继续；Ctrl+C 取消：' || exit 1
  [[ -z "$answer" ]] || { print -r -- '已取消。'; exit 2; }
}
# 用 AppleScript argv 和 shell 引号传递路径，启动器不执行 Git 业务。
open_terminal_for_repository() {
  [[ "$#" -eq 1 && -d "$1" ]] || { print -u2 -r -- 'SourceTree 必须传入一个有效仓库目录（$REPO）。'; return 1; }
  /usr/bin/osascript - "$SCRIPT_PATH" "${1:A}" <<'APPLESCRIPT'
on run argv
  set scriptPath to item 1 of argv
  set repositoryPath to item 2 of argv
  set shellCommand to "/bin/zsh " & quoted form of scriptPath & " --terminal-run " & quoted form of repositoryPath & "; jobs_pull_result=$?; printf '\n只拉取结束，退出码：%s\n' \"$jobs_pull_result\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  local launch_result=$?
  if (( launch_result != 0 )); then
    print -u2 -r -- 'Terminal 启动失败，请检查自动化权限或在终端手动运行脚本。'
    return "$launch_result"
  fi
  print -r -- '已打开 Terminal；确认、实时日志与最终退出码请查看新终端。'
}
# 确认后初始化私有日志和清理钩子。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  umask 077
  : > "$LOG_FILE" || { print -u2 -r -- "无法创建日志：${LOG_FILE}"; exit 1; }
  configure_output_mode
  configure_gitee_https_transport
}
# 兼容旧根仓 / 子仓的 Gitee 标准 SSH 地址；只追加本次进程配置，保留既有 Git 环境规则。
configure_gitee_https_transport() {
  local config_count="${GIT_CONFIG_COUNT:-0}" prefix=""
  [[ "$config_count" == <-> && ${#config_count} -le 9 ]] || fail 'GIT_CONFIG_COUNT 无效，不能安全追加本次 HTTPS 兼容配置。'
  local -i config_index=$(( 10#$config_count ))
  local -a ssh_prefixes
  ssh_prefixes=('git@gitee.com:' 'ssh://git@gitee.com/' 'ssh://git@gitee.com:22/')
  for prefix in "${ssh_prefixes[@]}"; do
    typeset -gx "GIT_CONFIG_KEY_${config_index}=url.https://gitee.com/.insteadOf"
    typeset -gx "GIT_CONFIG_VALUE_${config_index}=$prefix"
    (( config_index += 1 ))
  done
  export GIT_CONFIG_COUNT="$config_index"
  log_message info 'Gitee 标准 SSH 地址在本次进程兼容 HTTPS；来源块显示 Git 配置展开后的拉取地址。'
}
# 同步记录脱敏纯文本和终端展示颜色。
log_message() {
  local role="$1" message="$2" clean_message="" color=""
  clean_message="$(print -r -- "$message" | sanitize_stream)" || exit 1
  print -r -- "$clean_message" >> "$LOG_FILE" || exit 1
  case "$role" in
    danger) color="$COLOR_RED" ;;
    success) color="$COLOR_GREEN" ;;
    *) color="$COLOR_BLUE" ;;
  esac
  print -r -- "${color}${clean_message}${COLOR_RESET}"
}
# 明确报错并停止后续写操作。
fail() {
  log_message danger "✖ $1"
  (( ! SYNC_STARTED )) || log_message danger '部分仓库可能已经检出目标；未创建提交或推送。请按日志处理后重新运行，不能将本次视为完成。'
  log_message info "日志：${LOG_FILE}"
  exit 1
}
# 只还原已配置的目录过滤器；无配置不安装，保留当前正文与暂存内容。
restore_configured_markdown_toc() {
  local toc_root="${1:A}" toc_smudge="" toc_process="" toc_node="" toc_result=0
  toc_smudge="$(command git -C "$toc_root" config --get filter.jobs-markdown-toc.smudge)" || toc_result=$?
  if (( toc_result > 1 )); then
    print -u2 -r -- "无法读取 Markdown 目录过滤器，保留现场：${toc_root}"
    return 1
  fi
  toc_result=0
  toc_process="$(command git -C "$toc_root" config --get filter.jobs-markdown-toc.process)" || toc_result=$?
  if (( toc_result > 1 )) || [[ -n "$toc_process" ]]; then
    print -u2 -r -- "Markdown 目录 process 配置冲突或读取失败，保留现场：${toc_root}"
    return 1
  fi
  if [[ -z "$toc_smudge" ]]; then
    print -r -- "Markdown 目录：未配置还原过滤器，跳过：${toc_root}"
    return 0
  fi
  # 还原不跨越未完成的合并、冲突或其它 Git 写操作。
  local toc_marker="" toc_marker_path="" toc_unmerged=""
  for toc_marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START index.lock; do
    toc_marker_path="$(command git -C "$toc_root" rev-parse --git-path "$toc_marker")" || return 1
    [[ "$toc_marker_path" == /* ]] || toc_marker_path="${toc_root}/${toc_marker_path}"
    if [[ -e "$toc_marker_path" ]]; then
      print -u2 -r -- "存在未完成 Git 操作或锁，未还原目录：${toc_root}（${toc_marker}）"
      return 1
    fi
  done
  toc_unmerged="$(command git -C "$toc_root" ls-files --unmerged)" || return 1
  if [[ -n "$toc_unmerged" ]]; then
    print -u2 -r -- "索引存在未解决冲突，未还原目录：${toc_root}"
    return 1
  fi
  local toc_tool="${toc_root}/.jobs-markdown-toc/MarkdownToc.mjs"
  if [[ ! -f "$toc_tool" || -L "$toc_tool" || -L "${toc_tool:h}" ]]; then
    print -u2 -r -- "已配置 Markdown 目录过滤器，但缺少本仓安全还原工具，停止：${toc_tool}"
    return 1
  fi
  # 优先使用过滤器已登记的 Node 路径，不求值或执行配置中的 Shell 文本。
  local -a toc_words
  toc_words=(${(z)toc_smudge})
  toc_node="${(Q)toc_words[1]}"
  if [[ "$toc_node" != /* || "${toc_node:t}" != node || ! -x "$toc_node" ]]; then
    toc_node="$(command -v node 2>/dev/null)" || toc_node=""
  fi
  if [[ -z "$toc_node" || ! -x "$toc_node" ]]; then
    print -u2 -r -- "已配置 Markdown 目录过滤器，但 Node.js 不可用；未安装或改写配置：${toc_root}"
    return 1
  fi
  print -r -- "Markdown 目录：执行已配置过滤器的本仓还原与检查：${toc_root}"
  "$toc_node" "$toc_tool" restore || return 1
  "$toc_node" "$toc_tool" verify
}
# 把入口仓恢复日志纳入当前只拉取日志，失败交给主流程停止。
restore_entry_markdown_toc() {
  restore_configured_markdown_toc "$REPOSITORY" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE" || fail '入口仓 Markdown 目录还原失败。'
}
# 所有 Git 操作禁用递归和本地钩子，避免一次拉取扩展业务范围。
repo_git() {
  command git -C "$REPOSITORY" -c color.ui=false -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"
}
# 外部 Git 输出脱敏落盘，并保留管道失败状态。
run_git() {
  repo_git "$@" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE"
}
# 仅接受有效目标目录，并确认 Git 真实可执行。
resolve_repository() {
  (( TERMINAL_RUN )) && shift
  [[ "$#" -le 1 ]] || fail '只接受一个仓库目录。'
  local requested="${1:-$PWD}"
  [[ -d "$requested" ]] || fail "目标目录不存在：${requested}"
  command -v git >/dev/null 2>&1 && command git --version >/dev/null 2>&1 || fail 'Git 不可用，请先安装或修复 Command Line Tools。'
  REPOSITORY="$(command git -C "$requested" rev-parse --show-toplevel 2>/dev/null)" || fail '目标不是 Git 工作树。'
  REPOSITORY="${REPOSITORY:A}"
  [[ "$(repo_git rev-parse --is-bare-repository)" == false ]] || fail '不支持裸仓库。'
  log_message info "仓库：${REPOSITORY}"
  LOCK_DIRECTORY="$(repo_git rev-parse --git-path jobs-readonly-pull.lock)" || fail '无法确定锁目录。'
  [[ "$LOCK_DIRECTORY" == /* ]] || LOCK_DIRECTORY="${REPOSITORY}/${LOCK_DIRECTORY}"
  /bin/mkdir "$LOCK_DIRECTORY" 2>/dev/null || fail "另一次只拉取任务可能正在运行；请核实后处理锁目录：${LOCK_DIRECTORY}"
  LOCK_HELD=1
}
# 只释放本进程取得的空锁目录。
release_repository_lock() {
  if (( LOCK_HELD && ZSH_SUBSHELL == 0 )); then
    if [[ -n "$PREPARE_DIRECTORY" && "$PREPARE_DIRECTORY" == "${LOCK_DIRECTORY}/prepare."* && -d "$PREPARE_DIRECTORY" ]]; then
      /usr/bin/find "$PREPARE_DIRECTORY" -depth -delete || print -u2 -r -- "无法清理本次临时准备目录：${PREPARE_DIRECTORY}"
    fi
    /bin/rm -f -- "${LOCK_DIRECTORY}/head-tree" "${LOCK_DIRECTORY}/target-tree" "${LOCK_DIRECTORY}/untracked" "${LOCK_DIRECTORY}/nested" "${LOCK_DIRECTORY}/ignored" "${LOCK_DIRECTORY}/protected-tree" "${LOCK_DIRECTORY}/snapshot" "${LOCK_DIRECTORY}/snapshot-paths"
    /bin/rmdir "$LOCK_DIRECTORY" 2>/dev/null || print -u2 -r -- "无法释放锁目录：${LOCK_DIRECTORY}"
    LOCK_HELD=0
  fi
}
# zsh 的函数内 EXIT trap 会随函数返回触发，改用脚本级退出函数。
TRAPEXIT() {
  release_repository_lock
}
# 中断进入脚本级退出清理，返回可识别的终止状态。
TRAPINT() {
  exit 130
}
# 终止信号不继续 Git 写操作。
TRAPTERM() {
  exit 143
}
# 终端断开时同样保留失败状态并释放本脚本锁。
TRAPHUP() {
  exit 129
}
# 冲突、进行中的 Git 操作和隐藏状态在任何 fetch / 清理前阻断。
assert_repository_ready() {
  local marker="" marker_path="" flags="" entry=""
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START index.lock; do
    marker_path="$(repo_git rev-parse --git-path "$marker")" || fail '无法检查 Git 操作状态。'
    [[ "$marker_path" == /* ]] || marker_path="${REPOSITORY}/${marker_path}"
    [[ ! -e "$marker_path" ]] || fail "存在未完成操作或 Git 锁：${REPOSITORY}（${marker}）；请先处理。"
  done
  [[ -z "$(repo_git ls-files -u)" ]] || fail '索引存在未解决冲突。'
  flags="$(repo_git ls-files -v)" || fail '无法检查索引标记。'
  for entry in "${(@f)flags}"; do
    [[ "$entry" != [a-zS]' '* ]] || fail '存在 assume-unchanged / skip-worktree（含稀疏检出），请先显式恢复普通工作树。'
  done
}
# 游离入口先按直接父仓清单选分支；独立仓库缺省查询明确远端的 HEAD。
resolve_detached_entry_upstream() {
  local keys="" key="" candidate_path="" section="" requested="" result=0 remote_listing="" advertised="" configured_remote="" configured_merge=""
  ENTRY_DETACHED=1
  DETACHED_PARENT_ROOT="$(repo_git rev-parse --show-superproject-working-tree)" || fail '无法检查游离入口的直接父仓。'
  if [[ -n "$DETACHED_PARENT_ROOT" ]]; then
    DETACHED_PARENT_ROOT="${DETACHED_PARENT_ROOT:A}"
    DETACHED_PARENT_PATH="${REPOSITORY#"${DETACHED_PARENT_ROOT}/"}"
    [[ "$DETACHED_PARENT_PATH" != "$REPOSITORY" && -f "${DETACHED_PARENT_ROOT}/.gitmodules" ]] || fail '游离入口缺少有效的直接父仓清单。'
    DETACHED_PARENT_MANIFEST="$(tree_git "$DETACHED_PARENT_ROOT" hash-object --no-filters -- .gitmodules)" || fail '无法记录直接父仓清单。'
    DETACHED_PARENT_PIN="$(detached_entry_parent_pin)" || fail '无法记录直接父仓指针。'
    [[ -n "$DETACHED_PARENT_PIN" ]] || fail '直接父仓索引未登记当前子模块，不能接管游离入口。'
    keys="$(tree_git "$DETACHED_PARENT_ROOT" config --file "${DETACHED_PARENT_ROOT}/.gitmodules" --name-only --get-regexp '^submodule\..*\.path$')" || result=$?
    (( result == 0 || result == 1 )) || fail '直接父仓 .gitmodules 无法解析。'
    for key in "${(@f)keys}"; do
      [[ -n "$key" ]] || continue
      candidate_path="$(tree_git "$DETACHED_PARENT_ROOT" config --file "${DETACHED_PARENT_ROOT}/.gitmodules" --get-all "$key")" || fail '无法读取直接父仓子模块路径。'
      [[ "$candidate_path" == "$DETACHED_PARENT_PATH" ]] || continue
      [[ -z "$section" ]] || fail '直接父仓对子模块存在重复登记。'
      section="${key#submodule.}"
      section="${section%.path}"
    done
    [[ -n "$section" ]] || fail '直接父仓清单中找不到当前子仓。'
    result=0
    requested="$(tree_git "$DETACHED_PARENT_ROOT" config --file "${DETACHED_PARENT_ROOT}/.gitmodules" --get-all "submodule.${section}.branch")" || result=$?
    (( result == 0 || result == 1 )) || fail '无法读取直接父仓的目标分支。'
    [[ "$requested" != *$'\n'* ]] || fail '直接父仓的子模块分支配置不唯一。'
    if [[ "$requested" == . ]]; then
      DETACHED_PARENT_BRANCH="$(tree_git "$DETACHED_PARENT_ROOT" symbolic-ref --quiet --short HEAD)" || fail 'branch=. 需要直接父仓位于明确分支。'
      requested="$DETACHED_PARENT_BRANCH"
    fi
  fi
  BRANCH="$requested"
  if [[ -n "$BRANCH" ]] && repo_git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    REMOTE="$(repo_git config --get-all "branch.${BRANCH}.remote")" || fail '游离入口的目标本地分支没有明确远程上游。'
  elif repo_git config --get-all remote.origin.url >/dev/null; then
    REMOTE=origin
  else
    remote_listing="$(repo_git remote)" || fail '无法读取游离入口的远端。'
    [[ -n "$remote_listing" && "$remote_listing" != *$'\n'* ]] || fail '游离入口缺少 origin 或唯一远端，不能猜测下载来源。'
    REMOTE="$remote_listing"
  fi
  [[ -n "$REMOTE" && "$REMOTE" != . && "$REMOTE" != -* && "$REMOTE" != *$'\n'* ]] || fail '游离入口必须使用单个明确的远程上游。'
  SOURCE_URL="$(repo_git config --get-all "remote.${REMOTE}.url")" || fail '游离入口的远程地址未配置。'
  [[ -n "$SOURCE_URL" && "$SOURCE_URL" != *$'\n'* ]] || fail '游离入口的远程地址必须唯一。'
  EFFECTIVE_URL="$(repo_git ls-remote --get-url "$REMOTE")" || fail '无法展开游离入口的 Git URL 配置。'
  if [[ -z "$BRANCH" ]]; then
    log_message info "游离入口查询远端默认分支；来源：${SOURCE_URL}；拉取地址：${EFFECTIVE_URL}"
    advertised="$(repo_git ls-remote --symref -- "$REMOTE" HEAD)" || fail '无法查询游离入口的远端默认分支。'
    BRANCH="$(print -r -- "$advertised" | /usr/bin/awk '$1 == "ref:" && $2 ~ /^refs\/heads\// { sub(/^refs\/heads\//, "", $2); print $2; exit }')"
    [[ -n "$BRANCH" ]] || fail '远端 HEAD 未指向明确分支；请在直接父仓 .gitmodules 指定 branch。'
  fi
  MERGE_REF="refs/heads/${BRANCH}"
  repo_git check-ref-format "$MERGE_REF" || fail '游离入口目标分支名无效。'
  [[ "$BRANCH" != -* && "$BRANCH" != HEAD ]] || fail '游离入口目标必须是普通分支。'
  DETACHED_TARGET_HEAD="$(repo_git rev-parse --verify "refs/heads/${BRANCH}^{commit}" 2>/dev/null)" || DETACHED_TARGET_HEAD=""
  DETACHED_TARGET_REMOTE_CONFIG="$(repo_git config --get-all "branch.${BRANCH}.remote" 2>/dev/null)" || DETACHED_TARGET_REMOTE_CONFIG=""
  DETACHED_TARGET_MERGE_CONFIG="$(repo_git config --get-all "branch.${BRANCH}.merge" 2>/dev/null)" || DETACHED_TARGET_MERGE_CONFIG=""
  if [[ -n "$DETACHED_TARGET_HEAD" ]]; then
    [[ "$DETACHED_TARGET_REMOTE_CONFIG" == "$REMOTE" && "$DETACHED_TARGET_MERGE_CONFIG" == "$MERGE_REF" ]] || fail '游离入口的目标本地分支必须明确跟踪所选远端的同名分支；请先修复上游配置。'
    TRACKING_REF="$(repo_git for-each-ref --format='%(upstream)' "refs/heads/${BRANCH}")" || fail '无法解析游离入口目标分支的跟踪引用。'
    [[ "$TRACKING_REF" == refs/remotes/* && "$TRACKING_REF" != *$'\n'* ]] || fail '游离入口目标分支的远程跟踪映射不明确。'
  else
    TRACKING_REF="refs/remotes/${REMOTE}/${BRANCH}"
  fi
  log_message info "游离入口已计划恢复跟踪分支：${BRANCH} → ${REMOTE}/${BRANCH}；预检完成前保留原 HEAD。"
}
# 父仓索引中的旧 pin 仍保护首次递归下载取得的提交。
detached_entry_parent_pin() {
  tree_git "$DETACHED_PARENT_ROOT" --literal-pathspecs ls-files --stage -- "$DETACHED_PARENT_PATH" | /usr/bin/awk '$1 == "160000" && $3 == "0" { print $2; exit }'
}
# detached 独有历史和目标本地分支的分叉不接受根仓 YES 舍弃授权。
assert_detached_entry_history_safe() {
  (( ENTRY_DETACHED )) || return 0
  assert_child_head_is_preserved "$REPOSITORY" "$DETACHED_PARENT_PIN" "$TARGET_HEAD"
  if [[ -n "$DETACHED_TARGET_HEAD" ]]; then
    repo_git merge-base --is-ancestor "$DETACHED_TARGET_HEAD" "$TARGET_HEAD" || fail '游离入口的目标本地分支存在独有提交或无法快进；保留现场，请先整合。'
  fi
}
# 确认期只核对原现场，不提前切分支或创建本地引用。
assert_detached_entry_unchanged() {
  local current_branch="" local_head="" remote_config="" merge_config=""
  current_branch="$(repo_git symbolic-ref --quiet --short HEAD 2>/dev/null)" || current_branch=""
  [[ -z "$current_branch" && "$(repo_git rev-parse HEAD)" == "$ORIGINAL_HEAD" ]] || fail '确认期间游离入口 HEAD 或分支已变化，请重新运行。'
  local_head="$(repo_git rev-parse --verify "refs/heads/${BRANCH}^{commit}" 2>/dev/null)" || local_head=""
  [[ "$local_head" == "$DETACHED_TARGET_HEAD" ]] || fail '确认期间游离入口的目标本地分支已变化，请重新运行。'
  remote_config="$(repo_git config --get-all "branch.${BRANCH}.remote" 2>/dev/null)" || remote_config=""
  merge_config="$(repo_git config --get-all "branch.${BRANCH}.merge" 2>/dev/null)" || merge_config=""
  [[ "$remote_config" == "$DETACHED_TARGET_REMOTE_CONFIG" && "$merge_config" == "$DETACHED_TARGET_MERGE_CONFIG" ]] || fail '确认期间游离入口的目标分支上游配置已变化。'
  if [[ -n "$DETACHED_PARENT_ROOT" ]]; then
    [[ "$(tree_git "$DETACHED_PARENT_ROOT" hash-object --no-filters -- .gitmodules)" == "$DETACHED_PARENT_MANIFEST" && "$(detached_entry_parent_pin)" == "$DETACHED_PARENT_PIN" ]] || fail '确认期间直接父仓清单或子模块指针已变化。'
    if [[ -n "$DETACHED_PARENT_BRANCH" ]]; then
      [[ "$(tree_git "$DETACHED_PARENT_ROOT" symbolic-ref --quiet --short HEAD)" == "$DETACHED_PARENT_BRANCH" ]] || fail '确认期间 branch=. 的直接父仓分支已变化。'
    fi
  fi
  assert_detached_entry_history_safe
}
# 所有预检通过后才恢复跟踪分支；已存在的分支仅允许快进。
synchronize_detached_entry() {
  assert_detached_entry_unchanged
  if [[ -n "$DETACHED_TARGET_HEAD" ]]; then
    run_git checkout --no-recurse-submodules --no-overwrite-ignore "$BRANCH" || fail '无法恢复游离入口的目标分支。'
    run_git -c "branch.${BRANCH}.mergeOptions=" merge --ff-only --no-autostash --no-overwrite-ignore --no-edit "$TARGET_HEAD" || fail '游离入口的目标分支无法快进。'
  else
    run_git checkout --no-recurse-submodules --no-overwrite-ignore -b "$BRANCH" "$TARGET_HEAD" || fail '无法创建游离入口的跟踪分支。'
    if [[ "$(repo_git -c "branch.${BRANCH}.remote=${REMOTE}" -c "branch.${BRANCH}.merge=${MERGE_REF}" rev-parse --symbolic-full-name "${BRANCH}@{upstream}" 2>/dev/null)" != "$TRACKING_REF" ]]; then
      run_git config --local --add "remote.${REMOTE}.fetch" "+${MERGE_REF}:${TRACKING_REF}" || fail '无法补齐游离入口的目标分支映射。'
    fi
    run_git branch --set-upstream-to="${REMOTE}/${BRANCH}" "$BRANCH" || fail '无法设置游离入口分支上游。'
  fi
  [[ "$(repo_git symbolic-ref --quiet --short HEAD)" == "$BRANCH" && "$(repo_git rev-parse HEAD)" == "$TARGET_HEAD" ]] || fail '游离入口恢复后的分支或提交核验失败。'
}
# 正常分支沿用明确上游；游离入口先计划恢复，不提前修改工作树。
resolve_upstream() {
  ORIGINAL_HEAD="$(repo_git rev-parse --verify HEAD)" || fail '当前仓库没有有效提交。'
  BRANCH="$(repo_git symbolic-ref --quiet --short HEAD 2>/dev/null)" || BRANCH=""
  if [[ -z "$BRANCH" ]]; then
    resolve_detached_entry_upstream
    return
  fi
  REMOTE="$(repo_git config --get-all "branch.${BRANCH}.remote")" || fail '当前分支没有配置远程上游。'
  MERGE_REF="$(repo_git config --get-all "branch.${BRANCH}.merge")" || fail '当前分支没有配置上游分支。'
  [[ -n "$REMOTE" && "$REMOTE" != . && "$REMOTE" != -* && "$REMOTE" != *$'\n'* ]] || fail '只支持一个明确的远程上游。'
  [[ "$MERGE_REF" == refs/heads/* && "$MERGE_REF" != *$'\n'* ]] || fail '上游必须是单个远程分支。'
  repo_git check-ref-format "$MERGE_REF" || fail '上游分支名无效。'
  TRACKING_REF="$(repo_git for-each-ref --format='%(upstream)' "refs/heads/${BRANCH}")" || fail '无法解析远程跟踪引用。'
  [[ "$TRACKING_REF" == refs/remotes/* && "$TRACKING_REF" != *$'\n'* ]] || fail '远程跟踪映射不明确；请先修复分支上游配置。'
  SOURCE_URL="$(repo_git config --get-all "remote.${REMOTE}.url")" || fail '远程地址未配置。'
  [[ -n "$SOURCE_URL" && "$SOURCE_URL" != *$'\n'* ]] || fail '远程地址必须唯一。'
  EFFECTIVE_URL="$(repo_git ls-remote --get-url "$REMOTE")" || fail '无法展开当前 Git URL 配置。'
}
# 来源先于传输展示；只获取目标分支，失败时绝不清理工作区。
fetch_target() {
  log_message info '━━━━━━━━━━ 来源｜只拉取 ━━━━━━━━━━'
  log_message info "对象：${BRANCH} → ${REMOTE}/${MERGE_REF#refs/heads/}"
  log_message info "配置来源：${SOURCE_URL}"
  log_message info "拉取地址（本地 Git 配置展开）：${EFFECTIVE_URL}"
  log_message info "目标位置：${REPOSITORY}"
  run_git fetch --no-tags --no-recurse-submodules -- "$REMOTE" "+${MERGE_REF}:${TRACKING_REF}" || fail '远程获取失败，未舍弃本地内容。'
  TARGET_HEAD="$(repo_git rev-parse --verify "${TRACKING_REF}^{commit}")" || fail '远程目标不是有效提交。'
  log_message info "本次固定目标：${TARGET_HEAD}"
  assert_detached_entry_history_safe
}
# 完整检查可能被覆盖或清理的目录，枚举失败也必须停止。
assert_directory_has_no_nested_git() {
  local directory="$1" nested=""
  /usr/bin/find "$directory" \( -name .git -print0 -prune \) -o \( -type d -name objects -print0 -prune \) > "${LOCK_DIRECTORY}/nested" || fail "无法完整检查目录，已停止清理：${directory}"
  while IFS= read -r -d '' nested; do
    [[ "${nested:t}" != .git ]] || fail "存在嵌套 Git 仓库，不能安全清理：${nested:h}"
    if [[ -f "${nested:h}/HEAD" && -d "${nested:h}/refs" ]]; then
      fail "存在嵌套裸仓库，不能安全清理：${nested:h}"
    fi
  done < "${LOCK_DIRECTORY}/nested"
}
# 已跟踪目录内也可能被另行 git init，不能仅依赖未跟踪文件列表。
assert_tracked_paths_have_no_nested_git() {
  local listing="$1" entry="" item="" parent=""
  local -A checked_parents=()
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] && continue
    item="${entry#*$'\t'}"
    if [[ -d "${REPOSITORY}/${item}" && ! -L "${REPOSITORY}/${item}" ]]; then
      assert_directory_has_no_nested_git "${REPOSITORY}/${item}"
    fi
    parent="${item:h}"
    while [[ "$parent" != . && -n "$parent" ]]; do
      [[ "${checked_parents[$parent]:-0}" != 1 ]] || break
      checked_parents[$parent]=1
      [[ ! -e "${REPOSITORY}/${parent}/.git" ]] || fail "已跟踪路径内存在独立 Git 仓库：${REPOSITORY}/${parent}"
      if [[ -f "${REPOSITORY}/${parent}/HEAD" && -d "${REPOSITORY}/${parent}/objects" && -d "${REPOSITORY}/${parent}/refs" ]]; then
        fail "已跟踪路径内存在裸仓库：${REPOSITORY}/${parent}"
      fi
      parent="${parent:h}"
    done
  done < "$listing"
}
# 子仓和临时裸仓共用最小 Git 配置；URL 仅逐层显式传入，不覆盖 root remote。
tree_git() {
  local tree_repository="$1"
  shift
  command git -C "$tree_repository" -c color.ui=false -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"
}
# 保留 Git 失败状态，所有子仓传输输出同样脱敏。
run_tree_git() {
  tree_git "$@" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE"
}
# 子模块路径不能穿过符号链接、仓外目录或 Git 元数据。
validate_submodule_path() {
  local parent_root="$1" child_path="$2" component="" prefix="$1"
  [[ -n "$child_path" && "$child_path" != /* && "$child_path" != -* && "$child_path" != *$'\n'* && "$child_path" != *$'\r'* ]] || fail "子模块路径无效：${parent_root}/${child_path}"
  for component in "${(@s:/:)child_path}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. && "${component:l}" != .git ]] || fail "子模块路径越界或涉及元数据：${parent_root}/${child_path}"
    prefix+="/${component}"
    [[ ! -L "$prefix" ]] || fail "子模块路径经过符号链接：${prefix}"
  done
  [[ "${prefix:A}" == "${parent_root}/"* ]] || fail "子模块路径不在父仓内：${prefix}"
}
# 按远端仓库目录语义解析相对地址，保留 host、namespace、协议和自定义端口。
resolve_child_source_url() {
  local parent_url="$1" raw_url="$2" parent_root="$3" resolved=""
  [[ -n "$raw_url" && "$raw_url" != -* && "$raw_url" != *$'\n'* && "$raw_url" != *$'\r'* && "$raw_url" != *'::'* ]] || fail "子模块来源无效：${parent_root}"
  resolved="$(/usr/bin/perl -e '
    use strict; use warnings;
    my ($base, $url, $root) = @ARGV;
    if ($url =~ m{^\./|^\.\./}) {
      my ($prefix, $path);
      if ($base =~ m{^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]*)(/.*)$}) { ($prefix, $path) = ($1, $2); }
      elsif ($base =~ m{^([^/:]+(?:\@[^/:]+)?:)(.+)$}) { ($prefix, $path) = ($1, $2); }
      else { ($prefix, $path) = ("", $base); $path = "$root/$path" unless $path =~ m{^/}; }
      my $absolute = $path =~ m{^/};
      my @parts;
      for my $part (split m{/}, "$path/$url") {
        next if $part eq "" || $part eq ".";
        if ($part eq "..") { die "Relative URL escapes repository scope\n" unless @parts; pop @parts; }
        else { push @parts, $part; }
      }
      die "Empty repository URL\n" unless @parts;
      $url = $prefix . ($absolute ? "/" : "") . join("/", @parts);
    }
    $url =~ s{^git\@gitee\.com:}{https://gitee.com/};
    $url =~ s{^ssh://git\@gitee\.com(?::22)?/}{https://gitee.com/};
    print $url;
  ' "$parent_url" "$raw_url" "$parent_root")" || fail "不能解析子模块相对来源：${parent_root}"
  print -r -- "$resolved"
}
# 已暂存的 gitlink 是用户意图，不能用 ignore-submodules=all 将它隐藏。
assert_no_staged_gitlinks() {
  local staged_raw=""
  staged_raw="$(repo_git diff --cached --raw --no-abbrev --ignore-submodules=none HEAD)" || fail "无法检查暂存指针：${REPOSITORY}"
  [[ -z "$(print -r -- "$staged_raw" | /usr/bin/awk '$1 == ":160000" || $2 == "160000"')" ]] || fail "存在已暂存的子模块指针或类型变化：${REPOSITORY}；请单独处理。"
}
# 对已有工作树保留原先的嵌套仓库保护，但允许纯子模块检出漂移。
assert_worktree_paths_safe() {
  assert_no_staged_gitlinks
  repo_git ls-tree -rz HEAD > "${LOCK_DIRECTORY}/head-tree" || fail "无法枚举当前树：${REPOSITORY}"
  repo_git ls-tree -rz "$TARGET_HEAD" > "${LOCK_DIRECTORY}/target-tree" || fail "无法枚举目标树：${REPOSITORY}"
  assert_tracked_paths_have_no_nested_git "${LOCK_DIRECTORY}/head-tree"
  assert_tracked_paths_have_no_nested_git "${LOCK_DIRECTORY}/target-tree"
  local candidate=""
  repo_git ls-files --others --exclude-standard --directory -z > "${LOCK_DIRECTORY}/untracked" || fail '无法枚举未跟踪目录。'
  # 只检查将被清理的未跟踪目录；其中的 Git 元数据不能因依赖目录名而漏检。
  while IFS= read -r -d '' candidate; do
    candidate="${candidate%/}"
    [[ -d "${REPOSITORY}/${candidate}" && ! -L "${REPOSITORY}/${candidate}" ]] || continue
    assert_directory_has_no_nested_git "${REPOSITORY}/${candidate}"
  done < "${LOCK_DIRECTORY}/untracked"
}
# 空目录可以初始化；非空普通目录或失效 Git 指针不作为下载目标覆盖。
assert_new_submodule_path_empty() {
  local child_root="$1" contents=""
  [[ ! -e "$child_root" ]] && return 0
  [[ -d "$child_root" && ! -L "$child_root" ]] || fail "新子模块目标不是空目录：${child_root}"
  contents="$(/usr/bin/find "$child_root" -mindepth 1 -maxdepth 1 -print)" || fail "无法检查新子模块目录：${child_root}"
  [[ -z "$contents" ]] || fail "子模块未初始化但目标目录非空，保留原内容并停止：${child_root}"
}
# 游离 HEAD 只在仍受已知引用或旧 / 新父仓指针保护时允许离开。
assert_child_head_is_preserved() {
  local child_root="$1" old_pin="$2" target_pin="$3" current_head="" containing_refs=""
  current_head="$(tree_git "$child_root" rev-parse --verify HEAD)" || fail "子仓没有有效 HEAD：${child_root}"
  containing_refs="$(tree_git "$child_root" for-each-ref --contains "$current_head" --format='%(refname)')" || fail "无法核对子仓提交引用：${child_root}"
  [[ -n "$containing_refs" || "$current_head" == "$old_pin" || "$current_head" == "$target_pin" ]] && return 0
  if [[ -n "$old_pin" ]] && tree_git "$child_root" merge-base --is-ancestor "$current_head" "$old_pin" 2>/dev/null; then
    return 0
  fi
  tree_git "$child_root" merge-base --is-ancestor "$current_head" "$target_pin" 2>/dev/null && return 0
  fail "子仓存在未受引用或父仓指针保护的游离提交：${child_root}（${current_head}）；请先保存该提交。"
}
# 子仓不继承父仓 YES；普通源码、暂存指针和未完成操作均须单独处理。
assert_child_worktree_ready() {
  local REPOSITORY="$1" TARGET_HEAD="$2" child_state="" actual_root=""
  actual_root="$(repo_git rev-parse --show-toplevel)" || fail "子模块工作树无效：${REPOSITORY}"
  [[ "${actual_root:A}" == "$REPOSITORY" ]] || fail "子模块路径指向其它工作树：${REPOSITORY}"
  log_message info "检查子仓：${REPOSITORY}"
  assert_repository_ready
  assert_no_staged_gitlinks
  child_state="$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" || fail "无法检查子仓源码：${REPOSITORY}"
  [[ -z "$child_state" ]] || fail "子仓存在暂存 / 未暂存 / 未跟踪源码：${REPOSITORY}"$'\n'"${child_state}"
  assert_worktree_paths_safe
  assert_ignored_paths_safe
}
# 在分支查询和获取前显示本层真实来源；默认分支未查询时明确标注。
show_child_source() {
  local child_root="$1" source_url="$2" branch="$3" object_repo="$4" effective_url=""
  effective_url="$(tree_git "$object_repo" ls-remote --get-url -- "$source_url")" || fail "无法解析子仓来源：${child_root}"
  log_message info '━━━━━━━━━━ 来源｜子模块分支最新 ━━━━━━━━━━'
  log_message info "对象：${child_root}"
  log_message info "目标分支：${branch:-远端默认分支（待查询）}"
  log_message info "解析来源：${source_url}"
  log_message info "拉取地址（本地 Git 配置展开）：${effective_url}"
}
# 预取目标分支最新提交并固定本次 SHA；只在临时裸仓准备首次克隆，不强制改写本地分支。
prepare_child_commit() {
  local child_root="$1" source_url="$2" requested_branch="$3" parent_branch="$4" plan_number="$5"
  local object_repo="$child_root" branch="$requested_branch" remote_name=origin remote_listing="" current_branch="" local_head="" advertised=""
  if [[ ! -e "${child_root}/.git" ]]; then
    object_repo="${PREPARE_DIRECTORY}/objects-${plan_number}.git"
    run_tree_git "$PREPARE_DIRECTORY" init --bare --quiet "$object_repo" || fail "无法建立子模块临时对象库：${child_root}"
  else
    remote_listing="$(tree_git "$child_root" remote)" || fail "无法读取子仓远端：${child_root}"
    current_branch="$(tree_git "$child_root" symbolic-ref --quiet --short HEAD 2>/dev/null)" || current_branch=""
  fi
  if [[ "$branch" == . ]]; then
    branch="$parent_branch"
  fi
  show_child_source "$child_root" "$source_url" "$branch" "$object_repo"
  if [[ -z "$branch" ]]; then
    advertised="$(tree_git "$object_repo" ls-remote --symref -- "$source_url" HEAD)" || fail "无法查询子仓默认分支：${child_root}"
    branch="$(print -r -- "$advertised" | /usr/bin/awk '$1 == "ref:" && $2 ~ /^refs\/heads\// { sub(/^refs\/heads\//, "", $2); print $2; exit }')"
    [[ -n "$branch" ]] || fail "远端 HEAD 未指向明确分支：${child_root}；请在 .gitmodules 指定 branch。"
  fi
  tree_git "$object_repo" check-ref-format "refs/heads/${branch}" || fail "子仓目标分支无效：${child_root}（${branch}）"
  [[ "$branch" != -* && "$branch" != HEAD ]] || fail "子仓目标必须是普通分支：${child_root}（${branch}）"
  if [[ "$object_repo" == "$child_root" ]]; then
    remote_name="$(tree_git "$child_root" config --get "branch.${branch}.remote" 2>/dev/null)" || remote_name=""
    if [[ -z "$remote_name" || "$remote_name" == . ]]; then
      remote_name="$(tree_git "$child_root" config --get "branch.${current_branch}.remote" 2>/dev/null)" || remote_name=""
    fi
    if [[ -z "$remote_name" || "$remote_name" == . ]]; then
      if tree_git "$child_root" config --get "remote.origin.url" >/dev/null; then
        remote_name=origin
      else
        [[ -n "$remote_listing" && "$remote_listing" != *$'\n'* ]] || fail "子仓没有明确的下载远端：${child_root}"
        remote_name="$remote_listing"
      fi
    fi
    [[ -n "$remote_name" && "$remote_name" != -* && "$remote_name" != *$'\n'* ]] || fail "子仓远端名称无效：${child_root}"
    tree_git "$child_root" config --get "remote.${remote_name}.url" >/dev/null || fail "子仓目标分支远端不存在：${child_root}（${remote_name}）"
  fi
  log_message info "拉取分支：${child_root} → ${remote_name}/${branch}"
  local -a fetch_options
  fetch_options=(--no-tags --no-recurse-submodules)
  [[ "$object_repo" != "$child_root" ]] && fetch_options+=(--depth=1)
  run_tree_git "$object_repo" fetch "${fetch_options[@]}" -- "$source_url" "+refs/heads/${branch}:refs/remotes/${remote_name}/${branch}" || fail "子仓分支获取失败：${child_root}（${branch}；来源：${source_url}）"
  PLAN_TARGETS[$plan_number]="$(tree_git "$object_repo" rev-parse --verify "refs/remotes/${remote_name}/${branch}^{commit}")" || fail "无法确定子仓最新提交：${child_root}"
  if [[ "$object_repo" == "$child_root" ]]; then
    local_head="$(tree_git "$child_root" rev-parse --verify "refs/heads/${branch}^{commit}" 2>/dev/null)" || local_head=""
    if [[ -n "$local_head" ]]; then
      tree_git "$child_root" merge-base --is-ancestor "$local_head" "${PLAN_TARGETS[$plan_number]}" || fail "子仓目标本地分支存在独有提交或无法快进：${child_root}（${branch}）；保留现场，请先整合。"
    fi
  else
    run_tree_git "$object_repo" update-ref "refs/heads/${branch}" "${PLAN_TARGETS[$plan_number]}" || fail "无法准备子仓分支：${child_root}"
  fi
  PLAN_OBJECT_REPOS[$plan_number]="$object_repo"
  PLAN_BRANCHES[$plan_number]="$branch"
  PLAN_REMOTES[$plan_number]="$remote_name"
  PLAN_LOCAL_HEADS[$plan_number]="$local_head"
}
# 删除、改名和子模块 / 普通路径互换会产生有损现场，本动作只接受保留路径和正常新增。
assert_gitlink_paths_preserved() {
  local object_repo="$1" original_revision="$2" target_revision="$3" working_root="$4" listing="${PREPARE_DIRECTORY}/paths-${#PLAN_PATHS}.tree" entry="" item="" target_entry=""
  [[ -n "$original_revision" ]] || return 0
  tree_git "$object_repo" ls-tree -rz "$original_revision" > "$listing" || fail "无法枚举子仓旧指针：${working_root}"
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] || continue
    item="${entry#*$'\t'}"
    target_entry="$(tree_git "$object_repo" --literal-pathspecs ls-tree "$target_revision" -- "$item")" || fail "无法核对目标子模块路径：${working_root}/${item}"
    [[ "$target_entry" == 160000\ * ]] || fail "远程删除、改名或转换了子模块路径，保留现场并停止：${working_root}/${item}"
  done < "$listing"
}
# 先读取各层目标提交的 .gitmodules；整个计划记录分支最新的固定 SHA，不执行工作树检出。
prepare_descendant_plan() {
  local parent_root="$1" object_repo="$2" target_revision="$3" parent_url="$4" depth="$5" old_revision="$6" parent_branch="$7"
  (( depth <= 64 )) || fail "子模块递归超过 64 层，可能存在循环：${parent_root}"
  assert_gitlink_paths_preserved "$object_repo" "$old_revision" "$target_revision" "$parent_root"
  local manifest="${PREPARE_DIRECTORY}/manifest-${#PLAN_PATHS}.gitmodules" tree_listing="${PREPARE_DIRECTORY}/target-${#PLAN_PATHS}.tree" keys_listing="${PREPARE_DIRECTORY}/keys-${#PLAN_PATHS}"
  local entry="" child_path="" child_pin="" old_pin="" old_entry="" metadata="" section="" config_entry="" config_key="" configured_path="" raw_url="" child_url="" child_root="" child_head="" child_branch="" cache_path="" requested_branch="" plan_number=0
  local -A path_sections=()
  tree_git "$object_repo" ls-tree -rz "$target_revision" > "$tree_listing" || fail "无法读取目标目录树：${parent_root}"
  if tree_git "$object_repo" cat-file -e "${target_revision}:.gitmodules" 2>/dev/null; then
    tree_git "$object_repo" show "${target_revision}:.gitmodules" > "$manifest" || fail "无法读取目标 .gitmodules：${parent_root}"
    tree_git "$object_repo" config --file "$manifest" --list >/dev/null || fail "目标 .gitmodules 解析失败：${parent_root}"
    local config_result=0
    tree_git "$object_repo" config --file "$manifest" --null --get-regexp '^submodule\..*\.path$' > "$keys_listing" || config_result=$?
    (( config_result == 0 || config_result == 1 )) || fail "无法读取目标子模块登记：${parent_root}"
    while IFS= read -r -d '' config_entry; do
      config_key="${config_entry%%$'\n'*}"
      configured_path="${config_entry#*$'\n'}"
      section="${config_key#submodule.}"
      section="${section%.path}"
      validate_submodule_path "$parent_root" "$configured_path"
      validate_submodule_path "$parent_root" "$section"
      [[ -z "${path_sections[$configured_path]:-}" ]] || fail "重复的子模块 path：${parent_root}/${configured_path}"
      path_sections[$configured_path]="$section"
    done < "$keys_listing"
  fi
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] || continue
    child_path="${entry#*$'\t'}"
    metadata="${entry%%$'\t'*}"
    child_pin="${metadata##* }"
    validate_submodule_path "$parent_root" "$child_path"
    section="${path_sections[$child_path]:-}"
    [[ -n "$section" ]] || fail "gitlink 缺少明确的 .gitmodules 登记：${parent_root}/${child_path}"
    raw_url="$(tree_git "$object_repo" config --file "$manifest" --get-all "submodule.${section}.url")" || fail "子模块没有来源：${parent_root}/${child_path}"
    child_url="$(resolve_child_source_url "$parent_url" "$raw_url" "$parent_root")" || fail "子模块来源解析失败：${parent_root}/${child_path}"
    child_root="${parent_root}/${child_path}"
    old_pin=""
    if [[ -n "$old_revision" ]]; then
      old_entry="$(tree_git "$object_repo" --literal-pathspecs ls-tree "$old_revision" -- "$child_path")" || fail "无法检查原子模块路径：${child_root}"
      [[ -z "$old_entry" || "$old_entry" == 160000\ * ]] || fail "远程将普通路径转换为子模块，保留现场并停止：${child_root}"
      if [[ -n "$old_entry" ]]; then
        metadata="${old_entry%%$'\t'*}"
        old_pin="${metadata##* }"
      fi
    fi
    child_head=""
    child_branch=""
    if [[ -e "${child_root}/.git" ]]; then
      [[ -n "$old_pin" ]] || fail "新增 gitlink 路径已有独立 Git，不能接管：${child_root}"
      child_head="$(tree_git "$child_root" rev-parse --verify HEAD)" || fail "子模块 Git 指针损坏：${child_root}"
      child_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || child_branch=""
      restore_configured_markdown_toc "$child_root" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE" || fail "子仓 Markdown 目录还原失败：${child_root}"
      assert_child_worktree_ready "$child_root" "$child_head"
    else
      assert_new_submodule_path_empty "$child_root"
      cache_path="$(tree_git "$object_repo" rev-parse --git-path "modules/${section}")" || fail "无法检查子模块缓存：${child_root}"
      [[ "$cache_path" == /* ]] || cache_path="${object_repo}/${cache_path}"
      [[ ! -e "$cache_path" ]] || fail "子模块工作树缺失但仍有缓存，先恢复工作树以保护索引和独有提交：${child_root}"
    fi
    PLAN_PATHS+=("$child_root")
    PLAN_PARENTS+=("$parent_root")
    PLAN_SECTIONS+=("$section")
    PLAN_TARGETS+=("$child_pin")
    PLAN_URLS+=("$child_url")
    PLAN_ORIGINAL_HEADS+=("$child_head")
    PLAN_ORIGINAL_BRANCHES+=("$child_branch")
    PLAN_OBJECT_REPOS+=("")
    PLAN_OLD_PINS+=("$old_pin")
    PLAN_BRANCHES+=("")
    PLAN_REMOTES+=("")
    PLAN_LOCAL_HEADS+=("")
    plan_number=${#PLAN_PATHS}
    requested_branch="$(tree_git "$object_repo" config --file "$manifest" --get-all "submodule.${section}.branch" 2>/dev/null)" || requested_branch=""
    [[ "$requested_branch" != *$'\n'* ]] || fail "子模块分支配置不唯一：${child_root}"
    prepare_child_commit "$child_root" "$child_url" "$requested_branch" "$parent_branch" "$plan_number"
    child_pin="${PLAN_TARGETS[$plan_number]}"
    if [[ -n "$child_head" ]]; then
      assert_child_head_is_preserved "$child_root" "$old_pin" "$child_pin"
      assert_child_worktree_ready "$child_root" "$child_pin"
    fi
    prepare_descendant_plan "$child_root" "${PLAN_OBJECT_REPOS[$plan_number]}" "$child_pin" "$child_url" "$((depth + 1))" "$child_head" "${PLAN_BRANCHES[$plan_number]}"
  done < "$tree_listing"
}
# 顶层保护先完成，再预检整棵将要检出的提交树。
assert_nested_repositories_safe() {
  assert_worktree_paths_safe
  PREPARE_DIRECTORY="$(/usr/bin/mktemp -d "${LOCK_DIRECTORY}/prepare.XXXXXX")" || fail '无法创建私有子模块准备目录。'
  prepare_descendant_plan "$REPOSITORY" "$REPOSITORY" "$TARGET_HEAD" "$SOURCE_URL" 0 "$ORIGINAL_HEAD" "$BRANCH"
  log_message info "已预检 ${#PLAN_PATHS} 个子模块的分支和最新提交；尚未修改工作树。"
}
# 确认期间的子仓 HEAD、分支、源码或路径变化使整次计划失效。
assert_submodule_plan_unchanged() {
  local index=0 child_root="" current_branch=""
  for (( index=1; index<=${#PLAN_PATHS}; index++ )); do
    child_root="${PLAN_PATHS[$index]}"
    if [[ -n "${PLAN_ORIGINAL_HEADS[$index]}" ]]; then
      [[ -e "${child_root}/.git" && "$(tree_git "$child_root" rev-parse HEAD)" == "${PLAN_ORIGINAL_HEADS[$index]}" ]] || fail "确认期间子仓 HEAD 或路径变化：${child_root}"
      current_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || current_branch=""
      [[ "$current_branch" == "${PLAN_ORIGINAL_BRANCHES[$index]}" ]] || fail "确认期间子仓分支变化：${child_root}"
      assert_child_worktree_ready "$child_root" "${PLAN_TARGETS[$index]}"
      assert_child_head_is_preserved "$child_root" "${PLAN_OLD_PINS[$index]}" "${PLAN_TARGETS[$index]}"
      assert_child_branch_unchanged "$index"
    else
      assert_new_submodule_path_empty "$child_root"
    fi
  done
}
# 目标本地分支即使尚未检出，也必须与预检时相同，防止覆盖并发提交。
assert_child_branch_unchanged() {
  local index="$1" local_head=""
  local_head="$(tree_git "${PLAN_PATHS[$index]}" rev-parse --verify "refs/heads/${PLAN_BRANCHES[$index]}^{commit}" 2>/dev/null)" || local_head=""
  [[ "$local_head" == "${PLAN_LOCAL_HEADS[$index]}" ]] || fail "预检后目标分支已变化：${PLAN_PATHS[$index]}（${PLAN_BRANCHES[$index]}）"
}
# 按预检的分支和最新提交逐层检出；现有分支仅快进，首次克隆也保持分支态。
synchronize_submodule_plan() {
  local index=0 child_root="" parent_root="" child_path="" target_pin="" branch="" remote_name="" current_branch=""
  for (( index=1; index<=${#PLAN_PATHS}; index++ )); do
    child_root="${PLAN_PATHS[$index]}"
    parent_root="${PLAN_PARENTS[$index]}"
    child_path="${child_root#"${parent_root}/"}"
    target_pin="${PLAN_TARGETS[$index]}"
    branch="${PLAN_BRANCHES[$index]}"
    remote_name="${PLAN_REMOTES[$index]}"
    if [[ -n "${PLAN_ORIGINAL_HEADS[$index]}" ]]; then
      [[ "$(tree_git "$child_root" rev-parse HEAD)" == "${PLAN_ORIGINAL_HEADS[$index]}" ]] || fail "检出前子仓 HEAD 已变化：${child_root}"
      current_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || current_branch=""
      [[ "$current_branch" == "${PLAN_ORIGINAL_BRANCHES[$index]}" ]] || fail "检出前子仓分支已变化：${child_root}"
      assert_child_worktree_ready "$child_root" "$target_pin"
      assert_child_branch_unchanged "$index"
      if [[ -n "${PLAN_LOCAL_HEADS[$index]}" ]]; then
        run_tree_git "$child_root" checkout --no-recurse-submodules --no-overwrite-ignore "$branch" || fail "无法切回子仓分支：${child_root}"
        run_tree_git "$child_root" -c "branch.${branch}.mergeOptions=" merge --ff-only --no-autostash --no-overwrite-ignore --no-edit "$target_pin" || fail "子仓分支无法快进：${child_root}"
      else
        run_tree_git "$child_root" checkout --no-recurse-submodules --no-overwrite-ignore -b "$branch" "$target_pin" || fail "无法建立子仓跟踪分支：${child_root}"
      fi
    else
      assert_new_submodule_path_empty "$child_root"
      log_message info "首次克隆已预检分支：${child_root} → ${branch}；来源：${PLAN_URLS[$index]}"
      # 先复制已预检对象但不写工作树，登记真实远端后才让条件过滤器参与首次检出。
      run_tree_git "$parent_root" clone --no-checkout --no-local --single-branch --branch "$branch" --origin "$remote_name" --no-recurse-submodules -- "${PLAN_OBJECT_REPOS[$index]}" "$child_root" || fail "子模块分支克隆失败：${child_root}"
    fi
    run_tree_git "$child_root" remote set-url "$remote_name" "${PLAN_URLS[$index]}" || fail "无法记录子仓下载来源：${child_root}"
    if [[ -z "${PLAN_ORIGINAL_HEADS[$index]}" ]]; then
      run_tree_git "$child_root" checkout --no-recurse-submodules --no-overwrite-ignore "$branch" || fail "子仓首次检出失败：${child_root}"
    fi
    # 保留已有宽映射和其它分支；仅在目标缺少有效上游映射时补一条精确 refspec。
    if [[ "$(tree_git "$child_root" -c "branch.${branch}.remote=${remote_name}" -c "branch.${branch}.merge=refs/heads/${branch}" rev-parse --symbolic-full-name "${branch}@{upstream}" 2>/dev/null)" != "refs/remotes/${remote_name}/${branch}" ]]; then
      run_tree_git "$child_root" config --local --add "remote.${remote_name}.fetch" "+refs/heads/${branch}:refs/remotes/${remote_name}/${branch}" || fail "无法配置子仓分支映射：${child_root}"
    fi
    run_tree_git "$child_root" branch --set-upstream-to="${remote_name}/${branch}" "$branch" || fail "无法设置子仓上游：${child_root}"
    # 与原生 --init 一样登记本层子模块，避免已克隆工作树仍被 Git 标为未初始化。
    run_tree_git "$parent_root" config --local "submodule.${PLAN_SECTIONS[$index]}.url" "${PLAN_URLS[$index]}" || fail "无法登记子模块来源：${child_root}"
    run_tree_git "$parent_root" config --local "submodule.${PLAN_SECTIONS[$index]}.active" true || fail "无法激活子模块登记：${child_root}"
    run_tree_git "$parent_root" --literal-pathspecs submodule absorbgitdirs -- "$child_path" || fail "无法归集子模块元数据：${child_root}"
    [[ "$(tree_git "$child_root" symbolic-ref --quiet --short HEAD)" == "$branch" && "$(tree_git "$child_root" rev-parse HEAD)" == "$target_pin" ]] || fail "子模块分支或最新提交核验失败：${child_root}"
    restore_configured_markdown_toc "$child_root" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE" || fail "子仓 Markdown 目录还原失败：${child_root}"
    log_message success "✔ 子模块已同步分支最新：${child_root} → ${remote_name}/${branch}（${target_pin}）；来源：${PLAN_URLS[$index]}"
  done
}
# hard reset 也可能移除挡路的忽略文件，先检查两棵树中的路径碰撞。
assert_ignored_paths_safe() {
  local collision=""
  repo_git ls-files --others --ignored --exclude-standard --directory -z > "${LOCK_DIRECTORY}/ignored" || fail '无法检查忽略文件。'
  [[ -s "${LOCK_DIRECTORY}/ignored" ]] || return 0
  repo_git ls-tree -rz --name-only HEAD > "${LOCK_DIRECTORY}/protected-tree" || fail '无法检查当前文件树。'
  repo_git ls-tree -rz --name-only "$TARGET_HEAD" >> "${LOCK_DIRECTORY}/protected-tree" || fail '无法检查目标文件树。'
  collision="$(/usr/bin/perl -e '
    use strict; use warnings; use feature "fc";
    use Encode qw(decode FB_CROAK);
    use Unicode::Normalize qw(NFD);
    sub normalized { my ($value) = @_; return NFD(fc(decode("UTF-8", $value, FB_CROAK))); }
    my ($tree_file, $ignored_file) = @ARGV;
    my (%ignored, %parents);
    open my $ignored_fh, "<", $ignored_file or die "Cannot read ignored paths: $!";
    local $/ = "\0";
    while (my $item = <$ignored_fh>) {
      chomp $item; $item =~ s{/$}{};
      my $key = normalized($item);
      $ignored{$key} = $item;
      my $parent = $key;
      while ($parent =~ s{/[^/]+$}{}) { $parents{$parent} = $item; }
    }
    open my $tree_fh, "<", $tree_file or die "Cannot read tree paths: $!";
    while (my $path = <$tree_fh>) {
      chomp $path; $path = normalized($path);
      if (exists $ignored{$path}) { print $ignored{$path}; exit 0; }
      if (exists $parents{$path}) { print $parents{$path}; exit 0; }
      while ($path =~ s{/[^/]+$}{}) {
        if (exists $ignored{$path}) { print $ignored{$path}; exit 0; }
      }
    }
  ' "${LOCK_DIRECTORY}/protected-tree" "${LOCK_DIRECTORY}/ignored")" || fail '忽略文件保护检查失败。'
  [[ -z "$collision" ]] || fail "忽略内容可能被目标覆盖：${REPOSITORY}/${collision}；请先手动移走。"
}
# 对暂存、未暂存和未跟踪内容建立只读摘要，确认后仍需完全相同。
capture_worktree_fingerprint() {
  local item="" snapshot="${LOCK_DIRECTORY}/snapshot"
  repo_git diff --no-ext-diff --no-textconv --binary --ignore-submodules=all > "$snapshot" || fail '无法读取未暂存内容摘要。'
  repo_git diff --cached --no-ext-diff --no-textconv --binary --ignore-submodules=all >> "$snapshot" || fail '无法读取暂存内容摘要。'
  repo_git ls-files --others --exclude-standard -z > "${LOCK_DIRECTORY}/snapshot-paths" || fail '无法读取未跟踪内容摘要。'
  while IFS= read -r -d '' item; do
    print -rn -- "$item" >> "$snapshot" || fail '无法保存内容摘要。'
    printf '\0' >> "$snapshot" || fail '无法保存内容摘要。'
    if [[ -L "${REPOSITORY}/${item}" ]]; then
      /usr/bin/readlink "${REPOSITORY}/${item}" >> "$snapshot" || fail '无法读取符号链接摘要。'
    elif [[ -f "${REPOSITORY}/${item}" ]]; then
      repo_git hash-object --no-filters -- "$item" >> "$snapshot" || fail '无法读取未跟踪文件摘要。'
    else
      fail "不支持的未跟踪文件类型或文件已变化：${REPOSITORY}/${item}"
    fi
  done < "${LOCK_DIRECTORY}/snapshot-paths"
  /usr/bin/shasum -a 256 "$snapshot" | /usr/bin/awk '{ print $1 }'
}
# 列出全部会被舍弃的路径和本地独有提交，再等待精确 YES。
review_local_risk() {
  WORKTREE_STATE="$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" || fail '无法检查工作区。'
  LOCAL_ONLY_COUNT="$(repo_git rev-list --count "${TARGET_HEAD}..HEAD")" || fail '无法检查本地独有提交。'
  if (( ENTRY_DETACHED )); then
    [[ -z "$WORKTREE_STATE" ]] || fail '游离入口存在暂存 / 未暂存 / 未跟踪源码；请先处理后再恢复分支。'
    assert_detached_entry_history_safe
    LOCAL_ONLY_COUNT=0
  fi
  WORKTREE_FINGERPRINT="$(capture_worktree_fingerprint)" || fail '无法建立工作区内容摘要。'
  if [[ -n "$WORKTREE_STATE" || "$LOCAL_ONLY_COUNT" != 0 ]]; then
    log_message danger '⚠ 高危：继续将永久舍弃以下本地内容；不生成 stash 或备份。'
    log_message danger "仓库：${REPOSITORY}"
    log_message danger "当前分支：${BRANCH}；当前提交：${ORIGINAL_HEAD}"
    log_message danger "恢复目标：${REMOTE}/${MERGE_REF#refs/heads/}；提交：${TARGET_HEAD}"
    [[ -z "$WORKTREE_STATE" ]] || log_message danger "待舍弃的暂存 / 未暂存 / 未跟踪路径："$'\n'"${WORKTREE_STATE}"
    if [[ "$LOCAL_ONLY_COUNT" != 0 ]]; then
      log_message danger "待舍弃的本地独有提交：${LOCAL_ONLY_COUNT} 个"
      log_message danger "$(repo_git log --format='%h %s' "${TARGET_HEAD}..HEAD")"
    fi
    log_message danger '删除预览（不包含忽略文件，不使用双重 -f）：'
    run_git clean -nd || fail '无法预览未跟踪文件清理。'
    log_message danger '只有精确输入大写 YES 才舍弃并同步；回车、其它输入或 Ctrl+C 均取消。'
    local answer=""
    [[ -t 0 && -t 1 ]] || fail '危险操作必须在可交互终端确认。'
    print -n -r -- "${COLOR_RED}请输入 YES：${COLOR_RESET}"
    IFS= read -r answer || { log_message info '已取消，未舍弃本地内容。'; exit 2; }
    [[ "$answer" == YES ]] || { log_message info '已取消，未舍弃本地内容。'; exit 2; }
    log_message danger '已确认 YES：仅授权本次显示的仓库和固定目标。'
  fi
}
# 用户确认后重新核对 HEAD、分支、配置及路径，避免沿用失效计划。
assert_plan_unchanged() {
  assert_repository_ready
  if (( ENTRY_DETACHED )); then
    assert_detached_entry_unchanged
  else
    [[ "$(repo_git symbolic-ref --quiet --short HEAD)" == "$BRANCH" && "$(repo_git rev-parse HEAD)" == "$ORIGINAL_HEAD" ]] || fail '确认期间分支或 HEAD 已变化，请重新运行。'
    [[ "$(repo_git config --get-all "branch.${BRANCH}.remote")" == "$REMOTE" && "$(repo_git config --get-all "branch.${BRANCH}.merge")" == "$MERGE_REF" ]] || fail '确认期间上游配置已变化，请重新运行。'
  fi
  [[ "$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" == "$WORKTREE_STATE" ]] || fail '确认期间工作区状态已变化，请重新运行。'
  [[ "$(capture_worktree_fingerprint)" == "$WORKTREE_FINGERPRINT" ]] || fail '确认期间文件内容已变化，请重新运行并重新确认。'
  [[ "$(repo_git config --get-all "remote.${REMOTE}.url")" == "$SOURCE_URL" ]] || fail '确认期间远程来源已变化，请重新运行。'
  assert_worktree_paths_safe
  assert_submodule_plan_unchanged
  assert_ignored_paths_safe
}
# 干净分支仅快进；有明确 YES 授权时才 reset 和清理非忽略内容。
synchronize_repository() {
  SYNC_STARTED=1
  if (( ENTRY_DETACHED )); then
    synchronize_detached_entry
  elif [[ -n "$WORKTREE_STATE" || "$LOCAL_ONLY_COUNT" != 0 ]]; then
    run_git reset --hard --no-recurse-submodules "$TARGET_HEAD" || fail '重置失败，已停止；请检查工作区与日志。'
    run_git clean -fd || fail '清理失败，已停止；请检查工作区与日志。'
  elif [[ "$ORIGINAL_HEAD" != "$TARGET_HEAD" ]]; then
    run_git -c "branch.${BRANCH}.mergeOptions=" merge --ff-only --no-autostash --no-overwrite-ignore --no-edit "$TARGET_HEAD" || fail '无法安全快进，已停止。'
  fi
  [[ "$(repo_git rev-parse HEAD)" == "$TARGET_HEAD" ]] || fail '同步后提交号核验失败。'
  restore_entry_markdown_toc
  synchronize_submodule_plan
  [[ -z "$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" ]] || fail '同步后仍有本地变化，未标记成功。'
  log_message success "✔ 已同步：${BRANCH} → ${TARGET_HEAD}"
  log_message success "来源：${EFFECTIVE_URL}；${#PLAN_PATHS} 个子模块已按目标分支最新提交核验；gitlink 漂移保留在工作区；未执行提交或推送。"
  log_message info "日志：${LOG_FILE}"
}
# 逐步完成根仓及分支最新子模块的安全拉取，任何失败立即停止后续步骤。
main() {
  show_script_intro_and_wait "$@" # 先显示自述，由 SourceTree 转交终端并确认。
  initialize_runtime # 确认后建立私有日志与退出清理。
  resolve_repository "$@" # 校验目标并防止同一动作并行运行。
  assert_repository_ready # 未完成 Git 操作和隐藏状态先停止。
  restore_entry_markdown_toc # 已配置才还原当前文档，无配置不安装。
  resolve_upstream # 仅使用当前分支明确配置的远程上游。
  fetch_target # 成功获取并固定提交后才考虑舍弃。
  assert_nested_repositories_safe # 预检各层最新分支，保护子仓和嵌套仓库。
  assert_ignored_paths_safe # 防止 hard reset 间接覆盖忽略内容。
  review_local_risk # 红字列明风险，危险操作强制精确 YES。
  assert_plan_unchanged # 写操作前重新核对确认计划。
  synchronize_repository # 安全快进或按 YES 授权舍弃并核验结果。
}

main "$@"
JOBS_READONLY_PULL_ENGINE
)" || return 1
  /bin/zsh -c "$engine_code" "$SCRIPT_FILE" --terminal-run "$REPO_ROOT"
}
# 模式分流在 Homebrew、清单登记和父仓拉取之前完成。
run_selected_download_mode() {
  case "$DOWNLOAD_OPERATION_MODE" in
    readonly)
      if [[ "${DRY_RUN:-0}" != 0 ]]; then
        print -u2 -r -- '只拉取模式暂不提供 DRY_RUN 演练，未执行同步；请取消 DRY_RUN 后选择只拉取，或选择维护模式演练原流程。'
        return 2
      fi
      run_embedded_readonly_pull
      ;;
    maintenance) run_management_download "$@" ;;
    *) return 1 ;;
  esac
}
# 先选择只拉取或维护，再执行各自独立的确认与业务流程。
run_download_selection_loop() {
  setopt LOCAL_OPTIONS
  unsetopt ERR_EXIT
  local pull_result=0
  while true; do
    select_download_operation_mode || return $?
    pull_result=0
    # 独立执行以保留业务失败即停，返回 20 仅表示回到用途选择。
    ( set -e; run_selected_download_mode "$@" )
    pull_result=$?
    if (( pull_result == 20 )); then
      continue
    fi
    (( pull_result == 0 )) || return "$pull_result"
    if (( $+functions[offer_global_markdown_toc_setup] )); then
      offer_global_markdown_toc_setup
    fi
    return 0
  done
}
# 编排用途选择与可返回的下载流程。
main() {
  run_download_selection_loop "$@" # 逐层选择并执行业务，返回时重新进入用途页。
}

main "$@"
