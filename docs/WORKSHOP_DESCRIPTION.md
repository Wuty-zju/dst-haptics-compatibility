# Workshop listing / 创意工坊文案 — 1.6.1

Existing item: https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756

## Title

DST Haptics Compatibility / 手柄震动兼容

## Tags

Select only relevant labels offered by the official uploader: client-only, utility.
Keep the existing item ID. This document does not itself upload content.

## Description — paste into Steam

[h2]原版事件，兼容输出[/h2]
纯客户端Windows手柄震动兼容Mod，读取当前DST的haptics.lua，通过TheInputProxy输出可观察的原版事件。支持Xbox/XInput、DualShock4与DualSense；服务器和其他玩家无需安装。

[list]
[*]真实声音、经过审计的工具动作确认与具名声音生命周期，不监听A/X按键补震。
[*]保留原版相对强度、player_only和分类；世界事件平滑衰减，本地UI不走世界距离。
[*]总体/分类强度与时长0%–200%，每档5%；设备适配、柔和/强力响应与空间范围可调。
[*]F8或手柄暂停菜单打开局内设置；中文/英文提示即时切换。
[*]Compatibility/Native/Diagnostic模式互斥；暂停、断连、声音替换和退出会清理反馈。
[*]近战与受击近似补偿默认关闭。开启才按复制信号估计，不保证原版实际播放了对应声音。
[/list]

[h2]范围和限制[/h2]
1.6核对DST762172/build26474873的506条定义、503个唯一事件。事件在表中不代表远端触发一定可观察。
部分服务器声音绕过客户端Lua；新增光束只读真实loop/bigloop句柄，仍需远程实机确认可见性。
100%表示兼容包络基准，不是原始波形逐采样复刻。DS4/DS5依赖DST或Steam Input提供rumble；不提供自适应扳机或DualSense高频触觉。完整物理连接矩阵尚未验收。

[h2]Installation and settings[/h2]
Enable this client mod and DST Controller Vibration. Press F8 in-world, or use the controller pause-menu shortcut. Avoid a duplicate manual copy.

The mod dynamically reads native haptics.lua and routes observable sounds and audited tool confirmations to TheInputProxy. Melee/hurt estimates are separate and OFF by default. Native and Compatibility output never intentionally run together.

Core envelopes, spatial falloff and controller curves are approximations. Some server-only one-shots have no provable client signal. Automated tests are not physical motor acceptance. If Klei restores native output, select Native or disable compatibility.

[url=https://github.com/Wuty-zju/dst-haptics-compatibility]Source, documentation and issues[/url]

## 1.6.1 Change note

维护现有行为：修复失活API干扰、世界/玩家观察资源清理、存活光束和暂停屏幕重装，纠正静态审计和证据覆盖。保留全部设置、严格默认、包络和设备曲线；未增加功能。实机验收仍待完成。

Maintains existing behavior: fixes inactive API ownership, entity resource cleanup and surviving world/beam/pause-screen rebinding; corrects static evidence and protects prior reports. Settings, strict defaults, envelopes and device curves are retained. No new features or physical acceptance claims.
