# inFAMOUS 港版性能诊断

普通启动使用 `scripts/launch_infamous_1080p.bat` 或 `launch_infamous_4k_pro.bat`。
性能诊断使用对应的 `launch_infamous_1080p_debug.bat` 或 `launch_infamous_4k_pro_debug.bat`，
它们使用同一个构建输出、相同分辨率补丁和游戏优化，额外开启日志与 CPU/GPU 采样。
诊断采样会影响性能，最终帧率应以普通启动为准。

## 已保留的改造

- 着色器、计算/图形管线与 Vulkan 驱动缓存持久化，并在后续启动时预热。
- 首次计算管线在编译工作线程创建；录制线程在绑定前等待完成，不丢弃计算任务。
- 精确 GPU 回读、异步上传与线程化录制继续使用既有策略。
- 港版 GPU 可写缓冲提前设置访问保护，避免粒子反馈读取旧 CPU 数据。
- 已提交的运行时查找/不可变资源表复用，用户实测剧情选择约 40→50 FPS。

缓存覆盖实际遇到并记录的程序及状态，不能自动预测所有尚未出现的游戏资源。
用户复测中，已有缓存的重伤/死亡效果未再次卡顿；车祸持续低帧率仍未明显改善。
最后一轮追加同步/全屏候选没有明显收益，已撤回，见
[最终对照](infamous-particle-final-round.md)。实验 CPU 分组、候选着色器替换及粒子范围
实现已从提交代码中移除；旧 58–60 FPS 结果存在火焰重启错误，不作为性能收益。

## 诊断入口

```powershell
.\scripts\run_infamous_hk.ps1 -EmulatorPath '.\Build\x64-Clang-Release\shadps4.exe' -Resolution 1080p -Performance -CacheDiagnostic
.\scripts\run_infamous_hk.ps1 -EmulatorPath '.\Build\x64-Clang-Release\shadps4.exe' -Resolution 1080p -PerformanceDiagnostic
.\scripts\run_infamous_hk.ps1 -EmulatorPath '.\Build\x64-Clang-Release\shadps4.exe' -Resolution 1080p -PerformanceDiagnostic -LightProfile
```

第一条保留缓存/慢帧简报；第二条开启 CPU 栈与逐计算着色器 GPU 计时；第三条只采集
概览。PowerShell 控制台支持可选标记：1=卡顿，2=粒子场景，3=普通场景。
切换控制台本身可能影响帧时间，标记会记录这一操作。

日志每个文件上限 16 MiB；退出后在 `Build/diagnostics/` 保存运行参数、缓存变化和
日志副本。脚本仅临时调整用户配置、补丁选择和 tuning，正常退出后恢复原文件。
不修改游戏文件，不更改用户/系统环境变量；现有游戏缓存可以继续增长。
构建脚本的 `-DiagnosticMap` 可生成 CPU 符号映射，额外地图文件留在 Build 中。

## 隔离存档测试

`prepare_infamous_benchmark.ps1` 从用户命名的车祸/选择备份创建独立 home。
`--benchmark-dir` 限定港版测试，帧记录、控制指令、日志和截图使用该目录。
普通启动不轮询控制文件，也不切换存档目录。
`infamous_benchmark_command.ps1` 支持按键、摇杆、状态、截图与正常退出；
`compare_infamous_tuning.ps1` 可做有界参数对照并确认引擎实际参数。
这些工具默认使用已准备的场景备份，运行前应确认路径、资料容量和当前游戏已关闭。

GPU 分进程观察脚本只读取 Windows 计数器，不调整或停止其他程序。
Windows GPU 活动、Vulkan 提交计时和跨线程累计等待不能直接相加为一帧耗时。
截图在性能窗口结束后采集；PNG/历史资料压缩后核对像素或文件校验值。
原活动存档不参与测试写入，历史正确基线按记录指纹核验。

## 验证边界

提交前清除实验代码后，Release 构建和保留的 5 项检查通过。
实机证据主要来自 CUSA00309 1.07、1080p；没有完成本轮欧/美版、原生 PS4 Pro 4K
或完整章节的回归。诊断资料、存档、缓存和 EXE 不纳入 Git 提交。
