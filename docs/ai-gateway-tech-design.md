# Compositor AI 能力技术方案

## 0. 架构判定

- **不嵌入 newapi-sc 服务**，照搬它的配置契约：`Channel（渠道）+ EndpointType（能力槽位）+ priority/weight（优先级/权重）+ 多 Key 轮换 + 失败降级 + 连续失败自动禁用 + error.message 错误结构`。Compositor 作为客户端**直连 OpenAI 兼容上游**。
- 你给的 8 个地址是**同一 base_url + 8 条路径**，所以配置模型是「一个渠道，8 个能力槽位」，每槽位可独立覆盖 model 名与路径。
- 关键红利：AIPDD 上游有 `GET {base}/v1/new-api/catalog`（`pkg/aipddcatalog/atomic.go:17`），返回每个能力的 `inputModalities/outputModalities/params 约束/execution.protocol+path/pricing`。**客户端 UI 应由目录驱动**，而不是把模型名和参数硬编码进 Swift。
- 分层：`GatewayCore`（纯 Swift、无 UI、可单测）→ `CatalogStore` → `ImageBridge`（CGImage ↔ base64/multipart）→ `AI 功能面板`。

## 1. 技术要点

### 1.1 新代码落点

```
Compositor/
├── Gateway/              # 配置模型 + URLSession async 层 + Keychain 封装 + 任务轮询状态机
│   ├── GatewayConfiguration.swift    # 渠道/槽位/Key 数据模型
│   ├── GatewayClient.swift           # URLSession async actor
│   ├── KeychainStore.swift           # SecItem 封装
│   ├── CatalogStore.swift            # 目录同步 + 本地快照
│   └── TaskPoller.swift              # 异步任务轮询状态机
├── Catalog/              # 能力目录解析与 UI 驱动
│   ├── CatalogEntry.swift
│   └── CapabilityResolver.swift
├── AI/                   # 功能与 UI sheet
│   ├── ImageGeneration/  # B1 文生图
│   ├── ImageEditing/     # B2-B3 图生图/inpainting
│   ├── Enhancement/      # B4 一键增强
│   ├── Video/            # B9 视频生成
│   ├── Audio/            # B10-B11 TTS/STT
│   ├── NaturalLanguage/  # C1-C5 自然语言修图
│   └── LivePhoto/        # D-40 Live 图生成
└── CompositorTests/      # 对应同名测试
```

### 1.2 字段逐字对齐

照搬 newapi-sc 的 OpenAI 兼容字段名，不可自创：

| 能力 | 路径 | 必填字段 | 响应取值 |
|---|---|---|---|
| 文本 | POST `/v1/chat/completions` | `model, messages[]`（`stream` 可选） | `choices[0].message.content`；流式 `choices[0].delta.content`，结束 `data: [DONE]` |
| 图生 | POST `/v1/images/generations` | `model, prompt`（`n,size,quality,response_format`） | `data[0].url` 或 `data[0].b64_json` |
| 图编 | POST `/v1/images/edits` | multipart：`image`(多图 `image[]`), `prompt`；可选 `mask, size, n`；或 JSON `model+image/images+mask` | `data[0].url` / `data[0].b64_json` |
| 视频创建 | POST `/v1/videos` | `model, prompt`（图生视频 `image`；`duration/resolution/ratio/seconds`） | `id` 或 `task_id`，`status=queued` |
| 视频轮询 | GET `/v1/videos/{task_id}` | — | `status∈{queued,in_progress,completed,failed}`, `progress`, 产物 `output[]`/`url`（或 `/v1/videos/{id}/content`） |
| TTS | POST `/v1/audio/speech` | `model, input, voice`（`response_format, speed`） | 响应体本身为二进制音频（Content-Type 透传） |
| 转写 | POST `/v1/audio/transcriptions` | multipart `file, model`（`language, prompt, response_format`） | `text`（verbose_json 时 `segments[].start/end/text`） |
| 向量 | POST `/v1/embeddings` | `model, input` | `data[0].embedding` |
| 决策模型 | POST `/v1/systemone` | `model, state, questions` | 上游 JSON 原样 |
| 模型列表 | GET `/v1/models` | Header 决定形态 | `data[].id` |

Header 一律 `Authorization: Bearer <key>`；错误取 `error.message`/`error.type`，任务类取 `code`/`message`。

### 1.3 两种响应都要处理

- **同步**：`data[0].b64_json` 或 `data[0].url`
- **异步任务**：`{code,message,data{output[],status,task_id}}`（状态 `queued/in_progress/completed/failed`），后者需退避轮询与超时

