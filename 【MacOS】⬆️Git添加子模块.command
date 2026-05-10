#!/usr/bin/env zsh
set -euo pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

# ============================== 全局配置 ==============================
SUBMODULE_BRANCH="${SUBMODULE_BRANCH:-main}"   # 统一子模块分支（main | master 等）
REMOTE_NAME="${REMOTE_NAME:-origin}"           # 父仓远端名
DRY_RUN="${DRY_RUN:-0}"                        # 1=干跑，只打印动作不执行
ONLY_PATHS="${ONLY_PATHS:-}"                   # 仅更新这些子模块路径（空格分隔）；空=全部
FORCE_DELETE="${FORCE_DELETE:-0}"              # 1=直接删除冲突目录；0=移动到备份目录

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

# ============================== 固定 URL（父/子分离） ==============================
# 父仓写死；不可达才询问
PARENT_DEFAULT_URL="${PARENT_DEFAULT_URL:-https://github.com/JobsKits/VScodeConfigs}"
# 子模块仓库
SUBMODULE_URL="${SUBMODULE_URL:-https://github.com/JobsKits/VScodeConfigByFlutter.git}"
# 子模块本地路径
SUBMODULE_PATH="VScodeConfig@Flutter"

# 需要优先清理的冲突目录（避免历史脏状态）
CONFLICT_PATHS=(
  "$SUBMODULE_PATH"
)

# ============================== 输出 & 工具 ==============================
log()          { echo -e "$1" | tee -a "$LOG_FILE"; }
info_echo()    { log "ℹ️  $*"; }
success_echo() { log "✅ $*"; }
warn_echo()    { log "⚠️  $*"; }
error_echo()   { log "❌ $*" >&2; }
note_echo()    { log "📝 $*"; }

_do_or_echo() {
  if [[ "$DRY_RUN" == "1" ]]; then
    note_echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

get_ncpu() { command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu || echo 1; }

# 兼容 zsh 获取脚本目录
cd_to_script_dir() {
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  cd "$script_path"
}

show_intro_and_wait() {
  cat <<EOF
📘 Git 子模块批量管理脚本（统一分支：$SUBMODULE_BRANCH）
------------------------------------------------------------
父仓远端(固定)：$PARENT_DEFAULT_URL
子模块 URL：    $SUBMODULE_URL
子模块路径：    $SUBMODULE_PATH
干跑：          $DRY_RUN
仅更新路径：    ${ONLY_PATHS:-全部子模块}
删除策略：      $( [[ "$FORCE_DELETE" == "1" ]] && echo "直接删除" || echo "先备份再移除" )

流程：
  1) 切到脚本目录
  2) 初始化父仓（不做全量 add）
  3) 确认父仓远端（误配=子仓时自动纠正；不可达才询问）
  4) 清理冲突目录（索引/.git/modules/物理目录/.gitmodules 段）
  5) 添加/修复子模块（立即校验是 gitlink）
  6) submodule sync & update --init --recursive
  7) 对齐子模块到远端最新（reset --hard），固化 gitlink 提交

⚠️ 从此脚本中已移除任何“git add .”之类的危险操作。
------------------------------------------------------------
按 [回车] 继续，或 Ctrl+C 取消。
EOF
  read -r
}

# ============================== 父仓操作 ==============================
ensure_repo_initialized() {
  _do_or_echo "git init"
  # 只查看状态，绝不全量 add
  _do_or_echo "git status >/dev/null"
}

# 忽略 *.command.local（幂等）
ensure_gitignore_for_local() {
  if [[ ! -f .gitignore ]] || ! grep -qxE '\.command\.local$' .gitignore; then
    echo ".command.local" >> .gitignore
    _do_or_echo "git add .gitignore || true"
    _do_or_echo "git commit -m 'chore: ignore *.command.local' || true"
  fi
}

