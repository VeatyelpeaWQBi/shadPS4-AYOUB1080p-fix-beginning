<!--
SPDX-FileCopyrightText: 2026 shadPS4-AYOUB1080p contributors
SPDX-License-Identifier: GPL-2.0-or-later
-->

# inFAMOUS Second Son 港版 1.07 开场喷漆卡住：排查记录

## 最新结果：两个构建均已进入体感提示（2026-10-11 22:28）

用户使用官方 shadPS4 0.19.0、1080p 和 `-ProtectGuestStack` 实测，已越过固定天空，进入
体感提示。最新日志 241,103 字节，最后写入北京时间 22:23:31，确认官方 revision
`c7e065d1b415be16c23e260a21f1dd8bbfc4cb57`、`isRedZonePatchingEnabled: true`、精确回读
和基础 PS4 模式。启动统计显示 eboot 的 73/73 短 CPU 补丁全部应用、0 个不支持；
6,097/6,104 条候选内存指令受到保护，另有 7 条不可重定位，日志明确说明覆盖为 partial。

用户随后使用默认启用保护的港版脚本复测 AYOUB 1.0，同样进入体感提示。该轮日志
541,689 字节，最后写入北京时间 22:28:20，确认 revision
`153a5aa7f6b6be0e547d46719b793cb5145571d7`、Remote 为 weshayoub92 的 AYOUB 仓库、
`isRedZonePatchingEnabled: true`、基础 PS4 模式、精确回读及同组性能 tuning 生效。
栈保护覆盖统计与官方对照相同：6,097/6,104 内存指令、73/73 短 CPU 补丁、0 个不支持。

这两次验证确认：在该用户的官方及 AYOUB 构建运行条件下，启用 Windows guest red-zone
保护能解除开场固定天空阻塞。结合另一引擎的动画栈修复记录，证据支持 Windows 栈兼容
问题；当前运行尚未直接捕获相机 NaN 或证明唯一故障指令就是 `0x892a80` 函数中的 EXTRQ。
不能把开关生效描述为全部代码都已受保护。

港版随包配置和启动脚本现默认启用 `General.redzone_patches: true`，兼容旧配置中的
StaticPatching 模式。`-ProtectGuestStack` 参数仍接受，常规启动无需再添加。配置仍在游戏
退出后恢复；原始游戏和另一引擎未被修改。用户已验证两个构建进入体感提示，尚未验证
完成喷漆教学、后续剧情或 4K/60 FPS。下面保留各轮调查的历史证据。

## 已核对的证据（2026-10-11）

