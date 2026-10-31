# CamerMemo

[程序结构说明](ARCHITECTURE.md) · [产品设计](PRODUCT_SPEC.md)

iPhone / iOS 17+ / SwiftUI，无第三方依赖。

## 运行

双击 CamerMemo.xcodeproj，选择 CamerMemo scheme 和 iPhone 模拟器运行。首次使用设置至少 12 字符的主密码；该密码无法找回。
真机需在 Signing & Capabilities 选择自己的 Team，将 com.example.CamerMemo 改为唯一 Bundle Identifier。

## 已实现

- 创建、解锁本地加密资料库；进入后台锁定，应用非活跃时遮挡内容。
- 新建文字 memo：可选标题、必填正文、创建和修改时间。
- 列表与详情、编辑保存；取消时确认放弃修改，修改期间禁用下滑关闭编辑页。
- 搜索标题和正文：中日文子串、大小写/全半角折叠，空格分词按 AND 匹配，标题命中优先，再按更新时间排序。
- AES-256-GCM 信封加密，PBKDF2-HMAC-SHA256（600,000 轮、随机 salt）包装随机资料库密钥。密钥仅驻留当前解锁会话；密文原子写入 Application Support/CamerMemo/vault.cmemo。
- 写入成功后才发布内存变更；错密码/损坏文件不会当作空库或覆盖原件。

## 当前阶段与限制

当前使用版本化 JSON 加密快照作为基础实现，尚未采用产品规划的 SQLite。格式标识为 CamerMemo.JSONVault v1；后续切换存储格式需要显式迁移，不可直接替换文件。

非活跃时尝试将非空编辑自动保存为正式 memo（尚未实现单独 draft 表）。取消修改不会撤回先前自动保存的版本。空正文不保存；后台保存若因磁盘等错误失败，锁定页提示未保存修改未被保留，最后成功版本不变。强制终止前未收到生命周期回调的未保存内容可能丢失，请使用保存按钮。

整库读写与搜索适用于首版小规模文字库，保存目前在主线程串行执行；大库性能、后台失败草稿恢复、重试退避与完整安全审查仍需完善。文件大小设有 100 MB 上限，不代表已完成大库性能验证。

尚未实现：置顶、云端 AI、修改密码、备份导入导出。请勿把开发版当作唯一的数据副本。

## 验证

模拟器目标编译：

```sh
xcodebuild -project CamerMemo.xcodeproj -scheme CamerMemo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/CamerMemo-DerivedData CODE_SIGNING_ALLOWED=NO build
```

macOS 核心验证（使用相同的模型与加密源文件）：

```sh
swiftc CamerMemo/Memo.swift CamerMemo/EncryptedVault.swift CamerMemo/L10n.swift CamerMemo/TextRecognitionService.swift CamerMemo/TagRules.swift Tests/CoreChecks.swift -o /private/tmp/CamerMemo-CoreChecks
/private/tmp/CamerMemo-CoreChecks
```

覆盖新建/编辑后解密往返、Unicode/全半角/大小写与多词搜索、错密码、nonce 更新、文件篡改/截断、禁止覆盖已有库。尚未完成模拟器交互和真机测试。

## 多语言文案配置

- `CamerMemo/Localizable.xcstrings`：全部应用自有界面文字、无障碍标签、校验提示、错误与未命名标题，共 108 个 key；提供简体中文（zh-Hans）、英文（en）、日文（ja）。
- `CamerMemo/InfoPlist.xcstrings`：桌面显示名称与相机权限说明，支持三种语言。
- `CamerMemo/L10n.swift`：类型化 key 与资源读取/格式化入口；不保存翻译正文。

语言跟随 iOS 的 App 首选语言；可以在系统设置的 CamerMemo 语言选项中选择，也可以通过 Xcode scheme 的 Run → Options → App Language 验证。系统最终未匹配到支持语言时回退到开发语言简体中文。日期和系统自带控件由系统本地化。用户记录的标题和正文保持原样，不参与翻译。

