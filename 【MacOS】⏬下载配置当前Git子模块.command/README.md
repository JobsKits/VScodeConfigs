# `【MacOS】⏬下载配置当前Git子模块.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`【MacOS】⏬下载配置当前Git子模块.command` 用于执行“【MacOS】⏬下载配置当前Git子模块”对应的 MacOS 自动化流程。主脚本与本 `README.md` 必须保持在同一目录，运行前先阅读影响范围。

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

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 需要执行“【MacOS】⏬下载配置当前Git子模块”所描述的本机开发或维护任务。
- 希望通过可重复运行的 Shell 脚本减少手工命令遗漏。
- 需要结合终端日志定位环境、路径或第三方工具问题。

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
- 涉及安装、更新或升级时，以脚本终端提示为准；直接回车应表示跳过。

## 四、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 4.1、双击运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在 Finder 中打开当前目录并双击 `【MacOS】⏬下载配置当前Git子模块.command`。阅读终端自述后按回车继续，按 `Ctrl+C` 取消。

进入“选择指定子模块同步（可多选）”后，用 ↑ / ↓ 移动，按回车（Enter）勾选或取消项目；最后按 **空格键（Space）确认并开始同步**，无需再按回车。列表底部会持续显示操作提示；按 ← 返回上一页。

### 4.2、终端运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
cd "脚本所在目录/【MacOS】⏬下载配置当前Git子模块.command"
./【MacOS】⏬下载配置当前Git子模块.command
```

## 五、操作流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、展示脚本内置自述并等待回车。
2、检查运行环境、输入参数和目标路径。
3、按脚本提示确认需要执行的业务步骤。
4、输出执行结果、失败原因和日志位置。

## 六、风险说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 脚本包含删除、清理或重置动作，执行前必须确认目标路径和影响范围。
- 脚本可能访问网络、下载文件或更新本机工具链。
- 脚本可能修改 Git 工作区或仓库配置，运行前应确认当前仓库和分支。
- 脚本会调用 Flutter / Dart 工具链，运行前应确认工程根目录和 SDK 版本。

危险操作必须以脚本中的 `YES` 确认为准；如果脚本尚未提供明确确认，应先审查脚本内容，不要盲目执行。

## 七、日志文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Jobs 标准脚本日志默认写入：

```text
$TMPDIR/【MacOS】⏬下载配置当前Git子模块.log
```

如果脚本内部另有 `LOG_FILE` 定义，以主脚本实际配置为准。

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
- `GIT_URL_STYLE=auto` 保留实际地址；显式指定 `https` 或 `ssh` 只转换无歧义地址，无法推断跨协议端口时停止。`AUTO_PARENT_COMMIT` 默认 `1`，`AUTO_PARENT_PUSH` 默认 `0`；需要只同步并保留修改待检查时，将自动提交设为 `0`。

父仓已配置名为 `gitee` 的 remote 时，可以在脚本所在目录运行：

```shell
REMOTE_NAME=gitee \
AUTO_PARENT_COMMIT=0 \
./【MacOS】⏬下载配置当前Git子模块.command
```

普通 `git clone --recurse-submodules` 由 Git 依据父仓默认 remote 解析相对 URL；`REMOTE_NAME` 是本脚本的线路选择参数。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
