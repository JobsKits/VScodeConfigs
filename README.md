# `VScodeConfigs`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、目录定位](#jobs-toc-heading-2)
- [二、维护规则](#jobs-toc-heading-3)
- [三、Git 子模块脚本](#git-submodule-scripts)
  - [【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](#jobs-toc-heading-5)
- [四、实际目录结构](#repository-layout)

</details>
<!-- jobs-toc:end -->

[实际目录结构](#repository-layout) · [Git 子模块脚本](#git-submodule-scripts)

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

[**Git**](https://git-scm.com/) 子模块脚本的用途与执行顺序见[专章说明](#git-submodule-scripts)。

这里集中维护 [**Visual Studio Code**](https://code.visualstudio.com) 相关配置，方便新系统、新项目或脚本注入时复用。

<strong id="readonly-submodule-mode">先选用途：只拉取电脑默认按父仓锁定版本同步</strong>

| 启动选择 | 版本依据 | 是否写入父仓提交 |
| --- | --- | --- |
| 只拉取，默认 | 获取当前父仓明确的远程上游，再逐层检出父仓 gitlink 记录的 SHA | 不暂存、不提交、不推送 |
| 维护子模块，显式选择 | 按本仓清单及原有菜单，把所选子树更新到各自远端目标分支最新 | 沿用 `AUTO_PARENT_COMMIT` / `AUTO_PARENT_PUSH` 原有开关 |

只拉取模式从脚本所在仓库向下处理全部已登记子模块；不向上处理，不使用清单新增关联，也不把各子仓的分支最新提交回写父仓。每层相对 URL 随当前父仓的下载线路解析；子仓通常检出为游离 HEAD，属于固定版本消费的正常状态。只拉取模式只依赖系统 Git、zsh、Perl 等现有工具，不进入维护模式的 Homebrew / fzf 安装流程。

纯子仓 HEAD 漂移自动对齐；子仓源码、未跟踪内容、已暂存 gitlink、未完成操作和无法保护的独有游离提交会报出具体路径并停止，父仓 `YES` 不扩散到子仓。当前父仓自己的源码改动或本地独有提交，仍须红字列明并精确输入 `YES` 才舍弃。遇到 `not our ref`，先在有权限的发布电脑补齐同一平台的子仓提交；删库重拉、提交旧指针和在只拉取电脑 push 都不能补出服务端缺失的对象。

只拉取模式要求当前父仓已有明确上游；`REMOTE_NAME` 等原有清单参数只用于维护模式。设置 `DRY_RUN=1` 时，默认只拉取会停止并提示选择维护演练，不能忽略演练标志后执行真实更新。未初始化但存在旧 Git 缓存的空工作树须先恢复，脚本不会覆盖缓存内索引或独有提交。

下文关于清单新增、多选、同步深度、追踪分支最新、目录清理及自动提交的既有流程，均指显式选择的**维护模式**。只拉取模式默认向下递归固定版本，不使用这些写入父仓的开关。两种模式都保留各仓独立清单和来源显示；只拉取日志带运行时间与进程号，终端会输出实际路径。

<strong id="submodule-quick-look">父子仓多平台地址速览</strong>

当前 `./.gitmodules` 使用相对地址，例如：

```ini
[submodule "🐦VScodeConfigByFlutter"]
    path = 🐦VScodeConfigByFlutter
    url = ../VScodeConfigByFlutter.git
    branch = main
```

从下列父仓地址全新克隆、没有本地 URL 覆盖时，结果如下。前两行来自本地已配置的 [**GitHub**](https://github.com) / [**Gitee**](https://gitee.com) 远端；自建平台仅为结构示例，未部署。

| 平台 | 父仓克隆地址 | 子仓解析地址 |
| --- | --- | --- |
| GitHub | `git@github.com:JobsKits/VScodeConfigs.git` | `git@github.com:JobsKits/VScodeConfigByFlutter.git` |
| Gitee | `git@gitee.com:JobsGo/VScodeConfigs.git` | `git@gitee.com:JobsGo/VScodeConfigByFlutter.git` |
| 自建平台，仅结构示例 | `ssh://git@git.example.com:2222/team/VScodeConfigs.git` | `ssh://git@git.example.com:2222/team/VScodeConfigByFlutter.git` |

`path` 是本地目录，`url` 是远端仓库位置；相对 URL 跟随父仓默认远端的平台、组织、协议与端口，前提是该平台已有对应子仓及父仓锁定的提交。已有克隆须核对默认远端和本地子模块配置，仅新增 remote 不会切换线路。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、目录定位 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 通用编辑器配置放在当前目录。
- [**Flutter**](https://flutter.dev/) 专用配置放在 `🐦VScodeConfigByFlutter`。
- 后续新增语言或项目类型配置时，优先使用独立子目录承载。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、维护规则 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 配置文件名、路径、命令统一使用反引号。
- 不提交本机隐私路径、账号信息或临时缓存。
- 修改配置后，同步说明适用场景和是否会覆盖用户已有配置。

## 三、<span id="git-submodule-scripts">Git 子模块脚本</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](./【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command)</span><!-- jobs-toc:heading-end -->


> **目的：** 默认只拉取父仓锁定的完整子模块版本；显式维护模式保留清单、追踪分支和登记能力。

- 启动时回车默认进入[只拉取模式](#readonly-submodule-mode)，先预检完整目标提交树，再更新当前父仓并逐层检出固定版本；不提交、不推送。
- 显式选择维护模式后，按以下原有清单和菜单流程处理。

* 阅读说明并确认，定位父仓，载入脚本清单（`VScodeConfigByFlutter` 挂载到 `🐦VScodeConfigByFlutter`）。

* 检查父仓远端和分支，先拉取父仓更新。
  * 父仓有未提交改动时跳过拉取，继续进入子模块菜单。

* 在主菜单选择同步范围；“切换同步深度”可在默认“向下递归”和“仅直属子模块”之间切换，当前深度适用于各同步动作。
  * 全量：逐项同步清单内全部目标，按目录状态复用或首次克隆。
  * 只更新已有：更新清单中本地已有的子仓；一个也没有时转全量。
  * 多选：只同步勾选项；添加：输入新仓地址后登记并同步。

* 补齐登记，所有模式都按目录状态处理：空或缺失时首次克隆，已有有效 Git 工作区原地更新；既有缓存核验后恢复，非 Git 非空目录保护并停止。
  * 子仓有未提交、已暂存或未跟踪内容：红字加粗显示该仓绝对路径并循环等待；精确输入 `YES` 只放弃当前仓自己的未提交内容，或在外部处理后回车复检。其它输入继续复检；无交互或输入结束则停止。

* 拉取并强制对齐远端目标分支最新提交：优先使用该层 `.gitmodules` 显式 `branch`，`.` 继承直接父仓分支；未设置时优先 `main`，不存在则使用远端默认分支。

* 按当前深度同步：默认逐层读取所选子仓下的 `.gitmodules`，将已登记后代同步到各自远端目标分支最新提交；仅直属模式不下载或更新下层代码。
  * 只处理本层所选子树，不向上扫描，也不接管未登记的嵌套仓库。
  * 递归更新本层前先检查当前已有后代；各仓单独确认，子模块 HEAD 与父仓 gitlink 的普通差异不作为源码未提交反复提示。
  * `YES` 清理仅作用于当前仓：`reset --hard HEAD` 与 `clean -fd`；保留忽略文件和独立嵌套 Git 仓，残留冲突须外部处理后复检。
  * `PRUNE_STALE_GITMODULES` 默认 `0`，保留清单外旧登记；主动设为 `1` 时，每个旧登记另用红字加粗列明目录和后代删除范围，逐项精确输入 `YES` 才删除，其它输入、输入结束或非交互则停止；演练只展示，删除前仍逐仓检查已有后代。
  * 深层只下载更新，不自动暂存或提交其父仓的 gitlink；递归后这些父仓可能显示子模块指针改动，保留待审阅。
  * 强制对齐仍可能覆盖本地目标分支的独有提交；运行前核对分支和本地提交。

* 默认自动提交入口父仓的子模块登记与指针变化，不自动推送；设 `AUTO_PARENT_COMMIT=0` 可保留待检查。

入口：`./【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command`。

## 四、<span id="repository-layout">实际目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
⚙️VScodeConfigs/
├── README.md / .gitignore / .gitmodules / icon.png
├── 【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/
│   ├── 【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command
│   └── README.md
└── 🐦VScodeConfigByFlutter/                 # 独立 Git 子仓，配置和注入入口见其 README
```

下载包内的入口会定位本仓父目录作为仓库根；子仓内部配置与脚本由[子仓 README](./🐦VScodeConfigByFlutter/README.md)说明。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