修改已有文案：在 Xcode 打开 Localizable.xcstrings，修改相应 key 的翻译即可，也可以按 JSON 编辑。添加语言：在 String Catalog 中添加语言并补齐翻译，同时在工程 Localizations 中登记。添加文案：添加 catalog 条目及 L10n.Key 枚举项，代码通过 L10n.text 引用。包含 `%@` 的两项错误模板必须保留一个字符串占位符，不要拼接语言片段。

系统文件错误统一映射为配置中的可操作提示，避免直接展示含内部路径、语言不一致的系统诊断。加密文件格式标识、文件名和图标名称属于技术标识，不随语言改变。

检查编译后的资源（先完成上方构建）：

```sh
swiftc CamerMemo/Memo.swift CamerMemo/EncryptedVault.swift CamerMemo/L10n.swift CamerMemo/TextRecognitionService.swift CamerMemo/TagRules.swift Tests/LocalizationChecks.swift -o /private/tmp/CamerMemo-LocalizationChecks
/private/tmp/CamerMemo-LocalizationChecks /private/tmp/CamerMemo-DerivedData/Build/Products/Debug-iphonesimulator/CamerMemo.app
```

## 拍照、选图与本机文字识别

列表底部“图片记录” → “拍照识别”或“从照片中选择” → 自动识别 → 校对标题、正文 → 保存。可在选图前设置自动、中、日、英识别语言。无文字或识别失败时可更换语言、重新识别或选择其他图片。成功后的校对文本不自动重新识别，避免覆盖修改；重新选择会先询问是否放弃。

相机使用 UIImagePickerController 和显式相机权限检查；无相机（例如模拟器）、权限拒绝/受限均提示，拒绝时提供系统设置入口。照片使用 PhotosPicker，仅选择的照片会被读取，不申请整个照片库访问权限。云端照片读取可能需要网络下载；OCR 本身完全使用本机 Apple Vision，不调用云端 API。

当前每次单张图片，读取上限 40 MB。相册图片保留所选文件的完整数据；相机照片以完整尺寸进行方向规范化并编码为 JPEG（质量 0.9），并非原始无损数据。OCR 单独生成最长边 3200 像素的临时图像副本，附件不使用该缩小副本。保存的 memo 包含图片附件、校对后的文字、原始识别文本、camera/photo 来源及已有元数据，一起加密；不创建明文附件文件，不自动保存到系统相册。旧 memo 缺少新增可选字段时仍可读取。

处理可取消；Vision 在后台执行，视图关闭或真正进入后台时取消任务，迟到结果不能写回锁定界面。相机权限弹窗或系统相机引起的 inactive 状态仅遮挡，不直接解锁/锁定资料库；真正进入后台仍锁定。图片校对文字必须主动保存；进入后台会清除未保存的图片校对内容，并尝试在锁定页提示（独立加密草稿恢复尚未实现）。

识别精度取决于清晰度、语言和排版；复杂多栏、竖排、手写内容需人工校对。目前不提供裁剪、旋转或多图合并。

OCR 核心验证使用 macOS 的同一 Vision 服务：

```sh
swiftc CamerMemo/Memo.swift CamerMemo/EncryptedVault.swift CamerMemo/L10n.swift CamerMemo/TextRecognitionService.swift CamerMemo/TagRules.swift Tests/OCRChecks.swift -o /private/tmp/CamerMemo-OCRChecks
/private/tmp/CamerMemo-OCRChecks
```

真机需验证：首次相机授权/拒绝与设置恢复、拍摄重拍/取消、相册选择取消及 iCloud 下载、旋转/镜像照片、中日英实际照片、处理中与校对中切换后台。模拟器无法验证相机实拍。

## 图片附件

