# Meteoric Engine 更新日志

> 版本：1.1.3

## 未发布（打击特效预览 + 皮肤解析修复 + CNE 模组兼容）

- **【新增】「CNE 模组兼容」：Codename Engine 格式的 mod 可直接在 Meteoric 里加载**（设置 → 编程 → **CNE 模组兼容**，
  **默认关**；关闭时 mod 加载路径与改动前完全一致）。与上一轮落地的「CNE 式 HScript 编程层」是两条独立的线：
  `cneScripting` 管脚本能不能跑，`cneModCompat` 管 CNE 布局能不能读进来。覆盖：
  - **谱面转换**：`songs/<song>/charts/[<variant>/]<难度>.json`（`codenameChart`）→ **psych_v1**。新增
    `states/editors/content/CneExport.cneToPsych` / `isCneFormat`：`strumLines` type 1 → 玩家列 `<4`、
    type 0 → 对手列 `>=4`、type 2（GF 线）→ 取 `mustHitSection` 同向列并置 `gfSection`；
    `Camera Movement`（params[0] = strumLine 索引，type==1 → `mustHitSection`）、`BPM Change`、
    `Time Signature Change`、`Alt Animation Toggle` 烘焙进 section（归属规则对齐 CNE
    `funkin/backend/chart/FNFLegacyParser.hx` 的 `__convertToSwagSections`：事件落在本段窗口内即属本段）；
    `Scroll Speed Change`↔`Change Scroll Speed`、`Add Camera Zoom`、`Play Animation`、自定义事件透传；
    `No Anim Note`/`Alt Anim Note` 别名到 Psych 内建 `No Animation`/`Alt Animation`。
    ⚠ 两条刻意的"不照搬"：① 不用 CNE `FNFLegacyParser.encode` 的 0.6.x「相对 mustHitSection」老语义
    （Meteoric/Psych 1.0.4 的 psych_v1 是绝对列号，照搬会把对手段音符翻到玩家侧，见 `PlayState.hx:2156-2198`）；
    ② 指定难度缺谱时**不**回退 `normal`（CNE 自己直接报缺谱，静默换难度会让玩家玩到错谱）。
  - **音频**：Psych 路径 `songs/<song>/Inst.ogg` 缺失时回退 CNE `songs/<song>/song/Inst|Voices<suffix>[-<难度>]`
    （`.ogg` 优先、`.mp3` 兜底）；`suffix` 取 `meta.json` 的 `instSuffix`/`vocalsSuffix`，难度取当前难度（小写优先）；
    不接管 Psych 的 `Voices-Player/-Opponent`（拆分人声由调用方按既有逻辑回退）。
  - **人物**：`data/characters/<名>.xml`（CNE 人物定义）→ Psych 人物 JSON
    （`sprite`/`icon`/`color`/`holdTime`/`scale`/`flipX`/`x`/`y`/`camx`/`camy`/`antialiasing` +
    `<anim name anim x y fps loop indices>`，`indices="2..12,0,1"` 按 CNE `CoolUtil.parseNumberRange` 语义展开）。
  - **周目**：`data/weeks/weeks/*.xml` + `data/weeks/weeks.txt` → Psych `WeekFile`
    （`chars`→`weekCharacters`、`<song>`→`songs`、`<difficulty name>`→`difficulties`、`bgColor`→`freeplayColor`），
    使 CNE mod 的歌出现在 Story/Freeplay；无 `menubackgrounds/menu_<sprite>` 时 `weekBackground` 置空
    （不拼一个不存在的贴图路径去加载）。
  - **zip 包**：`mods/<名>.zip`（CNE 根级即 mod 根）被识别为 mod；首次访问透明解包到 `mods/_cnestage/<名>/`
    （指纹 = 体积 + mtime；Mod 列表刷新时 `CneModCompat.clearCaches()` 让运行中替换的 zip 重新解包；
    同名真实文件夹优先；`_cnestage` 已登记进 `Mods.ignoreModFolders`；zip mod 的启用状态在开关关闭时也不会被 `modsList.txt` 重写抹掉）。
    之所以是"落盘暂存"而不是内存挂载：Meteoric/Psych 的资源管线全是真实文件路径
    （`sys.io.File` / `FileSystem` / `FlxGraphic.fromFile` / `Sound.fromFile`），内存挂载等于重写整条资源管线
    （CNE 的 `AssetsLibraryList` + `__proxy` 那套）；暂存目录可随时整个删掉，下次自动重建。
  - **Mod 列表**：卡片与右侧信息区标注「CNE 格式」，开关未开时提示开关位置（`states/ModsMenuState.hx`）。
  - **未覆盖（本版明确不做，等实机测试后再排期）**：CNE 舞台 `data/stages/*.xml|.hx`、人物 `.hx` 扩展
    （`pico-speakers.hx`/`spirit.hx`）、`data/notes/*.hx` 自定义音符行为、`.pack` 脚本包、
    独立 `events.json`（CNE 格式 `{events:[...]}` 不喂给 Psych 解析器；谱面内嵌 `events` 已转换）、
    CNE 自定义难度在 Freeplay 的档位扩展（Story 里按周目 `<difficulty>` 生效）。
  - **验证**（本轮无 CNE 样本 mod，且按用户要求"只构建、不启动"）：新增
    `tools/cne_mod_compat_test/run.sh` —— 把**仓库真实源码**逐字节复制进临时工程、只替换 flixel/lime/backend 替身后
    `haxe --interp` 直跑：谱面转换 34 条 + 兼容层 47 条 = **81 条断言全过、0 失败**
    （含 CNE 官方 base 谱面 118 音符守恒、玩家 59 / 对手 59 列号分布、zip 指纹失效重解）；
    `./compile-mac.sh typecheck` 通过、`./compile-mac.sh` release 构建通过（exit 0），
    产物内字符串含 `CNE 模组兼容`/`codenameChart`/`mods/_cnestage`/`cneModCompat`；实机由用户第二轮测试。
    证据：`tools/cne_mod_compat_test/{EVIDENCE.md,out/*.log}`。
  - **第二轮补充（CNE 模组实测后）**：① **CNE 舞台 XML** → 背景图层 + 角色站位/相机偏移/zoom
    （新增 `cne/CneModCompat.stageFile/stageSpriteNodes` + `states/stages/CneXmlStage.hx`，
    挂点 `StageData.getStageFile` 与 `PlayState` 舞台 switch 的 default 分支）；
    ② **人物加载优先级修正**：mod 的 CNE `data/characters/<名>.xml` 现在排在**引擎内置 JSON 之前**
    （CNE 是 mod 覆盖引擎；旧顺序下 mod 的同名人物 gf/bf/dad 永远读不到，实测 SMA 的 GF 一直用引擎内置贴图）；
    ③ 事件布尔参数归一化为 `'1'/'0'`（Psych 事件值是数字字符串约定）。
    ④ 顺带定位一个**既有引擎 bug**（与本兼容层无关）：谱面事件名命中 `custom_events/<名>.lua` 时进曲 SEGV
    （空 body 也崩；CNE 关闭 + 纯 Psych 谱面同样复现），已在 `PROGRAMMING.md` 第 8 节记录并给出规避方式。
    测试断言 41+66=107 条全过；本轮按要求只构建、不启动，实机由用户截图验证。

- **【修复】设置里「音符打击特效」的 4 个非默认皮肤此前全部静默失效**：`NoteSplash.defaultNoteSplash`
  在 v5 性能改动里被改成 `'noteSplashes/noteSplashes-063'`，而 `getSplashSkinPostfix()` 会给它拼 `-<skin>`
  后缀 → 解析成 `noteSplashes-063-vanilla`（仓库无此文件），`loadAnims` 回退链于是一律回退到 063：
  选 Diamond / Electric / Sparkles / Vanilla 与选默认皮肤看到的是同一张图。
  **修复**：`defaultNoteSplash` 回到 Psych Engine 0.7.3 的约定 `'noteSplashes/noteSplashes'`
  （PE 0.7.3 `objects/NoteSplash.hx:24` 与 `states/editors/NoteSplashDebugState.hx` 的 `defaultTexture` 同值），
  后缀拼出来即 `noteSplashes-vanilla` / `noteSplashes-diamond` / … 真实文件；
  `images/noteSplashes/list.txt` 新增 `063` → 063 成为**可选皮肤**，选中时按 `use063Raw` 判据
  （贴图名含 `noteSplashes-063`）**不挂着色器**，预染色四色 raw 直出。
  - 行为变化（**须知晓**）：默认皮肤（Psych）从"强制 063 raw"变回 `noteSplashes` + 各轨 RGB 着色
    （即 v5 之前的行为）。想保留 063 观感，把「音符打击特效」选成 `063` 即可。
  - 迁移：老存档 `splashSkin = "Psych"` 仍有效；已失效的自定义皮肤名按既有逻辑重置为默认。

- **【新增】选中「音符打击特效」行时，内容区预览带显示 4 轨打击特效预览**：排版与精灵形态照搬
  Psych Engine 0.7.3 `states/editors/NoteSplashDebugState.hx`（站立箭头 `alpha 0.75`、`x = i * 220 + 240`、
  溅射位 = 箭头位 − `(swagWidth*0.95, swagWidth)`、`offset = (10,10) + config 偏移`、
  帧率取 config 区间随机值、着色器取该轨箭头的 RGB 调色板）；与调试界面的唯一差别是动画设为循环。
  - **尺寸（用户确认保留原行数后的必然结果）**：`OptionsPane` 预览带改为跟随分区行窗口
    `[ROW_Y + rowsVisible * ROW_GAP, STRIP_Y − 6]`（6 行 = 464..572 = 108px，与既有常量逐像素一致）。
    6 行下 108px 装不下最高的 splash 皮肤（`noteSplashes-vanilla` 整段动画包络 316px），
    因此**预览带路径整体等比缩小到 0.33×**（316 × 0.33 ≈ 104px，上下各留 ~2px）；暂停内嵌路径
    没有预览带约束，仍是 PE 0.7.3 的**全尺寸**。要全尺寸只能二选一：行窗口缩到 2 行（预览带 316px），
    或让预览浮在选项行之上（会压住行文字，违反 system 域排版契约）。
  - **量测用整段动画包络、不用首帧**：sparrow 每帧 trim/rect 都不同（063 的 trim.y 在动画里从 87 变到 30），
    首帧只有峰值帧的 ~85% —— 拿首帧当尺寸会让峰值帧顶出预览带。宿主的包围盒（`x + width`）
    也据此来，配合"打击特效整组与箭头预览同心"，三种选中态、任意皮肤的落位逐像素一致（不跳位）。

- **【修复】单界面设置里的预览此前走错了分支（实机截图定位）**：`BaseOptionsMenu.headless` 只在**构造期**
  为 true（`OptionsState.sectionInstance` 构造完就还原），而 `NoteSettingsSubState.onPaneSelectionChange`
  拿它判断"我在不在预览带里" → 换行时误走整屏分支：箭头被 tween 到 `noteY = 90` 压到选项行上、
  溅射被摆到 `y = −22` 顶出面板。**修复**：新增常驻标志 `BaseOptionsMenu.paneHosted`（由
  `OptionsPane.setSection` 置位），预览联动一律以它为准；单界面里只切显隐、y 交给宿主摆位。

## 未发布（设置界面融合：一个界面 + 侧边栏切分区）

- **【重写】设置界面从"两级界面"变成"一个界面"**：左侧 `SettingsRail`（230 宽）切分区，
  右侧 `OptionsPane`（956 宽）就地渲染该分区的选项行 —— 不再"进二级页 → 退出 → 再进下一页"。
  分区**选中即切换**（navigation rail 预览手感），焦点用 `Tab` 在"分区栏/内容区"之间迁移；
  鼠标点分区行 = 切分区并接管焦点；触控点分区行同理，◀▶/A 仍作用于内容区。
  - 新增：`source/options/SettingsRail.hx`（分区栏）、`OptionsPane.hx`（内容区宿主）、
    `OptionsUi.hx`（令牌化面板绘制）、`OptionValue.hx`（取值/显示单点）、`SettingsCanvas.hx`（画布基类）。
  - 重写：`source/options/OptionsState.hx`（唯一入口）。
  - 布局（1280×720 基准，已核算）：侧栏 40,70,230,570；内容 284,70,956,570（右缘 1240）；
    选项行首 y 152、行距 52、可见 8 行；说明行与主题色板条共用底部 578..632 条带（互斥显示）；
    底部提示条 40,662,1200,48。层级仍是**面板 → 高亮条 → 行文字**（高亮条先 `add()`）。

- **【关键机制】选项定义只有一份，不存在两套表漂移**：`BaseOptionsMenu` 新增 `headless` 模式 ——
  7 个选项分区（音符/界面/画面/效果/玩法/判定/性能）由各自子类**照旧在构造里 `addOption()` 并挂 `onChange`**，
  只是不建任何 UI（背景/面板/行/按钮/pad 全部跳过），选项表与回调由 `OptionsPane` 渲染与驱动。
  `formatValue` 抽成 `OptionValue.display()`（显示优先级）供两条路径共用；`onPaneSelectionChange()` 是
  预览类联动的新钩子（分页路径的 `changeSelection` 覆写体改为调用它）。

- **【就地化】两块自带绝对布局的画布搬进内容区**：`NotesSubState` → `NotesPane`、`ControlsSubState` → `ControlsPane`，
  两者都接受一个内容区矩形（`hosted` 分支）：
  - `ControlsPane`：清单左缩进 = 内容区 x+40，键位列右贴（`KEY_X = 右缘 − 500`），绑定弹层在内容区居中；
  - `NotesPane`：左右面板重排为 560/382（中间 14 间距），模式列与箭头列在左面板内居中，
    色轮 300→250 且亮度渐变条移到色轮**右侧**（382 宽放不下原始的"渐变条 46 + 16 间距 + 色轮 300"横向排布），
    RGB/HEX 三列按面板宽度等比压缩。
  - 两个 `*SubState` 变成**薄壳**：`new XXXPane(null)`（null = 整屏几何，像素级不变）+ `onExit = close()`。
    暂停菜单内的设置路径（`PauseSettingsSubstate`）因此与改造前完全一致，且不再有第二份实现。
  - 焦点不在内容区时，宿主把画布 `inputEnabled = false`（只绘制不吃键），
    避免 ↑↓/Esc 被"画布内部列表"与"分区栏"同时消费。

- **【边界，明确声明】**「调整延迟与Combo」「自定义界面」「容器」「移动触控」仍是**独立整屏页出口**：
  侧栏列出，**点分区栏即一步直达**（键盘选中后 Enter 直达；内容区确认同样可开），
  容器自带引擎界面、启动会整机重启，因此不做就地嵌入；
  音符皮肤预览 / 抗锯齿 BF 预览在融合界面里**未显示**（headless 分区不创建预览精灵；预览承载位待做）。

- **【兼容契约不变】**：`OptionsState.onPlayState`（曲目内进入设置后返回要重载曲目）、
  `pendingSelectLabel`（容器界面返回按标签恢复分区）、`enterContainersMenu()`（容器入口"不挂转场"修复）。
  单界面没有"关子页"这一步，因此落盘点从 `closeSubState()` 改为 `goBack()` / `openCurrentExternal()` /
  `destroy()`（否则 `destroy()` 里的 `loadPrefs()` 会把本次改动读没）。

- 证据：`tools/evidence/settings-single-ui-20260915/`（类型检查/构建日志、静态契约自查、用户实测截图）。

- **【滚动】侧栏滚轮 = 页面滚动**（一格滚轮翻一整页，桌面 9 项；两端自然夹取，不回卷）：
  翻页过程走**时间插值**（`FlxMath.lerp(..., elapsed * SCROLL_LERP)`，与 Freeplay/MainMenu 同款），
  所以是"整栏滑过去"而不是"一行一行闪"；窗口位置跟随选中项居中，因此翻页时**高亮条停在同一屏幕行、列表在它下面滑**。
  键盘 ↑↓/长按仍是一行一行；点击分区行仍是单击直达。移动端触屏拖动会合成大量滚轮事件，故移动端一格 = 一行（只桌面翻页）。
  翻页间隔 ≥110ms（连续飞滚不会一帧翻好几页）；跨行 >2（如回卷）直接吸附，不做长距离滑动。
  行不越列表带：面板没有裁剪遮罩，靠近上下边缘的行按位置隐藏（否则文字会压到「设置」标题）。

- **【修复】色板选中环残留在别的分区/别的选项行**：`ColorSwatchPicker.setSelectedVisual()` 点亮"当前档位环"时
  **不看整行是否隐藏**，而它会由 `keyboardFocus`（宿主切焦点）与 DesignTokens 主题监听（改主题色）回调触发 ——
  于是切到「音符」等没有主题色选项的分区后，那里会留下一个孤零零的白圈。现在该方法以 `isVisible` 为闸门
  （整行隐藏就不点亮任何环）；`OptionsPane.set_focused` 也只在"色板确实显示着"时才动 `keyboardFocus`。

- **【新增】音符皮肤（箭头样式）预览进内容区**：`OptionsPane` 新增**预览带**（y 464..572，高 108），
  带预览的分区把选项行窗口从 8 行缩到 6 行（`BaseOptionsMenu.previewRows`），省下的空间给预览；
  预览容器由宿主按**叶子精灵包围盒**在预览带内居中（普通 `FlxGroup` 没有 x/y，且分区往往再套一层自己的
  `FlxTypedGroup`，所以递归收集叶子、逐个平移，且同一容器只摆一次以免偏移累加）。
  `NoteSettingsSubState` 现在两种路径都创建预览：整屏路径仍是"从屏幕上方滑入"，单界面路径只做显隐
  （内容区没有裁剪遮罩，滑入会画到选项行上面）。

- **【修复】预览带上残留"两个没有文字的空开关"**：给音符分区开预览带后选项行窗口从 8 行缩到 6 行，
  但 `setRowsVisible(true)` 会把**全部 8 行**的行文字/开关/值文字都显示出来，而 `refreshRows()` 只遍历 `rowsVisible` 行
  → 第 7、8 行的开关被留在预览带位置、文字却从未填过（用户实测截图）。现在 `refreshRows()` 末尾显式隐藏尾部未用行
  并复位文本缓存。

