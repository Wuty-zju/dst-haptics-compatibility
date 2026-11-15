# 工作区使用 / Workspace operations

## 目录职责

```text
repository/
  AGENTS.md                 Agent 入口，保持简短
  .codex/                   项目级可选模型/角色配置
  modinfo.lua, modmain.lua   标准 DST Mod 根入口
  scripts/                  唯一运行时代码
  assets/                   原创图标源
  tests/, tools/            验证和维护工具
  docs/                     当前状态、证据、架构、历史和任务
  .github/                  CI 和发布流程
  outputs/                  最近已发布版本的本地成品（忽略）
  .local/evidence/           按会话保存的日志、输入快照、验证 JSON（忽略）
  build/<session>/          可重建候选包（忽略）
  archive/<date>/            旧工作材料、旧构建和旧输出（忽略）
```

仓库目录保留现有位置，防止已有路径和发布工具失效；不再创建 `work/` 下的独立
clone 或复制一份运行时代码。并行 worktree 放在仓库外的兄弟目录。原版资源不入 Git。

## 开始一次工作

1. 将这个 Git 仓库作为项目主文件夹打开，检查分支、改动和任务归属。
2. 阅读 `AGENTS.md`、`docs/STATUS.md` 与相关任务。不必重读全部历史报告。
3. 用任务分支工作；只有独立写入任务才创建额外 worktree。
4. 验证后更新任务交接与证据；发布沿用已存在的 Workshop ID。

当前聊天的默认目录若仍是用户主目录，命令须显式指定本仓库。建议在桌面项目菜单中
将本仓库设为主文件夹；仅仅把它列为次要文件夹不会自动发现它的 AGENTS/config。
不要为此在用户主目录创建全局规则，也不要改动别的项目。

## 统一验证

需要可用的 Python 3.11+。Windows 的 `python.exe` 可能只是 Microsoft Store
占位符；先确认 `python --version` 确实输出版本。可使用 Codex 当前会话返回的
bundled Python 绝对路径；该路径随应用升级变化，不写入仓库配置。

```powershell
python tools/verify.py --report .local/evidence/new-session/verify.json
python tools/verify.py --lua-deps "<包含 lua51Original.dll 的目录>" --original-scripts "<当前快照>/scripts" --report .local/evidence/new-native-session/verify.json
```

第一个命令运行可移植检查，原版数据检查显示 SKIP。第二个命令才证明指定原版快照
通过 profile/倍率测试。二者都不驱动马达，不启动游戏，不重建 release。已有报告路径
拒绝覆盖，避免把失败历史或已发布凭证覆盖掉。

## 采集当前游戏数据

```powershell
pwsh -File tools/snapshot_game.ps1 -GameRoot "<DST 安装目录>" -ClientLog "<client_log.txt>"
```

它读取 `data/databundles/scripts.zip`、游戏版本和 Steam manifest，写入新的
`.local/evidence/<session>/`，包含 `snapshot.json`、原版脚本和可选日志副本。
记录源文件哈希及日志原始修改时间。日志只证明那个会话，不代表采集当天的复测。
输出中 `originalScripts` 可直接传给验证工具。需要全量源码审计时使用工具的显式
`--scripts` 参数；不要悄悄使用 9 月旧快照。

## 成品与归档

```powershell
pwsh -File tools/build_release.ps1 -OutputRoot build/new-candidate-session
```

输出目录必须新鲜。若 stage、ZIP、checksum 或 preview 已存在，构建工具停止，
不再先删除旧 stage/ZIP。正式版本仍从 `modinfo.lua` 读取；维护提交不擅自升版。

2026-11-15 整理将旧 `work/`、旧 `build/` 和非当前 `outputs/` 项移动到
`archive/2026-11-15/`。`manifest.json` 记录每个原路径、新路径、文件大小和 SHA-256，
移动后重新核对。只归档，不永久删除；有历史 `.git` 的 clone 整体保留。
外部 `DST Mod Backups` 的卸载备份保持原位置。

恢复某项时按 manifest 对照，先核对 hash，再复制到新目录；不要覆盖当前分支源码。
归档中的旧 clone 不再作为工作区。`outputs/` 内的最终发布收据已另存成可跟踪的
[历史发布凭证](../reports/1.5.0-release-receipt.md)。

## 换电脑

开发：clone GitHub 仓库，读取状态与任务；原版快照和 DLL 在新电脑重新定位/采集，
不依赖旧电脑绝对路径。分支推送不等于 merge，也不等于发布。

分发：[按 Workshop 文档](../STEAM_WORKSHOP.md)下载 release ZIP、校验文件和
preview，登录原作者 Steam 账号，在上传器中编辑原项目 `3805091756`。
不得再次 Add 创建重复项目。Steam 密码和验证码由账号本人处理。

English: keep one canonical repository, isolated task worktrees and immutable evidence
sessions. Rebuild into fresh directories. Archives retain hashes and restore paths;
raw game data, logs and machine-specific paths never enter commits.
