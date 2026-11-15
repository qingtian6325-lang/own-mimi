# Changelog - 咪咪记账 (Mimi Money iOS)

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.3.19] - 2026-11-14

### 🎯 Highlights
- **已分类预算按使用巴仙排序**：预算管理「已分类预算」与首页「分类预算」按 spent/limit 从高到低排列（用最多在上、最少在下）；零限额安全处理。
- **发版**：`VERSION` / Intent 默认版本升至 1.3.19。

## [v1.3.18] - 2026-11-14

### 🎯 Highlights
- **日历式日期选择**：共享 `MimiDatePickerSheet`（「日期」+「回今天」、月历蓝圈选日、时间灰胶囊 + 时分滚轮、大蓝「确认」）；账单详情 / 记账 / 统计自定义 / 导出自定义 / 全部记录月标题统一接线。
- **AI 日期解析与防误判**：新增 `MimiNaturalLanguageDateParser`（支持 `今天`/`昨天`/`前天`/`3天前`/`上周三`、`11月8日`/`2026年11月8日`/`08/11/2026`/`8号` 与 `早上8点半`/`晚上8点`/`20:07`/`9:54 AM` 等，按 `Asia/Kuala_Lumpur` / 中文语境准确落时，未提具体时刻时保留 `now` 时分且不把日期/时刻/品牌数字误判为金额）；收紧 Gemini / Groq 识图与问账提示词（`temperature: 0.1`、`LedgerContextBuilder.questionSystemPrompt()`）、扩充 `BillMessageClassifier` 问句词及 `DefaultCatalog.resolveCategoryIds` 跨组匹配。
- **AI 对话自动滚动到底部**：`MimiAIAskOverlayView` 与 `RecordAndAISheetView` 通过底部锚点监听消息内容变化（含就地刷新 AI 回复块）、思考状态、展开与输入焦点，自动平滑滚至最新消息。
- **发版**：`VERSION` / Intent 默认版本升至 1.3.18。

## [v1.3.17] - 2026-11-14

### 🎯 Highlights
- **账单详情离开即存**：去掉「保存修改」按钮；下滑关闭、边缘右滑返回、关闭按钮任一离开路径都会自动写入金额、分类、备注、时间、账户等可编辑字段。
- **无效金额不覆盖**：空/0/非数字金额保留进入页面前的有效金额，不静默写坏数据。
- **发版**：`VERSION` / Intent 默认版本升至 1.3.17。

## [v1.3.16] - 2026-11-14

### 🎯 Highlights
- **手动记账全屏**：`.presentationDetents([.large])`；保留下滑关闭与横滑分页。
- **账单分类选择**：账单详情「标准分类」半屏（胶囊切换、一/二级图标网格、确认）；「分类编辑」进分类管理。
- **说明**：v1.3.15 启动崩溃热修已在 SideStore。
- **发版**：`VERSION` / Intent 默认版本升至 1.3.16。

## [v1.3.15] - 2026-11-14

### 🎯 Highlights
- **启动崩溃热修**：v1.3.14 IPA 未打入 SPM 资源包 `MimiMoney_MimiMoneyCore.bundle`（CI 误搜 `MimiMoneyCore_MimiMoneyCore.bundle`），首屏 `Bundle.module` fatal。本版修正 CI 拷贝并缺包失败；运行时 `Bundle.mimiModule` 缺包回退不 fatal。
- **发版**：`VERSION` / Intent 默认版本升至 1.3.15。

## [v1.2.5] - 2026-11-12

### 🎯 Highlights
- **试用 Groq 识图引擎**：识别与问账默认改走 Groq（`qwen/qwen3.8-27b`，支持图片 data URL 输入 + JSON mode）；设置页改为填 Groq API Key（console.groq.com），保存/测试连接会把引擎固定为 Groq。
- **Gemini 代码保留可回切**：`AIEngineSettings.provider` 仍支持 gemini，本版默认与设置页面向 Groq 试用。
- **其余不动**：草稿确认才入账、可疑金额拦截、图片压缩、Keychain 存 Key 等逻辑保持。

## [v1.2.4] - 2026-11-12