- **【样式统一】布尔选项的开关改为「更新界面」同款 toggle**：新增可复用组件 `source/objects/ToggleSwitch.hx`
  （胶囊轨道 96×32 + 22px 白圆钮；开 = `primary` 填充 + primary 描边，关 = `0x66161622` + `panelOutline`；
  圆心空间插值 `elapsed*18`、首次落位吸附；轨道**原地重绘**避免同尺寸位图串图）。
  设置内容区（`OptionsPane`）的方框复选框整体替换为它，`switchCols` 取代 `checkBgs/checkFills`；
  命中区外扩 12px → 32+24 = **56 高**（触控红线）。开关比旧方框宽（96 vs 26），因此选项名起点右移
  到 `PANEL_X+130`（开关右缘 402 + 12 间距），名字可用宽 486px 仍充足。
  （暂停菜单内的设置页仍用旧方框复选框，属另一条已验证路径；后续可收敛为共用本组件。）

- **【全库统一】所有系统域界面的开关 = 胶囊 toggle**（`objects/ToggleSwitch`）：
  融合设置内容区 `OptionsPane`、分页设置页 `BaseOptionsMenu`（暂停内嵌 7 页）、模组列表 `ModsMenuState`
  三处把 26px 方框复选框整体替换（`checkBgs/checkFills` 引用归零）；更新界面 `OutdatedState` 的**私有胶囊实现
  收敛为共用组件**（圆钮坐标模型 / 原地重绘 / 首次落位都随之固化，那段临时探针也一并删除）。
  - 因开关比方框宽（96 vs 26），三处名字列右移：融合内容区 `NAME_X` → `PANEL_X+130`；
    `BaseOptionsMenu.LIST_X` 108 → **164**；`ModsMenuState.LIST_X` 88 → **164**（值列不动）。
  - 模组列表行位是动态的 → 新增 `ToggleSwitch.setPosition(x, y)` 整组移动（轨道 + 圆钮一起，避免圆钮留在旧行高）。
  - 4 个编辑器页（对话/角色/周目编辑器）的 `FlxUICheckBox` **不动**：meteoric-design 明列它们属非主题域工具界面。
  - Skill 已同步：`meteoric-system` 新增「开关（胶囊 toggle）」规范条目 + 「开关统一清单」+ 单界面设置章节；
    `meteoric-design` 形状表把「复选框」改为「开关（布尔项）」。

## 未发布（Lua 图形化编程 · 第一版界面缺陷修复）

- **【修复】第一版截图复核出的画布/底栏界面缺陷**（用户实机截图 + 源码定位，逐条根因如下）：

  1. **画布空提示与事件积木叠字**（截图左上"…木」面板拖一块事件积木…"被帽块压掉前半句）：
     `rebuildCanvas()` 用 `doc.isEmpty()` 控空提示，而它的语义是"没有任何**非事件**积木"——
     画布默认带 2 条空事件栈（`LuaGraphTemplates.blank`）→ 它恒为 `true`，提示常显；
     且提示 y = `CAN_Y+90` 正好落在第一条事件栈上。
     改为新增 `hasDrawableStack()`（有无可绘制事件栈）判定 + 提示移到画布中部空区；
     **`GDoc.isEmpty()` 语义保持不动**（`LuaCodeGen.validate` 的"画布上还没有任何积木"还要用它）。

  2. **底部按钮「保存生成」折行、「预览 Lua」被截**（截图里"保存生/成"两行 + 底部孤立的"成"）：
     `UIButton` 标签字号硬编码 26px，而本仓库 `FlxText.set_fieldWidth()` 在 `fieldWidth > 0` 时
     **强制 `wordWrap = true`**（`source/flixel/text/FlxText.hx:521-540`）→ 26px 下 96px 只放得下 3 个汉字。
     `UIButton` 新增可选 `labelSize`（默认 26，存量调用零变化）+ 标签强制单行；本界面底栏传 18。

  3. **画布右上「模组/脚本」折三行压进画布内容区**：`nameText` 宽 280 且未关 `wordWrap`。
     改为画布顶部固定两行（标题行 + 状态行），状态行宽 `CAN_W-32`、`wordWrap=false`、
     超长走新增 `fitText()` 加省略号；内容起始 y 提为 `CAN_CONTENT_Y = CAN_Y + 78`，
     `cullOne()` 上界跟着走（滚出顶部的积木不再压标题/状态行）。

  4. **帽块下的空凹槽被当成"另一块小积木"**：`LuaBlockSprite.EMPTY_BODY_H` 32→44、
     槽底 `0x33000000`→`0x59000000`、描边 `0x22FFFFFF`→`0x33FFFFFF`，
     并给**空**凹槽加底部对齐的占位文案（"把积木拖进这个凹槽"/"把积木拖进「否则」凹槽"）；
     帽块的"槽是空的"由 `stack.blocks.length == 0` 传入（模型里栈内积木与帽块同级，`block.body` 恒空）。

  5. **【可用性】"不知道怎么把第二块接到第一块上"**：`addGap()` 只塞了一个 16px 高的**不可见**命中带，
     插入点没有任何视觉；且从调色板拖出的积木**在画布外松手会静默丢弃**。
     新增拖拽插入指示（⑥）：`showDropHints()` 给每个插入点画插入线、`updateDropHints()` 用 primary
     高亮最近的插入点（拖拽期间不重建，只移动高亮条）；画布外松手改为红色状态提示 + 取消音，
     不再静默丢弃；新增事件栈的提示文案也改为"拖积木到凹槽或插入线上松手即接入"。
     并为**引擎内自检加了"模拟拖拽"一步**（`selfTestDragHold` 门控，不设 `ME_LUAGRAPH_SELFTEST` 时零影响）：
     走与鼠标拖拽完全相同的路径，使插入线/最近插入点高亮能在无人操作的环境里被截图复核。

  6. **【层级契约缺口·神秘堆叠】弹层/预览层会被画布积木压住**：`rebuildCanvas()` 每次都把积木 `add()`
     到 `members` 末尾 —— 只要弹层早已打开，一次重建就把积木画到**弹层之上**（实测截图：保存被拒弹层上
     压着「当脚本创建时」帽块与「把积木拖进这个凹槽」占位文案，弹层错误行被拦腰盖住）。
     新增 `raiseOverlay()` / `moveToFront()`：每次重建后把打开中的浮层（弹层 + 预览层）摘除再追加回末尾。
     依据 `FlxGroup.remove(o, true)` 只从 `members` 摘除、**不销毁对象**（flixel 5.2.2 `FlxGroup.hx:396-420`），
     所以"摘掉再 add"是安全的非破坏性抬层。

  7. **【可用性缺陷】程序块放上去就删不掉**：
     - 事件帽块的 `blockPath` 是 `[栈下标]`（长度 1、奇数），而 `GDoc.detach()` 首行即
       `if (blockPath.length < 2 || blockPath.length % 2 != 0) return null;` → `deleteSelected()`
       在此**静默返回**；更关键的是**全工程没有任何删除事件栈的代码**
       （`grep stacks.splice|removeStack|deleteStack` = 0 处），而点一下「事件」积木就会新增一条栈
       ⇒ 事件栈"只能加、不能减"（用户实测反馈：放置后无法删除）。
     - 修法：`deleteSelected()` 增加**奇数路径 = 事件栈**分支（`doc.stacks.splice(si,1)`，含撤销与
       "已删除事件栈：X（含 N 块积木）"反馈）；点击帽块 = 选中该栈并提示"Del 删除整条栈"
       （`startDragMove` 对奇数路径不再走 detach，避免帽块被误判可拖动）；未选中时按 Del 也给提示，
       不再静默。自检新增 `stack delete ok: before=2 afterDelete=1 afterUndo=2 restored=yes` 回归项。

  8. **【可用性缺陷】底部快捷键提示永远显示不全**（用户实测截图：提示止于"Enter 编"）：
     完整键位文案实测约 **1100px**，而底栏左侧可用宽度只有 **636px**（右侧 512px 被 5 个按钮占掉），
     `wordWrap=false` 下超宽部分被静默裁掉。修法：底栏 **48→58 高**（顶边 662→652，仍 ≥ 设计规范的
     底部安全线 648）并把提示**均衡拆成两行**（鼠标/拖拽一行、键盘一行，两行实测约 479px / 564px）；
     不采用"缩写丢键位"方案。另加两道防回归：
     ① `create()` 对每行跑 `fitText()` 兜底（真超宽时截断出**可见的省略号**，不再静默裁切）；
     ② 引擎内自检打印 `hint fit: row1=…/636 row2=…/636 truncated=no barBottom=710`。

  9. **【内存】`remove()` 不销毁 ⇒ unique 位图只增不减**：`FlxGroup.remove(o, true)` 只把对象从 `members`
     摘除、**不调用 destroy**（flixel 5.2.2 `FlxGroup.hx:396-420`），而旧代码以为它会销毁 ⇒ 每次重建画布 /
     拖一次幽灵块 / 弹层翻一页 / 切一次分类都留下新的 unique 位图（`makeGraphic(..., true)` 的结果仍在
     `FlxG.bitmap` 缓存里）。空画布下按 Del/切分类反复操作最明显。
     新增 `disposeSprite()` / `disposeAll()`：摘除 + `destroy()`，并对**纯 FlxSprite** 显式
     `FlxG.bitmap.removeIfNoUse(graphic)` —— `FlxSprite.destroy()` 只做 `graphic = null` + `useCount--`
     （haxelib `FlxSprite.hx:1490-1502`），不会摘缓存；而 Meteoric 版 `FlxText.set_graphic` 已自带
     `removeIfNoUse`（`FlxText.hx:739`），故对文本不再二次摘除（避免重复调用）。
     覆盖点：`rebuildCanvas`（顺序：先摘除全部成员 → 按 `canvasBits` 销毁 texts/chips → 清空
     `spr.texts/chips` 引用 → 销毁底图；顺序颠倒会对同一对象二次 destroy）、`clearGhost`、`clearDropHints`、
     `renderPopup`/`closePopup`、`rebuildPreview`/`closePreview`、`rebuildCategories`/`rebuildPalette`
     （含旧高亮条 `catBar`/`palBar`）、`closeInputBox`（`UIInputBox.destroy()` 才会把**原生输入框**从 stage
     摘掉并解绑监听，只 remove 会每次编辑参数留一个僵尸原生框）。
     另把 `openParamEditor` 的枚举闭包改为捕获 `blockPath` **副本** —— 销毁语义变真之后，捕获 sprite 本身
     会在"弹层开着又重建画布"时读到已销毁对象。

  10. **【可用性】新增 `F1` 操作说明弹层**：底栏两行只放高频键位，完整键位表（10 行）走 `F1` 打开。
      复用通用弹层 ⇒ 自动获得 `raiseOverlay()`（永远在积木之上）、滚轮/↑↓ 翻页、Enter/点击确认、Esc 关闭。
      自检新增宽度断言 `help fit: max=…/556 rows=10`（超宽会在弹层内折行、把正文挤出面板）。

  11. **【界面】编辑器菜单（`MasterEditorMenu`）背景改为主题色**：原实现把 `menuDesat` 染成**当前选中条目
      自带的强调色**（`optionShit[r][4]`）并做 0.4s `FlxTween.color` 过渡 —— 于是"看哪个选项、整屏就是什么色"，
      与玩家选的主题色无关。现改为 `bg.color = DesignTokens.menuTint`（= 当前主题 primary），
      与 Options / Pause / Lua 图形化编辑器统一；随之删掉逐选项的颜色过渡与 `colorTween` 字段
      （否则会留一个 `newColor` 恒等于 `bg.color` 的空转 tween）。
      条目自带强调色保留在表中但不再驱动背景；令牌在 `create()` 读取 ⇒ 切换主题后下次进入生效。
      边界写进 `meteoric-system`：**菜单**属系统域可主题化，**编辑器页本体**仍是非主题域深灰工具界面，未改动。

- **本轮验证（第一版界面缺陷修复 ①-⑩，全部为真产物验证）**
  - 编译：`./compile-mac.sh` 共 8 次 **EXIT=0 / 0 error**（post-build 每次均还原墙钟版 `lime.ndll`
    `cd890285f1d3def18d9f5aafc04a198d` + 重签）；另跑本仓库只读模式 `./compile-mac.sh typecheck`
    **✔ 通过且 app 未被改动**。最后产物 `Meteoric`：20176320 字节，mtime > 全部源码修改时间。
  - 引擎内自检（`ME_LUAGRAPH_SELFTEST=1`，零行为影响的门控入口）。**已实测观测到**（build 6/7 运行日志）：
    `hint fit: row1=505/636 row2=564/636 truncated=no barBottom=710` ｜ `edit ok … undoRedoMatch=yes` ｜
    `stack delete ok: before=2 afterDelete=1 afterUndo=2 restored=yes` ｜
    `hat select: selPath=[0] status=已选中事件栈：当脚本创建时（Del 删除整条栈）` ｜
    `stack delete via Del: stacks 2 -> 1` ｜ `drag hints: gaps=2 lines=2 cursor=on` ｜
    `overlay restack: popupOpen=true popupIdx=52 > lastBlockIdx=51` ｜ `DONE`。
    **尚未运行、仅按估宽推算**（build 8 新增/变更项，待下次自检日志确认）：行 1 追加「F1 说明」后 ≈576/636；
    `help fit: max≈520/556 rows=10`。
  - 视觉复核（逐张 read_image，非摘要）：静止态（无叠字 / 按钮单行 / 状态行单行 / 空凹槽占位文案）、
    拖拽态（插入线 + primary 高亮最近插入点）、弹层层级（复现"弹层开着又重建画布"）、底栏两行提示完整。
    证据留档：`tools/evidence/luagraph-ui-20260915/`（含各图 sha256 与自检/构建日志）。
  - **用户实测确认：功能正常**（事件栈可删除、拖拽接入可用），本轮无遗留阻塞项。

- **已知项**：画布没有真正的裁剪遮罩，向上滚动时积木仍可能贴近标题行（`cullOne()` 已收窄上界缓解）。
- **已知项**：引擎无上限帧率（窗口标题实测 FPS 500~990、CPU ~84%），以及状态切换时 flixel 只 `clear()`
  不销毁成员的固有行为；两者都不是本界面引入，未在本轮处理。

## 未发布（Lua 图形化编程）

- **【新功能】Lua 图形化编程编辑器（积木块 → Lua，桌面端）**：用积木拼出 Lua 脚本，一次生成 `.lua` + 图文件。

  **入口与落点**
  - 编辑器菜单（主菜单按 `7` = debug_1）新增第 8 项「Lua 图形化编程」；Android 上该条目隐藏（`#if mobile` 裁剪）。
    进入走 `LoadingState.loadAndSwitchState`，与 Chart / Character / Dialogue 编辑器一致。
  - 产物：`mods/<当前模组>/scripts/<名字>.lua` + 同名 `<名字>.luagraph.json`；脚本目录不存在自动创建。
    未选择模组时**拒绝保存**并提示，不会误写别的模组；`.json` 不会被当脚本加载（`PlayState.create` 的 `scripts/` 扫描只认 `.lua` / `.hx`）。

  **界面（系统域：遵循 `meteoric-design` / `meteoric-system`）**
  - 分类（156）／积木（300）／画布（720）三面板 + 底部状态条与 5 个 MD3 按钮；圆角磨砂面板、令牌化配色、底图一次绘制。
  - 画布为**多栈**结构：每个事件帽块 = 生成文件里的一个真实回调，帽块凹槽内装整条栈。
  - 高亮条先 `add`、行文字后 `add`（层级契约）；语义色用局部 `COLOR_OK` / `COLOR_ERROR`
    （`DesignTokens` 没有 `error` 字段）。
  - 输入：鼠标拖拽放置/移动 + 点击参数就地编辑（枚举弹清单、数字/文本走 `UIInputBox`，为此给该组件加了可选
    `maxLength` 参数，默认 24 保持既有调用不变）+ 键盘全路径（`[ ]` 分类、`,/./PgUp/PgDn` 选块、`Insert` 插入、
    `←/→` 选参数并微调、`Enter` 编辑、`Del` 删除、`Ctrl+Z/Y/C/X/V/S/O`、`Tab` 预览、`Esc` 返回）。

  **积木库**：10 类 **81 块** —— 事件 9 / 流程 6 / 变量 5 / 精灵 16 / 补间 8 / 相机 5 / 音频 10 / 文本 10 / 杂项 10 / 兜底 2。
  全部函数名与参数序逐条核对自 `source/psychlua/**` 的 `add_callback` 注册原文（203 个注册函数）；
  缓动、混合模式、相机名取自 `LuaUtils` 的**接受值集合**（写别的会静默回落）。
  兜底两块（「调用任意 Lua 函数」「直接写一行 Lua」）覆盖全部引擎 API。

  **语义要点（改动时勿破）**
  - 「等待 N 秒后继续」= `runTimer` + 续接闭包 + 本编辑器生成的 `onTimerCompleted` 调度器
    （仅当图里真的用了等待块才生成）；自定义区若也定义 `onTimerCompleted`，保存前会告警"等待将失效"。
  - 变量为脚本级 `local`，声明在文件顶部；被引用但未声明时自动补 `local x = 0` 并告警。
  - 生成文件分「受管区」与「底部自定义代码区」：受管区整体重写，**自定义区永不覆盖**；
    目标 `.lua` 已存在且**不含标记**（手写脚本）时先弹确认，再把原内容整体搬进自定义区（不丢手写代码）。
  - 预览层只读、不自动执行；保存前静态校验（错误阻止保存、警告只提示）。

  **新增文件**：`source/luagraph/`（15 个：模型 `GBlock`/`GStack`/`GVar`/`GDoc`、目录 `GKind`/`PDef`/`BlockDef`/`LuaBlockDefs`、
  生成器 `LuaCodeGen`、模板 `LuaGraphTemplates`、落盘 `LuaGraphIO`、视觉 `SlotHit`/`BlockMetrics`/`LuaBlockSprite`、`JsonModel`）、
  `source/states/editors/LuaGraphEditorState.hx`；改动：`MasterEditorMenu.hx`（新条目）、`UIInputBox.hx`（maxLength）、
  `TitleState.hx`（自检入口）、`skills/meteoric-system/SKILL.md`（新增该界面小节）。

  **验证（真产物 + 引擎内自检 + 真 LuaJIT）**
  - `./compile-mac.sh` **EXIT=0**（0 类型错误），post-build 已还原墙钟版 `lime.ndll`（9368752 字节 / `cd890285…`）并重签。
  - 引擎内自检（`ME_LUAGRAPH_SELFTEST=1`，环境变量门控、零行为影响的 CI 入口）：
    载入 15 块 / 3 栈 / 1 变量的图 → 插入 → 删除/撤销/重做（edit ok: delete=15 undo=16 redo=15）→ 生成 61 行 **0 issue** →
    保存成功 → 预览 61 行。
  - 生成的 Lua 用**与引擎同源的 LuaJIT**：语法/编译通过，且行为断言全通过（回调齐备、参数无引号污染、
    等待续接为一次性、10 次命中恰好触发 1 次条件分支、`onDestroy` 清理、自定义区在载入期执行）。
  - 手写保护实测：手改自定义区后重新生成，手写内容（含多行）保留且仍可编译。
  - 视觉复核：三面板 / 分类与积木列表 / 画布多栈（含 if-else 双井嵌套与参数槽）/ 预览层 / 状态条与按钮，逐张人工看图。

  **本轮验证中发现并修掉的真实缺陷（记录以免回归）**
  1. **事件名与积木 id 不一致**：栈里存回调名（`onCreatePost`）、目录按 id（`ev_onCreatePost`）查 → 任何图都会"未知事件"、保存被拒。
     新增 `LuaBlockDefs.eventName()` / `byEvent()` 做正式映射（GUI 拖拽与键盘插入两处同步）。
  2. **帽块模板未展开 `$BODY$`**：帽块走"整段字符串 push"，绕过了负责替换占位符的行处理 → 生成物残留 `$BODY$`（LuaJIT 直接拒绝）。
     重构为统一的 `emitTemplate`（帽块与普通积木共用）。
  3. **字符串参数被双重加引号**：模板已写 `'{p:x}'`，`quote()` 又补一层 `"` → `makeLuaSprite('"tag"', '"img"')` 会查不到贴图。
     改为「模板负责引号、生成器只做转义」（`esc` / `sq`）。
  4. **预览层代码行与底部提示重叠**、**状态条文字宽度越界压到按钮区** → 可见行数按面板高度反算、宽度收到按钮区左侧。
  5. **在某个 State 的 `create()` 期间 `switchState` 会原生崩溃（SIGSEGV）**：自检入口改为 `update()` 首帧派发；
     菜单入口改用 `LoadingState.loadAndSwitchState`（与其它重型编辑器一致）。

  **已知限制**：① Android 上入口隐藏（拖拽+键盘为主，触屏没有完整操作路径）；
  ② 仅单向「图 → Lua」，不逆向解析已有 `.lua`（手写脚本仍可整体保留进自定义区）；
  ③ 预览层沿用系统域玻璃面板（半透明），下方编辑器文字会轻微透出（令牌化规范内的既定观感）。

