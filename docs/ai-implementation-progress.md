# PhotoCompositor AI 能力实现进度

## M1 网关配置中心 ✅ 已完成

### 已实现文件

#### Gateway 模块（`Compositor/Gateway/`）
1. **KeychainStore.swift** — API Key 安全存储
   - 使用 macOS Keychain（SecItem API）
   - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 保护级别
   - 仅显示末 4 位，不落 UserDefaults 明文
   
2. **GatewayConfiguration.swift** — 配置数据模型
   - `EndpointType`：8 种能力类型（chat/image_generation/image_edits/video/audio_speech/embeddings/audio_transcriptions/systemone）
   - `ProviderChannel`：渠道模型（name/baseURL/enabled/priority/weight/timeout/proxy/isBuiltIn）
   - `CapabilitySlot`：能力槽位（endpointType/modelOverride/pathOverride/channelIDOverride）
   - `GatewayConfiguration`：完整配置（channels/defaultChannelID/capabilitySlots）
   - `GatewayConfigurationStore`：配置管理（UserDefaults 持久化，AIPDD 内置默认）

3. **GatewayClient.swift** — HTTP 客户端
   - `actor GatewayClient`：async/await URLSession
   - JSON 请求（`request<T: Decodable>`）
   - Multipart 上传（`uploadMultipart`，用于 image edits/audio transcriptions）
   - 二进制下载（`downloadBinary`，用于 TTS/视频）
   - 连接测试（`testConnection`）
   - 错误处理（`GatewayError`/`GatewayClientError`）

#### UI 模块（`Compositor/UI/`）
4. **GatewaySettingsView.swift** — 设置界面
   - `GatewaySettingsView`：TabView（Channels + Capabilities）
   - `ChannelsTab`：渠道列表（优先级排序、启用/停用、编辑/删除/设为默认）
   - `ChannelRow`：单渠道行（名称/URL/Key 末 4 位/状态徽章）
   - `ChannelEditorView`：渠道编辑器（添加/编辑、连接测试、表单验证）
   - `CapabilitiesTab`：能力槽位列表
   - `CapabilitySlotRow`：单槽位行（model/path/channel 覆盖）

#### App 入口（`Compositor/CompositorApp.swift`）
5. **Settings Scene** — 设置窗口
   - 新增 `Settings { GatewaySettingsView() }`
   - 菜单项：PhotoCompositor › AI Gateway Settings…

### 技术要点
- ✅ Keychain 存储 API Key（非 UserDefaults）
- ✅ AIPDD 内置默认渠道（priority=100，isBuiltIn=true）
- ✅ 8 个能力槽位预置默认路径
- ✅ 多渠道管理（添加/编辑/删除/设为默认）
- ✅ 能力槽位覆盖（model/path/channel）
- ✅ 连接测试功能
- ✅ 深色主题 UI（匹配 PhotoCompositor 风格）
- ✅ Xcode 自动发现（PBXFileSystemSynchronizedRootGroup）

### 验收标准
- [ ] 在 macOS 上打开 Xcode，构建项目
- [ ] 运行 App，菜单出现「AI Gateway Settings…」
- [ ] 打开设置窗口，看到 Channels 和 Capabilities 两个 Tab
- [ ] Channels Tab：AIPDD 内置渠道置顶，显示「Built-in」和「Default」徽章
- [ ] 点击「Add Channel」，填写表单，测试连接，保存
- [ ] 编辑渠道，修改参数，保存
- [ ] 删除自定义渠道（AIPDD 不可删除）
- [ ] 切换默认渠道
- [ ] Capabilities Tab：8 个能力槽位，可覆盖 model/path/channel
- [ ] Keychain 检查：`security find-generic-password -s "com.compositor.gateway"` 能看到 Key

---

## M2 出图/修图端到端 ✅ 已完成

