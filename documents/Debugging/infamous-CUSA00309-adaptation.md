<!--
SPDX-FileCopyrightText: 2026 shadPS4-AYOUB1080p contributors
SPDX-License-Identifier: GPL-2.0-or-later
-->

# inFAMOUS Second Son 港版 1.07 适配

## 支持范围与证据

本次适配针对用户提供的 CUSA00309、APP_VER 01.07、CONTENT_ID
`HP9000-CUSA00309_00-SECONDSONSHIP000`。`eboot.bin` 为可直接读取的 SELF，文件大小
17,079,995 字节，SHA-256 为：

```text
2d1ca79630d7bbe6fa29575f59aa7996d43071d74ac8e4f7d40137967d9039ab
```

对照欧版 1.00 原有补丁，11 项补丁的 48 条修改、27 个独立地址均通过了原始字节
FNV-1a 校验，因此这份港版程序可沿用这些地址和修改值。这不代表两份完整游戏程序相同，
也不代表未经核对的其他港版更新可以直接使用。

另行核对了需要地址关联的部分：

- 碰撞保护代码空洞 `0x010c5680` 是可执行段的零填充对齐区域，128 字节空间未占用。
- 碰撞计数器 `0x083a5500` 在可写段的零填充对齐区域，初始值为零。
- 两个入口跳转分别进入代码空洞起点和 `+0x40`；三个返回跳转正确指向原指令续接位置。
- 两组 FOV 补丁中的四个 RIP 相对引用均指向 `0x010c5720`，该常量空洞未占用。

完整的哈希、段映射及跳转证据见 [审计报告](infamous-CUSA00309-audit.json)。报告只包含
标识、地址、校验值与修改信息，不包含原始游戏字节或密钥。分析工具使用系统 Python
标准库，不写入游戏目录，也不需要安装反汇编或 ELF 解析依赖。

## 已完成的项目改动

1. `ApplyGameProfile` 将 CUSA00309 纳入模拟器优化：回读队列、线程化记录/上传、缓存复用、
   遮挡查询、跨 wave 屏障、GPU 时钟节奏等。图形管线异步编译，计算管线同步编译。
2. 新增 `package/user-files/custom_configs/CUSA00309.json`：PS4 Pro 模式、精确回读、
   512 MiB 额外直接内存、管线缓存、Windows guest red-zone 栈保护。
3. 新增 `inFAMOUS Second Son CUSA00309.xml`，并注册至补丁索引，准确匹配港版 APP_VER 01.07。
   11 项原有功能均已移植：动态质量阈值、碰撞循环保护、4K 灯光列表、城市块 streaming、
   基础 PS4 的 1440p/4K、PS4 Pro 的 1440p/1800p/4K，以及两种 FOV。
4. 港版 01.07 获得内置棋盘格关闭修复。该修复检查版本、地址范围及原始字节校验；
   外部补丁已做相同修改时，不再重复写入。

发布配置默认开启 PS4 Pro 原生 **3200×1800**，与欧版原有默认值一致。4K 为可选项，
扩大灯光列表的补丁默认开启。一次只能选择一个分辨率补丁；基础 PS4 的分辨率补丁
需要关闭 `neo_mode`。源码改动需编译新程序才能生效，下面的启动脚本也可让现有 AYOUB 1.0
通过其已经支持的 XML 和 `perf_tuning.ini` 接口加载等价的适配设置。

## 使用现有 AYOUB 1.0 运行

在项目根目录的 PowerShell 中执行以下命令。脚本默认使用用户已提供的模拟器和游戏路径。
也可通过 `-EmulatorPath`、`-GameDirectory` 指定现有文件。用户目录自动选择程序工作目录下
已有的 `user` 便携目录，否则使用 `%APPDATA%\shadPS4`。`-UserDirectory` 只能指定符合这个
原生选择规则的目录；现有程序不支持通过 `--override-root` 更改用户配置目录，该参数控制
的是游戏挂载根目录。

```powershell
.\scripts\run_infamous_hk.ps1 -Resolution 1800p
```

选择其他分辨率：

```powershell
.\scripts\run_infamous_hk.ps1 -Resolution 1080p
.\scripts\run_infamous_hk.ps1 -Resolution 1440p
.\scripts\run_infamous_hk.ps1 -Resolution 4k
```

### 本机 BAT 性能对照启动