## 未发布（UI 设计系统审查修复）

- **【界面】更新提示界面（`OutdatedState`）按系统域规范重做**。

  **版式**（用户要求：仍是"一个大窗口"，但按 `meteoric-design` 设计）：
  900×520 圆角玻璃面板居中；标题「发现新版本！」30 白；下方**版本对比行**
  （当前版本 → 最新版本，箭头与最新版号走 `primary`）；说明 20 `onSurfaceVariant`；
  底部两个**真按钮**（`前往下载更新` = filled、`忽略更新` = tonal）；
  再下一行「稍后提醒 / 不再提示」开关；最底 16 操作提示。

  **相对旧版的四类改动**：
  ① **两条文字链接 → MD3 按钮**：新增可复用组件 `source/objects/UIButton.hx`
     （filled / tonal / text 三语义；圆角 14；hover 叠 `0x18` 白、pressed 叠 `0x30` 白 + 缩放 0.97 / 100ms；
     带悬停唤醒，避免开界面就"亮着"；`refreshColors()` 走令牌，主题切换即时跟随）。
     ⚠ 组件里踩到与 `makePanel` 同类的坑：**参数默认值必须是编译期常量**，
     不能写 `variant:String = VARIANT_TONAL`（static final 不是常量表达式，Haxe 直接报错），
     已改为字面量默认值 + 构造内规范化。
  ② **背景换域**：`menuBG`（手绘域）→ `menuDesat` 染主题色 + **0.6 黑遮罩**
     （系统域弹层必须压暗；旧版没有遮罩，面板直接浮在手绘背景上）。
  ③ **新增「稍后提醒 / 不再提示」开关**：写 `ClientPrefs.data.updateNotify`（默认 true；
     全字段反射存档 → 旧存档缺字段自动用默认值，无需迁移代码）。关闭后 `TitleState` 不再弹本界面
     （更新检查照旧执行），并在 **设置 → 效果 → 更新提示** 补了回程入口 ——
     否则玩家关掉之后永远看不到更新提示。
  ④ **对齐规范**：圆角 22 / 14、面板内边距 40、按钮高 56（触控红线）、底部不越 648；
     入场 = 面板 α + 上移 12px 的单组 tween 250ms `quadOut`（并发动效 1 组），出场 200ms `quadIn`。

  **三套输入**：键盘 ←/→/↑/↓ 切焦点 + Enter 触发 + Esc 忽略；鼠标/触控悬停高亮、点击即触发；
  开关热区 260×56（含文字），点击翻转并落盘。

  **验证**：`./compile-mac.sh typecheck` 与正式 `./compile-mac.sh` 均 `EXIT=0`；启动冒烟存活、异常行 0。

  **首版实测打脸后的修复（同轮内，用户截图反馈）**：
  1. **底部提示压进开关行、文字糊成一团**：我把写死的屏幕绝对底线 `648` 当成了**面板内相对偏移**
     （`PANEL_BOTTOM - py - 44` → 面板内 216，正好落在版本行下方）。已改为面板内坐标
     `py + PANEL_H - 44`，并把 `PANEL_H` 从常量改为 `panelHeight()`（`min(520, FlxG.height - 48)`），
     窗口非 720 高时也不溢出。
  2. **「最新版本 1.1.2 < 当前版本 1.1.3」**：更新判定原来写的是"索引**不相等**"，
     而本地已升到 `1.1.3 / 4`、远端 `gitVersion.txt` 还是 `1.1.2 / 3` → 本地比远端新也弹更新，
     右栏还画的是那个更旧的远端号。现在判定改为 **`onlineIndex > meVersionIndex` 才提示更新**
     （新增 `TitleState.onlineVersionIndex`），并且版本界面按"远端是否真的更新"切换全部文案：
     标题、右栏（`最新版本` vs `仓库版本`）、说明、主按钮（`前往下载更新` vs `前往仓库查看`）。
  3. **白圆钮出现在面板外、胶囊夹在文字里**：圆钮初值 0 → 从面板左边插值滑入（可见伪影），
     且初值未落位；已改为开关状态确定时**直接落位**、之后才由 `update` 插值。

- **【工具链修复】`compile-mac.sh typecheck` 的 ndll 还原会"忠实地保留坏文件"（实测事故，复现两次）**。
  typecheck 开始前 app 内 `lime.ndll` 已被**前一次构建的 lime 异步收尾**覆盖成非墙钟版
  （8789152 字节），而旧逻辑只做「备份 → 还原 → 与原备份比对」，于是把那份坏 ndll 原样还原并打印
  "已还原"，静默埋下**启动 100% CPU 卡加载界面**的雷（该症状本项目已两次实测）。
  更狠的是：lime 收尾会在还原**之后**继续覆盖，第二次实测直接落到构建树里的未打补丁版
  **8660712 字节**（缺 `HiResMs` / `WaitEventTimeout`）。
  现在还原流程改为**多轮判据 + 复验**：① 识别已知坏指纹（8660712 字节）→ 用
  `tools/lime.ndll.wallclock` 覆盖；② 与权威墙钟版逐字节一致 → 通过；③ 与备份一致且大小 > 9000000
  （另一份墙钟构建）→ 通过；④ 其余先还原再验，最多 10 轮，末尾打印 `size` 便于判断。
  提示文案也改为"已还原**墙钟版**"。`./compile-mac.sh` 正式构建的后处理本来就会恢复墙钟版，
  所以构建产物一直是好的 —— 出问题的是 typecheck 这条本该"只读"的路径。
  **实测**：同一次 typecheck 前后 `size` 均为 9368752、`md5` 均为 `cd890285f1d3def18d9f5aafc04a198d`。

- **【界面】Mods 左面板：选中项套用与 Credits 同款「大卡片」（图标 + Mod 名 + 启用状态）**。

  **实现**：行高改为不等距 —— 选中行 `CARD_H = 104`、其余 `ROW_H = 56`、留白 `ROW_GAP_S = 4`；
  行位逐行累加（原来写死的 `LIST_Y + r * ROW_GAP` 全部删除），卡片展开时下面的行整体让位。
  滚动窗口规则与 `CreditsState` 完全一致（按真实可用高度 `LIST_H = 476` 算容量 = 7 格；
  `lo/hi` 夹取，卡片最多落在**倒数第二格**；`cardY` 再做一次硬夹取兜底）。

  **三处必须一起改的地方**（改一处漏一处就会错位）：
  1. **复选框与状态文字位置**：原来写死 `LIST_Y + 4 + r * ROW_GAP`，卡片一展开整列错位 →
     改为跟随行位表 `top`。
  2. **选中行的复选框/状态文字收进卡片**：卡片本身承担选中视觉，行文字与复选框隐藏，
     避免"两个选中框"（Credits 那边踩过一次）。
  3. **`updateRows()` 的续接调用**：`changeSelection()` 末尾原来只挪 `selectorBar`、不刷新行位 →
     现在改为调用 `updateRows() + updateInfo()`，否则卡片位置永远停在旧行位。

  **卡片图标**：复用 Mod 自己的 `pack.png`（与右侧大图同源同 `iconCache`）。这里有个时序坑：
  图标是 `updateInfo()` 首次加载时才写入 `iconCache` 的，而卡片在 `updateRows()` 里构建 →
  所以图标由 `applyCardAvatar()` 单独负责，并在 `updateInfo()` / 卡片定位两处做**懒同步兜底**
  （`cardAvatarApplied` 守卫，就绪后不再重复套用）。图标缺失时退化为名称首字母。

  顺带清理：`updateRows()` 里每帧刷屏的 `trace('[STATUS] ...')` 调试残留已删除。

  **验证**：`./compile-mac.sh` → `MAC_BUILD_EXIT=0`；静态数学自检（脚本按源码常量与算法复刻，
  150 条 × 800 次上下切换）：卡片越界事件 **0**，卡片底边最大 **616**、底线 **628**（余量 12px）。

- **【界面】Credits 左面板：选中项改为「头像 + 名字 + 职位」大卡片（下面行让位）**。

  **实现**：`CreditsState` 行高改为不等距 —— 选中行 `CARD_H = 104`、未选中行 `ROW_H = 56`、
  行间留白 `ROW_GAP_S = 4`；行位由 `computeRowYs()` **逐行累加**得出（原来写死的 `r * ROW_GAP`
  已删除），所以卡片展开时下面的行整体让位。卡片内容 = 头像（缺图退化为磨砂圆 + 首字母，
  与右侧大图标同款）+ 名字 + 职位（取条目描述首句，按像素宽逐字截断，不依赖 `numField.numLines`
  这类非公开成员）。头像/名字只在选中项变化时构建一次（`cardShownIndex` 守卫），不在每帧重建。

  **三个实测踩坑（都写进代码注释了）**：
  1. **两个框**：旧的 `selectorBar`（632×46）只被卡片盖住一部分 —— 卡片 104 高、它 46 高且下移 3px，
     会从卡片下缘露出约 55px，看起来就是"小长方形 + 大卡片"两个选中框。现改为卡片是唯一选中视觉，
     `selectorBar.visible` 恒为 false。
  2. **滚动后卡片消失**：滚动窗口一度被裁到"越过 `curSelected`"的非法值，行位表里根本没有选中项，
     卡片与它的行文字一起被裁掉。窗口规则现已统一到 `changeSelection()`：
     `hi = cur-selectedCapacity+1`、`lo = hi-1`，把旧窗口位置**夹进 [lo,hi]**（优先保持原位、越界才最小移动）。
  3. **顶出左面板**：容量一度按"面板高度"算（偏大一格）→ 卡片被放到窗口最后一格时底边越过底线。
     改为按**真实可用高度** `LIST_H = LIST_BOTTOM - LIST_Y = 476` 算容量（= 7 格），
     且让卡片最多落在窗口**倒数第二格**；`layoutRows()` 里另加一道硬夹取
     `cardY = min(cardY, LIST_BOTTOM - CARD_H)` 兜底。

  **验证**：`./compile-mac.sh` → `MAC_BUILD_EXIT=0`；另做**静态数学自检**（脚本按源码常量与
  算法逐行复刻，遍历 120 条 × 600 次上下切换）：卡片越界事件 **0**，卡片底边最大 **616**、
  底线 **628**（永远留 12px 余量）。

- **【入口修复】设置 → 容器界面：进入先黑屏再跳 —— 重写入口，改为即时换状态（不挂转场）**。

  **现象**：从「设置」按 Enter 进「容器」管理页时，先黑一下、然后容器界面才跳出来。
  探针实测排除了两类猜测：`ContainersMenuState.create()` 只花 **16ms**、容器目录扫描 **0ms**
  （1 个容器）→ **不是加载卡顿**，是转场层本身的问题。

  **根因**：`MusicBeatState.switchState()` 会先挂 `CustomFadeTransition(0.6,false)` 出场转场，
  而 `FlxGame.switchState()` 的顺序是 `FlxG.cameras.reset()` → `FlxG.bitmap.clearCache()` →
  旧状态 `destroy()` → 新状态 `create()` → 下一帧 `draw()`：**这一整段里屏幕上没有任何东西被绘制**，
  玩家看到的黑屏就是这个空窗；随后新状态又自己挂一层入场转场（`MusicBeatState.create()` 里
  `if(!skip) openSubState(new CustomFadeTransition(0.7,true))`）→ 观感「黑一下再跳出来」。
  进曲那条路没这问题，是因为 `LoadingState.create()` 不调用 `MusicBeatState.create()`，
  **从来不挂这个转场**。

  **改法（只动入口，不动过渡动画实现）**：
  ① `OptionsState` 新增唯一入口 `enterContainersMenu()`（`#if desktop`）：
  `FlxTransitionableState.skipNextTransOut = true`（跳过新状态自己那层入场转场，
  用到引擎自带的 `skip` 开关）+ `FlxG.switchState(new ContainersMenuState())`
  （不进 `startTransition`，因此不挂出场转场）。
  ② `ContainersMenuState.exitToOptions()` 对称处理：返回设置同样直接换状态，
  不再走 `LoadingState.loadAndSwitchState`（那条路会过渡场 + 加载界面）。
  ③ 删掉 `ContainersMenuState.create()` 里的 `transIn/transOut = defaultTrans*` 死代码
  （本界面已不走 `transitionIn/Out()` 路径，留着会让人误以为转场仍生效）。

  **注意（改前必读）**：**不要**为了"看起来更连贯"把入口换回 `MusicBeatState.switchState` ——
  那正是本次要修的黑屏；要恢复转场就必须同时解决"转场层空窗"（转场层自己先铺不透明底）。
  本轮**未改动** `source/backend/CustomFadeTransition.hx`（中途一版曾改它，判断为方向错误后整文件还原）。

  **验证**：`./compile-mac.sh` → `MAC_BUILD_EXIT=0`（类型检查零错误，后处理已恢复墙钟版
  `lime.ndll` md5 `cd890285f1d3def18d9f5aafc04a198d`）；启动冒烟未闪退、异常行 0；
  **用户运行期实测：黑屏消失，进入即时**。

- **【界面修复】容器界面背景跟随主题色 + 设置分类列表文字被选中框压住（用户实测通过）**。

  **① 容器界面背景没跟随主题色 `source/states/ContainersMenuState.hx`**：背景精灵加载
  `menuDesat` 后**缺 `bg.color` 赋值**，于是永远显示贴图原始品红，换主题色毫无反应。
  补 `bg.color = DesignTokens.menuTint`（= 本主题 `primary`，见 `DesignTokens.MENU_TINTS`），
  与设置一级页（`OptionsState.create`）、所有设置二级页（`BaseOptionsMenu.create`）**同一取色路径**。
  令牌在「设置→界面→主题色」里即时重算，本界面下次 `create()` 生效；
  按 `R` 重新扫描只刷新列表，不重建背景（无需也不应重绘）。

  **② 设置分类列表文字被选中框盖住 `source/options/OptionsState.hx`**：Flixel 的绘制顺序 =
  `FlxGroup.members` 顺序 = `add()` 先后，而后 add 的盖住先 add 的。原实现把 `selectorBar`
  建在选项行**之后**（`add(row)` 在前、`add(selectorBar)` 在后）→ 高亮条压在所有分类文字上方，
  表现即「选项框滑过时把文字压住/糊住」。改为**高亮条先 add、文字后 add**，文字恒在最上层，
  高亮只从文字底下滑过。**只调整 add 顺序，不动坐标系/面板尺寸/动效**（`selectorTween` 0.12s `cubeOut` 未变）。
  代码里已留「禁止挪回 rows 之后」的契约注释；同一条层级规则写进 `skills/meteoric-system/SKILL.md`
  新增的「绘制层级（z-order）」小节（并登记 `ModsMenuState` / `MasterEditorMenu` 尚未收敛）。

  **验证**：`./compile-mac.sh` → `MAC_BUILD_EXIT=0`（类型检查零错误，后处理已恢复墙钟版
  `lime.ndll` md5 `cd890285f1d3def18d9f5aafc04a198d`）；运行期用户实测两项均通过。

