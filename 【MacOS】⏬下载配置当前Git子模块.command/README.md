# `【MacOS】⏬下载配置当前Git子模块.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

[**Git**](https://git-scm.com/) 子模块脚本的用途与执行顺序见[专章说明](#git-submodule-scripts)。

`【MacOS】⏬下载配置当前Git子模块.command` 用于下载、更新上一级 `VScodeConfigs` 父仓清单中的子模块。脚本与本 `README.md` 放在当前同名目录，运行时自动定位上一级父仓。

<strong id="git-source-log">运行时先看这里：子 Git 从哪里拉取</strong>

以父仓线路为 `https://gitee.com/JobsGo/JobsGenesis.git`、下载 `JobsCommand@iOS` 为例，终端会突出显示完整来源；提交号仅展示成功日志的格式：

```text
━━━━━━━━━━ Git 来源｜首次克隆 ━━━━━━━━━━
📦 仓库：JobsCommand@iOS
🌐 平台 / 主机：Gitee（gitee.com）
📥 拉取地址：https://gitee.com/JobsGo/JobsCommand-iOS.git
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  克隆分支：main
... Git 原生下载进度 ...
✅ JobsCommand@iOS 已浅同步到 origin/main：17b467d（来源：https://gitee.com/JobsGo/JobsCommand-iOS.git）
```

父仓线路、首次克隆和拉取更新各有来源块；已能读取 `.gitmodules` 的递归子仓，在更新前显示“递归来源核对”。首次原生递归克隆仍由 Git 输出注册 URL。平台按地址中的主机识别，不按本地目录名判断。

若 `insteadOf` 改写了 URL，来源块同时列出“解析地址”和“拉取地址”；后者由 `git ls-remote --get-url` 在本地展开，未探测 HTTP 重定向或代理最终出口。首次克隆只读取系统、全局及本次进程的规则，不沿用父仓本地 `insteadOf`；已有子仓拉取读取自身配置，递归子仓也分别按未初始化 / 已初始化采用这两种作用域。新来源块在支持颜色的终端重点显示，写入日志时保留纯文本；URL 凭据与查询参数会脱敏。来源日志位于系统临时目录，文件名为 `【MacOS】⏬下载配置当前Git子模块.log`，Git 原生进度仍以终端输出为准。

<strong id="submodule-quick-look">先看例子：从哪个平台下载父仓，子仓就跟着走</strong>

以本仓 `VScodeConfigs` 的 `🐦VScodeConfigByFlutter` 子模块为例。先对照固定到 [**GitHub**](https://github.com) 的写法（仅作对照，不代表本仓历史配置）：

```ini
url = https://github.com/JobsKits/VScodeConfigByFlutter.git
```

当前 [`.gitmodules`](../.gitmodules) 使用相对地址：

```ini
[submodule "🐦VScodeConfigByFlutter"]
    path = 🐦VScodeConfigByFlutter
    url = ../VScodeConfigByFlutter.git
    branch = main
```

同一条 `url` 根据父仓地址解析，支持 [**Gitee**](https://gitee.com) 和任意自建平台；自建地址仅作示例：

| 所选父仓 remote 地址 | 子仓实际地址 |
| --- | --- |
| `https://github.com/JobsKits/VScodeConfigs.git` | `https://github.com/JobsKits/VScodeConfigByFlutter.git` |
| `https://gitee.com/JobsGo/VScodeConfigs.git` | `https://gitee.com/JobsGo/VScodeConfigByFlutter.git` |
| `ssh://git@git.example.com:2222/team/tools/VScodeConfigs.git` | `ssh://git@git.example.com:2222/team/tools/VScodeConfigByFlutter.git` |

`path` 是本地目录名，`url` 中必须写真实远端仓名；这里本地目录带 `🐦`，远端仓名不带。目标平台必须已有子仓镜像，并包含父仓 gitlink 指定的提交。

本下载脚本用 `REMOTE_NAME` 选择父仓线路，默认 `origin`；本仓已有 `gitee` remote，使用 `REMOTE_NAME=gitee` 可按 Gitee 父仓地址解析相对 URL。已有绝对 URL 例外仍按其明确地址下载，脚本保留它，不会因选了 `gitee` 就强行替换。新登记缺少目标平台真实地址证据时会停止；完整参数见[多平台子模块地址](#submodule-address-rules)。

**下载脚本的 Gitee 传输规则：** `【MacOS】⏬下载配置当前Git子模块.command` 在本次运行中，将 `git@gitee.com:`、`ssh://git@gitee.com/`、`ssh://git@gitee.com:22/` 开头的标准地址统一通过 `https://gitee.com/` 访问，保留账号、真实仓名和分支；即使设置 `GIT_URL_STYLE=ssh`，这类 Gitee 地址仍使用 HTTPS。首次 `clone --recurse-submodules` 和后续递归同步都继承该规则，历史子模块中的 SSH 地址无需新电脑先配置 SSH 密钥。

规则通过追加进程级 `GIT_CONFIG_COUNT` / `url.https://gitee.com/.insteadOf` 配置传给子进程，不写入全局 Git 配置，也不依赖其它工程路径。GitHub、其它主机及非 `22` 的自定义 SSH 端口保持原规则。克隆或递归更新失败会返回非零状态，停止本轮同步并保留错误；不会再输出该项同步成功。各仓清单与浅克隆参数保留；全量删除重建须输入 `YES` 确认，范围限定为清单目标及对应旧仓名目录。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 首次下载清单中的 `🐦VScodeConfigByFlutter` 子模块。
- 更新已有子仓到远端目标分支最新提交，或多选指定同步项。
- 输入新仓地址，补齐登记并同步到父仓。

## 二、目录结构 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
【MacOS】⏬下载配置当前Git子模块.command/
├── 【MacOS】⏬下载配置当前Git子模块.command
└── README.md
```

## 三、执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 确认当前系统为 MacOS，并已安装脚本实际调用的工具。
- 确认脚本路径、工程目录、输入文件和当前 Git 工作区正确。
- 打开主脚本检查其中的业务命令，不理解的操作不要直接执行。
- 进入脚本自述时回车继续；菜单中的全量模式须输入 `YES` 才删除并重建目标目录，执行前确认范围。

## 四、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 4.1、<span id="download-double-click">双击运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在 Finder 中打开当前目录并双击 `【MacOS】⏬下载配置当前Git子模块.command`。阅读终端自述后按回车继续，按 `Ctrl+C` 取消。

进入“选择指定子模块同步（可多选）”后，用 ↑ / ↓ 移动，按回车（Enter）勾选或取消项目；最后按 **空格键（Space）确认并开始同步**，无需再按回车。列表底部会持续显示操作提示；按 ← 返回上一页。

### 4.2、终端运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
cd "脚本所在目录/【MacOS】⏬下载配置当前Git子模块.command"
./【MacOS】⏬下载配置当前Git子模块.command
```

## 五、操作流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

按 [Git 子模块脚本](#git-submodule-scripts) 中的时间顺序执行，菜单操作见[双击运行](#download-double-click)。

## 六、风险说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 全量模式删除清单目标及对应旧仓名目录后重建；须输入 `YES` 确认，其它输入取消。
- 更新使用 `checkout -B` / `reset --hard` 强制对齐远端；未提交改动会阻断，但本地独有提交仍可能被覆盖或随目录重建丢失。
- 默认会创建父仓提交，不自动推送；运行前检查父仓暂存区，设 `AUTO_PARENT_COMMIT=0` 可保留修改待审阅。
- 脚本会联网拉取代码；缺少菜单工具时可能安装 Homebrew / fzf，按终端实际提示操作。

## 七、日志文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

脚本日志写入系统临时目录，文件名为 `【MacOS】⏬下载配置当前Git子模块.log`。新来源块以纯文本保存；Git 原生下载进度仍以终端输出为准。

## 八、常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 8.1、提示命令不存在 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

根据终端错误确认缺少的工具，先完成安装并保证命令已经加入 `PATH`。

### 8.2、提示权限不足 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

检查目标文件权限和目录归属。只有确认命令及目标路径安全后，才按提示使用管理员权限。

### 8.3、双击后没有继续执行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

查看终端是否正在等待阅读确认或业务输入；不确定时按 `Ctrl+C` 退出后重新检查脚本。

## 九、未执行声明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

README 只描述脚本职责和通用风险，不代表已经在当前 MacOS 环境执行真实业务命令。交付前应至少通过对应 Shell 的静态语法检查。

[**Homebrew**](https://brew.sh/) 安装路径由用户选择：已有可运行安装时复用；确实需要安装时先强提示，只有精确输入大写 `YES` 才选择系统标准目录，其它输入或直接回车选择当前用户的 `.local/homebrew`。`YES` 只表示选择路径，权限与密码由官方安装器实际处理；有管理员权限也可以选用户目录。选定路径失败立即停止，不自动切换；`Ctrl+C` / 输入结束取消整个任务。

## 十、<span id="submodule-address-rules">多平台子模块地址</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 支持 [**GitHub**](https://github.com)、[**Gitee**](https://gitee.com)、[**GitLab**](https://about.gitlab.com) 和自建 Git 服务器；接受 HTTPS、`git@host:namespace/repo.git` 和 `ssh://git@host:端口/namespace/repo.git`，保留嵌套 namespace 与显式端口。配置中禁止携带 HTTP 用户凭据或 SSH 密码。
- `REMOTE_NAME` 默认 `origin`。已有 `.gitmodules` 的 URL、分支、缺省分支和扩展字段保持原样；`../真实仓名.git` 随所选父 remote 的平台、namespace、协议与端口解析，仓名不从本地目录猜测。
- 新条目依据真实子仓 remote 与父 remote 的对应关系生成相对 URL。已知镜像仓名不同、跨组织或端口不匹配时保留已确认的绝对地址；缺少目标平台地址证据时停止并提示在 `.gitmodules` 配置真实 URL，不自动退回其它平台。
- 递归同步逐层使用各自父仓地址。绝对子仓下面的相对子模块，以该绝对子仓为基准继续解析。
- Gitee 标准地址统一使用 HTTPS；其它地址在 `GIT_URL_STYLE=auto` 时保留实际地址，显式指定 `https` 或 `ssh` 只转换无歧义地址，无法推断跨协议端口时停止。`AUTO_PARENT_COMMIT` 默认 `1`，`AUTO_PARENT_PUSH` 默认 `0`；需要只同步并保留修改待检查时，将自动提交设为 `0`。

父仓已配置名为 `gitee` 的 remote 时，可以在脚本所在目录运行：

```shell
REMOTE_NAME=gitee \
AUTO_PARENT_COMMIT=0 \
./【MacOS】⏬下载配置当前Git子模块.command
```

普通 `git clone --recurse-submodules` 由 Git 依据父仓默认 remote 解析相对 URL；`REMOTE_NAME` 是本脚本的线路选择参数。

## 十一、<span id="git-submodule-scripts">Git 子模块脚本</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 11.1、`【MacOS】⏬下载配置当前Git子模块.command` <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

入口：`./【MacOS】⏬下载配置当前Git子模块.command`（脚本自动定位上一级父仓）。

- 1、阅读说明并确认，定位父仓，载入脚本清单（`VScodeConfigByFlutter` 挂载到 `🐦VScodeConfigByFlutter`）。

- 2、检查父仓远端和分支，先拉取父仓更新。
  - 父仓有未提交改动时跳过拉取，继续进入子模块菜单。

- 3、选择处理范围。
  - 全量：选择清单目标重建；须输入 `YES` 执行，其它输入取消。
  - 只更新已有：更新清单中本地已有的子仓；一个也没有时转全量。
  - 多选：只同步勾选项；添加：输入新仓地址后登记并同步。

- 4、补齐登记，按所选模式检查并处理目标目录；缺失目录会下载，全量模式会先删除重建。
  - 子仓有未提交改动时停止该次更新或删除。

- 5、拉取所选子仓，默认优先对齐远端 `main`，没有则改用远端默认分支；再同步其内部子模块到各自父仓记录的提交。
  - 强制对齐可能覆盖本地目标分支的独有提交；全量重建还可能丢失被删除目录中的本地历史。

- 6、默认自动提交父仓的子模块登记与指针变化，不自动推送；设 `AUTO_PARENT_COMMIT=0` 可保留待检查。

**目的：** 把所选子仓代码更新到远端目标分支最新提交，并维护父仓的子模块关联。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