# 父仓远端：写死为 PARENT_DEFAULT_URL；如误配为子仓 URL 则更正
ensure_git_remote() {
  local remote_name="${1:-$REMOTE_NAME}"
  local desired="${REMOTE_URL:-$PARENT_DEFAULT_URL}"

  local current=""
  current="$(git remote get-url "$remote_name" 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    if [[ "$current" == "$SUBMODULE_URL" ]]; then
      warn_echo "父仓远端 [$remote_name] 误指向子仓：$current"
      _do_or_echo "git remote set-url \"$remote_name\" \"$desired\""
      success_echo "已更正远端：$remote_name -> $desired"
    else
      info_echo "已存在远端 [$remote_name] -> $current"
    fi
    return
  fi

  if git ls-remote "$desired" >/dev/null 2>&1; then
    _do_or_echo "git remote add \"$remote_name\" \"$desired\""
    success_echo "已添加远端：$remote_name -> $desired"
    return
  fi

  while true; do
    read "?请输入 Git 远端地址（用于 $remote_name）: " remote_url
    local trimmed="${remote_url//[[:space:]]/}"
    [[ -z "$trimmed" ]] && { warn_echo "输入为空"; continue; }
    remote_url="$trimmed"
    if git ls-remote "$remote_url" >/dev/null 2>&1; then
      _do_or_echo "git remote add \"$remote_name\" \"$remote_url\""
      success_echo "已添加远端：$remote_name -> $remote_url"
      break
    else
      error_echo "无法访问：$remote_url"
    fi
  done
}

# 分支对齐（含 master→main 兜底）
ensure_parent_branch() {
  local b="$SUBMODULE_BRANCH"
  local cur
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

  if [[ "$cur" == "master" && "$b" == "main" ]]; then
    _do_or_echo "git fetch \"$REMOTE_NAME\" main || true"
    if git ls-remote --exit-code --heads "$REMOTE_NAME" main >/dev/null 2>&1; then
      _do_or_echo "git switch -C main --track \"$REMOTE_NAME/main\" 2>/dev/null || git checkout -B main \"$REMOTE_NAME/main\" || git switch -C main -f \"$REMOTE_NAME/main\""
      success_echo "本地 master 已改名并对齐远端 main"
      return
    fi
  fi

  if ! git rev-parse --verify "$b" >/dev/null 2>&1; then
    if git ls-remote --exit-code --heads "$REMOTE_NAME" "$b" >/dev/null 2>&1; then
      _do_or_echo "git fetch \"$REMOTE_NAME\" \"$b\""
      _do_or_echo "git switch -C \"$b\" --track \"$REMOTE_NAME/$b\" 2>/dev/null || git checkout -B \"$b\" \"$REMOTE_NAME/$b\" || git switch -C \"$b\" -f \"$REMOTE_NAME/$b\""
    else
      _do_or_echo "git switch -C \"$b\" 2>/dev/null || git checkout -B \"$b\""
      note_echo "远端无 $b 分支，已创建本地分支。"
    fi
  else
    _do_or_echo "git switch \"$b\" 2>/dev/null || git checkout \"$b\""
  fi

  if git ls-remote --exit-code --heads "$REMOTE_NAME" "$b" >/dev/null 2>&1; then
    _do_or_echo "git branch --set-upstream-to=\"$REMOTE_NAME/$b\" \"$b\" || true"
  fi
}

parent_pull_rebase() {
  local b; b="$(git rev-parse --abbrev-ref HEAD)"
  _do_or_echo "git fetch \"$REMOTE_NAME\" || true"
  if git ls-remote --exit-code --heads "$REMOTE_NAME" "$b" >/dev/null 2>&1; then
    _do_or_echo "git pull --rebase \"$REMOTE_NAME\" \"$b\" || git pull --no-rebase \"$REMOTE_NAME\" \"$b\" || true"
  fi
}