- **镜头换段「瞬移」—— 缓动强度写死 2.4（2026-09-12 定位）**：
  用户反馈换段时镜头像瞬移。上一轮曾试图重构相机（自管 scroll / 改 deadzone），已全部回退；
  本轮改为**只动一个数**。

  **根因（先纠正一个误判）**：`followLerp` 本身**没有问题**。原式
  `elapsed * 2.4 * cameraSpeed * playbackRate / (FlxG.updateFramerate / 60)` 里，
  哨兵 `updateFramerate = 100000` 在 flixel 的「写」与「用」两侧**完全约掉**：
  `每帧增益 = followLerp * updateFramerate / 60 = elapsed * 2.4 / 60 = 4%（@60fps）`。
  实测 60 / 120 / 480 / 1000 / 4000 fps 收敛时间一致（1.223 ~ 1.248s），**帧率无关**；
  且 `followLerp` 恒在 1e-5~1e-7 量级，远低于 flixel 硬阈值 `60/updateFramerate = 0.0006`，
  **从不触发**「无缓动」分支。
  真正的问题是**时长**：1.22s 才走完 95%；配合「死区几乎整屏 → 镜头平时完全静止」的既有语义，
  换段那一下在观感上就是瞬移。

  **修复（1 个公式 + 1 张档位表，几何行为零改动）**：
  ① `PlayState.cameraSmoothSpeed()`：强度改由设置档位提供，原写死的 `2.4` 降为兜底值；
     调用点公式逐字未变，只把 `2.4` 换成该函数。
  ② `ClientPrefs.camSmoothPresets`（唯一事实来源）：`fast=9.2` / `normal=5.7` / `smooth=3.63`
     —— 由 `k = 1 - 0.05^(1/(60T))` 反解，对应 95% 到位 **0.30s / 0.50s / 0.80s**。
  ③ `SaveVariables.camSmooth`（默认 `'normal'`）+ `EffectsSubState` 新增「镜头缓动」选项，
     沿用 `closeAnimStyle` 的「英文存储值 + `displayOptions` 中文显示名」模式。
  ④ `import.hx` 补 `flixel.math.FlxRect`（工程原本未导入，新代码用到即报 `Type not found : FlxRect`）。

  **⚠ 分母改不得**：`/ (FlxG.updateFramerate / 60)` 必须保留哨兵。若图省事改成写死的 `60`，
  60fps 下 `followLerp` 会升到 1e-3 量级、**越过 0.0006 阈值**，退回无缓动瞬移。

  **验证（纯数值；帧率无关性由「哨兵在分子分母约掉」结构保证，无需实机采样）**：

  | 档位 | SEC | 60fps 每帧增益 | 95%@60 | 95%@1000 | 95%@4000 | 标称 |
  | --- | --- | --- | --- | --- | --- | --- |
  | fast | 9.2 | 15.33% | 0.300s | 0.324s | 0.325s | 0.30s |
  | normal | 5.7 | 9.50% | 0.500s | 0.524s | 0.525s | 0.50s |
  | smooth | 3.63 | 6.05% | 0.800s | 0.824s | 0.825s | 0.80s |
  | 原样 | 2.4 | 4.00% | 1.223s | 1.247s | 1.248s | 复现校准基准 ✔ |

  **保留语义**：`cameraSpeed` 倍率（Tank 12 / PhillyStreets 1.5~2 / 舞台 `camera_speed`）、
  `cameraSpeed = 0` 冻结、暂停与过场冻结、`snapToTarget()` 瞬切演出、稳态落点
  （`camFollow - 半屏`）全部未动——因为死区、`_scrollTarget`、调用点几何一行未改。

- **Windows 启动黑屏卡在加载界面 —— 桌面端 100000 帧率哨兵缺前提（2026-09-11 实测事故）**：
  用户在 Windows 上启动即黑屏、卡在 Intro 不前进（无崩溃转储 → 不是异常，是**不推进**）。

  **根因**：桌面端启动帧率用的是 `100000`（"无人工限制"哨兵，`Main.hx` 的 `game.framerate`），
  它让原生帧循环的 `framePeriod = 1000/100000 = 0.01ms`。该值**只有存在「墙钟帧循环补丁」时才安全**：
  `ci/lime-sdl3-patch/project/src/backend/sdl/SDLApplication.h` 里明确写着
  「原 Uint32 在 framePeriod < 1.0 时每次 `+= framePeriod` 被截断成 +0 →
  catch-up 循环 `while (nextUpdate <= currentUpdate)` 永不前进 → 主线程 100% 死循环（加载卡死）」。
  macOS 靠构建后恢复 `tools/lime.ndll.wallclock`（含 `WaitEventTimeout` / `SDL_DelayNS` 补丁符号）
  来保证这个前提；**Windows 的 lime.ndll 不含该补丁，且项目没有任何对应机制**，
  而 `ClientPrefs.framerateMode` 的桌面默认值偏偏是 `'无上限'` —— 前提从未被代码强制过。

  **修复（三处，含一处我自己初版遗漏的关键点）**：
  ① `Main.hx` 启动值：`#if mac 100000 #else 120 #end`
     —— **这是关键**：`game.framerate` 是**首帧就生效**的初始值时，早于
     `ClientPrefs.loadPrefs() → applyFramerate()`，所以只改设置默认值**来不及**
     （Preloader 阶段就已经踩坑）；初版只改了 ClientPrefs，复查时才发现这个漏洞。
  ② `ClientPrefs.framerateMode` 默认值：macOS `'无上限'`，其它平台 `'120'`。
  ③ `applyFramerate()`：`'无上限'` 分支用 `#if mac` 包住，非 macOS 落到 `default: 120`。
  ④ `GraphicsSettingsSubState`：非 macOS 不再暴露「无上限」档位（选项数组按平台构造）。
  ⑤ `loadPrefs()` 新增旧值迁移：非 macOS 把存档里遗留的 `'无上限'` 收回 `'120'`
     （否则设置界面会出现"没有任何项被选中"的怪状态）。

  **验证**：不看二进制字符串（常量池会重复计数，不可靠），直接查**生成的 C++ 源码**——
  `export/release/windows/obj/src/Main.cpp:225` → `setFixed(5,"framerate",120)`；
  对照 `export/release/macos/obj/src/Main.cpp:225` → `100000`。两平台类型检查零错误。

  > ⚠ **本节结论已被下方「Windows 无上限档位恢复」取代**：当时把「无上限」档位整个摘掉，
  > 是因为误以为 Windows 编不出带墙钟补丁的 ndll。后来查明 32 位包早在 8/18 就成功编出过
  > 带补丁的 Windows ndll（10,638,336 字节），64 位包只是**从没重建过**。


- **Windows「无上限」帧率档位恢复 + 墙钟补丁能力自检（2026-09-11 二次修复）**：
  上一节的处置是"Windows 上不提供「无上限」"。用户要求恢复该档位，复查后确认当初的
  前提判断有误 —— **补丁版 Windows ndll 完全编得出来，缺的是"重建 + 校验"这道工序**。

  **真正的根因（三份 ndll 二进制比对）**：

  | 文件 | 大小 | Meteoric/SDL3 标记 | 墙钟补丁 |
  |---|---|---|---|
  | `export/release/windows/bin/lime.ndll`（64 位在用的） | 8,281,088 | 无 | 无 |
  | `export/32bit/windows/bin/lime.ndll`（8/18 构建） | 10,638,336 | 有 | 有 |
  | `tools/lime.ndll.wallclock`（mac 版） | 9,233,040 | 有 | 有 |

  即：`compile-windows.sh` **只跑 `lime build`、从不重建 lime.ndll**，而 `lime build` 会把
  haxelib 发行版目录里的**老 ndll 原样拷进产物**（本地实测复现：构建后产物里出现的
  正是那份 8,281,088 字节的老文件）。64 位包因此长期带着没补丁的 ndll，
  配上 100000 哨兵就是启动死循环 → 于是才有了"摘档位"这个治标处置。

  **修复（原生 + 引擎 + 构建三层）**：
  ① **原生能力标记**：`ci/lime-sdl3-patch/.../MeteoricFrameLoopPatch.cpp`（新增）导出纯 C 符号
     `lime_meteoric_frame_loop_patch`（返回 1 = 本次构建来自带墙钟补丁的 SDL3 树）。
     ⚠ 不用 `DEFINE_PRIME*` 注册 cffi 原语：hxcpp 规定一个模块只能有一次且需 `IMPLEMENT_API`，
     而 `src/ExternalInterface.cpp` 已占用，多一个就报一大片
     `multiple definition of 'hx_register_prim'`。纯导出符号 + `cpp.Lib._loadPrime` 无副作用。
  ② **启动自检 + 安全回退**：`ClientPrefs.hasWallclockFrameLoop()` / `unlimitedFramerateValue()`
     —— 探测到标记 → 「无上限」给 100000；探测不到（老 ndll、或新老混搭）→ **自动退回 480**
     （已实测可用档位）。从此不会因为换了一份 ndll 就黑屏。
  ③ **档位恢复**：`GraphicsSettingsSubState` 的档位列表 `#if (mac || windows)` 加回「无上限」；
     撤销 `loadPrefs()` 里"非 macOS 把 `'无上限'` 收回 120"的迁移（不再改写用户存档选择）。
     `Main.hx` 启动帧率改为 `#if mac 100000 #elseif windows ClientPrefs.unlimitedFramerateValue() #else 120 #end`。
  ④ **构建防再踩**：`compile-windows.sh` 增加"构建后恢复墙钟版 ndll"（与 `compile-mac.sh`
     恢复 `tools/lime.ndll.wallclock` 同款）+ 导出符号门禁（不通过则 exit 1）；
     新增 `ci/build-lime-win64-ndll.sh` 作为可复现的原生重建脚本。

  **本轮踩掉的构建坑（都已在补丁树里修好，别再踩）**：
  - `include/system/CFFI.h` 无条件 `#include <hl.h>`，而原版 `Build.xml` 把
    `-Ilib/hashlink/src` 放在所有 section 之外 —— hxcpp 不会下发，编译必然
    `fatal error: hl.h`。已移入 `lime` 分组（`lib/lzma-files.xml` 同步）。
  - `-Dstatic_link` 下 `LIME_MOJOAL` 被强制开启，而 mojoal 是为 SDL2 写的
    （`#include "SDL.h"` + SDL2 音频 API），SDL3 树上必然编译失败。新增
    `-Dmeteoric_no_mojoal` 开关回退到 openal-soft。
  - `-Dstatic_link` 产出的是静态库 `liblime.a`，而引擎是通过 `<ndll name="lime">`
    **动态加载** `lime.ndll` 的 —— 重建时**不能**带 `-Dstatic_link`。

  **产物**：`tools/lime.ndll.win64.wallclock`，10,881,024 字节、md5 `10f98167c1502f1f1f482efdb9eb98ff`，
  导出表含 `lime_meteoric_frame_loop_patch`；替代原来的 8,281,088 字节 / md5 `589d3781…` 老 ndll。


- **「无上限」档位探测的两个致命缺陷（2026-09-11 用户在 Windows 实测暴露）**：
  上一节的实现虽然把档位加回来了，但**探测本身从未真正执行**，且**会让新 exe 直接闪退**。

  ① **闪退**：`cpp.Lib._loadPrime(null, …)` 的第一个参数是**非空 `String`**，传 `null`
     时生成代码为 `_loadPrime(null(), …)`，C++ 侧拿到空指针后构造 `std::string` →
     `std::logic_error: basic_string: construction from null is not valid` →
     `terminate called after throwing…` → 双击启动即闪退（**与 ndll 无关**：老 exe 没有这段
     代码，所以同一份新 ndll 配老 exe 完全正常，这一点被用户的对照实验证实）。
     修复：改用空串 `''` 并带候选名回退 `['', 'lime', 'lime.ndll']`，彻底不传空指针。

  ② **探测恒失败**：原先用 `if (_wallclockFrameLoopProbe >= 0) return …` 当"已探测"缓存，
     但 hxcpp 把静态字段初值放进 `ClientPrefs_obj::__boot()`，而 `Main` 的字段初始化器在
     **Main 构造时**就调用探测 —— 跨编译单元静态初始化顺序不保证，`__boot()` 可能尚未执行，
     此时读到零初始化的 `0`，`0 >= 0` 恒真 → **直接 return false，一次都没查过 ndll**。
     修复：每次进入无条件重置哨兵，使探测对调用时机完全免疫。

  **新增启动诊断**（`TitleState`，仅 Windows）：打印
  `[FRAMERATE] 档位=… 墙钟补丁探测=有/无 无上限档取值=… update=… draw=…`，
  一次运行即可区分"探测失败 / 存档没选该档位 / 引擎确实到不了该帧率"三种情形。

- **「无上限」探测判据最终定为「文件身份」（2026-09-11 收尾，用户实测通过）**：
  上一节的原生符号探测经过**两条死路**后废弃，最终判据改为「读 exe 旁边的 lime.ndll 算 SHA1
  与常量比对」，确定性且与 hxcpp/lime 版本无关。

  **实测确认（用户 Windows 运行日志）**：
  `[FRAMERATE] 档位=无上限 墙钟补丁探测=有 无上限档取值=100000 update=100000 draw=100000`
  —— 探测命中、100000 生效、无闪退、无黑屏、窗口不再被裁。

  **两条死路的完整记录（避免今后再走）**：
  | 尝试 | 结果 |
  |---|---|
  | `cpp.Lib._loadPrime(null, …)` | 第一个参数是非空 String，传 null → C++ 构造 `std::string(nullptr)` → `std::logic_error: basic_string: construction from null is not valid` → `terminate` → **启动即闪退** |
  | `_loadPrime('' / 'lime', …)` | 不崩，但底层 `__hxcpp_get_proc_address(inLib, inPrim, inNdll=false, …)` 取的是**主程序里的 cffi 原语表**（hxcpp `CFFILoader.h`："Via 'GetProcAddress' on the exe"），**不是**按名字去已加载 DLL 里查符号 → 纯 C 导出符号永远查不到 → **探测恒为"无"** |
  | **文件 SHA1 比对（采用）** | `Sys.programPath()` 旁读 `lime.ndll` → `haxe.crypto.Sha1` → 与 `ClientPrefs.WALLCLOCK_NDLL_SHA1` 比对 |

  当前常量：`af8663cd2beeddf2cd16ad5179d78acba2c8501e`
  （对应 `tools/lime.ndll.win64.wallclock`，10,881,024 字节）。
  ⚠ **换新补丁版 ndll 时必须同步更新该常量**，否则「无上限」按设计退回 480（宁可降级、绝不黑屏）。

  原生导出符号 `lime_meteoric_frame_loop_patch` 保留，但**只作构建期门禁**：
  `compile-windows.sh` 用 `objdump` 查它，保证交付的 ndll 一定是补丁版。

- **多版本容器：Windows 端实现（2026-09-11）** —— 容器从「仅 macOS」扩到 **macOS / Windows 双平台**。
  不是照搬：macOS 的三根支柱在 Windows 上都不存在，因此按平台做了**有意不同的实现**：

  | | macOS | Windows |
  |---|---|---|
  | 包装器 | `wrapper.sh`（POSIX shell） | `wrapper.bat`（cmd，新增 `buildWrapperWindows()`） |
  | 宿主让位 | 缩窗 1×1 + `visible=false` + `kill -STOP` | `visible=false`，**不挂起**（`suspendHost()` 在 Windows 上是空操作） |
  | 唤醒 | wrapper `kill -CONT <hostPid>` | 宿主每帧 poll `exit.txt`（`Phase.Running` 变成主力路径） |
  | 宿主 pid | **必须**（失败即拒绝启动） | 不需要（`launch()` 里 `hostPid = 0`），顺带避开「宿主与目标同名 Meteoric.exe」误杀 |
  | 退出码 | `wait $ME_APP` → `$?` | `start "" /B /WAIT` → `%ERRORLEVEL%`（含"为空/非数字→-1"兜底） |
  | 前台化 | `activate.sh` + System Events（需授权） | `activate.ps1` + `WScript.Shell.AppActivate`（无需授权） |
  | 默认热键 | **Ctrl+C**（组合键） | **F10**（单键）；Windows 上宿主全局收键，Ctrl+C 在 FNF 里是常用操作会误触 |
  | 退出核对 | 不需要 | 新增宿主侧 `targetReallyGone()`：核对进程是否真的退出，1.5s 超时则 `taskkill /F /T` |

  **新增 `source/backend/ContainerProcess.hx`**（跨平台进程原语）：探活（macOS `kill -0` / Windows
  `tasklist /FI "PID eq"`）、前台化、命令执行。`ContainerSession` 的状态机因此保持与平台无关。

  **Windows 不挂起的理由**：`kill -STOP` 无干净等价物，`ntdll!NtSuspendProcess` 属未公开 API。
  隐窗后 SDL 不渲染隐藏窗口，CPU 接近零；代价是宿主进程留在内存（数百 MB），
  好处是全程无信号、无未公开 API，且能被任务管理器正常看到。

  **关于「把引擎启动在一个窗口里」（真窗口内嵌）——系统限制，不做**：Windows 唯一的跨进程内嵌手段
  `SetParent()` 官方明确要求「两个窗口必须由同一个进程创建」，而容器方案本质是两个独立进程；
  macOS 更无等价 API。已在 `CONTAINERS.md` 写明理由，避免以后重复踩。

  **本轮自查抓出并修掉的 7 个真 bug**（全部来自逐行审查生成脚本，而非纸面推演）：
  ① `.ps1` 用 `Get-NetTCPConnection` 探活 —— 单机 FNF 引擎没有 TCP 连接 ⇒ `alive` 恒 false ⇒
  第一轮就退出，**前台化永远不执行**；改用 `Get-Process -Id` + 抑制报错。
  ② wrapper 起手写 `app.pid = 0`，而 `.ps1` 只判 `target -le 0` 就 `give up` ⇒ 同样永远不激活；
  加 `target -le 4 ⇒ 视为无效` 继续轮询。
  ③ `wrapper.bat` 里的 pid 反查写在 `start /WAIT` **之后**（目标已退出）⇒ 必然落空，
  使宿主退出核对成死代码；改为"尽力反查 + 查不到即视为未知"。
  ④ **陈旧 `app.pid` 会让退出核对拿旧 pid 去 `taskkill`** —— 可能误杀恰好复用该 pid 的无关进程；
  wrapper 现在启动前先 `del app.pid`（macOS 版 wrapper 本来就会 rm）。
  ⑤ `:me_watch` 标签循环里用 `%ME_GUARD%` —— cmd 在多行标签块内是解析期展开，计数器永远读旧值（潜在死循环）；
  已改为 `enabledelayedexpansion` + `!ME_GUARD!`；同时把 watchdog 整体**移出脚本**，
  改由宿主侧 `targetReallyGone()` 承担（宿主侧能被类型检查与验证，cmd 脚本只能真机试错）。
  ⑥ `autoDetectApp()` 在 Windows 上会选错：NTFS 无 POSIX 执行位（第 2 步必然失败），
  且容器里同时存在 `.app` 与 `.exe` 时会优先选 `.app`；已按平台调整优先级（Windows 先找 `.exe`）。
  ⑦ 多处 `$` 陷阱：PowerShell 变量、以及**注释文字里的 `$alive`** 都会被 Haxe 当模板插值
  （编译期 `Unknown identifier`）；全部按项目惯例写 `$$`。

  **验证状态（诚实标注）**：macOS 与 Windows 两个目标 **类型检查零错误**；Windows 交叉编译
  **exit 0**，产物 `Meteoric.exe`（09-11 19:27）内 `ContainerProcess`×3、`buildWrapperWindows`×2、
  `buildActivatorWindows`×2、`wrapper.bat`、`activate.ps1`、`tasklist`、`taskkill`×3、`AppActivate`、
  `start "" /B /WAIT`、`wmic`、`forceKill`×5、`targetReallyGone`×2 全部在位；
  `wrapper.sh` / `activate.sh` 经 `sh -n` 语法校验。
  **但 `.bat` 与 `.ps1` 无法在 macOS 上执行**（本机无 wine——Homebrew 的 `wine-stable` 因未过
  Gatekeeper 被禁用；PowerShell cask 亦不可用），因此这两个脚本的**运行时行为必须在真 Windows 机器上验证**，
  已列入交付待验清单。


