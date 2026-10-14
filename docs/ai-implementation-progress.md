# Compositor AI 能力实现进度

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
   - 菜单项：Compositor › AI Gateway Settings…

### 技术要点
- ✅ Keychain 存储 API Key（非 UserDefaults）
- ✅ AIPDD 内置默认渠道（priority=100，isBuiltIn=true）
- ✅ 8 个能力槽位预置默认路径
- ✅ 多渠道管理（添加/编辑/删除/设为默认）
- ✅ 能力槽位覆盖（model/path/channel）
- ✅ 连接测试功能
- ✅ 深色主题 UI（匹配 Compositor 风格）
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

## M2 出图/修图端到端 ⏳ 待实现

### 计划文件
- `Compositor/AI/ImageGeneration/ImageGenerationSheet.swift` — 文生图 UI
- `Compositor/AI/ImageEditing/ImageEditingSheet.swift` — 图生图/inpainting UI
- `Compositor/AI/TaskQueue.swift` — 任务队列管理
- `Compositor/AI/ImageBridge.swift` — CGImage ↔ base64/multipart 转换

### 功能点
- B1 文生图：prompt/尺寸/张数/质量 → 落新图层
- B2 AI 修图：multipart `image` + `prompt` → 落新图层
- B3 局部重绘：选区/蒙版 → `mask` 字段 → 回填选区
- B8 任务队列：并发/进度/取消/重试/结果对比

---

## M3 目录驱动 + 异步 + 视频/音频 ⏳ 待实现

### 计划文件
- `Compositor/Gateway/CatalogStore.swift` — 目录同步 + 本地快照
- `Compositor/Catalog/CatalogEntry.swift` — 能力目录解析
- `Compositor/AI/Enhancement/EnhancementSheet.swift` — 一键增强
- `Compositor/AI/Video/VideoGenerationSheet.swift` — 视频生成
- `Compositor/AI/Audio/TTSSheet.swift` — 语音合成
- `Compositor/AI/Audio/STTSSheet.swift` — 语音转写
- `Compositor/Gateway/TaskPoller.swift` — 异步任务轮询

---

## M4 自然语言修图 ⏳ 待实现

### 计划文件
- `Compositor/AI/NaturalLanguage/IntentRecognition.swift` — 意图识别
- `Compositor/AI/NaturalLanguage/IntentExecution.swift` — 执行引擎
- `Compositor/AI/NaturalLanguage/NaturalLanguageSheet.swift` — UI

---

## M5 增量功能 ⏳ 待实现

### P1 功能（45 项）
见 `docs/ai-gateway-requirements.md` 模块 D

---

## 下一步

1. **在 macOS 上构建并测试 M1**
   - 打开 `Compositor.xcodeproj`
   - 构建项目（⌘B）
   - 运行 App（⌘R）
   - 测试设置窗口功能

2. **实现 M2（出图/修图）**
   - 创建 ImageGenerationSheet
   - 创建 ImageEditingSheet
   - 创建 TaskQueue
   - 创建 ImageBridge
   - 集成到菜单和命令面板

3. **迭代优化**
   - 根据测试结果调整 UI
   - 添加单元测试
   - 更新文档
