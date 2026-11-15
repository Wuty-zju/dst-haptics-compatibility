# 原版快照复核 / Native snapshot — 2026-11-15

维护基线：Mod1.5.0 / cd4f1a2。原版输入：当前本机正式安装，游戏762172、
Steam build26474873。没有重新启动游戏或执行本次物理手柄测试。

| 项目 | 9月历史快照 | 11月当前快照 |
|---|---:|---:|
| 定义 | 492 | 506 |
| 唯一事件 | 489 | 503 |
| 有源码字面引用的唯一事件 | 390 | 407 |
| 无源码字面引用的唯一事件 | 99 | 96 |
| 原版WAV资源数 | 1722 | 1762 |
| profile/分类双轴41档自动断言 | 40,344（历史记录） | 41,492（本次执行通过） |

当前hash：haptics.lua `e54ee51bd9cf3c0a682375dc5c5962b1e3eaa3307e131fc61c5088d3cc70f5b0`。
完整bundle hash见 [证据索引](../maintenance/EVIDENCE.md)。
原始数据与审计输出位于本地 `.local/evidence/2026-11-15-baseline/`，不分发原版源码/WAV。

当前唯一事件分类：BOSS180、PLAYER232、DANGER13、ENVIRONMENT53、UI22、未指定3。
若按506条定义统计，BOSS181、PLAYER234；两个口径不能混用。

## 新增事件

以下14项均为原版BOSS分类、vibration_intensity=1，未设置player_only。
旧事件无删除；按每个event最终定义的整行文本比较，既有定义未变。
行号属于本次原版快照，后续更新可能变化。

| event | 原版表行 | 字面引用数 | 一个原版来源 |
|---|---:|---:|---|
| rifts8/charlie/attack_aoe | 645 | 1 | stategraphs/SGcharlie_boss.lua:749 |
| rifts8/charlie/ground_hit | 646 | 5 | stategraphs/SGcharlie_boss.lua:462 |
| rifts8/charlie/rise_pst_1 | 647 | 1 | stategraphs/SGcharlie_boss.lua:326 |
| rifts8/shrouden/taunt | 648 | 1 | stategraphs/SGshrouden.lua:617 |
| rifts8/shrouden/taunt2 | 649 | 1 | stategraphs/SGshrouden.lua:732 |
| rifts8/shrouden/opticblast_LP | 650 | 2 | prefabs/shrouden_optic_blast.lua:238 |
| rifts8/shrouden/opticblast_big_LP | 651 | 2 | prefabs/shrouden_optic_blast.lua:349 |
| rifts8/shrouden/portal_punch_pre | 652 | 1 | stategraphs/SGshrouden.lua:1330 |
| rifts8/shrouden/death_a | 653 | 2 | stategraphs/SGshrouden.lua:908 |
| rifts8/shrouden/death_b | 654 | 1 | stategraphs/SGshrouden.lua:909 |
| rifts8/shrouden/charlie_death | 655 | 1 | stategraphs/SGcharlie_boss.lua:795 |
| rifts8/shrouden/spawn | 656 | 0 | 未找到字面引用，需调查动态/引擎路径 |
| rifts2/shrouden/pillar_explode | 657 | 1 | prefabs/charliearena_spike.lua:307 |
| terraria1/mini_eyeofterror/egg_crack | 658 | 5 | prefabs/eyeofterror_mini_projectile.lua:116 |

当前重复event仍为bodyfall_dirt、iceboulder_smash、alterguardian3/atk_beam，共3项。
profile测试通过说明它们能进入当前代码的数据处理路径，不代表13个有字面引用的新事件
都一定从客户端Lua触发。须进一步区分服务器SG、引擎复制、客户端可观察prefab和具名循环。
本报告不把“存在原版调用”当成“实际手柄震动通过”。
