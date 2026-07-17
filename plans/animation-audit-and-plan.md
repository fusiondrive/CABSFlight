# CABSFlight 动画审计与重构计划

日期：2026-07-17 ・ 状态：待确认（未修改任何代码）

## 一、技术栈确认

- 纯 SwiftUI + Swift，Observation 框架（`@Observable`），无 UIKit 动画代码
- 最低部署版本：**iOS 26.2**（Xcode 26 工程），主 UI 全面使用 Liquid Glass API（`glassEffect`）
- 架构：单屏地图应用（无 NavigationStack 主导航）。模态：`.sheet`（设置）、`.fullScreenCover`（引导页）、**自定义伪 sheet**（站点卡片）
- Widget 扩展：Live Activity / Dynamic Island（无自定义动画代码，系统驱动，健康）
- 关键事实：因最低版本为 26.2，`ContentView` 中 `if #available(iOS 26, *)` 恒为真 → **ClassicFlightyView 整条分支运行时不可达**

## 二、动画相关文件清单

| 文件 | 角色 | 状态 |
|---|---|---|
| CABSFlight/LiquidGlassView.swift | 主界面全部动画入口 | 活跃 |
| Views/CABSBottomSheetView.swift | 自定义拖拽 sheet | 活跃 |
| Views/OnboardingView.swift | 引导页序列动画 | 活跃 |
| Theme/Theme.swift | 动画 token（Theme.Anim）+ 按压反馈 | 活跃 |
| ViewModels/BusViewModel.swift | 手写 60fps 公交插值循环 | 活跃 |
| CABSFlight/ClassicFlightyView.swift | 重复实现全部组件动画 | **不可达死代码** |
| ViewModels/BusTrackingViewModel.swift | Timer 逐帧动画循环 | **无引用死代码** |
| Views/MapContainerView.swift, Views/RoutePickerView.swift, Theme/GlassCard.swift, CABSFlight/CABSMockEngine.swift | 旧 UI 残留 | **无引用死代码** |
| ViewModels/CABSHybridService.swift / CABSMockService.swift | 数据模拟插值（非 UI 动画） | 合理，不动 |
| CABSFlightWidget/* | Live Activity | 健康，不动 |

## 三、动画审计

### 1. 高优先级问题

**H1 手写 60fps 帧循环驱动公交移动**
- 文件：ViewModels/BusViewModel.swift `animateToBuses` / `interpolateBuses`（L265–306）+ Models/Bus.swift `interpolated(to:)`
- 现状：`Task.sleep(16.6ms)` 循环 + 手写 ease-out cubic，每帧改写 `@Observable animatedBuses`
- 问题：整个 Map 内容每秒重建 60 次（性能/电量）；`buses` / `animatedBuses` / `targetBuses` 三份重复状态；`targetBuses` 写后无人读；退后台无 scenePhase 处理，轮询+帧循环继续跑；不响应 Reduce Motion
- 推荐：直接在 `withAnimation(.linear(duration: 3))` 中更新 `buses`，由 SwiftUI/MapKit 原生动画 Annotation 坐标（iOS 17+ 支持）；删除帧循环与重复状态；用 `scenePhase` 暂停轮询
- 影响：地图上公交移动、"N buses active" 计数、LIVE 徽章显隐（均读 `animatedBuses`，需改读 `buses`）
- 兼容：无。注意 heading 需保持"最短弧"连续性（现有手写代码有处理，`rotationEffect(.degrees(heading))` 直接动画会在 359°→1° 时反向长转，需展开为连续角度）
- ⚠️ 需真机验证 Annotation 坐标动画观感后再删旧实现

**H2 站点 sheet 动画归属冲突（call-site 曲线实际失效）**
- 文件：CABSFlight/LiquidGlassView.swift L71 `.animation(Theme.Anim.stopSheet, value: selectedStop?.id)` vs L140 `withAnimation(dismissEaseOut)`、CABSBottomSheetView L131/L247 `withAnimation(dismissEaseOut)`
- 现状：同一 `selectedStop` 变化由容器级 `.animation(value:)` + 多处 `withAnimation` + transition 内嵌 `.animation` 三方声明
- 问题：容器 `.animation(value:)` 改写 transaction，覆盖 call-site 的 `dismissEaseOut` / `dismissSpring` → 这些 token 实际为死配置，调参无效；同一转场三处定义时长曲线，维护陷阱
- 推荐：单一归属——动画声明收敛到 transition 附带的 animation（或仅容器 `.animation`），删除其余 `withAnimation` 包装
- 影响：站点 sheet 出现/消失、地图空白处点按取消、关闭按钮
- 兼容：无

**H3 自定义 sheet 拖拽不可中断、无速度语义、消失时跳变**
- 文件：Views/CABSBottomSheetView.swift `dismissGesture`（L238–256）、`onChange`（L78–82）
- 现状：固定 80pt 阈值判定；`onEnded` 后一次性 `withAnimation` 消失；`onChange(selectedStop?.id)` 在变 nil 时立刻把 `dragOffset` 归 0
- 问题：快速轻扫不足 80pt 不能关闭（应按 `predictedEndTranslation` 投影判定）；释放速度未交给回弹弹簧（拖拽→动画有"接缝"）；消失瞬间 dragOffset 归 0 使卡片先跳回原位再播放 move 转场（可见跳变）；上拖硬止无 rubber-band；转场进行中无法再次抓住反向
- 推荐：`value.predictedEndTranslation.height` 决策 + `.interpolatingSpring(initialVelocity:)` 或带速度的 `.spring` 回弹；`onChange` 加 `newValue != nil` 守卫；上拖加阻尼；（备选：整体迁移系统 `.sheet` + `presentationDetents` + `presentationBackgroundInteraction(.enabled)`，免费获得全部系统行为，但会改变悬浮卡片视觉——默认不采用）
- 影响：站点 sheet 全部拖拽交互
- 兼容：无

**H4 引导页 AllSetPage：延时回调链 + 四个状态变量拼一个序列**
- 文件：Views/OnboardingView.swift `AllSetPage`（L334–425）
- 现状：`withAnimation(...).delay(0.12)` / `.delay(0.32)` + `DispatchQueue.asyncAfter(0.05)` 协调 `badgeScale/badgeOpacity/checkProgress/pulse` 四个变量；`repeatForever` 脉冲环
- 问题：快速前后翻页时 `asyncAfter` 在 `resetEntrance()` 之后到达 → 非活跃页上遗留 `repeatForever` 动画（耗电、再次进入状态错乱）；一个视觉序列被四个布尔/数值状态分治；不响应 Reduce Motion
- 推荐：`PhaseAnimator` 或 `KeyframeAnimator`（由 `isActive` 触发，一处声明整条时间线，天然可取消）；对勾可用 SF Symbol + `symbolEffect(.drawOn)`（iOS 26）；脉冲环受 `isActive && !reduceMotion` 门控
- 影响：引导页第三页入场动画
- 兼容：无

### 2. 中优先级问题

**M1 ClassicFlightyView 整体不可达**（CABSFlight/ClassicFlightyView.swift，461 行）：最低版本 26.2 下永不执行，却重复实现 RouteChip/LiveBadge/InfoCard/相机动画且全部硬编码时长曲线。→ 删除（若你计划降低部署版本请说明，则改为保留并共享 token）。影响：无（死代码）。

**M2 旧动画系统死代码仍在编译**：BusTrackingViewModel（Timer 60fps 帧循环 + 每帧 `Task { @MainActor }` 存在乱序竞态）、MapContainerView、RoutePickerView、GlassCard、CABSMockEngine。→ 删除。影响：无引用；Theme 中 `animationSpring/animationSmooth/animationMapTap` legacy token 随之清理。

**M3 LIVE 徽章脉冲用 onAppear+repeatForever 旧模式**（LiquidGlassView `LiquidLiveBadge` L576–594）：徽章随 `animatedBuses.isEmpty` 条件插拔，重新插入时动画状态重置闪跳；不响应 Reduce Motion。→ `symbolEffect(.pulse)` 或 phaseAnimator。影响：头部徽章。

**M4 MapItemPressEffect 按压状态可能卡死**（Theme.swift L189–216）：`@State isPressed` 依赖 `onEnded` 复位，手势被系统取消时不触发 → 恒暗态。→ 改 `@GestureState`（自动复位）。MapKit 手势冲突的 workaround 本身合理，保留。影响：地图站点/公交按压反馈。

**M5 全项目零 Reduce Motion 适配**：脉冲、3D 旋转、repeatForever、弹簧均无 `accessibilityReduceMotion` 门控。→ 环境值门控装饰性动画，保留理解性淡入淡出。

**M6 退后台行为**：轮询与动画循环无 `scenePhase` 处理（`onDisappear` 不会在退后台时触发）。→ 与 H1 一并处理。

**M7 引导页弹簧参数散落**（OnboardingView）：`interpolatingSpring(stiffness:170, damping:22)` 重复 6 处，另有 240/18、190/16 —— 旧式 API + magic number，未进 Theme。→ 统一为 `.spring(duration:bounce:)` 语义 token 收入 Theme.Anim。

**M8 相机动画的 withAnimation 包装可能无效**（LiquidGlassView 多处 `withAnimation(cameraFly/stopCameraFly) { cameraPosition = ... }`）：MapKit 对相机变化执行自身的 fly-to 动画，外层曲线/时长大概率不被采纳 → token 造成"可调"假象。→ 真机验证；无效则移除包装、删除 token，依赖 MapKit 默认。

**M9 heading 魔法值**（LiquidBusMarker L355 `bus.heading == 0 ? 45 : bus.heading`）：用 45° 掩盖"无 heading 数据"；且 H1 改造后需最短弧处理。→ 数据层区分"无朝向"，视图不再造假。

### 3. 低优先级问题

- **L1** InfoCard 内容切换：`Group + .id` + `.transition(.opacity.animation(0.15s))`，与外层 0.5s 插入弹簧节奏脱节；可改 `.contentTransition` / 统一 token（LiquidGlassView L432–514）
- **L2** TextContentView 叠两个 `.animation` 修饰符（value: page.id 与 value: subtitle），职责可合并（OnboardingView L497–530）
- **L3** 引导页背景 4 个 blur(48) 大圆随翻页整体弹簧移动 —— 主次元素同时等权运动，且大面积模糊动画在 ProMotion 上有合成压力；建议背景改慢速淡变，弱于前景
- **L4** 路线条 `.padding(.vertical, 30)` + `.padding(.vertical, -18)` 负 padding 阴影 hack（LiquidGlassView L628–631）——布局问题非动画，暂记录
- **L5** 全项目固定字号（`.system(size:)`），无 Dynamic Type —— 按你的约束**本次不动**，仅记录
- **L6** `Theme.Anim` 命名与实际用途已有漂移（如 dismissEaseOut 实际被 H2 覆盖）——随 H2 清理

## 四、分阶段重构计划

原则：每阶段独立可编译可运行，一阶段一 commit（即回滚点）；先加新实现验证，后删旧实现。

**Phase 0 死代码清理（先行，风险最低，收益最大）**
- 文件：删除 ClassicFlightyView、BusTrackingViewModel、MapContainerView、RoutePickerView、GlassCard、CABSMockEngine（及根目录疑似陈旧副本 CABSMockEngine.swift / CABSFlightAttributes.swift / CABSFlightLiveActivity.swift，需先核对 target membership）；ContentView 移除 #available 分支；Theme 清理 legacy token
- API：无新 API
- 风险：低。唯一决策点：是否确认放弃 iOS 25 及以下（当前工程设置已放弃）
- 验证：全量编译 + 冒烟运行主流程
- 回滚：git revert 单 commit

**Phase 1 公交移动动画（H1 + M6 + M9）**
- 文件：BusViewModel.swift、Bus.swift、LiquidGlassView.swift、CABSFlightApp/ContentView（scenePhase）
- API：`withAnimation(.linear(duration:))` 驱动模型状态、MapKit SwiftUI 原生 Annotation 动画、`\.scenePhase`
- 风险：中——Annotation 坐标动画观感需真机确认；heading 连续角处理
- 验证：真机观察移动平滑度/打断（3s 内新数据到达时应从当前位置续动）；退后台→返回无跳变；Instruments 对比帧循环前后 CPU
- 回滚：保留旧 `animateToBuses` 于同 commit 之前一个 commit，验证通过后单独 commit 删除

**Phase 2 站点 sheet（H2 + H3 + M4）**
- 文件：LiquidGlassView.swift、CABSBottomSheetView.swift、Theme.swift
- API：transition 附带 animation 单一归属、`predictedEndTranslation` 投影决策、带初速度的 spring、`@GestureState`
- 风险：中——高频交互路径，需覆盖快速连点、拖拽中反向、拖拽中切换站点
- 验证：快速轻扫可关闭；缓拖 79pt 释放回弹带速度连续性；消失过程无跳变；连续点多个站点无残影；手势取消不卡按压态
- 回滚：独立 commit

**Phase 3 引导页（H4 + M7 + L2 + L3）**
- 文件：OnboardingView.swift、Theme.swift
- API：`PhaseAnimator` / `KeyframeAnimator`、`symbolEffect(.drawOn/.pulse)`、`.spring(duration:bounce:)` token
- 风险：低——一次性流程，可整页重验
- 验证：三页快速往返翻页无遗留动画/错态；Reduce Motion 下序列退化为淡入
- 回滚：独立 commit

**Phase 4 一致性与可达性收尾（M3 + M5 + M8 + L1 + L6）**
- 文件：LiquidGlassView.swift、Theme.swift
- API：`symbolEffect(.pulse)`、`accessibilityReduceMotion`、相机 withAnimation 验证清理
- 风险：低
- 验证：开启 Reduce Motion 全流程走查；横竖屏/iPad 尺寸走查
- 回滚：独立 commit

**暂不修改**：Live Activity/Widget（系统驱动，健康）、SettingsView（标准 Form）、数据模拟服务的插值（属数据层职责）、ETA 预测业务逻辑、字体与 Dynamic Type（L5）、负 padding 布局 hack（L4，非动画）。

## 五、建议最先修改的模块

**Phase 0 → Phase 1（公交移动动画）**。理由：Phase 0 零风险移除两套手写帧循环中的一套及全部重复动画实现；Phase 1 处理唯一持续运行的手写插值系统，是性能、电量、代码量收益最大且与其他 UI 解耦的模块。