### 1.4 风险清单

- `MACOSX_DEPLOYMENT_TARGET=26.0`（覆盖面极窄，但这是上游既定）
- 无任何 HTTP 层先例，网络层要从零写并单测
- AIPDD 模型名是中文带空格（如 `AP Seedance-2.5 标准版`），必须原样传、不可 slugify
- 沙盒下文件访问受限
- Windows 机器无法构建/跑 `xcodebuild`，编码验证需 macOS CI（`.github/workflows/verify.yml` 已具备）

### 1.5 格式变更纪律

新增 AI 元数据 → `ProjectManifest.current` bump + `docs/project-format.md` 同步 + 往返测试（`AGENTS.md` 明确要求）。

## 2. 关键实现细节

### 2.1 GatewayConfiguration 数据模型

```swift
struct GatewayConfiguration: Codable {
    var channels: [ProviderChannel]
    var defaultChannelID: UUID?
    var capabilitySlots: [CapabilitySlot]
}

struct ProviderChannel: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: URL
    var apiKeyRef: String  // Keychain 引用，非明文
    var enabled: Bool
    var priority: Int      // 越高越优先
    var weight: Int        // 权重随机
    var timeout: TimeInterval
    var proxy: URL?
}

struct CapabilitySlot: Codable, Identifiable {
    let id: UUID
    var endpointType: EndpointType  // chat/image_generation/image_edits/video/audio_speech/embeddings/audio_transcriptions/systemone
    var modelOverride: String?
    var pathOverride: String?
    var channelIDOverride: UUID?
}
```

### 2.2 Keychain 封装

```swift
final class KeychainStore {
    func store(key: String, for channelID: UUID) throws
    func retrieve(for channelID: UUID) throws -> String?
    func delete(for channelID: UUID) throws
}
// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

### 2.3 URLSession async actor

```swift
actor GatewayClient {
    func request<T: Decodable>(_ endpoint: Endpoint, as: T.Type) async throws -> T
    func stream(_ endpoint: Endpoint) -> AsyncThrowingStream<ServerSentEvent, Error>
    func uploadMultipart(_ endpoint: Endpoint, parts: [MultipartPart]) async throws -> Data
}
```

### 2.4 任务轮询状态机

```swift
actor TaskPoller {
    enum State { case queued, inProgress(progress: Double), completed(URL), failed(Error) }
    func poll(taskID: String, channel: ProviderChannel) -> AsyncStream<State>
}
// 退避：1s → 2s → 4s → 8s → max 30s
```

### 2.5 目录同步

```swift
actor CatalogStore {
    func sync(baseURL: URL, apiKey: String) async throws -> CatalogSnapshot
    func loadLocalSnapshot(baseURL: URL) -> CatalogSnapshot?
}
// GET {base}/v1/new-api/catalog
// 失败时回落 GET /v1/models
// 快照绑定 base_url，不匹配则拒绝
```

### 2.6 自然语言修图意图 JSON

```swift
struct EditingIntent: Codable {
    enum Action: String, Codable {
        case adjustLevels, adjustCurves, addAdjustmentLayer, reorderLayers, addMask, ...
    }
    let action: Action
    let parameters: [String: AnyCodable]
    let targetLayerIDs: [String]?
    let requiresConfirmation: Bool
}
```

### 2.7 Live 图生成流程

```
1. /v1/images/generations → 静态图（JPEG/HEIC）
2. /v1/videos (image=静态图, duration=3) → 异步任务
3. 轮询 /v1/videos/{task_id} → completed
4. 下载视频（MOV）
5. AVFoundation 提取关键帧（或让用户选帧）
6. 打包：静态图 + MOV → .livephoto 或 PHAsset
7. 导出到相册或嵌入项目资源库
```

## 3. 测试策略

- **CompositorTests** 单测：配置编解码、multipart 构造、异步任务状态机、目录解析
- CI 已跑（`.github/workflows/verify.yml`）
- 新增测试文件命名：`GatewayTests.swift`、`CatalogTests.swift`、`AIFeatureTests.swift`

## 4. 安全清单

- [ ] API Key 存 Keychain，不落 UserDefaults/plist/json
- [ ] 日志脱敏（不打印完整 Key、不打印用户图像 base64）
- [ ] TLS 1.2+ 强制
- [ ] 隐私模式开关（禁止任何图像上传）
- [ ] 沙盒权限审查（`network.client` 已开，文件访问需用户选择）