- **容器三连修（2026-09-11，全部有实测证据）**：针对「按 Control 就回主引擎 / 容器窗口无法聚焦 / 返回后 TitleState 不跳」三个报告：

  ① **按 Control 就回主引擎 —— 组合键语义实现错**（真 bug）：`ClientPrefs.containerExitKeys` 默认 `[CONTROL, C]`，
  界面 `describeHotkey()` 渲染成 `CONTROL + C`（组合键），但 `ContainerSession.checkHotkey()` 是**逐键独立判定
  `JUST_PRESSED`**，等价于 `CONTROL || C` ⇒ 单独按 Control 立即 `requestQuit()` → 目标进程被 TERM → wrapper
  唤醒宿主 → `finishReturn()` → `FlxG.resetGame()`，于是“一按 Control 就回主引擎”。修法：`CONTROL` 必须处于
  **PRESSED（按住）**、`containerExitKeys` 里必须有一个键 **JUST_PRESSED**，且修饰键本身不算主键；命中时写
  `hotkey hit: CONTROL+C` 日志（旧日志只有 `exit=0 (hotkey)`，无法定位按键来源）。界面提示同步改为
  「组合键：先按住 CONTROL，再按 C；单独按任一键都不会退出」。

  ② **容器窗口无法聚焦（点标题栏能弄到最前、随即掉焦）—— 让位方式 + 前台化时序双错**：
  - **让位方式错**：原实现「缩成 1×1」，但缩小的窗口**仍是 key window**，macOS 认为 Meteoric 仍占据前台，
    目标引擎的激活请求被判为后台应用抢焦点而拒绝。改为 `window.visible = false`（SDL_HideWindow），
    SDL 才会交出窗口级焦点（`lime.ui.Window.set_visible` → `SDLWindow::SetVisible` 已核实链路；
    旧注释“隐藏窗口会连菜单栏一起摘掉”是错的，那只发生在应用级隐藏）。
  - **前台化时序错（根因）**：`activateApp()` 在 0.6s 触发一次，而目标引擎窗口要几百毫秒到数秒才创建；
    首次失败后 `activated = true`，唯一的重试落在 `Phase.Running` —— 但宿主在 `STOPPING` 阶段就已 `SIGSTOP`，
    **那个分支永远不会执行**，等于前台化从未成功过。修法：新增 `ContainerLauncher.buildActivator()` 生成
    `runtime/activate.sh`，由 `nohup` 独立于宿主生命周期运行：轮询 `app.pid`（60×0.1s）→ 每 2s 用 System Events
    查目标是否**已在前台**（是则不动，避免反复抢焦点）→ 否则 `set frontmost ... to true` → 进程已死 /
    连续 3 次失败即放弃并留痕（绝不无限重试刷日志）。
  - **宿主回不来的兜底**：`restoreHostWindow()` 现在先 `visible = true`，再用 osascript 按**宿主自己的 pid**
    抢回前台。这一步不能省：宿主若停在失焦状态，flixel 在 `_lostFocus && FlxG.autoPause` 下**整机不更新**
    （`FlxGame.hx:520`），state 切换请求也不会执行。

  ③ **返回后 TitleState 节拍静止 —— 与 ② 同源的失焦冻结 + 保命闸 + 一次性定位埋点**：`finishReturn()` 在
  `FlxG.resetGame()` 之前临时关闭 `autoPause`（复位后 `FlxGame.onFocus()` 会按
  `FlxG.autoPause = ClientPrefs.data.autoPause` 恢复用户设置），确保整机复位这一帧一定跑得动。
  并新增 `backend/Diag.hx`：`TitleState` 每 60 帧把 `frame / musicNull / musicPlaying / musicTime / songPos /
  curStep / curBeat / autoPause / timeScale` 写入 `mods/_containers/_diag.log`，用于区分「失焦冻结（frame 不涨）」
  与「音乐时间源冻结（frame 涨而 musicTime 不动）」，不再靠猜。

  **顺带修掉的两个真缺陷**：`container.json` 的 `suspendHost` 字段**从未被解析**（`ContainerStore.parse` 不读它，
  改它没有任何效果），文档已标注；wrapper 的日志重定向由 `>` 改为 `>>` —— 旧写法会在 wrapper 起跑时把宿主刚写入的
  `launch:` 记录整段截掉（实测日志里只剩 `session end`），截断改由宿主侧 `ContainerLauncher.rotateLog()` 负责。

- **容器：修「返回后 TitleState 节拍静止」—— 根因是标题音乐引用被销毁后再没重建（2026-09-11 二次定位，含实测日志）**：
  首轮我给了两个候选（失焦冻结 / 音乐时间源冻结），**实测证明两个都不是**。`backend.Diag` 埋点日志显示返回后
  `frame` 从 40 一路涨到 6600（更新循环完全正常），但 `musicNull=true` 持续整段、`songPos` 冻在 `3797`、
  `curStep/curBeat` 冻在 `25/6`、`sickBeats=0`。真实链条：
  `FlxG.resetGame()` → `FlxGame.switchState()` → `FlxG.sound.destroy()` 把 `FlxG.sound.music` 置为 **null**
  （标题音乐未设 persist，会被销毁）→ 第二次进 `TitleState` 时 `initialized=true` 于是 `startIntro()` 不执行 →
  而**唯一**会启动标题音乐的地方是 `beatHit()` 里的 `case 1: playMusic(...)`（靠 `sickBeats` 从 1 起计数）
  ⇒ 没音乐 ⇒ `Conductor.songPosition` 永远 0 ⇒ `curStep` 永不递增 ⇒ `beatHit()` 永不触发 ⇒ `sickBeats` 永远 0
  —— **自举死锁**。玩家侧听到的是旧音频对象的残留，不是新播放的音乐。
  修法（`TitleState.hx`）：返回路径（`initialized == true` 分支）在 `startIntro()` 之后补一句
  `if (FlxG.sound.music == null) { playMusic('freakyMenu', 0); music.fadeIn(4, 0, 0.7); }`，
  与首次启动的写法完全一致（音量 0 + 4s 淡入），不动首次启动既有流程。
  定位完成后**已删除全部埋点代码**（`source/backend/Diag.hx` 整个文件 + `TitleState` 内三处调用与两个计数器）。

- **容器：退出方式的真相与文档修正（实测 `session end: exit=0` 无 `(hotkey)` 标记）**：
  前台化修好之后，**前台是目标引擎、宿主被 SIGSTOP 冻着**，宿主收不到任何键盘事件 —— 因此
  `Ctrl + C` 这类"宿主侧全局热键"与该模式**物理互斥**（目标引擎内按 Ctrl+C 只会触发它自己进程里的
  `requestQuit()`，写进它自己的 runtime 目录 = 空操作）。经确认，退出方式以**关闭目标引擎窗口**为准
  （wrapper watchdog 已验证能正确收尾）。`CONTAINERS.md` 第 3 节改写为「退出容器（怎么回来）」并说明
  热键仅在 Meteoric 窗口仍为前台时有效；容器界面详情区文案同步改为「退出容器：直接关掉目标引擎窗口」。

  **本轮实测证据（第二次运行，全部来自用户机器的真实日志）**：`[ME] launch: … hostPid=22884 wait=1.4s`
  （证明日志覆盖缺陷已修，上一轮这行会被抹掉）；`[ME] activator: frontmost ok (pid 22892, try 1)`
  （**前台化真实成功**，第一次轮询时目标进程尚未注册为 application，`-1719` 后 try 1 成功 —— 重试逻辑按设计工作）；
  目标进程 22892 退出后 `exit.txt=0`、`phase.txt=idle`、无残留进程（收尾链完好）。

  **本轮实测证据**：类型检查 `--no-output` 零错误；把 `buildWrapper`/`buildActivator` 编成真 cpp 二进制落盘后
  `sh -n` 双脚本通过、`$` 转义逐个核对无误；功能实测 ① 目标 pid 已死 → 0 秒退出零日志 ② 目标已在前台 → 不做任何
  设置（`CUR=1` 分支）③ **把后台应用 `motrix-next`(pid 9603) 激活为 frontmost，try 0 成功**。
  （测试目录与临时二进制已清理，测试期间抢走的前台已还原。）


- **多版本容器（Containers）：把别的引擎装进 Meteoric 里一键切换**：新增容器机制——玩家把任意版本的目标引擎（Psych 0.6.3 / 0.7.3 / 1.0.4、SeiunEngine 等）整个丢进 `mods/_containers/<名称>/`，补一个 `container.json`，即可在游戏内切过去跑它的 mod，退出后 Meteoric 自动回来并重启。改动：① 新增 `source/backend/ContainerManifestParser.hx`（清单解析，**永不抛异常**：字段缺失/类型错/JSON 损坏一律折成 `problem` 文案给界面红字）+ `ContainerManifest.hx`/`ContainerManifestData.hx`/`ContainerResourceSpec.hx`/`ContainerInfo.hx`/`Phase.hx`（**一类型一文件**——Haxe 一个文件只有一个顶层类型会提升为模块名，纯 typedef 文件不提升，混装会连环 `Type not found`，已用最小复现实证）；② 新增 `source/backend/ContainerStore.hx`（目录发现 `appRoot`/`modsRoot`/`containersRoot`、容器扫描、`resources/` → 目标引擎资源根的 staging（**只增不改**：不写目标引擎配置、不改主程序、工作目录设为该资源根以适配 Psych 0.6.3 的相对 `mods/`）、执行位与 `Info.plist` 可执行文件探测、文件系统小工具）；③ 新增 `source/backend/ContainerLauncher.hx`（生成 `wrapper.sh`、拉起目标引擎、`container.log` 日志、`app.pid`/`exit.txt`/`cmd.txt`/`phase.txt` 状态文件、shell 引用转义）；④ 新增 `source/backend/ContainerSession.hx`（会话状态机 IDLE→LAUNCHING→HIDING→STOPPING→RUNNING→RETURNING；窗口焦点用 `onFocusIn/onFocusOut` 自行记账——lime 的 `Window` 没有 `focused` 字段；热键查询用 `FlxKeyManager.checkStatus`——`FlxG.keys` 本身不可调用）；⑤ 新增 `source/states/ContainersMenuState.hx`（系统域 MD3 界面：圆角面板 + 列表 + 详情/自检 + 操作条，键盘/鼠标/触控三套输入，滚轮走 WheelScroll 限速）；⑥ `Main.hx` 新增 `onContainerFrame`（桌面端 ENTER_FRAME 驱动会话，宿主被 SIGSTOP 后由该帧接上收尾）；⑦ `ClientPrefs` 新增 `containersEnabled`（默认 false = 老玩家零感知）与 `containerExitKeys`（默认 Ctrl+C，**容器专属字段**，不动 `keyBinds` 表结构以免老存档 `controls_v3` 出现空洞）+ `normalizeLoadedKeys()`（JSON 往返后把 FlxKey 从裸 int/键名还原，名字走 `FlxKey.fromStringMap`；与 `normalizeLoadedMaps` 同因同治）；⑧ `OptionsState` 新增「容器」分类（`#if desktop`，**唯一入口**；从容器界面返回时按标签 `pendingSelectLabel` 恢复选中，不依赖 static 索引）；⑨ `Mods.ignoreModFolders` 登记 `'_containers'`——`getModDirectories()` 只按该白名单过滤，**没有**「下划线前缀自动跳过」这条规则（实测确认），不登记的话 `mods/_containers` 会被扫成一个名为 "_containers" 的假模组；⑩ `compile-mac.sh` 新增容器目录构建保全（构建会重置 Resources，容器是 GB 级玩家数据，独立快照 `tools/user_containers_prev/` 兜底）；⑪ 新增 `CONTAINERS.md`（清单字段表 / 目录布局 / 热键 / 实现概要 / 已知边界 / 排错表）。

  **运行机制（关键设计，非权宜之计）**：宿主 `kill -STOP` 自己 → 目标引擎独占屏幕 → wrapper（`nohup … &` 后台化，独立于宿主生命周期）在目标引擎退出后 `kill -CONT` 唤醒宿主 → 宿主恢复窗口尺寸并 `FlxG.resetGame()` 整机重启。之所以必须用 wrapper 而不是宿主自己 `wait`：宿主一旦被 STOP 就不可能再去 wait 子进程；唤醒信号由 wrapper 发出，所以目标引擎崩溃 / 被 Ctrl+C 强杀 / 秒退，宿主都一定会回来（另有 watchdog：宿主进程消失则不留孤儿容器；退出文件 40×0.25s 超时兜底）。全程**文件通信**，宿主侧零线程、零阻塞读 —— 规避本项目已确认的「工作线程分配 hxcpp GC 对象破坏堆」风险（同 `LoadingState.hx` 的处理结论）。视觉让位用**缩窗口到 1×1** 而非 `window.visible = false`：macOS 上隐藏窗口会连应用菜单栏一起摘掉且恢复时机受 SDL 事件循环影响不可控。

  **实测验证（非纸面推演）**：① 用与 `ContainerLauncher` 逐行同构的模板真跑一遍——目标引擎 pid 正确落到 `app.pid`（不是宿主 pid）、`cmd.txt` 触发 TERM→宽限→KILL 升级链、退出码正确写入 `exit.txt`（实测 7）、`phase.txt` 落 `idle`；② `kill -STOP` 宿主后目标引擎自然退出：宿主进程状态 `S → T → S`（**挂起→唤醒闭环成立**）、`exit.txt=0`；③ 把 Haxe 源里的 `s += '...'` 按 Haxe 语义（**`$$` = 字面 `$`**）展开成真实 wrapper 文本后 `sh -n` 语法检查通过。

  **隔离性**：容器目录 `mods/_containers/` 由 `Mods.ignoreModFolders` 显式排除 ⇒ 容器内 mod 不会出现在 Meteoric 的 Mod 列表，也不进 `modsList.txt`。

  **边界（已在 CONTAINERS.md 明示）**：本轮只做 macOS（Android 端按需求舍弃，相关入口全部 `#if desktop`）；目标引擎是**独立进程 + 独立窗口**，不做真窗口内嵌（那需要逐个第三方引擎改窗口/渲染层源码，与「现成发行包丢进去就能用」互斥）；首次切换会弹一次 macOS「自动化」授权用于自动前台化（拒绝仅需手动点一下目标引擎窗口）。

- **容器：修「启动失败：无法获得宿主进程 PID」（Haxe 的 `$$` 转义坑）**：`resolveHostPid()` 原实现只走
  「写临时文件 → 读回 → parseInt」这一条链，且临时文件还写在 app bundle 内部的 `appRoot()` 下 ——
  任何一步失败就只剩一句报错、容器完全无法启动（用户 2026-09-10 实测命中）。
  ① **真 bug**：命令字符串写的是 `'echo $$ > ' + path`，而 **Haxe 会把 `$$` 转义成一个字面 `$`**，
  于是 shell 收到的是 `echo $ > path`，写入文件的内容只有一个 `"$"` → `Std.parseInt` 返回 null →
  返回 0。真机 cpp 二进制实测复现：旧写法文件内容 `"$"`、新写法 `$$$$`（Haxe 吃掉两个、shell 收到 `$$`）
  得到 `"8646"` 有效 pid。
  ② **同类隐患**：`'echo $PPID'` 里的 `$PPID` 会被 Haxe 当**标识符插值**（当前作用域没有 `PPID` 才
  侥幸编译通过；将来出现同名变量即编译失败），已改为 `$$PPID`；`ps -o ppid= -p $$` 改为 `-p $$$$`。
  ③ **四级兜底**（任一路成功即可启动）：`$PPID` → `ps -o ppid= -p $$` → 临时文件通道（候选目录按可写性
  排序：容器 runtime → appRoot → `$TMPDIR`）→ `/usr/bin/perl -e 'print getppid()'`；四路全部失败时
  把具体原因（`lastPidError`）拼进错误文案，不再只给一句「无法取得」。
  ④ 取消对「写临时文件」这个单点的依赖：主通道用 `sys.io.Process` 直接捕获 stdout（不落盘、不受目录
  可写性影响）。