### 🎯 Highlights
- **转账识别贯通对方账户**：Gemini 返回的 `targetAccount` 写入草稿并在落账时带上 `targetAccountId`，本人账户互转不再丢对方账户、余额计算正确。
- **可疑金额拦截贯通 App 内路径**：首页相册/拍照识别出可疑金额时改为未确认入账并打开编辑；聊天识别会标红提示再确认；Gemini 路径对「电量区间整数 + 空/纯数字备注」补强拦截。
- **细分类问账不再被本地抢答**：「餐饮花了多少」等点名分类的问题交给 Gemini；「这个月花了多少」仍可离线答整月汇总。分类表改为从 `DefaultCatalog` 动态生成。
- **识别前统一压缩图片**：最长边 1280、JPEG ~0.72，降低超时与额度消耗；指南页剪贴板识别改为确认后才入账；自然语言记账默认沿用最近一笔账户；清除旧版 UserDefaults 明文 LLM Key。
- **工程与发版备注**：`xtool.yml` 最低系统版本与 Package/CI 对齐为 iOS 17.0；「识别账单」Intent Version 默认更新为 1.2.4；结构校验脚本改跟纯 AI + LocalBookkeepingAnswerer 结构；新增转账对方账户、可疑金额、细分类勿抢答、图片预处理、明文 Key 清理等回归测试。

## [v1.2.3] - 2026-11-11

### 🎯 Highlights
- **修复识别必报 HTTP 400**：真机暴露——相册选图识别每次失败，Google 服务器原话是 `response_schema.properties[subCategory].enum[62]: cannot be empty`。根因在识别请求的结构化输出 schema：二级分类（subCategory）与对方账户（targetAccount）的 enum 末尾各混了一个空字符串（本意是「可以没有二级分类」），而 Google 的规矩是 enum 只许非空字符串——请求在模型看图之前就被拒。本版两个 enum 去掉空值，「可以为空」改用 schema 正规的 `nullable` 表达（模型无二级分类时返回 null，App 侧映射回空）；DTO 的 subCategory 相应改可空，系统 prompt 里「subCategory 留空」同步改成「填 null」。测试连接与问账不用这份 schema，所以此前一直正常，唯独识别中招。
- **400/403 报错不再冤枉 Key**：以前 HTTP 400/403 一律显示「API Key 无效或请求被拒绝」，这次 schema 报错就被误导成 Key 问题。本版起 400/403 直接呈现 Google 服务器原话，不再替用户下结论；Key 真无效时服务器原话本身就会写明。
- **新增回归测试**：断言识别 schema 里所有 enum 都不含空/空白字符串、且 subCategory 与 targetAccount 带 nullable 标记——这类只在 Google 服务器端才生效的规矩，CI 从此能提前拦住。
- **其余不动**：呈现层、pending 单次消费幂等、金额合理性拦截、Keychain、设置页、AI 助手其他功能与数据模型均未改变；「识别账单」Version 参数默认更新为 1.2.3。

## [v1.2.2] - 2026-11-11

### 🎯 Highlights
- **修复问账必超时**：真机暴露——设置页「测试连接」成功，但 AI 助手问账每次都回「网络请求失败（请求超时）」。根因在问账这条真实 generateContent 路径（带最长 6000 字账目上下文、模型默认带思考，首字延迟高）被短超时掐死。本版给三条路径分开配超时：**问账/聊天 60 秒**（独立长超时）、**识别 30 秒**（原 8 秒，失败文案同步更新）、测试连接探针 30 秒。
- **识别与问账压低思考**：两条路径的 generationConfig 都带思考抑制（按模型世代选字段：Gemini 3 系用 thinkingLevel、2.5 系用 thinkingBudget），账单识别与查账不需要长思考，优先速度与稳定；若接口拒绝该字段（HTTP 400），会自动去掉该字段重发一次，不因思考配置失败而误报。
- **测试连接改成真验证**：在原「查模型详情」之后，追加一次最小 generateContent（让模型只回复 OK），生成成功才显示「连接成功（已实际生成验证）」；状态文案能区分「模型存在但实际生成失败」与真成功——设置页显示成功就等于真实路径可用。
- **聊天等待态**：发送问账后、回复到达前，聊天里显示「正在查账…」＋转圈的等待气泡，回复或报错后自动替换消失，不再对着空白干等。
- **思考档位按 Google 官方文档定案**：核对官方 thinking 文档后修正——默认模型 `gemini-3.8-flash` 用 `thinkingLevel: low`（该型号只支持 low/medium/high，没有 minimal、也不能完全关思考，先前给的 minimal 是错的）；3.x Lite 系列用 `minimal`；2.5 系继续用 `thinkingBudget: 0` 关闭思考。
- **瞬时错误自动重试一次**：问账与识别遇到 HTTP 429、5xx 或请求超时，会带随机抖动的短退避（约 1 秒）自动重试一次；400/403、缺 Key 等客户端错误不重试。
- **IPA 资产文件名带版本号**：从本版起 Release 资产名为 `MimiMoney-iOS-v1.2.2.ipa` 这种格式（版本号取自 VERSION 文件、CI 发版自动生成，往后每版都带），下载到电脑后一眼分清是哪一版，不再装错。
- **其余不动**：数据、呈现层、Keychain、分类/备注逻辑、金额合理性拦截、失败不落账原则均未改变；「识别账单」Version 参数默认更新为 1.2.2。