# ============================== 清理冲突目录 ==============================
pre_clean_conflicting_dirs() {
  local backup_root="/tmp/${SCRIPT_BASENAME}_backup_conflicts/$(date +%Y%m%d-%H%M%S)"
  local backup_created=0

  for p in "${CONFLICT_PATHS[@]}"; do
    # 1) 从索引移除
    if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      _do_or_echo "git rm -rf --cached \"$p\" || true"
      note_echo "已从索引移除：$p"
    fi
    # 2) 清理 .git/modules/<path>
    if [[ -d ".git/modules/$p" ]]; then
      _do_or_echo "rm -rf \".git/modules/$p\""
      note_echo "已清理 .git/modules/$p"
    fi
    # 3) 物理目录移动/删除
    if [[ -e "$p" ]]; then
      if [[ "$FORCE_DELETE" == "1" ]]; then
        _do_or_echo "rm -rf \"$p\""
        warn_echo "已删除：$p"
      else
        if [[ $backup_created -eq 0 ]]; then
          _do_or_echo "mkdir -p \"$backup_root\""
          backup_created=1
        fi
        _do_or_echo "mkdir -p \"$(dirname "$backup_root/$p")\""
        _do_or_echo "mv \"$p\" \"$backup_root/$p\""
        warn_echo "已备份并移除：$p  →  $backup_root/$p"
      fi
    fi
    # 4) 清理 .gitmodules 段
    if [[ -f ".gitmodules" ]] && git config -f .gitmodules --get-regexp "^submodule\..*\.path$" >/dev/null 2>&1; then
      local name
      name="$(
        git config -f .gitmodules --name-only --get-regexp "^submodule\..*\.path$" |
        while read -r k; do
          v="$(git config -f .gitmodules --get "$k")"
          [[ "$v" == "$p" ]] && echo "$k"
        done | sed -E 's/^submodule\.([^.]*)\.path.*/\1/' || true
      )"
      if [[ -n "$name" ]]; then
        _do_or_echo "git config -f .gitmodules --remove-section \"submodule.$name\" || true"
        note_echo "已从 .gitmodules 移除：submodule.$name"
      fi
    fi
  done

  if [[ -f ".gitmodules" ]]; then
    _do_or_echo "git add .gitmodules || true"
    _do_or_echo "git commit -m 'chore: cleanup conflicting paths before adding submodules' || true"
  fi
}

# ============================== 子模块操作 ==============================
# 强校验：必须是 gitlink（160000），否则中止
assert_gitlink() {
  local p="$1"
  local mode
  mode="$(git ls-files -s -- "$p" 2>/dev/null | awk '{print $1}' | head -n1)"
  if [[ "$mode" != "160000" ]]; then
    error_echo "路径 $p 不是 gitlink（子模块未正确注册/状态脏）。中止。"
    error_echo "自检：git ls-files -s $p  应返回以 160000 开头的一行。"
    exit 1
  fi
}

# .gitmodules 中是否已登记某 path
__in_gitmodules_paths() {
  [[ -f .gitmodules ]] || return 1
  git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}'
}

add_submodules() {
  local b="$SUBMODULE_BRANCH"
  info_echo "添加/修复子模块（分支：$b）"

  # 若 .gitmodules 已存在相同 path：只修 URL，跳过 add
  if __in_gitmodules_paths | grep -qx "$SUBMODULE_PATH"; then
    note_echo "已存在子模块记录，修正 URL 并跳过 add：$SUBMODULE_PATH"
    _do_or_echo "git config -f .gitmodules submodule.$SUBMODULE_PATH.path '$SUBMODULE_PATH' || true"
    _do_or_echo "git config -f .gitmodules submodule.$SUBMODULE_PATH.url  '$SUBMODULE_URL' || true"
  else
    # 如果路径已经是普通目录（而非子模块），直接中止，避免把目录内容加入父仓
    if [[ -d "$SUBMODULE_PATH" && -z "$(git ls-files -s -- "$SUBMODULE_PATH" 2>/dev/null)" ]]; then
      error_echo "检测到普通目录 $SUBMODULE_PATH 但没有子模块登记。请清理后重试。"
      error_echo "可执行：git rm -r --cached $SUBMODULE_PATH ; rm -rf .git/modules/$SUBMODULE_PATH"
      exit 1
    fi
    _do_or_echo "git submodule add -b \"$b\" \"$SUBMODULE_URL\" \"$SUBMODULE_PATH\""
  fi

  # 立刻校验：必须是 gitlink
  assert_gitlink "$SUBMODULE_PATH"
}