- **容器：修「点切换毫无反应」的可见性缺陷 + 非 ASCII 路径致命约束 + 陈旧进程保护**：
  ① **错误文案被同一帧覆盖**（本轮最关键的体验级 bug）：`update()` 原本每帧写
  `ContainerSession.active ? statusLine() : '容器功能：…'`，会把 `attemptLaunch()` 刚写入的
  `启动失败：xxx` 在同一帧冲掉 —— 玩家侧表现就是「点了切换没有任何反应」。改为粘性状态
  （`statusError` / `statusInfo` + `updateStatusText()`，错误红色显示且保留到下一次操作）。
  ② **目标引擎异常退出的结论**：`finishReturn()` 现在解析 `exit.txt`，非 0 退出码时提示
  「异常退出（退出码 N）—— 目标引擎可能无法在本机启动」并指向日志（原来只报退出码，玩家无从判断）。
  ③ **陈旧会话保护**：启动前用 `kill -0` 探测 `app.pid`，若上次的目标引擎仍在运行则拒绝重复启动
  （避免两个实例抢窗口）。
  ④ 「打开容器文件夹」改「打开日志/容器目录」：默认打开当前选中容器的 `runtime/`
  （`container.log` / `exit.txt` / `wrapper.sh` 都在这里，排障第一现场）。
  ⑤ **硬约束入档：容器目录名必须纯 ASCII**。实测把 Meteoric 1.1.0 的 `.app` 放进名为
  `示例-psych-0.6.3` 的容器后，每次启动都在 `lime.text.Font::__fromFile → NativeCFFI.lime_font_load_file`
  抛 `Error : Invalid UTF16` 秒退（退出码 255）；把**字节完全相同**的 app 复制到纯 ASCII 路径后
  立即正常。已逐项排除文件清单/大小/md5、扩展属性、代码签名、架构、字体与 manifest 内容。
  示例容器与模板已改名 `me-1.1.0-test`，中文说明文件改 `README.txt`；显示名继续由 `displayName` 提供。

- **容器入口收敛到设置 + 容器界面补鼠标光标**：① 移除 `MainMenuState` 的主菜单「容器」项（主菜单项必须有 `mainmenu/menu_*.png` 美术资源，容器没有；入口只保留在 `设置 → 容器`），连带删除为它引入的文字菜单项整套机制（`TEXT_OPTIONS` / `textItemLabels` / `isTextItem` / `styleTextItem` / `textOptionLabel` 及构建、平滑滚动、吸附、淡出四处分支），主菜单恢复原状、净减约 3000 字符；② `ContainersMenuState` 补齐鼠标光标：`create()` 里 `FlxG.mouse.visible = true`、`destroy()` 里置回 false（`MusicBeatState` 不会自动开鼠标，本界面全鼠标可交互却看不到光标）；③ `OptionsState.pendingSelectLabel` 让"从容器界面返回"按标签选中「容器」而不是靠 static 索引。

- **容器入口开关 + 构建链两处致命修复（本次实机启动容器时暴露）**：
  ① `ContainersMenuState` 新增左下「容器功能：已启用/已关闭」开关按钮（`containersEnabled` 默认关闭，
  原先**没有任何界面能打开它**，「切换到此容器」在关闭态是灰的 → 玩家进不了容器模式；现点按钮即写
  ClientPrefs 并落盘），操作条改为 4 键等宽布局，状态行移到操作条上方。
  ② **`compile-mac.sh` 修 `rm -rf` 被只读目录卡死**：macOS 上从 zip/外部解压来的 mod 常带 `dr-xr-xr-x`
  只读目录，`rm -rf` 报 "Permission denied" 并以非零码退出 —— 脚本开头是 `set -e`，会把**整个构建**
  干掉（实测 2026-09-10 构建就死在这里，产物停在 9-06，玩家侧表现就是"设置里根本没有容器入口"）。
  新增 `rm_force()`：删除前先 `chmod -R u+w`。
  ③ **`compile-mac.sh` 备份改 APFS 克隆**：新增 `cp_clone()` 优先 `cp -R -c`（copy-on-write 克隆；实测
  200MB 耗时 6ms），失败回退普通 `cp -R`。原先每次构建要对 14GB mods 做两次全量拷贝（备份 + 还原），
  这正是"四天没重建过"的实际原因；改后近乎瞬时且不占额外空间。
  ④ 环境侧：`haxelib` 的 lime dev 链接原指向 `/private/tmp/lime-full`（只剩 `.git`、`haxelib.json` 丢失），
  导致 `Error parsing haxelib.json for lime@dev`，构建第一步即失败。已 `haxelib dev lime /usr/local/lib/haxe/lib/lime/8,2,2`
  重指到有效版本目录（原 `.dev` 备份在 `/tmp/lime.dev.bak`）。

- **Obsolescence-spam v6：移植 Seiun 最新版 Turbo 模式（除"不建议"项）**：新增 `source/backend/TurboDensity.hx`（聚合区分析 + 指纹侧车缓存，移植自 Seiun `de03be5e`；假视觉流带/密度分箱与强制 botplay 开关不移植）。改动：① **聚合区 `buildZones`**：100ms 分箱 ≥4000NPS 且无长条的连续区间（≥500ms），缓存到 `crash/turbo_cache/<md5>.bin`（song|mod|数量|Fingerprint 指纹，二次加载免分析）；② **数据级批量结算**（fastSkipPastNotes 移植）：`CastNote.wasHit` 新字段；dense + botplay + 过载（上一帧结算 ≥128 条触发 30 帧滞回 `_overloadFrames`）且**非聚合区**时，视距内半带（≤ spawnWindow/2）的音符**不建 Sprite 直接结算**（判定恒为 `ratingsData[0]`、按 density 加权计分/命中/血量/combo/NPS、strum 高亮每帧每轨一次、250ms 评级节流复用），物化预算集中到外半带；长条走对象路径保链；聚合区内禁软截止（真实物化+对象上限，视觉完整）；③ **自适应物化预算**：dense+botplay 下 `spawnBudget = clamp(elapsed*30, 2048, 20000)`（掉帧自动追补；非 dense 保持原逻辑）；④ **notePool 复用（dense 门控）**：`NoteGroup.poolEnabled` 仅 densePerfMode 开启，击杀实例有界回池（≤256），复用走现有 `recycleNote` 复位链（与全新构造同一填充逻辑，省 new 分配）；非密集谱行为逐字节不变。

- **Obsolescence-spam v5.4：命中击杀延迟移除（批内 O(n²)→帧末 O(n)）**：定位 `notes_avg` 300us+ 的另一主因——`processBotHits` 每命中调用 `invalidateNote` → `FlxGroup.remove(n,true)` 是 **indexOf + splice（O(成员数)）**（flixel 5.2.2 `FlxGroup.hx:401/408` 实证），每帧数百命中 × ~900 成员 ≈ 每帧数十万次指针搬移。改动（`NoteGroup.hx` + `PlayState.hx`）：新增 `beginBatchKill/endBatchKill`——批内 `invalidateNote` 只做状态复位并登记 `Note.batchKillPending`（同一帧防重复登记），命中批 + 兄弟副本扫全部结束后**一次 O(n) 过滤**重建 `members`（`@:privateAccess length=w` 保持长度同步，存活顺序不变）；批外所有调用点（回收窗/重开/回溯）保持原即时剔除路径，零行为变化。
- **Obsolescence-spam v5.3：命中热点收敛（密集自动游玩安静命中档）**：新 profile 直方图定位——`notes_avg` 从 24~47us 涨到 300~380us（每帧数百命中 × 逐命中开销），主峰 1.0~1.25ms + 2~5ms 长尾（大命中批帧），`1.25~1.5:0` 空洞=非渲染抖动而是命中批处理。改动（全部仅 `densePerfMode && (cpuControlled || replayMode)` 生效，计分/命中/评级计数/溅射节流不受影响）：① `goodNoteHit` 跳过 `stagesFunc` 逐命中闭包（每命中一次闭包分配 + 派发）；② `popUpScore` 的 `RecalculateRating`（7×setOnScripts + callOnScripts('onRecalculateRating') + updateScore 字符串重建）改为每 250ms 结算一次——HUD 仍有 4Hz 刷新，`endSong` 的 RecalculateRating 保证结算值精确；③ 密集自动游玩强制免评级/连击/数字弹窗（等同 lessBotLag：弹窗精灵+FlxTween 每秒数百个，GC 关闭时 destroy 只断引用不回收内存，长期游玩线性上涨，也是 2~5ms 长尾来源）。手动游玩零变化。

- **Obsolescence-spam v5.2：帧率波段抖动（700~1000 乱跳）定位与节流**：墙钟帧循环（`ci/lime-sdl3-patch` SDLApplication.cpp）已确认零限速（`catchup>=4 → nextUpdate=currentUpdate+framePeriod`），抖动来自真实帧耗时的 100ms 级波段；主嫌疑=标题栏 FPS 模式（存档 `fpsInTitleBar=true`）下 `FPS.updateWindowTitle` 每 100ms 一次 `NSWindow.title` 写入（主线程 WindowServer IPC + 合成器打点）。改动：① **标题写入节流 500ms**（`source/openfl/display/FPS.hx`：`_titleSetInterval=0.5`，FPS 数字仍 100ms 计算、内存/CPU 数据仍 1s 采样；0=关闭节流）；② **MeteoricProfile 帧时直方图**（`source/backend/MeteoricProfile.hx`：每窗口输出 `frame_p50/p90/p99` + 10 档分布 `hist=[<0.5:…,0.5-0.75:…,…]`）——下次 `./compile-mac.sh profile` 复测，直方图可直接判定：双峰（快慢帧交替）→ 合成器/呈现节奏；长尾（绝大多数帧很快、个别尖峰）→ 单帧开销源。③ 判定线/063 溅射/对象上限/落盘去重/CHECK_POINTER 等 v5.x 改动保持。

- **Obsolescence-spam v5.1：hxcpp/Note 热路径榨干**：① **release 移除指针校验/栈行号/栈回溯**（`Project.xml`：`HXCPP_CHECK_POINTER/HXCPP_STACK_LINE/HXCPP_STACK_TRACE` 改为仅 debug 生效）——hxcpp 4.3.2 的 `HXCPP_CHECK_POINTER` 让**每一个 Haxe 对象指针解引用**走空值检查+NullReference 分支（`include/hx/Object.h` mPtr getter），是音符逐帧循环/quad 合批等热路径的固定开销，release 移除是经典大项；CrashHandler Haxe 侧阶段日志不受影响，原生地址仍可 atos；② **Note 快绘制路径去冗余**（`Note.hx` draw）：tile 渲染下 `calcFrame(false)` 是纯 no-op（`FlxSprite.calcFrame` 在 `FlxG.renderTile && !force` 直接 return），逐音符每帧白调一次——改为仅 `useFramePixels && dirty` 时 `calcFrame(true)`，语义等价；③ **followStrumNote 属性写去重**（`Note.hx`）：方向角恒 0、alpha 恒 1 的密集音符跳过值未变的 setter 写入（set_angle 每次重算弧度/标记 dirty、alpha 写同样开销），每音符每帧省 1~2 次属性写；④ `--dce full`、`HXCPP_LINK_OPTIMIZE`、`HXCPP_GC_BIG_BLOCKS` 已确认保持。未动（风险/观感权衡，待用户拍板）：音符对象池重启用（曾引发原生崩溃 SIGSEGV）、密集谱强制关 antialiasing、角色/舞台裁剪。

- **Obsolescence-spam v5：判定线回退 + NoteSplash 换 PE 0.6.3 经典皮肤 + 密集对象硬上限**：依据实测 `profile.txt`（v4 后曲末爆发段 2.15~2.19ms/约 460 FPS，峰帧 51ms）与 320MB 原谱统计（v4 视觉档同屏对象峰值 1,319 @T≈420.4s；截图 6:46 ≈406s 仅 ~270 对象，非渲染瓶颈）。改动：① **判定线回退**：`StrumNote` 静态帧恢复素材原色（灰蓝毛胚），仅按下/击中走 RGB 列色——v4 把 static 纳入 RGB 着色后，默认 NOTE_assets 静态帧（实测中心 RGB(135,163,173)，非白色）经通道加权输出粉白/浅青/浅绿/浅粉，即"判定线变色"根因；与 Psych 0.7.3/PE 0.6.3/原版一致；② **NoteSplash 换 PE 0.6.3 经典贴图**：新增 `noteSplashes-063`（png/xml/txt，预染色四色 紫/蓝/绿/红），`defaultNoteSplash` 指向它；该皮肤跳过 PixelSplashShader（`shader=null` raw 直出）——RGB 通道加权默认 blob 贴图是"五颜六色"来源，raw 直出同时省去每颗溅射的 shader 绑定；自定义 splashSkin 仍走原 RGB 路径；保留密集谱每轨 250ms 溅射节流；③ **密集谱对象硬上限 800**（仅 densePerfMode 自动生效、不写存档）：场上精灵对象数（`NoteGroup.aliveObjectCount` 自维护，**非** density 加权 `countLiving()`——后者一簇可达数百，直接复用会破坏判定）达到 800 时，距判定线 > 60ms（=击杀窗 6ms 的 10 倍，无排期竞态；溢出 ~70 颗，实际场上 ~870）的箭头延迟进场（不消失、可判定、可打，墙更贴线）；非密集谱恒关闭；④ **CrashHandler 落盘去重**：`PlayState.noteSpawn:start` 原条件 `currentSpawnId==0` 在空段每帧成立 → 每帧 `File.saveContent`（每秒 ~1000 次磁盘写，空段 1000→800 帧回归的直接来源）；`popUpScore:start` 原每命中落盘一次（团灭段每秒数千次）。两处收敛为每曲各记一次（与 `CrashHandler.mark` "约 10 次/曲" 的设计意图一致），快速重开时随 `generateChartNotes` 复位。


- **曲终结算崩溃修复（自动游玩/回放路径）**：`update` 中 boyfriend 待机恢复块（`PlayState.hx:3462`，仅在 botplay/replay 分支执行）缺少 `endingSong` 守卫——`finishSong→endSong` 启动转场/角色拆卸后同一帧继续走到该行，`boyfriend.animation.curAnim` 已被置空，内联的 `getAnimationName()` 抛 Null Object Reference（日志：`MeteoricEngine_2026-09-05_23'48'39.txt`，栈 `PlayState.hx:3462`，阶段 `PlayState.endSong`）。修复：该块与 `keysCheck` 内同型块（`PlayState.hx:5474` 附近）均加 `!endingSong && !finishingSong` 守卫 + `animation/curAnim` 非空校验。
- **0:00 卡结算修复（谱面目录名 ≠ JSON song 字段 / 空音频 resync 死循环）**：`data/Obsolescence-spam/` 内 `song="Obsolescence"` 时，PlayState 按 song 名找音频必然 `MISSING SOUND` → 空 Sound（length=0）。其连锁反应：`stepHit` 漂移检测 `|music.time(恒0) - songPosition| > 20ms` 在歌曲位置一越过 20ms 即成立 → `resyncVocals()` 用 `music.time=0` 回写 `songPosition` → **每 2~4 帧把歌曲时钟拉回 0** → 音符永不生成、HUD 恒 0:00、无法结算（逐帧日志 + `Conductor.songPosition` setter 调用栈实证 `PlayState.resyncVocals ← stepHit ← MusicBeatState.update`）。修复：① `resyncVocals`/`stepHit` 在 `music.length<=0` 时跳过同步（无音频可同步，绝不动时钟）；② 按 song 名加载失败时回退 `chartFolder` 目录音频（与 Freeplay 试听/预加载同路径），人声同步兜底；③ `generateChartNotes` 记录谱面末尾 `chartEndTimeMs`，`startSong` 取 `max(音频长度, 谱面末尾)`；④ `update` 中"歌曲位置越过 `songLength` 即 `finishSong`"作为全歌曲收尾兜底（不再依赖 `onComplete`），`finishSong` 加 `finishingSong` 防重入。
- **拖入安装 Mod 崩溃修复（20GB 级 mod / 2.1GB 谱面 JSON）**：文件夹安装不再在工作线程逐文件 `File.copy`（数十万次 Haxe 级读写 + 跨线程字符串消息 → Release 堆损坏 abort / Debug `hxcpp CriticalError`），改为后台线程执行系统原生命令（macOS `ditto` / Windows `xcopy` / Linux `cp -R`），工作线程零 Haxe 对象分配；`ZipExtractor` 全体消息改 `safeSend` 并全函数 try/catch，杜绝异常逃出线程闭包；临时目录清理改回主线程；`onDropFile` 入口加 `CrashHandler.mark('ModInstaller:drop')` 与兜底 try/catch；文件夹拷超时按目录字节数动态预估（30MB/s 下限 + 120s 保底，上限 30 分钟），不再固定 30 秒误杀大 mod。
- **暂停/结算入场动效收敛**：Pause / Results（含联机精简版）由 `FlxEase.quartInOut 0.4s + 逐行 startDelay`（最长可见延迟 1.15s）统一为 `quadOut 0.25s` 同步淡入，去掉逐行 stagger；修复合规项 P1-1
- **Pause 标题修复**：「已暂停」此前 `alpha = 0` 且无对应 tween（从不显示），现随面板淡入
- **主菜单确认动效**：Enter 确认由 `FlxFlicker 1s` 收敛至 `0.4s`（P1-2）
- **色彩令牌化（P2）**：Pause/Results 次级文本 `0xFFA9A9B8 → 0xFFD7D7E0`；空态/未选中 `0xFF6E6E7A / 0xFF9A9AA8 → 0xFFCFCFDC`；暖色强调 `0xFFFFD966 / 0xFFFFE066 → 0xFFFFD9A0`；高亮条统一 `0x3AFFFFFF`（原 Pause/Results 用 `0x2EFFFFFF`）
- **规则库**：新增 `skills/`（兼容 skills.sh 的 Agent Skills 规则库，中文），已接入 `~/.dsh/skills`（软链接，仓库为唯一事实源）
- **Obsolescence-spam 500 帧优化（v4：串色修复 + 密集场成员减半）**：承接 v3（密集段 frame 9.8~11.5ms → 中段 1.8~2.5ms / 400~550 FPS，但不透明爆发段仍 5.7~7.2ms、峰值 14ms）。剩余大头＝同屏数千颗精灵（渲染 + `followStrumNote` 均随成员数线性涨）。本轮：① **串色修复**：`StrumNote` 静态帧恢复 RGB 列色渲染（原实现 static 刻意“恢复素材原色”→ 灰白毛胚帧在密集墙后露出即“串色/米灰箭头”，与 PE 0.6.3/原版一致改为静态/按下/确认全部列色）；② 密集谱出生窗口 2000ms→1100ms（同屏成员近似减半；音符约 1.1s 前出现，墙略短、判定/计分零影响）；③ 密集谱视觉采样预算 1200→700、单簇下限 2→1、上限 12→8。
- **Obsolescence-spam 500 帧优化（超密集谱自动高性能档，v3 视觉/性能修正）**：`METEORIC_PROFILE` 实测（空段 frame≈0.85ms/1100+ FPS；密集段 frame_avg 9.8~11.5ms，其中 `PlayState.update` 仅 0.66~2.14ms、`notes` 子阶段峰值 1.28ms → **瓶颈是几千颗音符的逐精灵渲染**）。改动：① 原始音符 ≥400 万（`DENSE_FORCE_MERGE`，Obsolescence-spam=1180 万）时自动启用 `densePerfMode`——Note 走 perfMode 同款 quad 合批快速路径（关 RGB 着色器），不改用户存档、非密集谱行为不变；② **视觉修正**：密集谱默认皮肤强制换 PE 0.6.3 原生贴图 `noteSkins/NOTE_assets-063` 且烘焙/着色走 raw（不叠 RGB、不叠平涂色——v1 的平涂色叠加烘焙色出现“阴间”配色，已撤销，仅用户手动 perfMode 仍平涂）；③ 密集谱视觉采样预算 1800→1200、单簇下限 3→2（纯渲染采样，覆盖 0→全跨度不变）；④ 对手命中/自动游玩批处理原「每命中全表反向扫描兄弟视觉副本」O(命中×成员) 改为登记 chartSeq、本帧一次 O(成员) 批扫（语义等价）；⑤ 撤销“密集谱自动开启重叠隐藏 10px”（隐藏真实箭头/长条头，只透传用户值）；⑥ **BF 待机恢复**：PlayState 回块改 `isAnimationFinished()`（atlas 安全），且 `Character.update` 为玩家镜像“非玩家侧已被验证”的 holdTimer 阈值回 idle + 「sing 播完被清空 curAnim 定格」兜底（双保险）；⑦ **合批路径覆盖长条头/视觉副本**：移除 `sustainLength <= 0` 子条件（非 sustain 箭头无 clipRect/无拉伸，批路径与慢路径一致，密集墙全部进 quad 批）；⑧ **密集谱自动游玩溅射节流**：每轨 250ms 最多 1 次（原 botHitBatch 仅每帧每轨 1 个，700fps 下每秒 2800 个、同屏上千个溅射精灵——既是“五颜六色”乱象也是密集段渲染大头）。注：`limitNotes`（场上上限）按 density 加权计数，密集簇密度可达数百，自动抬升会破坏判定，故一律不自动改。

