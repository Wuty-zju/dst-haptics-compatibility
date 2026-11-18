# 证据索引 / Evidence register

复核于 2026-11-18。维护起点为 1.5.0，本轮基线为 1.6.1 发布后的 main `5b8c3b5`。
本索引记录结论的来源和边界，不把聊天或报告中的断言自动升级成复测证据。

| ID | 结论 | 证据类别与日期 | 材料 / 局限 |
|---|---|---|---|
| E01 | 维护开始时最新正式 GitHub Release 为 1.5.0 | 当时远端 API 与 Git refs 核对 | [1.5 Release](https://github.com/Wuty-zju/dst-haptics-compatibility/releases/tag/v1.5.0)；后续1.6发布见E15 |
| E02 | 发布 ZIP 37,400 字节，本地 hash 与线上 digest 一致 | 当次直接 hash + GitHub API | 本地 outputs ZIP/checksum；未重新下载二进制，不宣称网络下载复验 |
| E03 | Workshop item 3805091756 已被游戏加载 | 11月7日原始 client_log，11月15日复制和hash | 原始日志行186、280；本机 Workshop 内容目录存在；网页公开状态/作者未核实 |
| E04 | 当前本机原版 506 定义/503 唯一事件 | 11月15日从当前安装 bundle 提取 | 游戏762172、Steam build26474873；原始脚本只保存在本地 |
| E05 | 相对旧快照新增14个唯一事件，无删除、既有最终定义无文本变化 | 当次单行定义静态比较 | [当前快照摘要](../audit/DST-Haptics-Snapshot-2026-11-15.md)；不是逐事件局内触发证明 |
| E06 | 维护源码的语法/逻辑/原版数据验证 | 当次执行，结果见 [工作区报告](../reports/2026-11-15-workspace-review.md) | 原始 JSON 位于新会话证据目录；自动测试不能证明马达和引擎实机覆盖 |
| E07 | 旧审计492/489和源码引用统计 | 历史输入hash与CSV本次核对 | [1.4审计](../audit/DST-Haptics-Audit-Summary-1.4.0.md)；390个字面引用不是实际触发率 |
| E08 | 9月发布、微基准、枚举、安装与加载 | 历史执行记录 | [开发记录](../notes/1.5.0-progress.md)、[审核](../reports/1.5.0-review.md)、[收据](../reports/1.5.0-release-receipt.md)；部分原始输出未归档 |
| E09 | Xbox底层输出曾成功 | 用户提供的历史实测事实 | XInputSetState 与 TheInputProxy:AddVibration 成功；不是本次完整设备/玩法验收 |
| E10 | 完整真实硬件矩阵未完成 | 明确保留的未验收项 | [硬件矩阵](../HARDWARE_MATRIX.md)；DS4/DS5代码路径测试和枚举不代替实际震动 |
| E11 | 旧工作材料移位后内容未变 | 当次逐文件移动后hash核对 | archive/2026-11-15/manifest.json；4,363文件，305,882,850字节，只归档未永久删除 |
| E12 | 1.6按有效代码重新审计：406唯一event有字面引用，97没有 | 11月15日排除Lua注释后重新运行 | [14新增事件触发路径](../audit/1.6.0-trigger-paths.md)；不覆盖历史407/96原始报告 |
| E13 | 当前Steam build26474873被官方接口确认为最新可列出版本 | 11月15日UpToDateCheck直接响应 | success/up_to_date/version_is_listable均true；本地pr1-merge-review/steam-up-to-date.json |
| E14 | 1.6重构的原版数据、集成与语言回归 | 新版本审核和CI | [1.6审核](../reports/1.6.0-review.md)；光束远程句柄可见性和物理体感尚未实测 |
| E15 | 1.6.0正式发布，线上附件已重新下载并核对 | 11月15日GitHub API、工作流、下载hash和Git blob比较 | [发布凭证](../reports/1.6.0-release-receipt.md)；不代表已经更新Steam Workshop |
| E16 | 当前输入不变；完整字面量审计404有引用、99没有，14新事件来源不变 | 11月17日新采集/hash、Steam接口及修正审计 | [1.6.1复审](../reports/1.6.1-review.md)；旧406/97包含前缀误计，不覆盖历史证据 |
| E17 | 同VM旧API、实体引用/观察和暂停屏幕缺陷已复现并修复 | 四条独立PR、回归和集成验证 | 17 PASS、18项Python；没有新1.6.x实机日志或马达验收 |
| E18 | 两份旧候选构建归档后内容不变 | 11月17日45文件大小和SHA-256复验 | archive/2026-11-17/manifest.json；outputs和原始证据保持原位 |
| E19 | 1.6.1正式发布，线上3附件重新下载并匹配digest/tag | 11月17日Release API、CI、下载及逐Lua Git blob比较 | [发布凭证](../reports/1.6.1-release-receipt.md)；未安装本地Mod、未更新Workshop、未新做马达验收 |
| E20 | 本机原版与留存快照的 4,109 个文件逐项同名同字节，Steam 确认 build26474873 为最新 | 本日实读 ZIP、两个 hash 与官方 UpToDateCheck | installed-source.json；[本版审查](../reports/1.6.2-review.md) |
| E21 | 两份新客户端日志共 14 次加载及初始化 1.5.0。第三份与旧样本字节相同 | 本机原件、工坊 modinfo、原行号和 SHA-256 | log-evidence.json；无本版物理马达记录 |
| E22 | 切回原生发送多余 Stop、暂停校准跨设备、天气同帧重复重混以及洞穴雨固定增益 | Lua 5.1 修复前后回放，原生组件及状态图行号 | [四项独立复审](../reports/1.6.2-review.md)；调用次数和幅度属于代理测量 |
| E23 | 当前原版 503 行全量表来自实际 Lua 包络与同一份原版输入，统计 30 个循环和 104 个 RMS 包络族事件 | 本机当前原版事件与运行时逐行核对 | [字段与统计](../audit/DST-Haptics-Audit-Summary-1.6.2.md)；[完整 CSV](../audit/DST-Haptics-Event-Audit-1.6.2.csv) |
| E24 | 上版候选 26 个文件按清单归档。本机复核三个日期清单共 4,434 项与先前两个正式 ZIP 的 checksum | workspace-inventory.json，逐项 SHA-256 | 新归档清单在 archive/2026-11-18/manifest.json |
| E25 | 1.6.2 标签和最终 PR 的代码树一致，线上三个附件的 hash 匹配。23 文件白名单通过，18 个 Lua 与标签逐字节一致 | GitHub Release、下载结果、本地校验、标签与 CI | [发布凭证](../reports/1.6.2-release-receipt.md) |

## 输入和成品哈希

| 输入/产物 | SHA-256 |
|---|---|
| 1.5.0 发布ZIP | `240dc01da7bce4601f6264759002b00c0cb76ce7c971cee9f287f16329468041` |
| 1.5.0 Workshop preview | `b9710dce343bf80b799b7ace57a61cffed013eee97f9c01795238a28a8118cbb` |
| 当前 scripts.zip | `733a0f7f97ace5a76aa5acee95405a6ec01697d93d844eeb4ecce7c001306980` |
| 当前 haptics.lua | `e54ee51bd9cf3c0a682375dc5c5962b1e3eaa3307e131fc61c5088d3cc70f5b0` |
| 9月旧 haptics.lua | `9fc8b8637971daceb71cadca1ef15a3b6d46218c7f39729c767eb51dffa7063c` |
| 归档manifest | `94e817c842e6d03972dcd2bf7b46f14a3b06b3bbd9692573367fa1f91aff6572` |

## 本地原始材料

11 月 18 日复核位于 `.local/evidence/2026-11-18-review/`，其中记录已逐文件核对的原版路径、安全归档的日志和新的回归结果。

早期采集：`.local/evidence/2026-11-15-baseline/`，包含 snapshot.json、client_log.txt、
github-release.json、native-delta.json、native/scripts/ 和 audit/。这些材料忽略不提交。
测试的 JSON 与实际命令单独保留，路径见工作区报告。

归档：`archive/2026-11-15/`，包含旧 work、旧 build、历史 outputs 和完整路径/hash清单。
外部手工卸载备份仍位于用户的 DST Mod Backups 目录，没有移动或删除。

## 新证据的最小字段

结论、观察日期/日志会话日期、Mod提交、游戏版本/build、输入hash、命令与退出码、
原始材料位置、PASS/FAIL/SKIP、适用范围。硬件加设备型号/连接/Steam Input/配置。
没有记录的写“未知/未测”，不从“没报错”推导“所有事件都正确”。

原版定义统计和去重事件统计分开：9月492定义对应489唯一事件，11月506对应503。
源码字面引用仅是静态可追溯线索，不能证明调用一定到达客户端Lua；波形相似候选也
不能替代FMOD bank的精确映射。未来原生Windows输出是否修复需要重新测试，历史故障
结论不能无限期沿用。

English: direct observations, historical assertions, static analysis, simulated tests
and physical acceptance are separate evidence classes. Keep raw logs local and retain
hashes, dates, build identifiers and explicit limitations in public summaries.
