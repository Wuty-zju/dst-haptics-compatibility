# DST Haptics Compatibility 1.6.1

现有行为的稳定性维护版。保留 1.6.0 的事件资格、强度/时长、全部配置键与严格默认；
不新增震动事件、设置、设备能力或游戏逻辑。

Maintenance of existing behavior: no new event mappings, settings, controller
capabilities or gameplay changes. Saved configuration and strict defaults remain compatible.

## 修复 / Fixes

- 失活适配器不再因迟到的关闭/设置调用停止新实例；世界监听精确解绑，重装绑定当前世界，退出清除旧监听坐标。
- 动作桥按玩家/世界释放监听、监控和引用，避免换身后长期持有移除对象；重装后仍能观察之后激活的本地玩家。
- 存活光束重装后恢复真实loop/bigloop句柄观察；仅安装时访问现有实体，不添加周期扫描或动画猜测。
- 已打开暂停界面的快捷键与中英文提示切换到当前实例；复用原包装，保留其他Mod及新所有者。
- 静态审计匹配完整Lua字符串，纠正前缀误计；拒绝覆盖证据及空输入，静音WAV保留零包络。

Inactive adapters cannot stop a replacement. Entity-owned observers and references
are released on removal. Existing worlds, beams and pause shortcuts rebind safely
after reload without stacking wrappers. Audits use exact Lua literals and preserve
prior evidence instead of overwriting it.

## 验证 / Validation

Four isolated fixes were reviewed in PRs #3–#6 before release integration.
Local Lua 5.1 verification: **17 PASS, 0 FAIL, 0 SKIP**, including 506 native definitions,
41,492 tuning assertions and 18 Python regression tests. Current input is still
DST 762172 / Steam build 26474873; official Steam UpToDateCheck returned up_to_date=true.

The corrected static audit finds **404 referenced / 99 unreferenced** unique events;
this is a source-reference correction, not a change to supported runtime events.
All 14 newer definitions and their source locations remain unchanged.

[Detailed review / 详细审查](https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v1.6.1/docs/reports/1.6.1-review.md)
· [Native trigger audit / 原版路径](https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v1.6.1/docs/audit/1.6.0-trigger-paths.md)

## 边界与安装 / Limits and installation

本轮没有新的1.6.x客户端日志或物理马达验收；最新保留日志是11月7日的1.5.0。
自动回归不能证明USB/蓝牙体感、远程光束句柄可见性或每个Boss的局内触发。
包络、空间和设备曲线仍为已披露近似，DS4/DS5需DST/Steam Input提供Legacy Rumble。

No fresh game launch or physical controller test is claimed. Exact native waveforms
and remote server-only event observability retain the documented limits.

Download the named release ZIP and checksum, or subscribe to
[Workshop item 3805091756](https://steamcommunity.com/sharedfiles/filedetails/?id=3805091756).
GitHub publication does not update Steam. The author must update this existing item
separately; avoid duplicate manual/Workshop copies.
