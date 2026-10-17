# `VScodeConfigs`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

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

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
