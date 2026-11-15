# Testing / 测试

## One entry point / 统一入口

需要 Python 3.11+，以及 Lua 5.1 可执行程序或 Windows `lua51Original.dll`。
`tools/verify.py` 是唯一可移植测试清单，CI 和本地共用。

```powershell
python tools/verify.py --lua lua5.1 --report .local/evidence/new-portable-session/verify.json
python tools/verify.py --lua-deps "<DLL目录>" --original-scripts "<当前原版scripts>" --report .local/evidence/new-native-session/verify.json
```

未传 `--lua` 时尝试 PATH 中的 Lua 5.1，再尝试 Windows DLL。显式选错版本或找不到
运行时会 FAIL，不偷偷回退。DLL 参数传给每个测试。没有原版脚本参数或
`DST_ORIGINAL_SCRIPTS` 时，原版检查为 SKIP；不再自动选择 `work/` 的旧快照。
已有 JSON 路径拒绝覆盖。输出包含命令、退出码、基线提交、源码 hash 和原版输入 hash。

| 范围 | 检查内容 |
|---|---|
| Lua 语法 | 根入口、scripts 下运行时代码和 tests 下 Lua 入口，排除归档/旧副本 |
| 八项 portable 行为测试 | adapter、动作桥、声音参数、配置、循环混合、运行时设置、光束observer、中英文本/沙箱配置 |
| 原版数据测试（可选） | 指定快照每条定义生成 profile，分类强度/时长双轴全部 41 档 |
| Python/TOML/Markdown | 工具语法、维护回归、项目 TOML 语法、本地相对文件链接 |
| 包验证（单独CI job/手工检查） | 不包含在 verify.py 结果中；新输出目录构建后检查根布局、白名单、checksum、preview 与拒绝覆盖 |

模拟行为包括工具/受击/近战确认、挥空无材质命中、hook 变参与返回值、player_only、
空间衰减、去重、loop 停止、暂停/断连/卸载、配置热更新和校准层级。
这些是逻辑测试，不等于引擎事件实际可观察或物理马达体感测试。

## Current game input / 当前原版输入

使用 [snapshot_game.ps1](../tools/snapshot_game.ps1)采集安装目录，保存游戏版本、build、
scripts.zip 与 haptics.lua hash。采集方法见 [工作区文档](maintenance/WORKSPACE.md)。
11 月 15 日快照是 506/503；9 月 492/489 是历史快照。断言次数依数据生成，不能写死。
1.6新增真实攻击构造（无invobject）、近似默认关闭、动作失败/连续确认、雨/冰雹循环、
同名替换、服务器暂停、玩家停用、句柄observer、热重装和中英文切换回归。

GitHub CI 不含 Klei 原版脚本，所以原版数据检查 SKIP。发布 workflow 先等待可复用
CI 通过再打包/发布；CI成功不代表原版数据或硬件验收通过。

## Rebuilding the audit / 重建静态审计

以下目录均应是新会话目录，`$scripts` 必须来自你采集的当前快照：

```powershell
python tools/audit_haptics.py --scripts $scripts --wav-root "<DST>/data/haptics/vibration/vibration" --out .local/evidence/new-audit/audit
python tools/analyze_waveform_envelopes.py --wav-root "<DST>/data/haptics/vibration/vibration" --out .local/evidence/new-audit/core_envelopes.json
```

审计先屏蔽Lua行/块注释并保留行号。当前406个唯一event有字面引用、97个没有；
历史407/96含已注释Charlie death。字面引用与文件名相似度都不能证明实际客户端触发
或精确event→WAV bank映射。
原有 `build_haptics_report.py` 的机制说明模板包含历史实现描述，不能未经逐项复审
就把它输出为新版本的完整保真结论。新数据先生成带 hash/build 的快照摘要。

## Physical acceptance / 物理验收

连续工具节奏、挥动/命中、当地受击、Boss近/远、UI、具名loop、退出世界、暂停、
断连/重连、洞穴切换分别记录。DS4/DS5 只测试实际向 DST 暴露 rumble 的直连/
Steam Input 路由。记录设备、USB/蓝牙、Steam Input、配置、游戏和Mod版本、日期、
日志位置及实际感受。使用 [硬件矩阵](HARDWARE_MATRIX.md)，不以枚举状态代替验收。