### 已实现文件
- `Compositor/AI/ImageBridge.swift` — CGImage ↔ base64/multipart 转换
- `Compositor/AI/TaskQueue.swift` — 异步任务队列（并发/进度/取消/重试）
- `Compositor/AI/GatewayDTOs.swift` — 请求/响应数据模型（含 `AnyCodable`）
- `Compositor/AI/ImageGeneration/ImageGenerationSheet.swift` — 文生图
- `Compositor/AI/ImageEditing/ImageEditingSheet.swift` — 图生图/inpainting

### 功能点
- ✅ B1 文生图：prompt/尺寸/张数/质量 → 落新图层
- ✅ B2 AI 修图：multipart `image` + `prompt` → 落新图层
- ✅ B3 局部重绘：选区/蒙版 → `mask` 字段 → 回填选区
- ✅ B8 任务队列：并发/进度/取消/重试/结果对比
- ✅ EditorSession 集成：结果通过 `session` 原语落层，可撤销

---

## M3 目录驱动 + 异步 + 视频/音频 ✅ 已完成

### 已实现文件
- `Compositor/Catalog/CatalogStore.swift` — 能力目录同步 + 本地快照 + 中文标签
- `Compositor/AI/Video/VideoGenerationSheet.swift` — 视频生成
- `Compositor/AI/Video/LivePhoto.swift` — 生成视频 → Live 图帧对导出
- `Compositor/AI/Audio/TTSSheet.swift` — 语音合成
- `Compositor/AI/Audio/STTSSheet.swift` — 语音转写

### 功能点
- ✅ A7 目录同步（catalog，回落 models）
- ✅ B9 视频生成（异步轮询）+ Live 图帧对导出
- ✅ B10 语音合成 TTS（二进制下载 + 播放）
- ✅ B11 语音转写 STT（multipart 上传）

---

## M4 自然语言修图 ✅ 已完成

### 已实现文件
- `Compositor/AI/NaturalLanguage/IntentRecognition.swift` — 意图识别
- `Compositor/AI/NaturalLanguage/AutoTidy.swift` — systemone 决策模型整理（重命名/成组）
- `Compositor/AI/NaturalLanguage/NaturalLanguageSheet.swift` — UI
- `Compositor/UI/AutoTidySheet.swift` — 整理预览确认
- `Compositor/Document/EditorSession+AI.swift` — `applyAIIntent` 落地 25+ 操作

### 功能点
- ✅ C1 意图识别（chat 结构化工具调用）
- ✅ C2 执行引擎：意图经 session 自身编辑路径落地
- ✅ C3 确认机制 + C4 历史回放（复用文档历史）
- ✅ Auto-Tidy 决策模型整理，可撤销

---

## M5 增量功能 ✅ 已完成（见下方清单）

已交付的增量功能（各自独立测试 + 7 语言翻译）：
- ✅ 隐私模式总开关（配置/拦截/菜单/设置页）
- ✅ OCR 文字识别（Vision → 复制或回落活文字层）
- ✅ 智能裁切 Auto Crop（Vision objectness）
- ✅ 语义选区（Vision 主体蒙版，端上运行）
- ✅ AI 修复与增强面板（网关预设）+ 批量逐层串行
- ✅ 图像描述（chat 读画布，v14 落项目）
- ✅ 智能导出建议 + AI 背景生成
- ✅ 智能对齐/排列 + 历史学习偏好
- ✅ embeddings 素材语义搜索（最近项目索引）
- ✅ 成本预估展示 + 内容安全前置（moderations）
- ✅ Live 图生成

项目格式：`ProjectManifest.current = 14`（v14），往返测试覆盖。

### 尚待补充（下一步）
- ⏳ B5 扩图 Outpainting：选区外扩 + mask 提交 + 画布变大落层
- ⏳ B7 提示词助手：图层名/选区缩略图 → chat 产出可编辑 prompt
- ⏳ D#5 文字替换半边：改文字 → AI 抹原文 → 新文字层回位
