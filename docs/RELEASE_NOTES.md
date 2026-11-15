# DST Haptics Compatibility 1.6.0

1.6.0 rebuilds the client haptics pipeline around observable native events, explicit
approximation boundaries and independently owned lifecycle modules.

## 更新 / Changes

- 将原版索引、设备输出、空间资格、声音钩子、循环和工具确认从大适配器拆开；模块本地缓存，原版完整事件记录仍动态读取。
- 核对当前DST762172 / Steam build26474873：506条定义、503唯一事件；审查14新增事件实际运行侧与来源，不把注释中的旧声音当producer。
- 新增Shrouden光束真实loop/bigloop句柄观察；不从wide、smoke或动画猜起停，不播放额外声音。
- 修复雨/冰雹、树冠和伞等10种无_LP持续声音的生命周期；修复同名替换、远端接近恢复和断连期间实体清理。
- serverpauseddirty即时取消输出；静态调度保证暂停中热设置可用。玩家停用、设备切换与过期回调不复活旧尾段。
- 修复普通攻击缺少invobject时的武器解析和动作取消/替换串扰，工具末击保留原版event。
- 近战与受击近似补偿分别默认关闭：performaction不是命中证明，attacked不是普通hit原声证明。需要旧式补偿须显式开启；未知护甲和远程/特殊攻击保守跳过。
- 统一中文/英文运行时提示和日志，缩短双语配置标签，保留旧配置键；语言与设置暂停中也可热切。
- 重写中英文README，加入清晰安装、升级、配置、架构和边界说明；直接提供现有Steam Workshop项目链接。
- 构建保持干净白名单、版本/tag一致性、SHA-256与先验证后发布。

## Validation

Checked against the installed current native scripts, Lua5.1 and simulated engine
integration tests. Full per-definition tuning covers 506 definitions and 41,492
assertions. CI validates portable behavior and the immutable Workshop package.

See [the release review](https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v1.6.0/docs/reports/1.6.0-review.md)
and [native trigger audit](https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v1.6.0/docs/audit/1.6.0-trigger-paths.md).

## Boundaries / 边界

本版未新做完整物理手柄矩阵，不把自动测试当成马达体感或实际远程Boss验收。
纯Lua仍不能逐采样复原Klei原始waveform；部分server-only一次性声音无客户端可证实信号。
光束句柄observer为条件覆盖，仍需远程实机确认其可见性。

Strict defaults may produce less remote combat feedback than 1.5.0, deliberately
avoiding unsupported generic hurt/material guesses. Optional estimates are labelled.

DS4/DS5 require rumble support from DST or Steam Input. No adaptive triggers,
DualSense high-frequency haptics or external bridge. Existing settings remain compatible.

## Install / 安装

Subscribe to [Workshop item 3805091756](https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756),
or verify/extract the named release ZIP into mods/dst_haptics_compat. Enable the mod
and Controller Vibration. Avoid duplicate local/Workshop copies.

GitHub publication does not upload to Workshop. The Workshop author must update
the existing item separately; do not create another item.