## [v1.2.1] - 2026-11-11

### 🎯 Highlights
- **识别改纯 AI，彻底移除 OCR**：v1.2.0 的「Gemini 优先、失败静默回退本地 Vision OCR」被取消——`ReceiptOCRService` 已从工程中删除，运行时再无任何路径调用它做识别。所有识别入口（「识别账单」Intent、首页问账条相册/拍照、聊天层相册/拍照、记账页加小票与剪贴板图片、指南页剪贴板一键记账）只走 Gemini。
- **失败明说、绝不凑数**：没填 key、无网络、超时（8 秒）、HTTP/额度错误、返回无法解析时，一律不暂存、不落账、不生成草稿：Intent 路径直接把失败原因弹给用户（简洁中文，含检查 Key/网络的指引）；App 内路径弹窗或在聊天里如实说明并可重试；设置页「最近一次调用状态」继续如实记录失败原因。Intent 在没有收到截图时同样明确提示，不再拿示例账单顶替。URL 快速记账入口不再解析文字，只保留带 amount 参数的快速记账，其余打开手动记账页；设置页与指南页中描述 OCR 兜底的文案已同步更正。
- **prompt 强化「认真读细节」**：新增硬指令——先读完整个交易详情页再填写；商家全名以页面上的商家/收款方字段为准（如 Paid to / Merchant / 收款方 / 店名抬头）；状态栏的时间、电量、信号绝不进入任何字段；参考号/交易号/Wallet Ref 等长编号不是金额也不是备注；备注仍按既有三规则生成，商家名必须是真读到的名字，读不到留空、不许用数字碎片凑。
- **其余不动**：Gemini 客户端、Key 的 Keychain 存储、设置页、金额合理性拦截、呈现层结构（iOS 26 requestChoice / 18–25 确认型 / 17 降级）、AI 助手其他功能与数据模型均未改变；「识别账单」Version 参数默认更新为 1.2.1。测试按新契约调整：新增纯 AI 失败/成功路径用例（失败不暂存不落账、超时文案、额度文案），旧 OCR 解析用例改用 Gemini 结构化结果表达同一批真实场景。

## [v1.2.0] - 2026-11-11

### 🤖 A 部分：识别改 Gemini 单引擎
- **Gemini 单引擎识别**：截图进来先走 Google Gemini（REST 直连 generativelanguage.googleapis.com，key 用 x-goog-api-key 头，结构化 JSON 输出由 responseSchema 约束）。出厂默认模型 **gemini-3.8-flash**（Google 官方定价页 ai.google.dev/gemini-api/docs/pricing 核实：Free Tier 列为 Free of charge 的现行旗舰 Flash），模型名可在设置里改。
- **分类与备注按规则生成**：prompt 写明判断顺序——先分收支类型，再按商家/业务性质选分类（一级+二级枚举限定为 App 现有分类体系，如餐厅→餐饮-餐厅、油站→交通-加油充电，账户枚举限定为现有账户）；备注规则：向商家付款「{商家名} 消费」、转账给个人「转账给{姓名}」、收到转账「{姓名} 转账」，名字照截图原文，另有本地格式兜底层过滤杂讯。日期一律马来西亚日/月/年解析，prompt 与本地校验双写明。
- **静默回退**：没填 key、无网络、超时（8 秒）、HTTP/额度错误时，静默退回现有本地 Vision OCR，不弹错、不丢账。Intent 呈现层（iOS 26 requestChoice / 18–25 确认型 / 17 降级）与暂存单次消费幂等完全不动。
- **金额合理性拦截**：金额 ≤0、超过 RM100,000、或与状态栏电量百分比同值这类明显误读，这笔只进未确认口径（暂存转未确认记录等 App 内核对），不走正常入账呈现。
- **设置页新增「AI 识别引擎（Gemini）」区**：API key 输入（只存 iOS Keychain，绝不进 UserDefaults 明文/仓库/日志）、模型名输入、「测试连接」按钮（查模型详情验通断）、最近一次调用状态。key 由用户自己在 AI Studio 免费申请后填写，本版不预置任何 key。

