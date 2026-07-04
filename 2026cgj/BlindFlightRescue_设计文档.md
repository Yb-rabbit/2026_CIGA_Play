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
9. [GameScene（核心游戏关卡）](#9-gamescene核心游戏关卡)
10. [PauseMenu（暂停菜单）](#10-pausemenu暂停菜单)
11. [输入映射](#11-输入映射)
12. [关卡剧情](#12-关卡剧情)

---

## 1. 项目概览

| 项目 | 值 |
|------|-----|
| 引擎 | Godot 4.7 |
| 分辨率 | 1600 × 1000 |
| 字体 | 禹凡丹青宋 (YuFanDanQingSong.otf) |
| 音效 | 程序化雷达滴声 + Power_Put.wav 推进力音效 |
| AutoLoad | `GameManager`（全局单例） |

---

## 2. 文件结构

```
res://
├── Main.tscn                    # 入口场景（引用 MainMenu.gd）
├── project.godot                # 引擎配置 + 输入映射 + AutoLoad
│
├── GameManager.gd               # AutoLoad 全局管理器
│
├── MainMenu.gd                  # 标题页脚本（Control）
├── LevelSelect.gd               # 关卡选择页脚本（Control）
├── StoryIntro.gd                # 剧情介绍页脚本（Control）
├── GameScene.gd                 # 核心游戏关卡脚本（Node2D）
├── PauseMenu.gd                 # 暂停菜单脚本（CanvasLayer）
│
├── game.gd                      # 原始单脚本（已弃用，保留参考）
├── icon.svg                     # 应用图标
├── YuFanDanQingSong.otf         # 中文字体
├── Power_Put.wav                # 推进力音效
│
├── addons/godot_mcp/            # Godot MCP 编辑器插件
└── .godot/                      # 缓存 / UID
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
              │             (关卡选择)
              │                │ 点击已解锁关卡
              │                ▼
              │             StoryIntro
              │             (打字机剧情)
              │                │ 剧情结束
              │                ▼
              ├────────────→ GameScene
              │  读写全局     (核心玩法)
              │  状态          │ Esc
              │  │            ▼
              │  │         PauseMenu
              │  │         (暂停层)
              │  │
              └──┘
```

所有场景切换通过 `GameManager.change_scene("场景名")` 完成，自动匹配 `.tscn` 文件或从 `.gd` 脚本动态构建。

---

## 4. 场景流水线

```
MainMenu → LevelSelect → StoryIntro → GameScene
   ↑           ↑                         │
   │           └────── 通关后 ────────────┘
   │
   └────── "返回主菜单"（暂停菜单 / 燃料耗尽后按 M）
```

所有切换带 0.6 秒淡入淡出动画：
- 淡出（黑屏）0.25 秒 → 场景切换 → 淡入（消去）0.35 秒

---

## 5. GameManager（全局单例）

### 全局数据

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MAX_LEVELS` | `const int` | `3` | 关卡总数上限 |
| `current_level` | `int` | `1` | 当前选中的关卡 |
| `unlocked_levels` | `Array` | `[1]` | 已解锁关卡 ID 列表 |
| `high_score` | `int` | `0` | 历史最高分 |
| `game_state` | `GameState` | `MENU` | 当前游戏状态 |
| `fuel` | `float` | `100.0` | 跨场景燃料缓存 |

### 枚举

```gdscript
enum GameState { MENU, PLAYING, PAUSED, STORY }
```

### 核心方法

| 方法 | 说明 |
|------|------|
| `change_scene(name)` | 带淡入淡出动画的场景切换 |
| `pause_game()` | 设置 `get_tree().paused = true` |
| `resume_game()` | 取消全局暂停 |
| `complete_level(id)` | 标记关卡解锁 + 自动解锁下一关 |
| `is_level_unlocked(id)` | 查询关卡解锁状态 |
| `set_game_state(state)` | 直接设置游戏状态并发射信号 |

### 关卡解锁规则

- 通关自动解锁下一关（`level_id + 1`）
- 第 3 关通关后不解锁第 4 关（`MAX_LEVELS` 上限保护）
- `unlocked_levels` 始终保持升序排列

---

## 6. MainMenu（标题页）

| 元素 | 内容 |
|------|------|
| 背景 | 全屏纯黑 `ColorRect` |
| 标题 | "Blind Flight Rescue"（72px 青色） |
| 副标题 | "盲飞救援"（36px 淡蓝） |
| 按钮 1 | "开始游戏" — `change_scene("LevelSelect")` |
| 按钮 2 | "退出游戏" — `get_tree().quit()` |
| 排版 | 整体下移约 1/3 视口高度 |

---

## 7. LevelSelect（关卡选择页）

| 元素 | 内容 |
|------|------|
| 标题 | "选择关卡" |
| 容器 | `GridContainer`，3 列 |
| 卡片 | 3 张关卡卡片（160×200），动态生成 |
| 返回按钮 | "返回主菜单" — `change_scene("MainMenu")` |

### 卡片状态逻辑

| 状态 | 外观 | 交互 |
|------|------|------|
| 已解锁 | 金色背景 + 金色数字 + 关卡描述 | 可点击 → `change_scene("StoryIntro")` |
| 未解锁 | 灰色背景，数字和描述隐藏 | `Button.disabled = true` |

---

## 8. StoryIntro（剧情介绍页）

| 元素 | 内容 |
|------|------|
| 背景 | 纯黑 + 顶部蓝色装饰线 |
| 文本 | `RichTextLabel`，BBCode 格式，支持彩色和字号 |
| 效果 | 打字机逐字显示（40ms/字） |
| 跳过 | 点击屏幕加速（2ms/字） |
| 光标 | 底部闪烁红色指示器 |
| 完成 | 自动跳转 `GameScene` |

### 关卡剧情文本（详见第 12 节）

---

## 9. GameScene（核心游戏关卡）

### 9.1 飞行参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `THRUST` | 320 | 推进力 |
| `BRAKE` | 200 | S 键减速力 |
| `ROT_ACCEL` | 20 | 旋转加速度 |
| `ROT_DRAG` | 0.80 | 旋转惯性衰减 |
| `LIN_DRAG` | 0.992 | 线性惯性 |
| `MAX_SPD` | 420 | 最大速度 |
| `FUEL_BURN` | 18.0/s | W 键油耗 |
| `FUEL_REFILL` | 40.0 | 救援回油量 |
| `FUEL_MAX` | 100.0 | 最大燃料 |
| `RESCUES_PER_LEVEL` | 4 | 每关需救援次数 |

### 9.2 操作

| 按键 | 功能 |
|------|------|
| A / D | 旋转飞船 |
| W | 加速推进（耗油 + 播放 Power_Put.wav） |
| S（按住） | 减速（不耗油） |
| S（单击/松开） | 抛锚建立临时锚点（耗 5 油） |
| Esc | 暂停游戏 |
| R（燃料耗尽时） | 重新开始 |
| M（燃料耗尽时） | 返回主菜单 |

### 9.3 渐进式风力（关卡 1 专属）

| 阶段 | 风力百分比 | 触发条件 |
|------|-----------|----------|
| 初始 | 0%（无风） | 关卡开始 |
| 第一次救援后 | 30% | 拾取信标 1 |
| 第二次救援后 | 65% | 拾取信标 2 |
| 第三次救援后 | 100% | 拾取信标 3 |

关卡 2 和 3 从 100% 风力起步。

### 9.4 虚假信标（Decoy Beacon）

- 外观：紫色六边形 + **X** 黑色叉号标记
- 碰撞效果：扣 22 燃 + 520 弹飞力度
- 碰撞提示：橙色文字 "赝品信标！燃料 -22"

### 9.5 电磁干扰区（EMI Zone）

- 外观：不可见圆形区域（半径 220-350）
- 效果：罗盘指针正弦抖动 ±35°（越靠近中心越强）
- 效果：信号报告文字乱码（如 "信%号^增@强"）

### 9.6 信号遮蔽云（Fog Cloud）

- 外观：3 层暗蓝灰色半透明圆环
- 效果：罗盘指针完全隐藏 + 雷达滴声静音
- 信号报告：显示 "信号丢失..."

### 9.7 关卡灾害分布

| 灾害类型 | 关卡 1 | 关卡 2 | 关卡 3 |
|----------|--------|--------|--------|
| 虚假信标 | 1 | 3 | 5 |
| EMI 区域 | 1 | 2 | 3 |
| 信号遮蔽云 | 1 | 2 | 3 |
| 风力 | 渐进 0→100% | 100% ×1.5 | 100% ×2.0 |

### 9.8 通关条件

救援 4 次真实信标（红色六边形）→ `complete_level()` → 自动解锁下一关 → 返回关卡选择页。

---

## 10. PauseMenu（暂停菜单）

| 元素 | 内容 |
|------|------|
| 遮罩 | 半透明黑色（alpha 0.65） |
| 面板 | 居中 Panel，360×340，深蓝背景 |
| 按钮 | "继续游戏" / "重新开始" / "返回主菜单" |
| Esc 键 | 再次按 Esc 等同于"继续游戏" |
| Android 返回键 | `NOTIFICATION_WM_GO_BACK_REQUEST` |

### Process Mode

`process_mode = Node.PROCESS_MODE_ALWAYS`

必须设为 `ALWAYS`，否则 `get_tree().paused = true` 会冻结暂停菜单自身的按钮和输入。

---

## 11. 输入映射

配置于 `project.godot` → `[input]`：

| Action | 按键 | Keycode |
|--------|------|---------|
| `ui_left` | A | 65 |
| `ui_right` | D | 68 |
| `ui_up` | W | 87 |
| `ui_down` | S | 83 |
| `ui_cancel` | Esc | 4194305 |

---

## 12. 关卡剧情

### 第一章：信号迷雾

- 公元 2147 年，飞船「破晓号」偏离航道
- **操作指南**：A/D 旋转、W 加速、S 减速/抛锚、Esc 暂停
- 目标提示：红色指针指上 = 对准真实信标
- 警告：首次救援后电磁风暴激活

### 第二章：陨石迷宫

- 古代舰队残骸区，风力极不稳定
- 锚定系统已解锁
- "这里埋葬了太多梦想……但你的故事不该到此为止。"

### 第三章：永夜尽头

- 完全黑暗的空域，极度酷寒
- 燃料存量到临界点
- "相信自己，飞行员。光就在前方。"

---

> 文档生成时间：2026-07-04
> 项目路径：`d:\GoDotUs\2026_CIGA_Play\2026cgj`