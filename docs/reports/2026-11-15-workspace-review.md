# 2026-11-15 工作区维护报告

维护基线：v1.5.0 / `cd4f1a2`；分支 `codex/workspace-maintenance`。
目标是文档、证据、归档与协作基础设施；Mod运行时代码和版本保持不变。

## 已整理

- AGENTS入口、状态、导航、证据索引、多智能体规则、任务模板与本任务交接。
- 项目级可选角色：Astra/xhigh设计、Sol/high实现与只读审查；主对话模型/速度不锁定。
- 统一验证入口与维护回归；Lua范围限定到实际源码/测试，原版数据显式输入。
- 打包拒绝已有产物；release依赖可复用CI；候选构建使用新目录。
- 当前原版和现存日志采集到本地，Git只保留摘要。历史发布收据新增可跟踪版本。

## 归档

19项旧目录/产物，共4,363文件、305,882,850字节，已移动并逐文件重新核对hash。
目录：`archive/2026-11-15/`；清单：`manifest.json`。
清单hash：`94e817c842e6d03972dcd2bf7b46f14a3b06b3bbd9692573367fa1f91aff6572`。
没有永久删除。最新1.5.0 ZIP/checksum/preview/历史收据仍在outputs。

## 当前事实

GitHub API确认最新release1.5.0，本地ZIP hash与线上digest一致。
11月7日的原始客户端日志加载Workshop项目3805091756、1.5.0、506/503初始化成功。
11月15日提取当前游戏762172/build26474873，同为506/503；相对9月新增14个唯一事件。
这不是本次重新运行游戏或完成设备体感验收。

## 验证记录

1. `tools/verify.py --original-scripts <本次快照>/native/scripts --report <新报告>`：
   Windows lua51Original.dll 路由，15 PASS / 0 FAIL / 0 SKIP；18个Lua文件解析、
   六项portable行为测试、506定义profile与41,492次倍率断言、7项维护回归、
   Python/TOML语法和相对链接检查通过。
2. 单独在 `build/workspace-check-20261115/` 构建维护候选，16文件白名单和根布局正确；
   checksum匹配，preview34,894字节。第二次构建拒绝覆盖，既有产物hash不变。
   再次采集到既有证据目录也被拒绝，snapshot.json未变。
3. 已发布outputs ZIP保持原hash，运行时 `scripts/`、modmain.lua、modinfo.lua
   相对v1.5.0无改动。`git diff --check` 通过。
4. 未提供原版数据的统一入口运行：14 PASS / 0 FAIL / 1 SKIP，原版检查如实跳过，
   不再自动复用旧快照。原始结果同目录 `verify-portable.json`。

统一入口结果：`.local/evidence/2026-11-15-validation/verify.json`；
独立包/保护检查：同目录 `package.json`。
提交 `9ebcdc3c57217d1dae04370523b8e048ac042b87` 后已再次验证15项全部PASS，
另存 `verify-final.json`，SHA-256为
`ccf57bf30e0d2b97eff88dfa0e1377850b44eb1b4c36ef415b974dfbec172266`，不覆盖原始记录。

远端 [CI run 43701891053](https://github.com/Wuty-zju/dst-haptics-compatibility/actions/runs/43701891053)
在同一提交上两项job均success：Linux Lua5.1验证、Windows发布包与拒绝覆盖检查。
维护分支已推送并跟踪origin同名分支，[草稿PR #1](https://github.com/Wuty-zju/dst-haptics-compatibility/pull/1)
保留差异；未合并main、未新发版。本文后补的交接信息是文档提交，不改运行时。

候选构建只是维护工具验收，不分发。Mod版本暂留1.5.0，因此新增README文档链接
会指向尚未包含这些文档的历史tag；下一次正式发版先升版并在对应tag包含这些文档，
不得用该维护候选覆盖正式1.5.0资产。

## 保留的边界

完整Xbox/DS4/DS5 USB/蓝牙/Steam Input体感矩阵未完成；World/Cave生命周期实际验收待补。
当前原版全定义profile/比例测试不证明每个Boss/环境触发都可被客户端Lua观察。
原生TheHaptics输出是否已修复没有重新做物理对照。Workshop公开状态和作者网页未核实。
模型角色文件遵循当前官方本地客户端配置；当前宿主是否自动加载须看实际工具支持，
本次子任务使用的是明确指定模型的spawn调用，不声称新角色已在此会话被自动加载。