### 🐱 B 部分：AI 助手按 Kapi 布局落地
- **记录页底部悬浮问账条**：[猫头像]「任何事情都能问我」[＋] 常驻列表底部；点 ＋ 展开面板（＋ 变 ✕），下方三格大瓷砖：相册（PHPicker 选图→Gemini 识别→账单草稿→App 内确认→入账）、拍照（同一流程）、导入导出（接 App 已有的 CSV 导入导出，设置页「导入导出」区）。
- **聊天层**：点问账条打开，标题行 [猫头像]「记账查账，问问题」[⇌ 手动记账][✕]，手动记账钮关聊天层回键盘记账页；层上方飘 3 个示例问题气泡（「查询本月单笔消费超过200块的账单」「我本周支出最高的一笔是什么？」「我最近一次购物买了什么？」），点即发送；输入行「发消息或按住说话...」带 ＋（同样展开相册/拍照面板）与蓝色 ↑ 发送。
- **问账**：问题 + 本地账目上下文（近 6 个月月度汇总、本月分类汇总、预算与剩余、账户余额、相关记录明细最多 30 条、全文约 6000 字上限）一起发 Gemini；system prompt 限定只答记账问题、金额用 RM 格式、数字必须来自所给数据、不足就明说。无 key/无网时在聊天里明说不可用并引导去设置页，绝不编答案；分类表/本月汇总等本地问题仍可离线回答。
- **自然语言记账**：明确记账句（如「午餐 38」「打车 50 TNG」）解析成账单草稿卡，带「确认记账／取消」，确认才入账；拿不准是问账还是记账时一律按问账处理（判别为可测纯函数）。
- **按住说话**：输入区按住麦克风录音，SFSpeechRecognizer（zh-CN）转文字填入输入框；权限按系统规范申请，不可用时降级提示，打字不受影响。
- **聊天记录本地持久化**：存本机文件，杀进程重开还在；聊天层标题行有低调的「清空」入口。

### 🔧 其他
- 「识别账单」Version 参数默认更新为 1.2.0。新增单测覆盖 Gemini JSON fixtures 解析、备注格式规则、金额拦截、记账句判别、Context 汇总数学与相关记录上限；原有测试无回归。

## [v1.1.4] - 2026-11-11

### 🧪 Highlights
- **呈现探针版：iOS 26+ 识别卡改走 requestChoice 选项卡**：前几版已证实——结果型卡底部必有系统 Done（HIG 解剖图写死）、确认型卡必带 Cancel＋主钮一对且 Cancel 删不掉（ConfirmationActionName 官方 API 只有带 denyLabel 的构造）。iOS 26 的 `requestChoice` 是唯一未被官方文档排除的呈现：perform 中途弹出「纯账单卡（view）＋提示文案（dialog）」与两个完全自定的选项 **View / Got it**，选中后回到 perform 继续。本版就是验证它能否复刻 Kapi 那张卡的探针版；选项按钮的实际排版（并排胶囊还是列表）、系统会不会另加取消，只能以真机截图定案。
- **选 Got it**：先在 perform 内把暂存正式落盘，再以 opensIntent 收尾——指向一个无操作、不打开 App 的后续 Intent，捷徑流程静默结束回原 App。
- **选 View**：不在 perform 内消费暂存，opensIntent 交给同一后续 Intent：它消费暂存→转未确认记录→定位编辑页，并以 `continueInForeground(alwaysConfirm: false)` 把 App 带到前台（刚点过 View、交互新鲜，预期免确认直达）。
- **取消/下滑**：requestChoice 抛错，作废暂存、不落盘，安静结束（catch 仅为作废暂存，随后返回的仍是无呈现的结果）。
- **实现说明**：perform 的全部出口统一为同一 opensIntent 目标（ScanChoiceFollowUpIntent，用参数区分动作）——v1.1.3 已用 CI 实证：同一 perform 混用普通结果、或指向不同 Intent 的 opensIntent，都会触发 #OpaqueTypeInference 编译失败。选项的 Style 只有 .default / .destructive / .cancel，没有主次样式之分，View 与 Got it 均为默认样式，颜色与排版由系统决定。另注意：因返回值带 openIntent，捷徑编辑器里「识别账单」动作会多出一个 **Open When Run** 开关（默认开），请保持开启，否则后续 Intent 不会被执行。
- **分层不变**：iOS 18–25 与 iOS 17 仍走 v1.1.3 的确认型流程，行为不变；App 内扫描后的浮层卡片行为不变。

