# Blind Flight Rescue（盲飞救援）— 项目设计文档

> Godot 4.7 | 纯代码构建 | AutoLoad 架构 | 2026 CIGA 赛事项目

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [架构总览](#3-架构总览)
4. [场景流水线](#4-场景流水线)
5. [GameManager（全局单例）](#5-gamemanager全局单例)
6. [MainMenu（标题页）](#6-mainmenu标题页)
7. [LevelSelect（关卡选择页）](#7-levelselect关卡选择页)
8. [StoryIntro（剧情介绍页）](#8-storyintro剧情介绍页)
9. [PreEndlessStory（通关表彰页）](#9-preendlessstory通关表彰页)
10. [GameScene（核心游戏关卡）](#10-gamescene核心游戏关卡)
11. [EndlessMode（无尽深空）](#11-endlessmode无尽深空)
12. [PauseMenu（暂停菜单）](#12-pausemenu暂停菜单)
13. [DevTools（开发者工具）](#13-devtools开发者工具)
14. [RadioAdvisor（机载通讯）](#14-radioadvisor机载通讯)
15. [OnboardSystem（飞控电脑）](#15-onboardsystem飞控电脑)
16. [输入映射](#16-输入映射)
17. [关卡剧情](#17-关卡剧情)

---

## 1. 项目概览

| 项目 | 值 |
|------|-----|
| 引擎 | Godot 4.7 |
| 分辨率 | 1600 × 1000 |
| 字体 | 禹凡丹青宋 (YuFanDanQingSong.otf) |
| 音效 | 程序化雷达滴声 + Power_Put.wav 推进力 |
| BGM | stage1(2.0).ogg / stage1(dm).ogg（关卡循环） |
| | talk_a.ogg（剧情对话） |
| | flute(remasterd_dm).ogg（通关表彰） |
| AutoLoad | `GameManager`（全局单例） |

---

## 2. 文件结构

```
res://
├── Main.tscn                       # 入口场景（引用 MainMenu.gd）
├── project.godot                   # 引擎配置 + 输入映射 + AutoLoad
│
├── GameManager.gd                  # AutoLoad 全局管理器
│
├── MainMenu.gd                     # 标题页脚本（Control）
├── LevelSelect.gd                  # 关卡选择页脚本（Control）
├── StoryIntro.gd                   # 剧情介绍页脚本（Control）
├── PreEndlessStory.gd              # 无尽深空引言脚本（Control）
├── WinStory.gd                     # 通关表彰故事脚本（Control）
├── GameScene.gd                    # 核心游戏关卡脚本（Node2D）
├── EndlessMode.gd                  # 无尽深空模式脚本（Node2D）
├── PauseMenu.gd                    # 暂停菜单脚本（CanvasLayer）
├── DevTools.gd                     # 开发者工具脚本（CanvasLayer）
├── RadioAdvisor.gd                 # 机载无线电通讯系统
├── OnboardSystem.gd                # 飞控电脑（过热/限推逻辑）
│
├── game.gd                         # 原始单脚本（已弃用，保留参考）
├── GameScene.g                     # 遗留文件（已弃用）
├── icon.svg                        # 应用图标
├── YuFanDanQingSong.otf            # 中文字体
│
├── stage1(2.0).ogg                 # 关卡 BGM（新版）
├── stage1(dm).ogg                  # 关卡 BGM（原版）/ 选关页面
├── talk_a.ogg                      # 剧情对话 BGM
├── flute(remasterd_dm).ogg         # 通关表彰 BGM
├── Power_Put.wav                   # 推进力音效
│
├── addons/godot_mcp/               # Godot MCP 编辑器插件
└── .godot/                         # 缓存 / UID
```

---

## 3. 架构总览

```
                   Godot Engine
                        │
              ┌─────────┴─────────┐
              │                   │
        AutoLoad               Main.tscn
        GameManager            (MainMenu.gd)
        (全局单例)                 │
              │                  ▼
              │             MainMenu
              │             (标题页)
              │                │ 点击"开始游戏"
              │                ▼
              │             LevelSelect
              │             (5列格子：日志1/2/3 + ∞ + WIN)
              │                │
              │         ┌──────┼──────┐
              │         │      │      │
              │         ▼      ▼      ▼
              │      StoryIntro  │  PreEndlessStory
              │      (打字机剧情) │  (flute + 表彰)
              │         │      │      │
              │         ▼      │      ▼
              │      GameScene │  EndlessMode
              │      (核心玩法) │  (无尽深空)
              │         │      │
              │         ▼      │
              │      PauseMenu │
              │      (暂停层)  │
              │                │
              └────────────────┘
                 (F12) DevTools
```

所有场景切换通过 `GameManager.change_scene("场景名")` 完成，自动匹配 `.tscn` 文件或从 `.gd` 脚本动态构建。

---

## 4. 场景流水线

```
┌──────────────────────────────────────────────────────────┐
│ 正常流程                                                   │
│ MainMenu → LevelSelect → StoryIntro → GameScene          │
│              ↑                        │  通关             │
│              └────────────────────────┘  (→ LevelSelect)  │
├──────────────────────────────────────────────────────────┤
│ 全部通关后                                                 │
│ LevelSelect                                              │
│   ├─ 无尽深空 (∞) → PreEndlessStory → EndlessMode        │
│   └─ 通关表彰 (WIN) → WinStory → LevelSelect             │
└──────────────────────────────────────────────────────────┘
```

淡入淡出动画：淡出 0.25s → 场景切换 → 淡入 0.35s。

---

## 5. GameManager（全局单例）

### 全局数据

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MAX_LEVELS` | `const int` | `3` | 关卡总数上限 |
| `current_level` | `int` | `1` | 当前选中的关卡 |
| `unlocked_levels` | `Array` | `[1]` | 已解锁关卡 ID 列表 |
| `completed_levels` | `Array[int]` | `[]` | 已通关的关卡列表 |
| `endless_unlocked` | `bool` | `false` | 无尽模式 + WIN 卡片解锁标志 |
| `high_score` | `int` | `0` | 历史最高分 |
| `game_state` | `GameState` | `MENU` | 当前游戏状态 |
| `fuel` | `float` | `170.0` | 跨场景燃料缓存 |

### 枚举

```gdscript
enum GameState { MENU, PLAYING, PAUSED, STORY, ENDLESS }
```

### 核心方法

| 方法 | 说明 |
|------|------|
| `change_scene(name)` | 带淡入淡出的场景切换 |
| `pause_game()` / `resume_game()` | 全局暂停/恢复 |
| `complete_level(id)` | 标记关卡通关 + 自动解锁下一关 |
| `check_all_levels_completed()` | 检测 1,2,3 全部通关 → 解锁 `endless_unlocked` |
| `is_level_unlocked(id)` | 查询关卡解锁状态 |

### 解锁规则

- `complete_level()` 将关卡加入 `completed_levels`，并自动解锁 `level_id + 1`
- `check_all_levels_completed()` 在所有三关通关后设置 `endless_unlocked = true`，同时解锁无尽模式和 WIN 卡片
- `endless_unlocked` 是 WIN 卡片和无尽模式卡片的共同锁

---

## 6. MainMenu（标题页）

| 元素 | 内容 |
|------|------|
| 背景 | 全屏纯黑 `ColorRect` |
| 标题 | "Blind Flight Rescue"（72px 青色） |
| 副标题 | "盲飞救援"（36px 淡蓝） |
| 按钮 1 | "开始游戏" → `change_scene("LevelSelect")` |
| 按钮 2 | "退出游戏" → `get_tree().quit()` |

---

## 7. LevelSelect（关卡选择页）

### 布局

| 项目 | 值 |
|------|-----|
| 标题 | "选择目标日志" |
| 容器 | `GridContainer`，5 列 × 1 行 |
| 卡片 | 日志 1 / 日志 2 / 日志 3 / 无尽深空 / 通关表彰 |
| 每卡 | 160×200，Button + ColorRect + Label(数字) + Label(描述) |

### 5 张卡片状态逻辑

| 卡片 | 主符号 | 描述 | 解锁条件 | 点击跳转 |
|------|--------|------|----------|----------|
| 日志 1 | 1 | 日志 1 | `1 in unlocked_levels`（默认解锁） | `StoryIntro` |
| 日志 2 | 2 | 日志 2 | `2 in unlocked_levels` | `StoryIntro` |
| 日志 3 | 3 | 日志 3 | `3 in unlocked_levels` | `StoryIntro` |
| 无尽深空 | ∞ | 无尽深空 | `endless_unlocked` | `PreEndlessStory` |
| 通关表彰 | WIN | 通关表彰 | `endless_unlocked` | `WinStory` |

- 未解锁卡片：灰色背景，符号和描述仍可见但半透明，按钮禁用
- 已解锁卡片：金色背景 + 金色文字，可点击

---

## 8. StoryIntro（剧情介绍页）

| 元素 | 内容 |
|------|------|
| 背景 | 纯黑 + 顶部蓝色装饰线 |
| 文本位置 | Y 坐标 -330（整体上移 1/6） |
| 文本尺寸 | 800×520 |
| 效果 | 打字机逐字显示（40ms/字） |
| 跳过 | 点击屏幕加速（2ms/字） |
| BGM | `talk_a.ogg` |
| 完成 | 自动跳转（level 1-3 → GameScene / level 99 → EndlessMode） |

---

## 9. PreEndlessStory（通关表彰页）

| 元素 | 内容 |
|------|------|
| 背景 | 纯黑 + 顶部/底部金色装饰线 |
| 文本位置 | Y 坐标 -330 |
| 标题 | "锚点之外"（42px 金色） |
| 内容 | 回顾三关经历、引擎限制解除、引出无尽深空 |
| BGM | `flute(remasterd_dm).ogg`（-4.0 dB） |
| 完成 | 直接跳转 `EndlessMode` |

---

## 10. GameScene（核心游戏关卡）

### 10.1 飞行参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `THRUST` | 320 | 推进力 |
| `BRAKE` | 200 | S 键减速力 |
| `ROT_ACCEL` | 20 | 旋转加速度 |
| `ROT_DRAG` | 0.80 | 旋转惯性衰减 |
| `LIN_DRAG` | 0.992 | 线性惯性 |
| `MAX_SPD` | 420 | 最大速度 |
| `FUEL_MAX` | 170.0 | 最大燃料 |
| `FUEL_BURN` | 10.0/s | W 键油耗 |
| `FUEL_REFILL` | 55.0 | 救援回油量 |
| `RESCUES_PER_LEVEL` | 4 | 每关需救援次数 |

### 10.2 操作

| 按键 | 功能 |
|------|------|
| A / D | 旋转飞船 |
| W | 加速推进 + 扫描搜索圈（耗油 + 播放推进音效） |
| S（按住）| 减速（不耗油） |
| S（单击）| 抛锚建立临时锚点（耗 5 油） |
| Esc | 暂停游戏 |
| F12 | 开发者工具 |
| R / M | 燃料耗尽时：重试 / 返回主菜单 |

### 10.3 渐进式风力（关卡 1 专属）

| 阶段 | 风力 | 触发 |
|------|------|------|
| 初始 | 0%（无风） | 关卡开始 |
| 救援 1 | ~30% | 第一次拾取信标 |
| 救援 2 | ~65% | 第二次拾取信标 |
| 救援 3 | ~100% | 第三次拾取信标 |

关卡 2 从 100% 风力起步（×1.5），关卡 3 从 100% 起步（×2.0）。

### 10.4 搜索圈 + 扫描锁定系统

- 信标初始隐藏，周围生成 3~4 个蓝色半透明搜索圈
- 进入搜索圈后按住 W 扫描（进度条 0→100%），松开 W 进度衰减
- 扫描完成 → 信标锁定（红色六边形从 0 缩放弹出）
- 靠近隐藏信标时 SOS 闪烁（三快闪节奏）

### 10.5 虚假信标

- 紫色六边形 + X 标记
- 碰撞：扣 22 燃料 + 520 弹飞力 + 飞船挤压变形动画

### 10.6 电磁干扰区 (EMI)

- 半径 220-350，紫色脉冲变形圆环绘制
- 罗盘正弦抖动 ±35°，信号文字乱码

### 10.7 信号遮蔽云 (Fog)

- 3 层暗蓝灰色半透明圆环
- 罗盘完全隐藏 + 雷达滴声静音 + 显示"信号丢失..."

### 10.8 关卡灾害分布

| 灾害 | 关卡 1 | 关卡 2 | 关卡 3 |
|------|--------|--------|--------|
| 虚假信标 | 1 | 3 | 5 |
| EMI 区域 | 1 | 2 | 3 |
| 信号遮蔽云 | 1 | 2 | 3 |

### 10.9 通关条件

救援 4 次 → `complete_level()` → 检测全部通关 → 返回 LevelSelect。

---

## 11. EndlessMode（无尽深空）

### 11.1 与 GameScene 的差异

| 特性 | GameScene | EndlessMode |
|------|-----------|-------------|
| 燃料 | 170 上限，W 消耗 | 100 上限，W 不消耗（∞） |
| 救援次数 | 4 次通关 | 无限循环 |
| 地图 | 3200×2000 | 4800×3000 |
| 锚点半径 | 150 | 180 |
| 最大速度 | 420 | 480 |
| 风场 | 渐进/固定倍率 | 随机方向 ×100，救援后递增 |
| 灾害 | 随关卡固定分布 | 全随机（假信标 2-6 / EMI 1-4 / 云 1-4） |
| 信标距离 | 300-750 | 350-850 |

### 11.2 制作人员名单

进入游戏后 2.5 秒开始通过 RadioAdvisor 滚动播出（间隔 7 秒）：

1. `[档案]` 程序：一笔兔
2. `[档案]` 策划：The昊子
3. `[档案]` 音频：UMC049
4. `[通讯]` 感谢你的体验以及助力

> **修复：** 使用 `call_deferred("set_process", false)` 阻止 RadioAdvisor 的闲置消息定时器（每 18s 自动播放），防止抢断制作人员名单。

### 11.3 操作

| 按键 | 功能 |
|------|------|
| A/D | 旋转 |
| W | 加速（不耗油） |
| S | 减速/抛锚（不耗油） |
| Esc | 返回关卡选择 |

---

## 12. PauseMenu（暂停菜单）

| 元素 | 内容 |
|------|------|
| ProcessMode | `PROCESS_MODE_ALWAYS`（防止暂停冻结自身） |
| 面板 | 居中 Panel，420×400 |
| 按钮 | "继续游戏" / "重新开始" / "返回主菜单" |
| Esc | 再次按 Esc = 继续游戏 |
| Android | `NOTIFICATION_WM_GO_BACK_REQUEST` 支持 |

---

## 13. DevTools（开发者工具）

| 元素 | 内容 |
|------|------|
| 呼出 | F12 键（全场景通用） |
| 面板 | 居中 Panel，420×700 |

### 按钮列表

| 按钮 | 功能 |
|------|------|
| 跳过当前关卡 | `complete_level()` + 返回选关 |
| 跳转到关卡 1/2/3 | 自动解锁前序关卡 + 进入 GameScene |
| 跳转到无尽深空 | 解锁全部 + 进入 EndlessMode |
| 跳转到通关表彰 (WIN) | 直接进入 PreEndlessStory |
| 解锁全部关卡+无尽+WIN | 填充 unlocked_levels + completed_levels，设 endless_unlocked |
| 重置所有进度 | 清空所有数据，仅保留关卡 1 |

### 信息面板

显示当前关卡、已解锁列表、无尽模式状态、WIN 卡片状态。

---

## 14. RadioAdvisor（机载通讯）

- `_process` 每 18±3 秒自动发送一条闲置通讯消息
- `_show_message(sender, msg, color)` 在右下角显示消息（6 秒后淡出）
- 监听 `OnboardSystem` 的过热/推力限制信号
- 监听 `decoy_collided` / `search_zone_scanned` 事件
- EndlessMode 中通过 `call_deferred("set_process", false)` 禁用闲置消息

---

## 15. OnboardSystem（飞控电脑）

- 管理过热系统和推力限制逻辑
- 发射 `overheat_warning` 和 `thrust_limited` 信号
- 由 RadioAdvisor 监听并转换为通讯文字

---

## 16. 输入映射

配置于 `project.godot` → `[input]`：

| Action | 按键 | Keycode |
|--------|------|---------|
| `ui_left` | A | 65 |
| `ui_right` | D | 68 |
| `ui_up` | W | 87 |
| `ui_down` | S | 83 |
| `ui_cancel` | Esc | 4194305 |

---

## 17. 关卡剧情

### 第一章：信号迷雾

- 公元 2147 年，飞船「破晓号」偏离航道
- 操作指南：A/D 旋转、W 加速、S 减速/抛锚、Esc 暂停
- 首次救援后电磁风暴激活

### 第二章：陨石迷宫

- 古代舰队残骸区，风力极不稳定
- 锚定系统已解锁

### 第三章：永夜尽头

- 完全黑暗的空域，极度酷寒
- 燃料存量到临界点

### 终章（无尽模式前置）

- 三份日志均已关闭，破晓号完成救援
- 引擎限制解除，燃料不再制约
- 深空中无限求救信号等待回应

---

> 文档更新时间：2026-07-05
> 项目路径：`d:\GoDotUs\2026_CIGA_Play\2026cgj`