sync_and_init_submodules() {
  _do_or_echo "git submodule sync"
  _do_or_echo "git submodule update --init --recursive --jobs=\"\$(get_ncpu)\""
}

__selected() {
  local p="$1"
  [[ -z "$ONLY_PATHS" ]] && return 0
  for x in ${(z)ONLY_PATHS}; do [[ "$x" == "$p" ]] && return 0; done
  return 1
}

record_and_normalize_submodules() {
  local b="$SUBMODULE_BRANCH"
  info_echo "对子模块强制对齐远端最新（分支：$b，DRY_RUN=$DRY_RUN）"

  local paths=()
  if [[ -f .gitmodules ]]; then
    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
      git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}'
    )
  fi

  for sp in "${paths[@]:-}"; do
    __selected "$sp" || { note_echo "跳过未选路径：$sp"; continue; }
    note_echo ">>> 处理子模块：$sp"

    if [[ "$DRY_RUN" == "1" ]]; then
      note_echo "[DRY-RUN] git -C \"$sp\" fetch --all --tags --prune"
      note_echo "[DRY-RUN] git -C \"$sp\" checkout -B \"$b\" --track origin/\"$b\" || true"
      note_echo "[DRY-RUN] git -C \"$sp\" reset --hard origin/\"$b\""
      continue
    fi

    (
      set -e
      cd "$sp"
      git fetch --all --tags --prune
      if git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
        git checkout -B "$b" --track "origin/$b" || git checkout "$b" || true
        git reset --hard "origin/$b"
      else
        local def; def="$(git remote show origin | awk '/HEAD branch/ {print $NF}')"
        if [[ -n "$def" ]] && git ls-remote --exit-code --heads origin "$def" >/dev/null 2>&1; then
          git checkout -B "$def" --track "origin/$def" || git checkout "$def" || true
          git reset --hard "origin/$def"
        else
          warn_echo "远端无 $b 且无法确定默认分支：$sp"
        fi
      fi
      success_echo "$sp → $(git rev-parse --short HEAD)"
    )
  done

  # 只固化子模块 gitlink（绝不全量 add）
  if [[ "$DRY_RUN" == "0" && ${#paths[@]} -gt 0 ]]; then
    local add_list=()
    for sp in "${paths[@]}"; do __selected "$sp" && add_list+=("$sp"); done
    if [[ ${#add_list[@]} -gt 0 ]]; then
      _do_or_echo "git add ${add_list[*]}"
      if ! git diff --cached --quiet -- "${add_list[@]}"; then
        _do_or_echo "git commit -m \"chore: bump submodules to latest ($b)\""
        success_echo "父仓已固化最新 gitlink"
      else
        info_echo "gitlink 无变化，跳过提交"
      fi
    fi
  fi
}

# ============================== main ==============================
main() {
  # 1) 自述 & 确认
  show_intro_and_wait
  # 2) 切到脚本目录
  cd_to_script_dir
  # 3) 父仓 init（不做全量 add）
  ensure_repo_initialized
  # 4) 父仓远端（固定 URL；误配为子仓则自动纠正；不可达才询问）
  ensure_git_remote "$REMOTE_NAME"
  # 5) 忽略 *.command.local
  ensure_gitignore_for_local
  # 6) 父仓分支（main/master 兜底）
  ensure_parent_branch
  # 7) 同步远端
  parent_pull_rebase
  # 8) 清理冲突目录
  pre_clean_conflicting_dirs
  # 9) 添加/修复子模块（并立即 gitlink 校验）
  add_submodules
  # 10) 初始化 & 同步子模块
  sync_and_init_submodules
  # 11) 强制对齐子模块 + 固化 gitlink
  record_and_normalize_submodules
  # 12) 完成提示
  success_echo "全部完成 ✅（分支：$SUBMODULE_BRANCH，干跑：$DRY_RUN，删除策略：$([[ "$FORCE_DELETE" == "1" ]] && echo 删除 || echo 备份)，路径：$SUBMODULE_PATH）"
  note_echo    "日志文件：$LOG_FILE"
}

main "$@"