## [v1.1.3] - 2026-11-11

### 🎨 Highlights
- **卡上只剩 View / Got it 两个按钮，与 Kapi 一模一样**：v1.1.2 的确认卡是系统按钮对「取消／确认」、卡内另有一颗自制「修改 (View)」按钮。v1.1.3 把系统确认按钮对的文案直接改名为 **View（左、灰）/ Got it（右、蓝）**——位置与配色本就是同一套系统排版——并撤掉卡内自制按钮。卡上只剩账单信息、✓ 提示行和这一对按钮，没有多余的选择。
- **点 View 打开 App 改这笔**：系统层面「点 deny 按钮」与「下滑关卡」是同一种取消信号、无法区分，本版统一接成「修改」语义：不落正式账，暂存转未确认记录并打开 App 定位到这笔的编辑页（下滑关卡同样会打开 App，这是该机制的已知行为）。其他异常则作废这笔、安静结束。
- **点 Got it 才入账**：与 v1.1.2 相同，点 Got it（原「确认」）后才正式记账，随后直接结束回原 App，全程没有 Done。
- **分层差异**：iOS 26+ 与 iOS 18–25 均使用 View / Got it 自定义文案；iOS 17 的旧确认 API 只接受系统预置文案（Log / Cancel），无法改名，功能不变。App 内扫描后的浮层卡片行为不变。

## [v1.1.2] - 2026-11-11

### 🚀 Highlights
- **识别卡改确认型，告别 Done**：此前「识别账单」是结果型 snippet——识别完先落盘再弹卡，按苹果设计（WWDC25-281）这类卡片底部必有系统 Done 按钮，无法隐藏（v1.1.1 去掉 dialog 后真机实测 Done 仍在）。v1.1.2 改走确认型呈现：识别结果先暂存（不落盘、不计入余额与列表），系统弹出确认卡；点「确认」才真正记账，随后 Intent 返回空结果——没有任何可呈现内容，捷徑流程直接结束回原 App，全程没有 Done。
- **点确认才入账，取消不记账**：在确认卡上取消或下滑 = 这笔不记（暂存永不落盘，自动丢弃），与「先记账再说」彻底分开。
- **「修改 (View)」保留在确认卡内**：点它会把这笔以未确认状态转入正式记录并打开 App 定位到编辑页，改完保存即可；暂存单次消费、双路径互斥，绝不重复记账。
- **按系统版本分层呈现**：iOS 26+ 用 SnippetIntent 驱动的互动确认卡（系统确认按钮文案「确认」，卡面与原结果卡一致）；iOS 18–25 用带卡面视图的确认；iOS 17 降级为纯文字确认。App 内扫描后的浮层卡片行为不变。

## [v1.1.1] - 2026-11-11

### 🔧 Fixes
- **识别提示不再重复显示**：「识别账单」Intent 不再返回 dialog——此前 iOS 会把 dialog「已识别记录以上信息，打开「咪咪记账」查看更多」单独显示成顶部大字，而 snippet 卡片内部又有同一句，于是出现两次。v1.1.1 起 perform() 只返回结果卡片，那句话只在卡片里出现一次（与 Kapi 一致）。

## [v1.1.0] - 2026-11-11

