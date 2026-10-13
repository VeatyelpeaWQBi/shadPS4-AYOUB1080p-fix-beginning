# Windows 本机构建入口

开发完成后，双击项目根目录的 `build.bat`。它默认使用 12 个并行任务（较少核心的机器
自动降低），增量构建 Release；窗口显示成功或失败，最后停留，方便查看结果。

生成程序：`Build\x64-Clang-Release\shadps4.exe`。
本次修改过的着色器、缓存、输入和港版适配代码都会随正常构建纳入新程序。

PowerShell 入口支持指定并行数量和可选的缓存合成测试：

```powershell
& 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\scripts\build_release.ps1'
& 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\scripts\build_release.ps1' -Jobs 8
& 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\scripts\build_release.ps1' -RunCacheTests
```

也可以运行 `build.bat -Jobs 8 -RunCacheTests`。测试不启动游戏，失败时整个命令返回失败。
成功只代表编译（以及选用的合成测试）通过，实际效果需游玩验证。

只检查已经安装的工具与现有依赖，不开始构建：

```powershell
& 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\scripts\build_release.ps1' -CheckEnvironment
```

脚本优先复用现有 CMake 构建目录记录的工具路径，再查找当前、用户和系统 PATH，最后
定位已有的 Visual Studio / MSYS 工具。必要时可指定 `-VisualStudioPath`、`-CMakePath`、
`-NinjaPath` 和 `-ClangPath`。Windows PowerShell 5.1 与 PowerShell 7 均可使用。
双击入口使用系统 Windows PowerShell，执行策略仅作用于该进程。

构建使用项目现有的第三方子模块和已下载、解压的 FFmpeg。脚本不安装、下载或更新依赖，
不清理构建目录，不修改全局环境；Visual Studio 编译环境仅在当前 PowerShell 进程生效。
依赖检查按 Windows 构建范围执行：`date`、`epoll-shim`、`mesa-kosmickrisp`、
`vulkan-loader` 及其子模块仅用于其他平台，在 Windows 上不要求初始化。
缺少依赖时会在配置之前指出缺失的路径；现有构建目录若属于别处或使用另一生成器，也会
明确退出，由你自行处理。

已有项目的增量编译可能新增或覆盖数百 MiB 的构建文件；完整首次构建占用更多。
日志保存在输出目录的 `configure-release.log` 和 `build-release.log`，每次覆盖。
选用缓存测试会使用 `Build\cache-runtime-test\`，日志为 `configure.log`、`build.log`、
`test.log`；测试只清理自己创建的数据文件，保留编译产物。

## 使用刚构建的程序测试游戏

当前普通与性能诊断 BAT 均指向本项目的 `Build\x64-Clang-Release\shadps4.exe`，
构建后即可使用。构建脚本不会替换启动器版本目录的文件，也可以直接指定新构建测试：

```powershell
& 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\scripts\run_infamous_hk.ps1' `
  -EmulatorPath 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\Build\x64-Clang-Release\shadps4.exe' `
  -GameDirectory 'D:\game\shadPS4QtLauncher\games\CUSA00309' `
  -Resolution 1080p -Performance -CacheDiagnostic
```

4K PS4 Pro 测试改为 `-Resolution 4k`；普通性能游玩可去掉 `-CacheDiagnostic`。
测试满意后，可关闭模拟器，自行将新 EXE 复制到上述 launcher 路径。

用户已使用该入口完成 Release 构建并游玩。提交前清除粒子/CPU 实验后，保留的
5 项缓存、运行时复用、编译等待与缓冲区间检查通过；实机验证范围主要为港版 1080p。