保存图片记录时，附件通过可选 imageData 字段和正文一起进入加密快照。打开对应 memo 后，正文下方显示图片缩略图，点击进入完整图片浏览；支持双指缩放、双击放大/还原和拖动，关闭返回正文。缩略图只在内存中生成（最长边 400 像素），全屏图片不经过 OCR 分辨率缩减。旋转屏幕时重新适配显示。

编辑已有 memo 的文字会保留附件。既有无附件 memo 正常显示；此前未保存图片的旧记录无法补回原图。无识别结果时可以手动填写正文并保留图片。进入后台会遮挡全屏浏览并关闭图片，后续仍需解锁资料库。

当前依然是整库 JSON 加密快照，包含图片后保存成本和内存使用随图片数量增加；密文文件总量限制为 100 MB，超限保存失败并保留最后成功版本。附件较多时需要进一步迁移独立加密附件存储；当前不提供附件删除/替换或一条 memo 多图。

附件验证：覆盖图片字节加密往返、密文不包含附件 Base64、编辑后图片不变、旧文件缺少 imageData 时可解码。全屏缩放、旋转和后台锁定需在模拟器或真机交互验证。

## 标签、自动建议与搜索

文字编辑页、图片识别校对页提供同一套标签编辑器。标题/正文停止修改约 1 秒后，使用 Apple Foundation Models 的本机模型自动建议 0～3 个标签（严格少于 4 个）。新候选默认勾选；点击可取消或恢复，手动输入后点“添加”或键盘提交。保存时会自动提交输入框中有效的未提交标签。

每个标签最多 32 字符，去除首尾空白与前导 #，规范化内部空白；大小写/全半角等价标签只保存一份。手动标签数量不受 AI 的 3 个候选限制。重新生成不覆盖手动或已有标签；明确取消/移除的标签保持不选中，该选择在保存后也会保留。停止生成后可手动继续，点击重新生成可恢复 AI。

生成中可以停止；正常保存等待当前建议生成完毕，也可停止后直接保存。非活跃自动保存仅写入当时有效的标签，不等待 AI。修改正文后丢弃旧候选，异步结果同时检查取消状态、内容和请求版本，不能覆盖新正文的候选或回写已关闭编辑器。

AI 要求 iOS 26+、支持且已启用 Apple Intelligence、模型就绪和相应语言/地区支持；不满足时显示原因，手动标签、保存和搜索仍可用，不回退云端。当前开发 Mac 模型未就绪，尚未验证实际模型输出质量；已验证接口编译、不可用分支和使用可控生成器的标签选择/取消状态行为。

提示与分段参数集中在 `CamerMemo/TagAIConfiguration.json`；以 1800 字符分段读取全文，长文各段候选通过有界分组归并至最多 3 个，不静默截断。AI 仅接收解锁后的标题和正文，不读取图片附件，不记录文档或生成结果日志。

列表和详情显示标签。搜索框默认“全部”，同时匹配标题、正文、标签；激活搜索后可切换“仅标签”。多个关键词以空格分隔并按 AND 匹配，支持中文子串、大小写和全半角等价匹配。

数据模型新增可选 tags 与 rejectedTagKeys 字段，与文字/附件统一加密；旧文档无这些字段仍能读取。不批量自动改写历史文档。当前未区分持久化的标签来源，也未提供全局标签重命名。

标签行为检查：

```sh
swiftc CamerMemo/Memo.swift CamerMemo/EncryptedVault.swift CamerMemo/L10n.swift CamerMemo/TextRecognitionService.swift CamerMemo/TagRules.swift CamerMemo/TagGenerationService.swift CamerMemo/TagDraft.swift Tests/TagChecks.swift -o /private/tmp/CamerMemo-TagChecks
/private/tmp/CamerMemo-TagChecks
```

## 多选删除

在备忘录列表或文字/标签搜索结果中点击右上角“选择”，逐条勾选或全选当前结果。底部显示删除数量，点击后弹出明确的永久删除确认；取消不写入资料库，确认后将所选记录及其内嵌图片、标签一起移除。未选中记录及其附件、共享标签保持不变。