### 🚀 Highlights
- **捷徑「识别账单」真正可用（修复根因）**：v1.0.9 及更早的 IPA 是 `swift build` 手工拼包，从不生成 `Metadata.appintents`，iOS 根本发现不了 `ScanScreenshotIntent`。v1.1.0 起 CI 显式运行 `appintentsmetadataprocessor` 提取元数据并塞入 .app，并新增硬验证：`extract.actionsdata` 缺失或不含 `ScanScreenshotIntent` 直接构建失败。
- **「识别账单」Intent 参数收干净**：只保留「内容 / 类型（默认 2）/ 版本（默认 1.1.0）」，与 Kapi 捷徑编排一致；「修改账单 / 确认记账」两个辅助 Intent 设为不在动作库中单独展示。
- **删除错误捷徑流程**：移除自带的截屏→剪贴板→openURL `.shortcut` 文件（未签名本就无法导入），不再打进 .app 与 Release。
- **自动记账指南页改版（Kapi 式）**：四种触发方式分区（①辅助触控 ②轻敲手机背面 ③操作按钮 ④控制中心），附「教程」6 步手动搭建与醒目蓝色「添加专属指令」按钮（iCloud 一键导入链接待用户在设备上生成后填入开通）。
- **分类图标贴纸风升级**：白底圆、浅灰细描边、轻微阴影、emoji 放大；图标库扩充至 14 个分组、520+ 个不重复 emoji。
- **全新 App 图标**：原创贴纸风——蓝白渐变底＋橘猫「咪咪」抱金币、脚边账本。

## [v1.0.8] - 2026-11-11

### 🚀 Highlights
- **全面完成「咪咪记账」(Mimi Money) 独立重构与去 Kapi 化**：
  - 仓库迁移至专属仓库 `https://github.com/qingtian6325-lang/own-mimi`。
  - 全局代码、架构模块、类名、协议、包名、文件夹全面重构更名为 `MimiMoney` 系列：
    - 应用程序核心：`MimiMoneyApp`、`MimiMoneyCore`、`MimiMoneyTests`；
    - 设计系统与状态：`MimiTheme`、`MimiStore`、`MimiModels`、`MimiRootContainerView`、`MimiStatsView`、`MimiStickerIconView`；
    - 智能化与服务：`MimiAIEngine`、`MimiCSVService`、`MimiShortcuts`、`MimiAppShortcutsProvider`。
  - URL Scheme 全面更名为 `mimimoney://`，系统深度链接与 Bundle ID 更新为 `com.jinghao.mimimoney`。
  - 打包生成专属 `MimiScreenshotBookkeeping.shortcut` 快捷指令及 `MimiMoney-iOS.ipa`。
  - 全工程完全清除所有历史遗留标识，实现 100% 独立纯净的「咪咪记账」。

## [v1.0.4] - 2026-11-10

### 🚀 Highlights
- **支持浮窗交互式 Dialog：停留在当前 App，按确认静默记账不跳转，按修改才跳转**：
  - 重构 `ScreenshotResultSnippetView` 与 `AppIntents` 交互体系：在 iOS 系统级浮窗卡片中，按「确认 (Got it)」由 `ConfirmBillIntent` 执行，完全停留在当前银行/支付 App 静默平账入库，绝不跳转；只有用户点击「修改 (View)」才由 `OpenBillForEditIntent` 唤起 App 进行编辑。
  - 提供了快捷指令原生「从菜单中选取 (Choose from Menu)」对话框配置指南，解决苹果阻止导入未签名 `.shortcut` 文件的限制。
- **修复负数余额被绝对值吞没的重大 Bug**：修复 `MimiTheme.formatRM` 错误调用 `abs(value)` 导致账户透支或负数金额（如 `-RM700.00`）错误显示为正数 `RM700.00` 的问题。若透支不够钱，严格显示 `-RM700.00` 并高亮红字警示。
- **重构并理清【期初起始资金 (Initial Capital)】全生命周期**：
  - 每个账户底层独立引入 `initialBalance`（全部记账前的初始资金）与 `balance`（当前实际余额）。
  - **正推法**：输入记账前的起始资金，系统结合历史流水净变动，自动计算当前真实余额。
  - **倒推法**：输入手机银行当前实际余额，系统自动逆向倒推出当年记账前的起始资金。
  - 在【资产管理】与【通用设置】中全面支持双模式校准，历史流水与当前身家严谨闭环。

