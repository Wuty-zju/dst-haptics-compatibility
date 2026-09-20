# Steam Workshop Listing / 创意工坊页面文案

## Title

DST Haptics Compatibility / 手柄震动兼容

## Tags

`utility`, `client_only_mod`

## Description

纯客户端 Windows 手柄震动兼容层。动态读取当前版本 DST 的 `haptics.lua`，将原版已经定义的工具、战斗、受击、Boss、环境和 UI/HUD Haptic 事件桥接到可工作的 `TheInputProxy` 输出。

- 不监听 A/X 键制造假震动；砍伐、采矿与近战材质命中等待原版服务器动作结果。
- 保留原版 `vibration_intensity`、`player_only`、category、音量/参数、空间距离和循环生命周期。
- 支持 Xbox/XInput、DualShock 4、PS5/DualSense，以及由 Steam Input 暴露给 DST 的兼容设备。
- 提供总强度、工具、战斗、危险、玩家、Boss、环境、UI、循环和空间范围设置。
- 提供用户主动触发的弱/中/强校准脉冲，用于验证 Xbox、DS4、DualSense 当前连接路径。
- Compatibility、Native、Diagnostic 三种输出模式，避免未来 Klei 修复后双重震动。
- 服务器和其他玩家无需安装，不修改存档、伤害、RPC 或玩法逻辑。

Client-only Windows controller haptics compatibility layer. It dynamically reads the installed DST `haptics.lua` and bridges the native tool, combat, hurt, Boss, environment and UI/HUD events to the working `TheInputProxy` output path.

- No A/X-button rumble and no unconfirmed animation guesses.
- Preserves native intensity order, `player_only`, category, sound parameters/volume, listener-relative distance and named-loop lifecycle.
- Supports Xbox/XInput, DualShock 4 and PS5/DualSense through DST/Steam Input's controller output path.
- Fine-grained in-world levels plus Compatibility, Native and no-motor Diagnostic modes.
- No server installation, save changes, gameplay RPCs or combat modifications.

Keep DST's own Controller Vibration setting enabled when using Compatibility mode. If Klei restores native Windows haptics, switch Output Mode to Native or disable Vibration Compatibility.

Source and issue tracking: https://github.com/Wuty-zju/dst-haptics-compatibility

## 1.4.0 Change Note

Fixed listener-local FocalPoint events and true 3D listener distance; added native one-shot/loop parameter handling, combined Boss/Combat and category scaling, special-hurt duplicate suppression, confirmed killing-blow material snapshots, explicit Native/Compatibility/Diagnostic modes, and expanded Lua 5.1/Workshop package validation.
