<!--
SPDX-FileCopyrightText: 2026 shadPS4-AYOUB1080p contributors
SPDX-License-Identifier: GPL-2.0-or-later
-->

# 鼠标体感、鼠标按键和 Windows 笔记本触摸板移植

已移植源码，尚未执行构建、自动测试或游戏验证。现有下载版 AYOUB 1.0 和官方 0.19.0
不会因修改源码获得这些功能，需要使用本项目重新编译的程序。已验证的开场栈保护与
本次新增输入功能的验证范围分开记录。

本机已有 `global.ini` 确认 F6 绑定到鼠标体感、Delete 绑定到触摸板模拟。旧二进制的
F6 只有简化角速度和固定 Y 轴重力，不能等同于另一引擎完整的竖握/摇罐实现。
用户反馈旧程序按 F6 移动没有反应，与该实现缺口相符，尚不能据此证明快捷键未触发。
新实现记录 `Mouse emulation mode` 开关信息；诊断模式还会每秒最多记录一次
`Mouse motion report` 的姿态、g、角速度、R2 和传感器启用状态，便于区分这两种情况。

## 操作方式

保留本项目快捷键，避免覆盖现有 F7 摇杆和 F8 重载功能。输入配置会补齐缺失的回中和
释放绑定，已有用户绑定不被覆盖。

| 默认按键 | 功能 |
| --- | --- |
| F6 | 开启/关闭鼠标体感，移动鼠标调整手柄姿态 |
| 快速往返移动鼠标 | 在体感模式生成摇动加速度，用于摇罐 |
| 体感模式下按住左键 | 模拟 R2，用于喷漆 |
| Delete | 开启/关闭触摸板模拟模式 |
| 触摸模式下左键 | 单指接触，松开后释放 |
| 触摸模式下右键 | 单指接触，同时按下手柄触摸板按钮 |
| 触摸模式下同时按住左右键 | 双指接触，同时按下触摸板按钮 |
| 触摸模式下笔记本触摸板 | 原生单指/双指坐标及物理按压 |
| Home | 回中；触摸模式同时释放接触 |
| Esc | 关闭模拟，释放捕获、触点和喷漆触发器 |

两种模式互斥。鼠标按键模拟单指/双指按压，按住时移动也保留原引擎的接触坐标移动。
Xbox 按钮和摇杆仍可使用。离开焦点、打开输入法/键盘界面或模拟器截获输入时释放模拟。
原生触摸板依赖 Windows Precision Touchpad HID 报告；没有该接口的设备仍可用鼠标
按键模拟。原生报告优先，Windows 派生鼠标事件不会把双指覆盖成单指。

## 实现与来源

来源是用户提供的 `D:\projects\infamous2ndson_pc`，本轮没有修改该引擎或游戏文件。

- `src/pad_motion.h` → `src/input/mouse_motion.h`：竖直姿态、重力、摇动加速度、角速度。
  游戏 ResetOrientation 只重置报告参考，不改变重力方向。
- `gpu/shim/bbport_mouse_motion.h` → `src/input/touchpad_input.h`：鼠标按键接触、双指、
  原生优先、事件队列和超时释放。
- `gpu/shim/bbport_touchpad_frames.h` → `src/input/touchpad_frames.h`：并行/混合 HID 帧
  拼接、稳定接触 ID、坐标归一化。
- `gpu/shim/bbport_windows_touchpad.h` → `src/input/windows_touchpad.h`：Windows HID
  字段解析、前台原始输入及设备断开处理，动态加载系统 `hid.dll`，不安装驱动。

模拟状态与真实手柄状态分开，在输出时合并。短按/松开排队到游戏读取时处理；队列有界，
溢出保留最新释放。原模型加速度单位为 g，接入时抵消 libScePad 已有的 0.098 换算。
传感器启停、朝向重置和角速度死区已接入。Windows 消息钩子保留 SDL/系统消息处理。

## 本地验证（由用户执行）

独立测试不需要 Google Test、GPU 或游戏文件，不下载依赖。路径检查确认系统已有
`C:\msys64\clang64\bin` 的 Clang、CMake、Ninja；本轮未运行它们。以下命令在现有
**MSYS2 CLANG64** 终端运行，产物和缓存写入 `Build/input-port-test`，预计数 MiB，
实际大小未测量，不修改全局环境或游戏文件。

```sh
cd /d/projects/shadPS4-AYOUB1080p-fix-beginning
cmake -S tests/input -B Build/input-port-test -G Ninja -DCMAKE_CXX_COMPILER=/clang64/bin/clang++.exe -DCMAKE_BUILD_TYPE=Release
cmake --build Build/input-port-test
ctest --test-dir Build/input-port-test --output-on-failure
```

测试覆盖：竖直姿态、重置后重力、摇罐加速度、采样频率、异常移动、鼠标单指/双指快速
转换、队列溢出释放、混合 HID 帧、稳定 ID、原生/派生事件去重及超时释放。Windows 下
也编译实际 HID 解析头，但不会注册设备或捕获输入。这不代替完整模拟器构建及硬件验证。

使用现有项目构建环境重建模拟器后，指定新程序启动：

```powershell
& 'D:\projects\shadPS4-AYOUB1080p-fix-beginning\scripts\run_infamous_hk.ps1' -EmulatorPath '<重新编译的 shadps4.exe 完整路径>' -Resolution 1080p -Diagnostic
```

实际验收先完成竖握、摇罐和喷漆，再检查鼠标单键/双键、原生单指/双指、Home/Esc、切换
窗口和输入法，以及退出模拟后 Xbox 的正常输入。构建、测试和硬件验收目前均未执行。
