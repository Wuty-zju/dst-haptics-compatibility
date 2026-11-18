# DST Haptics Compatibility 1.6.2 全量审计

[逐事件 CSV](DST-Haptics-Event-Audit-1.6.2.csv)记录最后生效的每条定义、原版七字段、静态引用位置和当前兼容包络。空原版字段表示未设置。定义行取自审计输入。

- 原版 `haptics.lua` SHA-256 `e54ee51bd9cf3c0a682375dc5c5962b1e3eaa3307e131fc61c5088d3cc70f5b0`
- 静态 `audit.json` SHA-256 `e4d0f2150ab35c11cdc2af55a78d57b63eb074a9f15afcd05053b058a4655a13`
- 运行时 `modinfo.lua` 版本 `1.6.2`

| 项目 | 数量 |
|---|---:|
| 原版定义 | 506 |
| 唯一事件 | 503 |
| 重复出现的附加定义 | 3 |
| 有静态 Lua 字面引用的事件 | 404 |
| 无静态 Lua 字面引用的事件 | 99 |
| `vibration=true` | 503 |
| `audio=false` | 14 |
| `player_only=true` | 44 |
| 具名可循环、匿名有界的 profile | 30 |
| 使用 RMS 包络族的事件 | 104 |

| 原版分类 | 唯一事件数 |
|---|---:|
| BOSS | 180 |
| DANGER | 13 |
| ENVIRONMENT | 53 |
| PLAYER | 232 |
| UI | 22 |
| 未设置 | 3 |

### 触发与可观察性

- 严格路径使用客户端可观察的原声，或经审计的工具动作确认、远程饥饿分支和光束句柄。字面引用可能出现在数据表内。绕过客户端 Lua 的引擎复制声音仍可能无法观察。
- `hurt_fallback` 默认 OFF，`combat_fallback` 默认 OFF。各自显式开启后才使用复制受击事件或近战动作确认来估计反馈。复制动作确认无法证明伤害或对应原声。
- `player_only` 先检查本地归属。经过核实的 FrontEnd/FocalPoint 声音、UI 和已审计的世界天气声音不按世界距离衰减。其他空间事件按听者位置衰减。实际输出仍受模式、Profile、暂停、控制器和强度配置影响。

### 兼容包络

- CSV 从 Lua 5.1 执行的运行时 registry、profile 和匿名循环路径取得包络。脉冲数组每项为 [延迟秒数, 时长秒数, 相对幅度]，字段 `profile_total_s` 为运行时声明的总时长。具名循环另列采样间隔和每次脉冲宽度。
- 数值为兼容映射、配置倍率、距离、参数和手柄响应调整前的 profile。部分包络来自已提取的 WAV RMS 采样。报表无法证明逐样本波形、引擎路由或物理马达响应。