## [v1.0.3] - 2026-11-10

### 🚀 Highlights
- **【自动记账】内置一键跳转添加快捷指令与离线集成**：
  - 在【自动记账】页面新增高亮按钮“⚡ 一键跳转导入「咪咪截屏自动记账」快捷指令”，点击直接唤起 iOS Safari / 快捷指令 App 进行一键安装。
  - 新增“打开「快捷指令」App”与“离线发送至快捷指令 (ShareLink)”双重通道，将 1007 字节的标准快捷指令文件永久内置打包于 App 内部，断网也能导入。
  - 新增“📸 无需快捷指令 · 一键读取剪贴板截图直接记账”快捷按钮，手机截图复制后在 App 内点按直接调用 Apple Vision OCR 记账。

## [v1.0.2] - 2026-11-10

### 🚀 Highlights
- **支持在【设置】与【资产】中自定义设置各账户起始金额（期初余额）**：
  - 【通用设置】新增“💳 账户起始金额与开局资产设置”配置卡，每个账户均可直接输入开局金额并实时保存。
  - 【资产管理】新增“添加自定义资产账户”功能，支持创建 Maybank、GrabPay、加密钱包、备用金等自定义资金账户，并设定其初始开局余额。
  - `MimiStore` 新增 `deleteAccount` 与账户审计全生命周期联动，日常记账、转账与改额实时平账。

## [v1.0.1] - 2026-11-10

### 🚀 Highlights
- **100% 完整交互功能上线**：重构并连接了全部 11 个模块与抽屉页面的底层业务逻辑，去除所有死按钮与空状态提示。
- **纯净空白初始状态 (Clean Empty State)**：新安装 App 打开后，总资产 `RM0.00`、净资产 `RM0.00`、记录天数 `0 天`、交易记录 `0 笔`，无任何伪造或默认演示数据。
- **真实 iOS 快捷指令截屏记账**：快捷指令 `MimiScreenshotBookkeeping.shortcut` 配合 `ReceiptOCRService`（Apple Vision OCR），支持自动截屏识别金额与商户，无截图时自动降级读取系统剪贴板。

### 🔧 Fixed & Improved
- **编译修复**：修复 `TransactionItem` 便利构造器缺少 `tags` 参数的问题，确保 `RecordAndAISheetView` 自定义标签保存正常编译与运行。
- **版本控制与 CI 自动化**：新增 `VERSION` 集中版本管理，GitHub Actions 自动化构建产物并同时同步发布到 `v1.0.1` 和 `v1.0.0` Release。
- **账本管理 (Ledger Management)**：支持账本实时切换、新建账本（名称、货币类型、月度预算）、删除非主账本、直接调整月预算。
- **标签管理 (Tag Management)**：支持新增自定义标签、删除标签、点击标签按当前账本筛选交易记录。
- **定时记账 (Scheduled Bills)**：支持周期性扣款项（房租、订阅、贷款等）开关、新增计划、以及“立即入账”真实写入账户余额与账本流水。
- **小组件交互预览 (Widgets Showcase)**：提供小号（今日可用）、中号（7日趋势与结余）、大号（月度总预算环图与三分类）及锁屏小组件的实时数据渲染预览。
- **通用设置 (General Settings)**：支持昵称编辑、触觉反馈开关、存储占用查看与完全离线沙盒重置。
- **收支统计筛选 (Dynamic Stats)**：支持“周 / 月 / 年 / 自定义”周期切换，分类环形图、每日收支柱状图与 Top 10 排行榜完全动态联动。
- **双表头 CSV 完整解析**：全面兼容包含 140 笔收支与 11 笔转账（共 151 笔）的多行带引号转账备注与账户映射。

## [v1.0.0] - 2026-11-10

### Initial Release
- 1:1 原生 SwiftUI 咪咪记账界面设计体系（MimiTheme、卡片设计、猫咪吉祥物插画、自研数字键盘）。
- 资产账户体系（Cash, Maybank, TNG eWallet, Touch 'n Go NFC）。
- 离线优先无服务器架构，本地 JSON 与 SQLite 双层持久化支持。
- 基础 GitHub Actions CI 跨平台编译流程。