搜索条件或范围改变后，自动移除不再可见的选择；确认对话框冻结待删除 ID 集合，执行时再次限制为当前可见记录。退出选择模式清空选择。删除失败显示错误并保留选择，便于重试。

批量删除将剩余记录一次性加密原子写入，成功后才更新内存/搜索结果。写入失败保留最后成功的数据和列表。当前为永久删除，没有最近删除或撤销；确认框明确提示不可恢复。锁定状态不能删除。

验证包括多选与可见范围限制、取消不写盘、空/无效 ID 不写盘、故意制造写入失败时数据保留、批量删除后重新解锁、保留记录及附件不变、共享标签仍可搜索、删除最后一条后仍可正常打开。尚未完成真机的选择与确认交互验证。

```sh
swiftc CamerMemo/Memo.swift CamerMemo/EncryptedVault.swift CamerMemo/L10n.swift CamerMemo/TextRecognitionService.swift CamerMemo/TagRules.swift CamerMemo/MemoStore.swift CamerMemo/MemoSelection.swift Tests/DeletionChecks.swift -o /private/tmp/CamerMemo-DeletionChecks
/private/tmp/CamerMemo-DeletionChecks
```

## 文档时间戳与同步基础

每条 memo 保留稳定 UUID、createdAt（创建时间）和 updatedAt（更新时间），随正文/标签/图片一起加密保存。详情以带标签的两项时间展示到秒，列表明确显示更新时间；UI 采用系统语言与设备时区，存储的是时区无关的绝对时间。

由 MemoStore 统一维护时间：首次成功保存时两项相同；后续实际更改标题、正文、标签选择、来源/识别原文或附件时保留创建时间并刷新更新时间。只打开、搜索、解锁或无内容变化的重复保存均不改时间、不重写密文。失败写入不发布新时间。草稿打开的时间不当作新文档首次保存时间；旧文档既有时间不重置。

若系统时间回拨，本地编辑的更新时间取当前时间、上次更新时间加 1 毫秒及创建时间的最大值，确保单文档本地变更时间递增。此保护不能解决不同设备时钟偏差或并发编辑冲突。

为兼容旧资料库，字段名与当前 v1 Date 编码保持不变：Foundation 默认 Codable 使用自 2001-01-01 UTC 起的秒数（并非 Unix 毫秒）；不能直接将该数值当作未来同步协议时间。同步传输层应明确转换为 ISO 8601 UTC 或 Unix 毫秒，并定义版本。

尚未实现同步、远端导入或冲突合并。未来同步还需定义版本/变更标识、删除墓碑及附件同步策略，不能仅凭本机更新时间判断多设备冲突；远端合并应使用独立接口，不能套用本地保存时钟覆盖远端时间。

```sh
swiftc CamerMemo/Memo.swift CamerMemo/EncryptedVault.swift CamerMemo/L10n.swift CamerMemo/TextRecognitionService.swift CamerMemo/TagRules.swift CamerMemo/MemoStore.swift Tests/TimestampChecks.swift -o /private/tmp/CamerMemo-TimestampChecks
/private/tmp/CamerMemo-TimestampChecks
```

## 开始页与锁定按钮

开始页使用居中的圆润斜体 CamerMemo 标题，采用系统字体与动态字号。下方居中显示已确认的图标图片，使用独立 LaunchArtwork 图片资源，宽高均为可用页面宽度的 75%。页面可滚动，以适应键盘、小屏幕和较大字体。

解锁/创建资料库与列表锁定按钮共用 VaultActionButton：48×48 点、21 点白色符号、蓝色渐变圆形和相同阴影/按压反馈。分别使用开锁和闭锁符号，具备本地化无障碍标签；生成密钥时显示进度且禁止重复操作。iOS 26+ 隐藏该工具栏项目的自动共享背景，保持按钮外观与开始页一致。选择模式下仍显示原有全选操作。