当前 BAT 使用本项目 `Build\x64-Clang-Release\shadps4.exe` 和
`D:\game\shadPS4QtLauncher\games\CUSA00309` 时，可直接双击：

- `scripts/launch_infamous_1080p.bat`：基础 PS4 模式、原生 1920×1080，关闭所有升分辨率补丁。
- `scripts/launch_infamous_4k_pro.bat`：PS4 Pro 模式、原生 3840×2160，启用 Pro 4K 补丁，
  关闭棋盘格及其他分辨率补丁，保留扩大灯光列表的补丁。

两者使用同一组既有 inFAMOUS 优化和 `-Performance` 配置：开场栈保护、精确回读、
异步回读与上传、线程化记录、图形管线异步编译及管线缓存。新构建并行创建计算管线，
在执行对应任务前等待编译完成，保留所有计算任务。
自动优先选择支持所需 Vulkan 版本的独立显卡，使用无边框全屏、60 Hz 游戏时钟和 FPS
显示，关闭 FSR、诊断采样、调试导出、RenderDoc 与 Vulkan 验证层；日志仅保留
error/critical，异步写入，上限 16 MiB。

BAT 应留在本项目的 `scripts` 目录中，依赖同目录的 `run_infamous_hk.ps1` 和项目中的
港版配置、XML 补丁及 tuning 文本。使用系统 Windows PowerShell；执行策略 Bypass
仅作用于本次 PowerShell 进程。无需重新构建模拟器，也不安装工具或修改系统设置。
`-Performance` 不能与 `-Diagnostic` 或 `-SynchronousReadbacks` 同时使用。

每次只启动一个脚本，保留命令窗口，正常关闭游戏并等到显示配置已恢复后再切换另一模式。
两个模式复用相同的用户目录、存档、输入设置和现有缓存，不改动游戏文件。
请在相同存档和场景下比较，记录首次进入与重复进入后的帧率和卡顿差异。
1080p 已进行用户游玩和隔离存档测试；本轮没有验证 PS4 Pro 原生 4K 的图像与性能。

性能诊断版为 `launch_infamous_1080p_debug.bat` 和 `launch_infamous_4k_pro_debug.bat`，
使用同一 EXE 和优化，增加 CPU/GPU 采样及退出后的独立报告。
使用方法、当前三次停顿的证据和下一轮测试重点见 [性能诊断说明](infamous-performance-diagnostics.md)。

### 缓存和预热改造

后台持久化、计算/图形管线启动预热、驱动缓存和自动内存预算，以及两轮对照命令，
见 [缓存与预热说明](infamous-cache-prewarm.md)。需要新的构建才能生效；
`-Performance -CacheDiagnostic` 可保留简要缓存和慢帧日志，用于比较复用效果。

脚本先核对游戏程序完整 SHA-256，然后只临时调整以下三个文件：

- 用户目录的 `custom_configs/CUSA00309.json`；
- 用户目录的 `patches/shadPS4-AYOUB1080p/inFAMOUS Second Son CUSA00309.xml`；
- 用户目录的 `perf_tuning.ini`。

配置、补丁及 tuning 文本合计约 16 KiB。原有内容保存在脚本进程内存中，正常退出游戏后
恢复；原本不存在的文件会被移除。游戏可能生成其正常的管线/着色器缓存，其大小取决于
实际场景。脚本不安装任何工具，不修改游戏文件、全局 PATH 或用户环境变量。运行时请保留
该 PowerShell 窗口，正常关闭游戏让脚本完成恢复。为避免共用 tuning 设置，运行前关闭其他
shadPS4 实例。

## 开场问题：栈保护对照已通过

用户于 2026-10-11 22:23 使用官方 0.19.0、1080p 和 `-ProtectGuestStack` 实测，已越过
固定天空并进入体感提示。日志确认保护开启，短 CPU 补丁 73/73 应用、0 个不支持。
港版配置和脚本现默认开启该保护，常规启动无需再添加 `-ProtectGuestStack`。目前验证
范围为进入教学；随后 22:28 的 AYOUB 1.0 复测也已通过，日志确认保护与同组优化生效。
完成喷漆及更高分辨率仍待实测。
以下保留此前排查过程，详细证据见 [开场记录最新结果](infamous-CUSA00309-intro.md)。

第一轮未移植补丁的实测已经确认：仅开启精确回读仍会卡在天空，而且卡住发生在体感
提示出现之前。因此尚不能将 Xbox 缺少体感视为开场问题的主要原因。

