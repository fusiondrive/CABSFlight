# CABSFlight 回归审计报告

基线：tag `v1.0-anim-stable`（Phase 0–2 完成，均真机验证）
日期：2026-07-17 ・ 性质：只读审计，未修改任何代码

结论先行：动画架构本身健康，可以冻结。发现的问题**没有一项**是已验证行为的回归，绝大多数是 Phase 0 删除旧 UI 后留下的**孤儿死代码**，属于低风险清理；其余集中在 Onboarding，属于 Phase 3 可选优化，不影响主流程。

---

## A. 建议清理（低风险，与已冻结的动画行为无关）

### A1. Theme 中已废弃的设计 token（0 引用）

Phase 0 删除 ClassicFlightyView / RoutePickerView / MapContainerView / GlassCard 后，这些 token 失去全部使用者，现为死代码：

- 颜色：`background`、`cardBackground`、`border`、`textPrimary`、`textSecondary`、`textTertiary`（`accent`、`accentSecondary` 仍被 Onboarding 使用，保留）
- 间距：`paddingSmall`、`paddingMedium`、`paddingLarge`
- 圆角：`cornerRadiusSmall`、`cornerRadiusMedium`、`cornerRadiusLarge`
- 字体助手：`headerFont`、`titleFont`、`bodyFont`、`captionFont`

文件：`Theme/Theme.swift`。风险：极低（删除即可，编译器会立刻暴露任何遗漏引用）。注意：`Color(hex:)` 扩展**仍在用**（Route.officialColor、Onboarding 背景），不要删。

**`Theme.Anim` 与 `Theme.UI` 全部 token 均有 ≥1 引用，无死 token**——Phase 0/2 的 token 清理是干净的。

### A2. 未使用的文件：`ScreenCornerRadius.swift`

整个 `enum ScreenCornerRadius`（`current` / `bottomCard` / `cornerStyle`）**零引用**。且它依赖 `UIScreen.main.bounds`（iOS 26 下 `UIScreen.main` 已废弃，多屏/Stage Manager 下不可靠）。

文件：`CABSFlight/ScreenCornerRadius.swift`（74 行）。风险：极低（删除文件 + 从 pbxproj 移除引用，参照 Phase 0 流程）。这也顺带消除项目里唯一的 `UIScreen.main` 用法。

### A3. `CABSColors.swift` 在 app 与 widget 中完全重复

`CABSFlight/CABSColors.swift` 与 `CABSFlightWidget/CABSColors.swift` **逐字节相同**。这是跨 target 的合理重复（widget extension 是独立模块），但可改为让 widget target 直接成员引用 app 的那份，消除副本漂移风险。风险：低，但涉及 pbxproj target membership，**非紧急**，可暂不动。

---

## B. 逐项核对结果（你列出的检查清单）

| 检查项 | 结论 |
|---|---|
| 废弃 Theme token | ✅ 见 A1（颜色/间距/圆角/字体助手死代码）；Anim/UI token 干净 |
| `.animation(value:)` 滥用 | ✅ 主 UI 无滥用——Phase 2 已移除互相覆盖的容器动画。剩余的（`selectionFeedback`/`bottomOverlay`/`routeChip`/`mapTap`）都是单一归属、作用域正确。**唯一集中点是 Onboarding**（见 C1） |
| `DispatchQueue.main.async` | ⚠️ 仅剩 1 处：`OnboardingView.swift:414` `asyncAfter`（见 C2）。主 UI/ViewModel/Service 已无 |
| `Task { @MainActor in }` 可收敛 | ✅ 无此模式。现有 `Task {}` 均为 MainActor 隔离上下文的合理 fire-and-forget；轮询/模拟 task 均 `[weak self]`。无需收敛 |
| `GeometryReader` 可替换 | ✅ 已无 `GeometryReader`；sheet 高度测量已用现代 `onGeometryChange`（iOS 16+） |
| 未使用 View / Modifier / Extension | ⚠️ `ScreenCornerRadius`（A2）。其余 Liquid* 组件、`MapItemPressEffect`、`Color(hex:)`、`IdentifiablePolyline` 均有引用 |
| iOS 26 新 API 替换旧实现 | 已良好采用 `glassEffect`/`symbolEffect`/`contentTransition`/`onGeometryChange`/`scrollTargetBehavior`。剩余替换机会集中在 Onboarding（见 C3） |
| 重复组件 | `CABSColors` 跨 target 重复（A3，合理但可优化）。玻璃高光叠层在 StationView/BusMarker 有小段重复，可接受 |

---

## C. Phase 3 领域（可选优化，建议**推迟**并定义为 optimization 而非 refactor）

这些几乎全部集中在 `OnboardingView.swift`（一次性首启流程），不影响主地图/sheet/公交动画。收益是打磨与可维护性，风险是触碰一个当前工作正常的流程。

### C1. Onboarding 弹簧 magic number 散落
`interpolatingSpring(stiffness: 170, damping: 22)` 在 7 处重复，另有 `240/18`、`190/16`。未进 Theme。建议将来收敛为 `Theme.Anim` 语义 token（`.spring(duration:bounce:)`）。同时 `TextContentView`（行 527–528）叠了两个 `.animation(value:)`，职责可合并。

### C2. Onboarding AllSetPage 延时回调链（原审计 H4）
`OnboardingView.swift:407–414`：`withAnimation(...).delay(0.12)` / `.delay(0.32)` + `DispatchQueue.asyncAfter(0.05)` 协调 4 个状态变量（`checkProgress/badgeScale/badgeOpacity/pulse`）拼一个入场序列；快速前后翻页时 `asyncAfter` 可能在 reset 之后到达，导致非活跃页遗留 `repeatForever` 脉冲。建议改 `PhaseAnimator`/`KeyframeAnimator`（单一时间线，天然可取消）。

### C3. iOS 26 API 替换机会（Onboarding + LiveBadge）
- 勾选动画 `CheckmarkShape().trim(to: checkProgress)` → SF Symbol + `symbolEffect(.drawOn)`（iOS 26）
- Onboarding 脉冲环 `repeatForever + delay` → `PhaseAnimator`，并加 `accessibilityReduceMotion` 门控
- `LiquidLiveBadge`（`LiquidGlassView.swift:626`）`onAppear + withAnimation(liveBadgePulse.repeatForever)` → 可换 phaseAnimator 且当前**无 Reduce Motion 门控**（原审计 M3/M5）

### C4. 全项目 Reduce Motion 覆盖
主 UI（公交、sheet）已支持。仍缺门控的装饰性动画：`LiquidLiveBadge` 脉冲、Onboarding 脉冲环/3D 旋转/repeatForever。属打磨项。

---

## 建议

冻结 `v1.0-anim-stable` 作为动画架构基线。若要做一次低风险收尾，**只做 A 区**（删除 Theme 死 token + 删除 `ScreenCornerRadius.swift`）——纯删除、零行为变化、可独立成一个 `chore(cleanup)` commit。**C 区整体推迟**，未来若进行请按 optimization 对待，逐项小步、每步真机验证，不为"更现代"牺牲已验证的稳定行为。