- 用户复现于 CUSA00309 / 01.07：开场喷漆阶段停在固定天空画面，声音和暂停菜单仍正常；使用 Xbox 手柄。AYOUB1080p 1.0 和官方 shadPS4 0.19.0 均出现问题。
- 用户提供的 AYOUB 可执行文件旁的 SOURCE.txt 指向 `153a5aa7f6b6be0e547d46719b793cb5145571d7`，为 Release 构建。
- 本机现存 `%APPDATA%\shadPS4\log\shad_log.txt` 最后写入于 2026-10-09 00:05。它记录的是官方 0.19.0、revision `c7e065d1b415be16c23e260a21f1dd8bbfc4cb57`，不能当作 AYOUB 构建的运行证据。
- 该日志确认 CUSA00309 / 01.07、`Game-specific config used: false`、`GPU readbacksMode: 0`、`General isNeo: false`；同时记录了 gyro 和 accel 初始化失败。机器为 i9-14900HX / RTX 4090 Laptop GPU / 64 GB RAM。
- 初次检查时，用户的标准用户目录中没有 CUSA00309 专用配置，全局配置为 `readbacks_mode: 0`。
- 初始源码的自动优化名单仅包括 CUSA00004 和 CUSA00223；它不负责启用精确回读。随包的欧版配置单独设置 `readbacks_mode: 2`。
- `src/core/emulator_settings.h` 中回读模式分别为 0 Disabled、1 Relaxed、2 Precise，默认 0。
- 初始游戏补丁 XML 的目标为 CUSA00004 / APP_VER 01.00，内置棋盘格修复也仅匹配 CUSA00004。移植前必须先核对港版程序，不能仅修改标题 ID 或版本号。
- 上游 [issue #3728](https://github.com/shadps4-emu/shadPS4/issues/3728) 是开场喷漆卡住问题；报告者于 2026-07-28 表示修复有效。关联 [PR #4742](https://github.com/shadps4-emu/shadPS4/pull/4742) 于 2026-07-23 合并，涉及文件读入宿主缓冲区再复制到游戏内存，以避免读取失败及竞态。本项目 `src/core/libraries/kernel/file_system.cpp::ReadFile` 已有这类中间缓冲区处理。这个事实不能证明全部地区、更新版本和运行配置都通过了开场测试。

## 早期判断（栈保护对照前）

用户已完成第一轮验证：2026-10-11 20:14 的 `CUSA00309.log` 确认运行 AYOUB 1.0 / revision
`153a5aa7f6b6be0e547d46719b793cb5145571d7`，专用配置生效，`readbacksMode: 2`、`isNeo: false`。
开场动画结束后直接停在天空，画面仍有变化、声音和暂停菜单可用，尚未出现横握或摇罐提示。
因此“只要启用精确回读就能修复”已被本次复现否定；现阶段不能将 Xbox 缺少体感视为主因。
日志未记录 fatal exception 或 GPU device lost，末尾仍有 GPU 绘制和手柄相关 API 调用。

尚未证明港版可执行代码存在独有缺陷，也未证明 GPU 回读或体感输入是本次卡住的唯一原因。
声音和暂停菜单可用说明进程仍在处理部分游戏逻辑，优先调查游戏流程等待、GPU 结果回读和体感输入，而不是先采集整个进程的内存。
原作者的欧版 1.00 补丁、性能展示及测试配置，不能作为港版 1.07 功能完整或稳定 4K / 60 FPS 的证据。

## 移植后运行日志：2026-10-11 21:53

最新 `CUSA00309.log` 为 1,781,933 字节，记录了修正启动脚本后的有效运行。用户确认仍停在
天空、没有体感提示。日志验证了以下事实：

- 运行 AYOUB 1.0，港版专用配置已加载，基础 PS4 / 1080p、精确回读和管线缓存生效。
- 当前模式启用的 9 条修改全部 `Applied patch`：动态质量阈值 4 条、碰撞保护 3 条、
  灯光列表 2 条。未记录补丁校验失败或跳过。其余分辨率/FOV/streaming 选项按配置关闭。
- `Perf tuning applied` 确认同组优化设置已加载，`async_pipelines=1`、`readback_queue=true`、
  `threaded_recording=true`、`wave_memory_barriers=true`。
- 末尾五个性能窗口约 59.9–60.1 FPS、平均 16.6–16.7 ms，记录中没有非零 pipeline skips。
  这只是当前场景的刷新情况，不能证明开场流程能继续。
- 两帧追踪均完成：f0 为 1,624 条记录、387 次绘制、546 次 dispatch；f1 为 1,652 条记录、
  387 次绘制、574 次 dispatch。未见 `draw-skipped` 或 `dispatch-skipped`。
- 两帧的 392 个间接绘制参数探针全部 `same`。部分 GPU 复制源/目标为 `DIFF`，但探针比较
  的是记录时的 CPU 快照与 GPU 结果，且不少页仍为 `gpu1 pending1`；不能仅据差异判定错误。
- 最后一个 20 秒热点窗口记录 8,215 次回读，集中于游戏偏移 `0x3f3e00`、`0x3ff600` 和
  `0x171700`；回读正在发生。主线程部分采样落在 Windows 等待函数，不能单凭等待占比
  判断死锁，也尚未定位到具体的游戏流程条件。
- 未见 fatal exception、device lost、文件读取失败或 InvalidFileFourCC。`profile.bin` 首次
  缺失是缓存加载信息，日志末尾随后成功写入缓存。Xbox gyro/accel 初始化失败仍存在。
- 此轮 `gpu_profile=0`，所以 GPU busy/submission timing 的零值表示未采集，不能解释为 GPU
  实际闲置。诊断脚本现启用 `gpu_profile=1` 以取得真正的 GPU 时间数据。

结论：本次运行进入游戏，当前启用的补丁加载成功；港版补丁及同组优化没有解决这次开场
卡住。现有证据尚未定位游戏流程等待的具体条件。

## 调查方向修正：优先检查共有路径

用户再次确认官方模拟器也出现相同现象。仅围绕 AYOUB 的性能改动排查，不足以解释这两次
复现。之前把分支特有的同步回读对照列为主线，证据不足；该对照现降为后续排除项，暂不
要求用户执行。两个构建的相同现象提高了共有模拟器逻辑、游戏资源及运行配置的调查优先级，
但本身还不能证明它们在相同游戏条件处失败。

补充只读核对：

- 对照本机官方日志对应的 revision `c7e065d1b415be16c23e260a21f1dd8bbfc4cb57` 的
  [controller.cpp](https://github.com/shadps4-emu/shadPS4/blob/c7e065d1b415be16c23e260a21f1dd8bbfc4cb57/src/input/controller.cpp)
  和 [pad.cpp](https://github.com/shadps4-emu/shadPS4/blob/c7e065d1b415be16c23e260a21f1dd8bbfc4cb57/src/core/libraries/pad/pad.cpp)：
  单样本返回最新状态、多样本读取历史队列，以及 `scePadReadState` 调用单样本读取的实现
  与本项目相同。这部分属于共有调查对象，尚未发现它造成本次卡住的证据。
- 现有 `Lib.Pad:debug` 日志记录了连接、重置朝向、灯光和振动调用，但没有
  `scePadRead` / `scePadReadState` 返回给游戏的数据。这两项调用当前使用 trace 级日志，
  而且该日志只记录调用，不记录体感数值。未出现体感提示也不能排除游戏在提示前读取
  手柄数据。既不能据此确认体感根因，也不能据此排除。
- 游戏目录旁未发现 CUSA00309 的更新或 mods 目录；当前目录内存在
  `sce_discmap_patch.plt`、补丁语言缓存和 01.07 的 SFO。最新日志中 42 个不同的 `/app0`
  只读打开路径均能在该目录找到。末尾包括开场影片 `v_vor_opening_no_text.bsf`、
  `vor_taggin_a10#tandem#0.xpps` 和 `graffiti_a8_family.xpps`。路径存在和打开记录不证明
  包内内容完整、读取长度正确或异步加载已完成；目前没有可信原始清单可作完整性比较。
- 官方旧日志使用回读模式 0，AYOUB 最新诊断使用模式 2。该差异需要在对照时记录，不能
  将两轮运行视为完全相同配置；也不能用它忽略官方同样卡住的事实。

接下来需要取得能区分原因的证据：动画退出到喷漆交互时游戏读取的手柄报告、开场资源的
读取结果和加载完成事件，以及游戏流程线程当时的调用栈和等待对象。现有两帧 GPU 追踪
与热点统计不足以给出这些信息，尤其热点采样不会完整覆盖低 CPU 占用的等待线程。
先定位等待条件，再选择针对输入、文件读取、同步或共有 GPU 回读路径的修复。
港版优化移植继续保留，但不再作为开场修复成立的证据，也不继续凭场景帧率推断根因。

## 与可进入喷漆场景的本地引擎对照

对照目录：`D:\projects\infamous2ndson_pc`。本轮仅只读源码、游戏文件及已有记录，未启动
引擎、调试器、构建或测试；没有修改该目录。用户明确指出该引擎在没有播放开场影片时也
可直接进入喷漆，因此视频播放修复不作为本次天空卡住的主线。

### 最强候选：Windows 异常破坏动画解码函数栈下临时数据

该引擎的 `docs/INFAMOUS_BRIGHT_SCREEN.2026-10-06.zh-CN.md` 记录：此前异常阶段中
相机父级骨骼来自游戏函数 `0x892a80–0x894886`，相机原点为 NaN。该函数同时使用负 RSP
临时数据和 AMD EXTRQ 指令；在 Intel/Windows 下，EXTRQ 异常交付可能覆盖栈下的
System V red zone 数据。实施明确栈空间保护后，记录的相机原点恢复为有限值，实际画面
恢复为主角站在广告牌前和「垂直握住無線控制器」教学提示。该次验证尚未实现体感输入。
这份记录证明了另一引擎的一次故障及其修复，不直接证明当前模拟器卡住的根因。
Windows 不保证保存当前栈指针以下的未分配数据，这一点也可对照
[Microsoft x64 stack usage](https://learn.microsoft.com/en-us/cpp/build/stack-usage?view=msvc-170)。

当前可独立核对的事实：

- 两个目录内原始 `eboot.bin` 的 SHA-256 完全相同，均为
  `2d1ca79630d7bbe6fa29575f59aa7996d43071d74ac8e4f7d40137967d9039ab`。
- 两份原始游戏中上述完整函数的 SHA-256 均为
  `9d47555a97b39e7cfd6cc8107712720cb5b514069779d623cb6b7c6b51927b75`，
  与 `scripts/infamous_cpu.py::protect_animation_leaf` 的严格校验相符。
- `link_modules.py` 在准备运行镜像时调用该保护函数，将原来 `0x3d8` 的栈帧扩为
  `0x458`，移动 10 处栈下操作数并调整 8 处传入栈参数；当前 `out/CUSA00309/link.json`
  记录 `windows_animation_stack_operands: 18`。原始游戏主程序不被修改。
- 本项目在 `cpu_patches.cpp::PatchesIllegalInstructionHandler` 对四字节 EXTRQ 使用
  异常解释路径；也已提供 `General.redzone_patches` 静态保护，但默认关闭。
- 当前 `CUSA00309.log` 已被另一轮运行覆盖：大小 2,614,779 字节，最后写入北京时间
  2026-10-11 22:09:18，运行官方 revision `c7e065d1b415be16c23e260a21f1dd8bbfc4cb57`。
  该轮明确记录 `isRedZonePatchingEnabled: false`、精确回读和基础 PS4 模式。
  不能将此文件与前述 21:53 AYOUB 日志当成同一次运行。
- 两个已安装模拟器程序均含 `redzone_patches`、`isRedZonePatchingEnabled` 和静态保护
  日志字符串，与本项目已有配置接口相符；二进制字符串本身不证明保护成功或覆盖完整。

因此先验证已有 Windows 栈保护是否改变开场，比继续调整分支性能参数更有直接依据。
脚本新增显式 `-ProtectGuestStack` 比较开关，仅在本次运行临时启用已有保护；退出后恢复
配置。初次加入时未默认启用；本次用户验证后已改为港版默认开启，详见顶部最新结果。
未移植另一引擎的函数地址补丁。

```powershell
& 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\scripts\run_infamous_hk.ps1' -EmulatorPath 'D:\game\shadPS4QtLauncher\versions\shadPS4v0.19.0.exe' -Resolution 1080p -Diagnostic -ProtectGuestStack
```

只运行一个模拟器，从相同的新游戏流程开始。沿用原有约 16 KiB 临时文件和 16 MiB 日志
上限；启用保护可能延长启动分析。检查 `isRedZonePatchingEnabled: true` 以及
`Windows guest red-zone static patching for` 的覆盖统计或 partial 警告。开关为 true 不保证
`0x892a80` 函数被完整保护。若仍卡住，应针对该函数的实际补丁覆盖、异常位置和相机数据
采样，再决定是否需要移植已审核的函数栈保护。

### 次级差异

- 未开启鼠标体感时，该引擎 `pad_motion.h::motion_step` 返回零加速度；本项目默认
  `accel_buf = {0, 9.81, 0}` 并在 `pad.cpp` 乘以 0.098，返回约正 Y 轴 0.96138。
  原始 HK 程序导入 `scePadReadState`，需核对故障时实际数据和消费条件，不能凭差异
  认定姿态检查导致了当前天空画面。
- 该引擎的 `game_profiles.py` 禁用 Second Son 地址补丁；当前开场可运行不能归功于
  AYOUB XML 里的碰撞保护或分辨率修改。
- 两边都基于 shadPS4 GPU 核心，但 Windows 系统接口、CPU 补丁及 GPU 反馈实现存在
  差异；不能把这次比较等同于“CPU 指令转译正确、GPU 一定无误”。

暂不需要两个游戏同时运行或全进程/内核大快照。已有资料已给出具体函数和单变量保护
对照；若需动态采集，分别运行、对齐开场阶段，重点取得该函数异常、栈内数据、相机
有限性和游戏线程栈，而不是比较全部进程内存。

## 港版优化适配范围（源码与补丁）

按用户要求，当前源码的 `ApplyGameProfile` 已将 CUSA00309 纳入同组模拟器性能优化：
GPU 回读队列、上传/命令记录线程、缓存复用、遮挡查询、计算着色器屏障和 GPU 时钟节奏等。
其中 `async_pipelines` 被设为 1，仅异步编译图形管线，计算管线同步编译；此前未匹配港版时
其默认值为 2，尚未完成编译的计算任务也可能被跳过。这个差异是待验证线索，尚非已证实根因。
`SHADPS4_GAME_PROFILE=0` 和 `perf_tuning.ini` 覆盖机制仍适用于港版。

现已分析用户提供的港版 1.07 SELF：11 项补丁、48 条修改、27 个独立地址全部匹配欧版
原始字节校验；碰撞保护及 FOV 的代码空洞和跳转/引用也已核对。因此已加入港版专用 XML、
内置棋盘格修复及 1440p/1800p/4K 等全部原有补丁。发布配置现采用 PS4 Pro 模式、精确回读、
512 MiB 额外游戏直接内存和管线缓存，默认原生 1800p。详细证据、启动入口及下一轮调试命令
见 [港版适配说明](infamous-CUSA00309-adaptation.md)。

这次改动尚未编译或运行验证；用户当前的 AYOUB 1.0 二进制不会因源码修改而自动改变。
新增启动脚本可通过该程序已有的 XML 和 tuning 接口加载等价适配设置；先前排查配置继续
保留，用于对照未移植补丁时的开场行为。

## 第一轮：只验证回读配置

旁边的 `infamous-CUSA00309-baseline.json` 是**第一轮排查配置：已确认加载生效，但未解决开场卡住**。它启用精确回读、使用基础 PS4 模式、保留正常 GPU 渲染，启用有限的日志，关闭 RenderDoc 和 Vulkan validation。配置本身不移植欧版补丁，也不修改模拟器内部的性能优化名单。

1. 退出模拟器。在实际用户目录的 `custom_configs` 下将配置命名为 `CUSA00309.json`。如果该文件已存在，应合并或先由用户保存原配置。用户现已安装此配置，重复验证无需再次覆盖。配置本身约 600 字节；本轮日志上限为 16 MiB，运行游戏也可能产生其正常的着色器缓存。
2. 第一轮使用用户已安装的 AYOUB 构建直接启动，不需要编译 Debug 或安装依赖。以下记录保留当时的命令；其中 `-i` 实际关闭的是游戏更新资源的覆盖加载，并不关闭 XML 机器码补丁。后续应使用港版启动脚本，它已移除此参数以保留更新资源：

   ```powershell
   & 'D:\game\shadPS4-AYOUB1080p-1.0-windows-x64\shadPS4-AYOUB1080p-1.0\shadps4.exe' -i -g 'D:\game\shadPS4QtLauncher\games\CUSA00309\eboot.bin'
   ```

3. 从相同开场流程复现，第一轮继续用 Xbox 手柄，先不要改体感映射。记录是否仍是固定天空、是否出现横握/摇动手柄的提示、是否能打开暂停菜单。卡住后等约 20 秒，退出模拟器以刷新日志。
4. 检查 `%APPDATA%\shadPS4\log\CUSA00309.log`，确认本次构建的 Remote/Revision、`Game-specific config used: true`、`GPU readbacksMode: 2`、`General isNeo: false`。如果仍写入 `shad_log.txt` 或回读仍为 0，应先调查配置未加载、用户目录或启动参数，而不是判定本轮无效修复。
5. 在相同游戏与配置下测试官方 0.19.0，分别保留两次日志；新运行可能覆盖同名日志。不要把两种模拟器、不同回读模式的结果混为一轮。

最小配置安装命令（只在目标尚不存在时写入）：

```powershell
$introConfigTarget = Join-Path $env:APPDATA 'shadPS4\custom_configs\CUSA00309.json'
if (Test-Path -LiteralPath $introConfigTarget) {
    throw '目标配置已存在，请先合并设置或保存原配置。'
}
Copy-Item -LiteralPath 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\documents\Debugging\infamous-CUSA00309-baseline.json' -Destination $introConfigTarget -ErrorAction Stop
```

## 第二轮：根据第一轮现象定位

- **出现正常横握/摇动提示但无法继续**：优先检查体感。Xbox 按钮和摇杆正常不代表游戏收到陀螺仪、加速度计或触摸板数据。如果已有 DualShock 4 / DualSense，可在同一配置下比较。源码和本机 global.ini 中 F6 对应鼠标体感开关，但当前鼠标模拟使用固定重力加速度，只改变角速度，因此不能保证满足“摇动喷漆罐”的加速度检测；按 F6 移动鼠标无效不等于 GPU 修复无效。
- **精确回读已确认仍是固定天空**：提供该次完整日志和卡住的具体时刻，再检查回读/文件加载路径及帧内同步。AYOUB 内置性能采样器可报告线程 CPU 占用和热点；需要时再由用户在其用户目录 `perf_tuning.ini` 中启用 `perf_log = 1`。若已有该文件，只添加/修改这一个键，先保留其他设置以便分析。
- **游戏线程或 GPU 不再前进**：下一轮才采集间隔数秒的线程调用栈；使用已有调试工具，无需默认生成完整内存 dump。
- **调用栈、日志指向 GPU 数据或渲染问题**：再安排少量帧的 GPU 命令/回读追踪或 RenderDoc 捕获。只有出现 device lost / GPU hang 证据时才优先采集 GPU 崩溃资料。
- **需要移植欧版机器码补丁**：必须先核对港版 1.07 的目标指令、相对跳转和原始字节校验；不能直接复用欧版地址。

第一轮精确回读验证没有解除卡住；后续 Windows 栈保护对照已由用户在官方 0.19.0 上
验证能够进入体感提示，随后 AYOUB 1.0 相同保护设置也已通过。后续流程尚未验证。
Codex 未执行游戏、编译或测试，
遵循项目要求由用户在已有环境中执行验证。