### 更新界面：开关圆点「飞出」+ 按钮「悬浮两个都亮」根因修复（2026-09-12）

> 依据《更新》对话的 bug 清单继续修。**上一轮对"圆点飞出"的结论是误判**：
> 探针 `knob(rel)=80,513 track=489,508` 被读成"横向是对的（80 = 轨道相对 x），只是低 5px"——
> 实际上 `toggleKnob` 与 `toggleTrack` 是 **content 的同级子精灵（同一坐标基准）**，
> 80 与 489 相差 409px，圆钮当时确实被画在面板外（面板从 x=190 起）。

| Before | After | Why |
| --- | --- | --- |
| `UIButton` 的 `bg/overlay` 用 `makeGraphic(w,h,TRANSPARENT)`（无 `unique`） | 构造时 `makeGraphic(w,h,TRANSPARENT, true)`，只建一次 | flixel 的 `makeGraphic` 对 (宽,高,色) 相同的调用会命中位图缓存、返回**同一张 BitmapData**；更新界面两个按钮同为 300×56 → 悬停 A 的状态层同时出现在 B 上（「悬浮两个都亮」），两个按钮还都会画成实心（用户截图实证）。同类坑此前已在 `ChartingPanel`/`ChartWidgets` 用 `unique=true` 修过 |
| 状态变化时 `makeGraphic` "重建" graphic | `pixels.fillRect(pixels.rect, TRANSPARENT)` 清空 → 重画 → `dirty = true` | 尺寸不变时 `makeGraphic` 不清旧像素 → 移开鼠标后白层永久留在位图里（「粘住不灭」）；"重建"实为原地叠加。（范式：`UIInputBox.redraw` / `ChartWidgets.redraw`） |
| `toggleTrack.makeGraphic(...)` 每次翻转重建 | 首次 `unique` 创建 + 翻转时原地清空重画 | 同上：开→关后 `primary` 填充会残留在"关"态胶囊上 |
| `toggleKnob.x = toggleKnobX`（16/80 = 轨道内相对量，直接当子精灵 x 用） | `toggleKnob.x = toggleTrack.x + 圆心 − KNOB_R(11)`；插值与夹取都在**圆心空间** | 轨道在 x=489、圆钮画在 x=80 → 「圆点飞出」。实测修复后 `dx=69 / knob.x=558 / track.x=489`（关态 dx 应为 5） |
| 夹取用胶囊半径 16 夹**精灵左边框** | 夹**圆心** `[16,80]`，半径用 11 | 圆钮直径 22（半径 11）≠ 胶囊半径 16，两个数被当成同一个 |
| 点击后 `setPressed(false)` 只在 `justReleased` 分支（被 `!leftState && !fading && interactable` 门控） | `goDownload()/goNext()` 开头 `clearPressed()` | 点击当帧即置 `leftState/fading` → 释放分支永不执行，按钮带 `0x30` 白层 + 0.97 缩放僵在整段转场 |

**改动文件**：`source/objects/UIButton.hx`、`source/states/OutdatedState.hx`。

**验证**：`./compile-mac.sh typecheck` EXIT=0（ndll 已还原墙钟版 md5 `cd890285f1d3def18d9f5aafc04a198d`）；
`./compile-mac.sh debug` 构建 EXIT=0；实机 macOS release 产物进更新界面截图复核——
圆钮完整落在胶囊内（右侧内缩 5px）、两按钮 filled/tonal 语义分离、三行文字不再重叠；
探针行 `[TOGGLE] dx=69 knob.x=558 track.x=489 center=80 target=80`。用户本机复核确认已修复。

**遗留**：探针留在 `#if meteoric_debug` 下（正式构建零开销，长期可用）；`Main.meVersionIndex`
预览用的临时值 `1` **已还原为 4**。

---

## 目录