先以 1080p 降低分辨率变量，启用完整适配和内置采样：

```powershell
.\scripts\run_infamous_hk.ps1 -Resolution 1080p -Diagnostic
```

1. 到达天空或可交互的开场提示后，回到 PowerShell 按 Enter。
2. 脚本动态触发两帧 GPU 命令追踪；继续运行至少 40 秒，确保覆盖线程热点采样周期。
3. 正常关闭游戏，读取 `%APPDATA%\shadPS4\log\CUSA00309.log`。

2026-10-11 21:53 的运行已确认补丁和优化加载成功，开场仍停在天空；两帧命令追踪有效，
末尾约 60 FPS。进一步证据见 [开场排查记录](infamous-CUSA00309-intro.md)。用户确认官方
模拟器同样卡住，因此调查优先转向共有的手柄读取、开场资源加载及游戏流程等待条件。
当前诊断没有记录游戏收到的体感数值或资源加载完成事件，热点统计也不等于完整线程栈。

随后对照用户提供的 `D:\projects\infamous2ndson_pc`，找到更具体的动画栈保护线索：
该引擎对同一港版主程序的 `0x892a80–0x894886` 函数实施栈内空间保护，并记录相机 NaN
修复后进入喷漆教学。当前官方运行日志显示已有 Windows 栈保护关闭。脚本新增显式
`-ProtectGuestStack` 开关，用于临时启用已有保护，随后用户验证成功并改为默认启用；具体证据和官方模拟器
对照命令见 [开场排查记录](infamous-CUSA00309-intro.md#与可进入喷漆场景的本地引擎对照)。
视频播放问题已按用户提供的复现范围移出主线。

`-SynchronousReadbacks` 开关仍保留为后续排除工具：关闭异步回读、独立回读队列和回读
预取，其他适配设置沿用原配置。该对照尚未执行，暂不作为用户下一轮操作，也不能单独
验证共有逻辑是否正确。诊断脚本现同时开启真实 GPU 时间采样。

日志上限 16 MiB，新运行可能覆盖同名日志。该轮输出包括模拟器配置、补丁应用结果、
线程 CPU 占用、活跃线程热点、GPU 等待和回读统计及两帧命令记录。不会请求完整内存
dump 或原始图像/缓冲区文件；低 CPU 占用的等待线程不一定进入热点采样，若仍不足，
再通过已有调试器采集全部线程调用栈。Release 程序已包含上述采样，不必先编译 Debug。

运行日志应包含 APP_VER 01.07、`readbacksMode: 2`、多条 `Applied patch`，以及
`Perf threads`、`Perf readback` 和 `DUMP` 等信息。1080p 下 `isNeo: false`，其余三种模式下
`isNeo: true`。脚本选用外部补丁，因此现有 AYOUB 1.0 不出现港版内置修复日志是正常现象。

## 验证状态

鼠标体感、鼠标按键单指/双指和 Windows 原生触摸板另已完成源码移植，尚未构建或验证。
需要重新编译程序，不能通过旧二进制的配置启用新增实现；操作及独立测试命令见
[输入移植说明](infamous-mouse-input-port.md)。

用户第一次执行启动脚本时，程序在加载游戏前退出。`shadps4.log` 明确记录：脚本把
`--override-root` 指向了配置目录，导致游戏文件无法相对该目录解析。已移除该参数，固定
启动工作目录，并增加早期退出和新日志错误报告。同时移除 `-i`，保留游戏更新资源加载；
`-p` 已明确选择港版 XML。该次失败没有进入补丁应用阶段，不能用于判断移植后的游戏行为。

已完成只读游戏文件分析、原始字节校验和补丁跳转/映射核对。Codex 未编译项目或代跑游戏。
此前 1080p 港版补丁和同组优化加载成功仍卡住；随后用户在官方 0.19.0 上启用 Windows
栈保护，已进入体感提示；随后 AYOUB 1.0 使用默认保护配置复测也已通过。当前 PS4 Pro
的 1440p/1800p/4K 运行及后续游戏流程仍未验证，不能宣称全部游戏流程可玩或已达到
稳定 4K/60 FPS。

可在系统现有 Python 环境重新核对：

```powershell
python -B .\scripts\analyze_infamous_patches.py 'D:\game\shadPS4QtLauncher\games\CUSA00309'
```

若游戏文件改变，必须重新分析，不要跳过校验强行应用补丁。
