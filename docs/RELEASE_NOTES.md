# DST Haptics Compatibility 1.5.0

状态：1.5.0 发布版。按用户要求缩减实机流程，保留代码回归、包校验与一次真实加载检查。

## 本版变化

- 总体及工具、战斗、危险、玩家、Boss、环境、界面、循环支持独立强度和时长设置；0%–200%，每档 5%，默认 100%。
- 手柄专用适配默认开启，可切换通用响应；保留 Xbox、DS4、PS5/DualSense 的多段包络与强弱层级。
- 单次包络同步缩放宽度与间隔；循环贡献分别到期，保留声音停止语义。
- 设置、暂停与断连使旧震动尾部失效；暂停期间的新声音不会在恢复后补震。
- 其他玩家的特殊受伤反馈不再抑制本地通用受击。
- 统一配置和倍率模块，缓存原版包络，循环混音改为 O(n log n)。
- 重写中文说明，单列英文说明；增加原创线条图标及游戏内纹理。

## 验证与边界

Lua 5.1 语法与全部行为测试通过；492 条本机原版定义完成双轴全档位检查（40,344 次断言）。三类手柄的数值层级、钩子共存、重复加载和生命周期已自动测试。

100% 是未增加用户倍率的原版兼容基准。精确原生马达波形、绝对时长与物理体感不能由 Lua 自动证明。DS4/DS5 实际输出仍依赖 DST/Steam Input 提供通道；不提供 DualSense 自适应扳机或原生高频触觉。

安装文件已与构建包核对。连接 DualSense 时启动 DST，日志确认 Version:1.5.0 与 492 条定义/489 个唯一事件初始化成功，未发现本模组加载错误。未执行三类手柄完整物理体感矩阵。完整状态见 docs/reports/1.5.0-review.md。

## 安装

解压至 `Don't Starve Together/mods/dst_haptics_compat`，启用客户端模组和原版“控制器震动”。F8 或手柄暂停菜单快捷键进入局内配置。避免同时开启本地和 Workshop 两份副本。

## English

Version 1.5.0 adds independent intensity and duration controls from 0% to 200% in 5% steps, optional controller-family adaptation, independent loop lifetimes, stale-pulse cancellation, cached native profiles and original minimal artwork. Chinese and English guides are separate.

Automated Lua 5.1 checks pass, including 40,344 native-definition tuning assertions. DST successfully loaded version 1.5.0 while DualSense was connected. The user requested reduced physical testing; a complete Xbox/DS4/DualSense feel matrix was not performed. The 100% reference is the native-compatible envelope baseline, not a claim of sample-exact native motor output.
