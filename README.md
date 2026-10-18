# `VScodeConfigs`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

[实际目录结构](#repository-layout) · [Git 子模块脚本](#git-submodule-scripts)

---

## 🔥 <font id=前言>前言</font>

[**Git**](https://git-scm.com/) 子模块脚本的用途与执行顺序见[专章说明](#git-submodule-scripts)。

这里集中维护 [**Visual Studio Code**](https://code.visualstudio.com) 相关配置，方便新系统、新项目或脚本注入时复用。

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

## 一、目录定位 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 通用编辑器配置放在当前目录。
- [**Flutter**](https://flutter.dev/) 专用配置放在 `🐦VScodeConfigByFlutter`。
- 后续新增语言或项目类型配置时，优先使用独立子目录承载。

## 二、维护规则 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 配置文件名、路径、命令统一使用反引号。
- 不提交本机隐私路径、账号信息或临时缓存。
- 修改配置后，同步说明适用场景和是否会覆盖用户已有配置。

## 三、<span id="git-submodule-scripts">Git 子模块脚本</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### [【MacOS】⏬下载配置当前Git子模块.command](./【MacOS】⏬下载配置当前Git子模块.command/【MacOS】⏬下载配置当前Git子模块.command)

> **目的：** 把所选子仓代码更新到远端目标分支最新提交，并维护父仓的子模块关联。

* 阅读说明并确认，定位父仓，载入脚本清单（`VScodeConfigByFlutter` 挂载到 `🐦VScodeConfigByFlutter`）。

* 检查父仓远端和分支，先拉取父仓更新。
  * 父仓有未提交改动时跳过拉取，继续进入子模块菜单。

* 选择处理范围。
  * 全量：选择清单目标重建；须输入 `YES` 执行，其它输入取消。
  * 只更新已有：更新清单中本地已有的子仓；一个也没有时转全量。
  * 多选：只同步勾选项；添加：输入新仓地址后登记并同步。

* 补齐登记，按所选模式检查并处理目标目录；缺失目录会下载，全量模式会先删除重建。
  * 子仓有未提交改动时停止该次更新或删除。

* 拉取所选子仓，默认优先对齐远端 `main`，没有则改用远端默认分支；再同步其内部子模块到各自父仓记录的提交。
  * 强制对齐可能覆盖本地目标分支的独有提交；全量重建还可能丢失被删除目录中的本地历史。

* 默认自动提交父仓的子模块登记与指针变化，不自动推送；设 `AUTO_PARENT_COMMIT=0` 可保留待检查。

入口：`./【MacOS】⏬下载配置当前Git子模块.command/【MacOS】⏬下载配置当前Git子模块.command`。

## 四、<span id="repository-layout">实际目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
⚙️VScodeConfigs/
├── README.md / .gitignore / .gitmodules / icon.png
├── 【MacOS】⏬下载配置当前Git子模块.command/
│   ├── 【MacOS】⏬下载配置当前Git子模块.command
│   └── README.md
└── 🐦VScodeConfigByFlutter/                 # 独立 Git 子仓，配置和注入入口见其 README
```

下载包内的入口会定位本仓父目录作为仓库根；子仓内部配置与脚本由[子仓 README](./🐦VScodeConfigByFlutter/README.md)说明。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