- [v1.1.2 更新总览](#v112-更新总览)
- [高帧率与性能](#高帧率与性能)
- [JS 引擎优化融合](#js-引擎优化融合)
- [渲染与 HUD 修复](#渲染与-hud-修复)
- [安卓兼容与存储修复](#安卓兼容与存储修复)
- [开发与诊断工具](#开发与诊断工具)
- [构建基础设施](#构建基础设施)
- [版本与更新校验](#版本与更新校验)
- [v1.1.1 更新总览](#v111-更新总览)
- [联机对战（全新）](#联机对战全新)
- [联机真双人（v1.1.1 核心）](#联机真双人v111-核心)
- [局域网房间自动发现](#局域网房间自动发现)
- [模组皮肤跨端同步（CHARSYNC）](#模组皮肤跨端同步charsync)
- [结算与判定](#结算与判定)
- [稳定性 · 性能 · 兼容](#稳定性--性能--兼容)
- [版本与发布](#版本与发布)
- [v1.1.0 更新总览](#v110-更新总览)
- [Meteoric Reboot 1 —— 环境搭建与基础优化](#meteoric-reboot-1--环境搭建与基础优化)
- [Meteoric Reboot 2 —— 交互与字体](#meteoric-reboot-2--交互与字体)
- [Meteoric Reboot 3 —— 界面全面重构](#meteoric-reboot-3--界面全面重构)
- [Meteoric Reboot 4 —— 玩法、性能与编辑器](#meteoric-reboot-4--玩法性能与编辑器)
- [Meteoric Reboot 5 —— 安卓端与模组兼容](#meteoric-reboot-5--安卓端与模组兼容)
- [后续维护 —— 回放重写 / HUD 重构 / 稳定性](#后续维护--回放重写--hud-重构--稳定性)

---

## v1.1.2 更新总览

- **版本 1.1.2 / 更新校验索引 3**，APK 包版本（versionName）同步为 1.1.2
- **Mac 高帧率与性能**：帧率上限设置（120/240/480/无上限）、高清渲染 / 性能模式、设置二级页性能、PlayState 万帧稳定、FPS 计数器修复
- **JS 引擎优化融合（9 项）**：HUD Only / Allow GC / Strum 呼吸灯 / 弹窗开关 / Less Botplay Lag / No Hit Lua Calls，全部默认原版行为
- **渲染修复**：「提前渲染音符」全朝左 bug、血条图标飞出 0.8s 回位、RGBPalette 移动端空指针
- **安卓**：CastNote 轻量管线接通（226 万音符大谱面）、Android 12 存储（`.meteoric` 释放）、设置 ◀▶ 长按连续调节
- **开发工具**：MeteoricProfile 性能探针（`-D METEORIC_PROFILE`）、GL 错误监控（Seiun 移植）；移除高开销 FPS 波动图
- **构建基础设施**：SDL3 lime 补丁更新（高精度计时 / 高 DPI 模式文件）、CI 缓存与重试调整

---

### ⚡ 高帧率与性能

- **「帧率上限」设置**（图像设置）：`120 / 240 / 480 / 无上限` 四档，切换即时生效（`applyFramerate`）；桌面默认无上限，移动端默认 120 防过热
- **「高清渲染」**：`meteoric_dpi_mode.txt` 运行时模式文件（1x 高性能 / 2x 高清），重启生效；1x 下 Retina 帧率约 3 倍
- **「性能模式」（perfMode）**：渲染开销收紧，游戏中实时生效
- **设置二级页性能**：打开二级页时父级 `persistentDraw = false`（不再被遮挡仍渲染）→ 二级页帧率 ~900 → ~1300+
- **PlayState 万帧稳定**：自定义 FlxGame 帧循环（桌面 100000 哨兵墙钟）；已消费音符引用定期释放（`releaseConsumedNotes`），GC 尖峰 120ms → ≤24ms
- **FPS 计数器修复**：`_lastStamp` 时间戳修正，标题栏 / 角标读数真实（并显示引擎版本）
- 移除 **FPS 波动图**（FPSGraph：高频重绘纹理，开销远大于收益）

### 🧩 JS 引擎优化融合

从 FNF-JS-Engine（Seiun 系）移植，全部**默认关闭 / 原版行为**，可在 设置 → 性能 逐项开启：

| 设置 | 作用 |
|---|---|
| HUD Only | 只渲染 HUD + 音符，角色/舞台（含全屏雨滤镜）不再绘制 |
| Allow GC | 关闭 GC 消除高帧率尖峰（内存可能上升） |
| 三个 Strum 灯（对手/自动/玩家） | 控制对方 / botplay / 玩家鼓面呼吸灯 |
| 评分弹窗 / 连击弹窗 | 关闭后大谱面高密度命中不掉帧 |
| Less Botplay Lag | 自动游玩只计分不弹窗 |
| No Hit Lua Calls | 关闭 goodNoteHit / opponentNoteHit 的 Lua/Hscript 回调 |

### 🎨 渲染与 HUD 修复

- **「提前渲染音符」全朝左 bug**（`Note.recycleNote`）：补 `defaultRGB()` + `tryUseBakedGraphic()`，模板复生音符按当前轨道着色 / 换烘焙图，不再全部是 lane0 左箭头
- **血条图标飞出回位**：`iconFlyTarget` 4.0 / `iconFlyOff` 6.0 追赶速率，600% 爆发后约 0.8s 回位（原 3~4s）
- **RGBPalette 移动端 NRE 修复**：4 个 setter 克隆条件改为 `allowNew && enabled && 值不同`——移动端/烘焙（着色器未渲染、uniform 为 null）不再克隆，桌面行为不变

### 📱 安卓兼容与存储修复

- **CastNote 轻量管线接通安卓**：PlayState 谱面管线 12 处 `#if android` → `#if false`（旧分支完整保留可回退）——Flocc Hard（2,260,102 音符）在安卓可加载并游玩，不再原生崩溃
- **Android 12 `.meteoric` 释放修复**：
  - 权限判定改为**真实写探测**（`probePublicRoot`：写入探针文件验证），绕开 MIUI/HyperOS、ColorOS 等定制 ROM 上 `isExternalStorageManager()` 不可靠的问题
  - 授权成功后**先迁移回退数据再建目录**，mods/assets 能搬到根目录 `.meteoric`
  - 资源复制**写盘失败不再静默跳过**（仅内嵌资源「不可提取」允许跳过）
  - 授权跳转三层兜底：按应用授权页 → 全局「所有文件访问」总览页 → 应用详情页（lime 模板 + 生成工程）
  - 未授权时显示手动授权路径，授权后重启自动迁移
- **设置 ◀▶ 长按连续调节**：按住 0.5s 后数字按 `scrollSpeed` 连续滚动、字符串档位每 0.2s 切换、开关仍单次切换；松手/滑出即停
- 9 项 JS 优化在安卓端验证可用；「帧率上限」在移动端默认 120 防过热

### 🧰 开发与诊断工具

- **MeteoricProfile**：每帧耗时探针（编译定义 `-D METEORIC_PROFILE` 启用，默认零开销 inline）
- **GlErrorWatchdog**（Seiun 移植）：渲染帧轮询 `glGetError()`，GL 错误写入 CrashHandler 结构化日志环，不再静默
- **CrashHandler**：结构化日志环（最近 60 条游戏日志）随崩溃报告输出，对接以上探针与 GL 监控

### 🔧 构建基础设施

- `ci/lime-sdl3-patch`：高精度性能计数器（`SDL_GetPerformanceCounter`）事件循环重写、高 DPI 模式文件开关（2x 高清 / 1x 高性能）
- CI：lime-full 缓存 key 纳入 `ci/lime-sdl3-patch/**`，setup 网络重试收紧

### 🔢 版本与更新校验

- 引擎版本 `1.1.2`（主菜单 / 水印 / FPS 角标 / 崩溃日志 / Lua `version`）
- 更新校验索引 `2 → 3`（`gitVersion.txt` = 1.1.2 / 3）
- APK 包版本 `versionName = 1.1.2`（与引擎版本一致；versionCode 由 lime 构建自动递增）

---

## v1.1.1 更新总览

- **联机功能完整落地**：局域网 1v1 实时对战（主菜单恢复入口）
- **联机真双人**：双方各唱半边谱面，不再「双方都唱 BF 侧、对方侧变空气」
- **局域网房间自动发现**：UDP 广播免输 IP 直连
- **模组皮肤跨端同步**：无模组端也能看到对方模组角色
- **结算界面重写**：KE 命中散点图 / 对方成绩对比 / 精简版联机结算
- **大量稳定性与模组兼容修复**（QT/FlxAnimate、FunkinMix shader、66mod HScript、三端 CI）
- **版本校验索引 1 → 2**（1.1.1）

---

### 🌐 联机对战（全新）

- 主菜单恢复「联机」入口；TCP 房主即服务器（27750），仅 1v1，满员拒绝
- 各自本地判定；HIT/MISS/PRESS/RELEASE 增量同步；对手按键条 / 血条 / 分数 / 连击 / 判定统计实时同步
- 单方暂停双端同步；暂停与结算期间持续轮询网络；防 PAUSE/RESUME 回声死锁；联机禁用重开
- 血条攻防式：己方 Hit 推己方条、己方 Miss 扣血、对方 Miss 按损失量 60% 回血
- 昵称 / IP 输入框重构（future.ttf 显示层 + 原生 TextField IME + 自绘光标）；中文昵称 UTF-8 修复
- 全界面鼠标为主 + 输入聚焦时屏蔽游戏键位；难度/选曲/发送/开始两段式
- 断线 / 对方退出自动回大厅并显示原因；退出对局与结算「继续」统一回「房间大厅」（连接保持，可再来一局）

### 🎤 联机真双人（v1.1.1 核心）

- 双端各唱半边：房主打 player1（BF 位）、玩家打 player2（Dad 位）；客户端镜像人声（Vocals ↔ OpponentVocals）
- 左右谱面均恢复滚动；对方按键命中左侧音符；Dad 唱歌 + 人声；对方 Miss 播 Miss 动画；长按完整判定
- HIT/MISS 携带 chartSeq，接收端按序号精确消费音符（`findOnlineOppNoteBySeq`，视觉副本覆盖时回退基准音符）
- 相机跟随当前演唱角色（客户端镜像 isDad）；中间滚动布局按物理位置修正，双端与单机标准布局一致
- 加载界面按角色映射预载双方贴图；角色槽位标签固定「我的角色（BF）/ 对手角色（Dad）」

### 📡 局域网房间自动发现

- UDP 27751 心跳广播（每 1s）：房间码 / 房主昵称 / 人数 / 是否已满；广播至广播地址 + 回环 + 本机局域网 IP（单机双开可发现）
- 首页新增「发现房间」；发现页实时列表、4s 超时移除、满房置灰、点击行直连（无需手输 IP）
- 建房即广播、离开/断线自动停止；跨路由器 AP 隔离仍可走原「加入房间」手输 IP

### 🧩 模组皮肤跨端同步（CHARSYNC）

- 选角确认时把模组角色资源（JSON / 图集 / 血条图标）分块（60KB base64）同步到对端 mods/ 兜底路径，无需安装模组
- 出站字节队列 + 每帧 pumpOut：非阻塞 socket Blocked 视为背压、不再误判断线
- 资源收集遍历全部已安装模组（resolveSyncFile）；加载界面预载双方贴图（pendingBitmaps）
- 角色列表过滤资源不全角色 / 同步前完整性校验 / 进曲锁定我方角色所在模组（currentModDirectory）
- 「开始对局」需等对方资源同步完成（oppSyncDone）

### 🧾 结算与判定

- KE 命中判定散点图移植（NoteHitGraph：时间轴 / 偏移 / 4 条判定窗 / Mean）
- 结算整体重写：左曲目+判定统计两列 / 右本局数据（分数/最高连击/准确率/新纪录）/ 大版散点图
- Marvelous 改金黄色；判定首行遮挡与数值间距修复；结算时隐藏 HUD 判定侧边栏
- 联机精简版结算（分数/连击/准确率/判定 + 「继续」→ 回房间大厅）；对方成绩栏实时刷新
- Psych-Forever Early / Late 指示器（sick/good/bad/shit -early/-late，普通 + 像素全套）
- 金色 Combo（全 Marvelous/Sick 时切换 combo-golden，Good 以下或 Miss 恢复；allSicks）
- 修复 Combo 词 x 被覆盖导致方向键偏移不生效（comboSpr.x 补上 comboOffset[0]）
- OSEngine 三帧胜利小图标（450×150：正常/劣势/胜利，>80% 血量切胜利帧、<20% 切劣势帧；原版 2 帧保留 -pe 后缀）
- 像素舞台下落箭头恢复 NEAREST 硬边（Note.recycleNote 按 isPixelStage 保留 antialiasing=false）
- 音量调节到边界（100%/0%）不再响提示音（SoundFrontEnd.changeVolume + FlxSoundTray.show silentOnly）

### 🛠️ 稳定性 · 性能 · 兼容

- 暂停→返回主菜单闪退根治（转场期 persistentUpdate=false + LuaJIT `pushing nil` Convert.hx 修复）
- QT / FlxAnimate 动画：ATLAS.SPRITES 坐标随降采样缩放、ATLAS 格式不回缩、playAnim 强制重启、DCE 保护（@:keep / 静态调用）、addLuaSprite 官方语义
- 内存：未用缓存每 60s 清理（useCount 守卫）、Character.atlas 销毁修复、回放/重开同曲 100% 死循环修复、StrumNote 缺资源兜底
- FunkinMix shader 白/黑屏（sos / Dogma 等）：FlxRuntimeShader 官方对齐 + viewOffset 公开访问 + FlxRuntimeShaderMap；runHaxeCode Map 变量预处理
- 编谱面板重写（ChartingPanel / ChartWidgets，每标签独立注册 + makeGraphic unique=true 根除「悬浮串亮」）；多引擎导出（CNE / 0.6.3）；修复「需要人声」NPE
- 多层级崩溃日志与报告：黑匣子心跳 / 阶段簿 / Haxe 未捕获 / 原生信号栈 / Java 层；Seiun 式系统报告
- 安卓：后台冻结（暂停 + 音频冻结）、Java 崩溃落盘、onTrimMemory 重复定义修复、重开回溯 NPE / VarTween 防御
- 66mod HScript 兼容：var 声明、camFollow 注入、SScript inline 静态反射修复
- CI：haxelib/lime 缓存提速、Windows 交叉构建修复（icon 注入、大小写头文件、_WIN32_WINNT、comsupp）、Windows job 迁 ubuntu
- 背景学生重开表情重置（bgGirls 构造完成态）、GF 快速重开修复（保留 stage/gfVersion 派生值）

### 🚀 版本与发布

- 版本号 1.1.0 → **1.1.1**；**版本校验索引 1 → 2**（gitVersion.txt 第 2 行同步为 2）；CrashHandler 引擎名更新
- GitHub 仓库补齐 .gitignore（Gradle/Android 构建产物、.DS_Store、build/bin/obj、export/）
- 三端产物自动构建：Windows x64/x86、macOS x64/arm64、Android arm64

---

## v1.1.0 更新总览

- 历经五轮 Meteoric Reboot 重构，基于 Psych Engine 深度魔改
- 新增 **Replay v2 回放系统**（按键注入式回放）
- 新增 **Phigros 玩法** 后已移除（见 [后续维护](#后续维护--回放重写--hud-重构--稳定性)）
- 新增 **联机功能**（当前暂时屏蔽，代码保留）
- 完成 **Windows / macOS / Android 三端** 构建支持
- 大量界面重写为统一设计语言：圆角磨砂玻璃面板 + 鼠标/触控/键盘三套操作

---

## Meteoric Reboot 1 —— 环境搭建与基础优化

- **编译环境搭建**：安装 Haxe 4.2.5、HaxeFlixel、SScript 等依赖，在 M4 MacBook Air 上完成 FNF Psych Engine 0.6.3 编译
- **底层逻辑优化**：提升帧率与运行稳定性；启用 `-release` 增量编译模式，大幅缩短编译时间
- **FPS 计数器重构**：精简检测逻辑，优化显示样式（修复"无法切换颜色、FPS 永远为 0"问题）
- **设置项中文化**：翻译各类设置项
- **移除 alphabet 渲染**：全部界面改为普通字体渲染（修复设置界面崩溃、黑屏卡启动等问题）
- **主界面鼠标点击操控**：加入鼠标点击控制方式

## Meteoric Reboot 2 —— 交互与字体

- **全界面鼠标点击控制**：所有界面加入鼠标点击操作
- **修复 neko 残留**：彻底修复 neko 构建并清理残留
- **字体显示不全修复**：修复暂停界面等字体截断问题（如"Phitty Nic"缺少尾部字符）

## Meteoric Reboot 3 —— 界面全面重构

- **暂停界面重写**：全新圆角磨砂玻璃面板，修复文本截断；右侧新增统计面板（当前分数、失误数、评分、准确度等）
- **Freeplay 界面重写**：圆角磨砂设计，修复小图标过大/错位；改为选中曲目后在信息区显示大图标
- **主界面重写**：键盘/鼠标操作互不冲突（悬浮只高亮不抢焦点）
- **Story Mode 界面重写**：修复鼠标选择问题
- **旧版更新提示界面重写**：版本检测链接更换为 gitproxy 加速地址；多轮重写后改为纯文字形式（`> 前往 Github 下载更新` / `> 忽略更新`）
- **制作人员界面重写**
- **系统鼠标光标**：替换 Haxe 自带光标，修复鼠标意外隐藏
- **按键设置重写**：加入返回按钮，修复背景纯白不可见、字母跳动
- **设置界面重写**：全部页面（除 Combo 设定外）统一设计语言
- **旧版 1.0.4 界面保留**：恢复 alphabet 支持，主界面可切换
- **Mod 列表界面修复**：面板错乱、模组名显示不全、启用/停用文字"飞上天"等问题
- **滚轮控制**：所有支持鼠标控制的界面加入滚轮滚动；悬浮高亮但界面不滚动
- **磨砂玻璃返回按钮**：圆形 `<` 样式，透明保持可见度，悬浮发光
- **暂停界面翻译**：返回游戏/重新开始/更换难度/自动游玩/设置/返回主菜单

## Meteoric Reboot 4 —— 玩法、性能与编辑器

### 玩法与判定
- **新版音符判定（KE 判定）**：Kade Engine 手感（提前窗口更短），旧版判定命名为 **PE 判定**，可在游玩设置切换
- **KE 防乱按**：只有一个音符却按下多个按键直接扣分；严格命中窗口
- **Bad 以下评分微量扣血**
- **KE 小图标跳动**：搬入 Kade Engine 图标跳动，加入设置开关
- **自动游玩重写**：真实 100% 准确率（非固定判定），支持加载预演
- **对方推条**：对手像玩家一样按键加血推你（保留一点血量不致死）
- **无限轮回**：曲目完成后时间回溯重新开始
- **Phigros 玩法**：判定线 + 彩色表演块玩法（此后已移除，见后续维护）
- **快速重开 + 箭头回溯**：重开时箭头像录像倒带般飞回起点，变速回溯（起始快、收尾慢），回溯完成后不重新绘制箭头、额外回溯 5 秒清场

### 结算与设置
- **结算界面**：新增本局结算；修复位置偏移；**Autoplay 不计分** + **GodMode 检测**判断成绩是否有效
- **游玩设置重写**：自动生效（暂停菜单内修改即时同步）
- **暂停界面**：去除自动游玩选项，新增**跳转时间**、**脚本管理**（游戏内开关 lua/hx 脚本，关闭加 `.disabled` 后缀）
- **快速重开开关**：`重新开始而不重新加载谱面` 加入设置
- **自定义 HUD 界面**：音符/时间条/血量条/评分位置自由调节（设置内模拟预览，重置回默认位置）
- **小图标与血量条强制绑定**：x 跟随 barCenter 左右滑动，经典 FNF 手感

### 性能与内存
- **自动清理 RAM**：完成/退出曲目后清理，全界面生效
- **加载界面重构**：多线程加载，超大数据（55670 音符）约 2 秒加载完成；跳过冗余过渡动画；进度条重写（时间条式逻辑）
- **音符渲染批处理**：堆叠音符统一批处理命中，消除卡顿
- **游戏内报错系统重写**：报错窗口显示在游戏内，大幅降低闪退率，附崩溃测试入口

#### H-Slice 音符管线性能移植（大谱面核心，基于 H-Slice 引擎架构）
- **CastNote 轻量数据层**：加载期只建位打包结构体（15 万级谱面从"建 15 万重对象"降为约 1 万条结构体），解析卡顿移除；`chartSeq/密度/时间偏移` 全部随数据走
- **堆叠音符合并（后台压缩）**：同轨 ±合并窗口 的堆叠箭头合并为一条 CastNote + `density` 计数（58,088 谱 65,888 → 9,945 条，6.6x 压缩）
- **表面不压缩（视觉展开）**：合并簇生成时按每颗原始时间偏移展开回独立视觉箭头（含长条子段），画面与原版逐像素一致；每簇采样上限按"2s 窗口簇数"动态预算（场上精灵 ≈3000 上限，密集段自动降采样 3–12/簇）
- **判定/计分**：基准音符 `density`=簇总颗数（一击记整簇×N，Miss/连击/血条同步 ×N）；采样副本纯视觉（不参与判定）
- **音符对象池（NoteGroup）**：`spawnNote` 池化复生 + `invalidateNote` 统一回收（替代 kill+remove+destroy）；`prevNote/nextNote` 链经 `seqNote/seqHit` 静态表重建（被杀段状态快照，长条链式判定语义不变）
- **botplay 命中排期架构**：生成即登记（`botSchedule`），到点按实测帧步长提前量入队（消除 alive-loop 因击杀 splice 的哨兵饿死）；评级基准=音符自身时刻（Marvelous/Sick 顶格）；批内 chartSeq 去重防二次计分
- **快速跳谱（bulkSkip，仅真实时间跳变触发）**：二分跳过已过音符，跳时间/重开不再卡顿
- **长条/箭头复生完整重建**：全轨动画补齐（换轨不再停在左箭头帧）、X 轴居中对齐（长条中线贴合判定键）、尺度/翻转/偏移重置（无拉伸残留）
- **新增「性能」设置页**：堆叠合并/计数模式/合并窗口/已过音符不生成/快速跳谱/可见音符排序/场上上限/重叠隐藏/生成回调，全部中文 + 默认值即大谱面最优
- **修复回归**：音符永不复活（active）、remove 数组空洞、箭头朝左（换轨动画缺失）、长条断层（offs 共享数组）、曲末秒死（endSong 全量扣血）、密集段整段缺失/渲染爆炸（池化入组 + 视觉预算）、多类空指针与两处死循环
- 验证基准：floccinaucinihilipilificatiophobia（522BPM / 速度 6.67 / 327,382 原始箭头）自动游玩全曲 —— **163,759/163,759 全连、Marvelous 主导 100% 准确率、无冻结无缺失**
- **超大谱面支持**：同曲 Hard 难度（42MB JSON / **2,260,102 原始音符**）——CastNote 生成后立即释放原始谱面 DOM（≈1-2GB 峰值内存回收），长加载后正常运行；解析期挤压音符探测门禁（标准谱省 ~4s）

### 时间条
- **新时间条样式**：黑底、圆角、走过部分显示对手图标颜色（过暗时兜底青色），时间文字位于时间条下方，血量阴影滚动 + 时间阴影

### 编辑器
- **编谱界面（Chart Editor）全面重构**：现代右侧面板（输入框/按钮/文字）、双方小图标、中文界面
- **脚本系统增强**：Lua `import` 导入库、`class` 支持与继承、自定义界面端口（主菜单等）、hx/lua 文件管理
- **音量悬浮窗重构**：拖动条 + 平滑加减，鼠标悬浮不消失
- **开屏文字界面重写**
- **加载界面优化**：`-release` 下跳过 `FlxG.log` 等调试开销

### 其他
- 修复快速重开 + Event 换人后人物"飞天"问题（重开按完整逻辑重载角色）
- 修复 FPS 计数器 Mem 溢出（新增 GB 单位）
- 修复多个 `Null Object Reference` 崩溃
- 按键设置、脚本管理等界面文字显示修复

## Meteoric Reboot 5 —— 安卓端与模组兼容

- **接 Reboot 4 尾巴**：修复小图标不跟血量条滑动的问题
- **性能优化**：加入「提前渲染」设置；自动游玩加载时预演；重写机器人/音符渲染逻辑为批处理命中
- **音符显示修复**：音符变绿（RGB 颜色矩阵行列颠倒）、长条偏左、音符消失等
- **HUD / 设置**：FPS 计数器加入内存/CPU 峰值指示；FPS 信息可集成到窗口标题栏；修复后台音乐卡顿；连击数突破 9999；Sick/9999 图片不堆叠
- **自动游玩**：针对 phonophobia-mohong 修到 100%
- **Replay 回放（初版）**：新增回放功能，修复判定音符常亮、关闭回放后选歌界面变黑
- **成就系统重写**：全中文命名与描述，加入触发方式显示
- **主界面/版本**：主界面"新版本"可点击跳转 GitHub Release；版本号改为 1.1.0；重写更新检测逻辑；主界面显示 GitHub 最新版本
- **安卓端**：加入安卓支持并构建 APK；修复 16KB 对齐闪退、启动闪退、界面偏移、读谱失败、虚拟按键、触控、FPS 不显示、mod 加载闪退、模组路径 `/sdcard/meteoric`
- **彩蛋**：主界面输入 `meforever` 触发字母乱飞/变色/全界面飞行/窗口标题滚动/窗口弹跳
- **Windows 编译**：Windows 端编译完成
- **兼容模式**：Psych 0.6.3 兼容模式（箭头贴图格式），spritemap1（Adobe Animate 2020）转换支持

## 后续维护 —— 回放重写 / HUD 重构 / 稳定性

### Replay 回放系统 v2（重写）
- 全新**按键注入式回放**：录制按键按下/抬起事件，回放时注入正常输入路径——判定、strum 动画、长按、幽灵点击全部按真实游玩复现
- 结算界面「回放本局」一键回看；自由选歌 P 键打开回放列表（播放/删除）
- 回放中暂停、重开、跳时间全部可用；死亡重试保留回放模式
- 旧版回放文件自动兼容

### PlayState HUD 重构（GameHUD 子系统）
- 全部 HUD 元素（血条/图标/分数/歌曲名/时间条/标签 + 阴影）的创建、每帧更新、可见性管理收敛到独立 `GameHUD` 类
- 内建**每帧可见性权威**：无论谁（Lua/Hscript/Mod/遗留代码）把血条/图标/分数改成不可见，下一帧强制拉回设置值——根治"游玩中 UI 突然消失"
- HUD 字段保持挂在 PlayState 上（`healthBar`/`iconP1`/`scoreTxt`…），Mod 的 `getProperty/setProperty` 兼容

### 稳定性修复
- **内存清理安全守卫**：`Paths.clearStoredMemory/clearUnusedMemory` 不再销毁仍在使用的贴图（`useCount` 守卫），修复贴图被误销毁导致的元素消失
- **暂停界面**：暂停音乐资源缺失不再阻止打开；`paused` 卡死自愈；触屏可直接点选菜单项
- **结算/回放/死亡界面触屏支持**：直接点按行/按钮即可操作（不依赖鼠标模拟）
- **上帝模式正常记分**：分数/Miss/准确率/全连照常记录、结算保存，仅保留"不会死"
- **hideHud 保护**：每帧恢复用户真实设置；设置保存时同步基准值
- 修复快速重开/完整重开/死亡重试/更换难度时回放数据丢失
- 修复设置里改 hideHud 后被强制还原的问题

### 功能移除与屏蔽
- **移除 Phigros 玩法**：删除判定线、表演块渲染、设置选项及相关代码（`PhigrosJudgeLine.hx`）
- **暂时屏蔽联机功能**：主菜单移除「联机」入口（`OnlineMenuState`/`Multiplayer` 代码保留，恢复时改回即可）

### 其他
- 三端构建脚本：`compile-windows.sh`（mingw-w64 交叉编译，x64）/ `compile-mac.sh` / `compile-android.sh`
- 清理工程根目录：移除 3.3GB 构建产物与冗余文件（已备份至桌面）

---

## 构建说明

| 平台 | 命令 | 产物 |
|------|------|------|
| Windows (x64) | `./compile-windows.sh` | `export/release/windows/bin/Meteoric.exe` |
| macOS | `./compile-mac.sh` | `export/release/macos/bin/Meteoric.app` |
| Android | `./compile-android.sh` | `export/release/android/bin/app/build/outputs/apk/debug/Meteoric-debug.apk` |

---

## 开发中：Windows 端高清显示修复（高清渲染开关在 Windows 生效）

- **根因**：SDL3 在 Windows 上不做逻辑/物理尺寸归一化（`SDL_GetWindowSize` 与 `SDL_GetWindowSizeInPixels` 都返回物理像素），`SDLWindow::GetScale()` 的 `SizeInPixels/Size` 比值恒为 1.0 → `window.scale` 永远是 1 → OpenFL 永不按物理像素渲染，Windows 显示画面与 macOS「高清渲染」关闭时同观感（偏小/拉伸模糊/锯齿），开关完全无效
- **修复（`ci/lime-sdl3-patch` SDL3 后端，仅 Windows 分支生效，macOS/安卓行为不变）**：
  - `SDLApplication` 在 `SDL_Init` 前按 `meteoric_dpi_mode.txt` 设定 `SDL_WINDOWS_DPI_AWARENESS`：高清开=`permonitorv2`（物理像素渲染），关=`unaware`（1x + 系统拉伸，模糊但帧率高，与 macOS 关高清语义一致）
  - `SDLWindow` 构造时高清开启则把窗口放大到「逻辑尺寸 × 显示器缩放」（100%→1.0，125%→1.25，150%→1.5，200%→2.0）
  - `GetScale()` 改用 SDL3 官方 `SDL_GetWindowDisplayScale()`（Windows=DPI/96；macOS Retina 仍为 2.0/1.0，与旧行为一致）
  - `GetWidth/GetHeight/Resize` 在 Windows 高清开启时做物理↔逻辑折算；鼠标坐标同样按缩放折算回逻辑（OpenFL 再乘回物理）
- **FlxText 超采样**：`_textDpi` 由 `Std.int(scale)` 改为向上取整（1.25/1.5→2），Windows 非整数缩放（125%/150%）下文字也获得 2x 光栅化（此前被截成 1 → 文字不清晰）；上限 4 防位图爆炸
- **验证方式**：Windows 125%/150%/200% 屏：设置→图形→「高清渲染」开 → 重启 → 窗口满尺寸且画面锐利；关 → 重启 → 1x 略糊、帧率上升（与 macOS 行为对齐）
