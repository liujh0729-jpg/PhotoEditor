# PhotoCompositor AI 能力需求方案

## 0. 架构判定

- **不嵌入 newapi-sc 服务**，照搬它的配置契约：`Channel（渠道）+ EndpointType（能力槽位）+ priority/weight（优先级/权重）+ 多 Key 轮换 + 失败降级 + 连续失败自动禁用 + error.message 错误结构`。PhotoCompositor 作为客户端**直连 OpenAI 兼容上游**。
- 你给的 8 个地址是**同一 base_url + 8 条路径**，所以配置模型是「一个渠道，8 个能力槽位」，每槽位可独立覆盖 model 名与路径。
- 关键红利：AIPDD 上游有 `GET {base}/v1/new-api/catalog`，返回每个能力的 `inputModalities/outputModalities/params 约束/execution.protocol+path/pricing`。**客户端 UI 应由目录驱动**，而不是把模型名和参数硬编码进 Swift。
- 分层：`GatewayCore`（纯 Swift、无 UI、可单测）→ `CatalogStore` → `ImageBridge`（CGImage ↔ base64/multipart）→ `AI 功能面板`。

## 1. 模块 A：大模型网关配置中心（P0）

| # | 需求 | 口径来源 |
|---|---|---|
| A1 | 渠道列表：名称、Base URL、API Key（多个）、启用/停用、**优先级**、权重、超时、代理 | 照搬 `model/channel.go:23-60` |
| A2 | **AIPDD 内置为默认渠道，优先级最高、置顶不可删**（可停用）；8 个槽位预置：文本 `/v1/chat/completions`、出图 `/v1/images/generations`、图编 `/v1/images/edits`、视频 `/v1/videos`、语音合成 `/v1/audio/speech`、向量 `/v1/embeddings`、转写 `/v1/audio/transcriptions`、决策 `/v1/systemone` | 用户给的 URL 逐字采用 |
| A3 | 每槽位可覆盖 model 名 / 路径 / 指定渠道（默认回落渠道 Base URL） | `EndpointType` 13 类 |
| A4 | 多 Key：`\n` 或 JSON 数组拆分，random / polling 轮换；单 Key 失败自动剔除并降级到下一优先级渠道，重试上限后报错 | `GetNextEnabledKey()`、`shouldRetry` |
| A5 | **Key 存 Keychain（SecItem）**，仅显示末 4 位；仓库现无 Keychain 先例，需新引入——绝不能落 UserDefaults 明文 | 安全红线 |
| A6 | 连通性自检：逐能力「测试」按钮，显示 HTTP 状态 + `error.message`/`error.type` | `types/error.go:13-19` |
| A7 | 目录同步：拉 catalog 缓存到本地，失败时用上次快照（快照绑定 base_url，不匹配则拒绝）；无 catalog 时回落 `GET /v1/models` | `model/aipdd_catalog_sync.go:44-81` |
| A8 | **多渠道管理**：用户可添加多个渠道（任意 OpenAI 兼容网关 / 自建 newapi-sc），使用时选一个；可设默认，但 AIPDD 优先级最高、置顶 | 用户口径 |
| A9 | 设置入口：新增 Settings 分区（PhotoCompositor 目前无偏好窗口，需新建一个 sheet/scene），并按既有约定做美式拼写、注释风格 | 现状 `ContentView.swift:6-7` |

## 2. 模块 B：AI 出图 / 修图（P0）

统一约束：产物一律作为普通 `ImageLayer` + 内嵌 PNG 入库；所有可撤销编辑包 `history.begin/endEdit`；长任务沿用 `isProjectBusy` + `ProgressView` + `Task` 取消。

- **B1 文生图**：prompt / 尺寸 / 张数 n / 质量 → `data[].b64_json` 或 `data[].url` → 落新图层（画布居中或替换所选层）。
- **B2 AI 修图（图生图）**：把当前层或选区像素以 multipart `image`（多图 `image[]`）+ `prompt` 提交 `/v1/images/edits`。
- **B3 局部重绘 inpainting**：现有选区/蒙版导出为 `mask` 字段一并提交；结果只回填选区（带羽化边界混合，复用 C 侧 `BlendPixels` 思路）。
- **B4 一键增强**：超分/去噪/老照片修复（目录里 `seedvr2-upscale` 这类 `taskKind`），**异步任务式**：提交→轮询→下载。
- **B5 扩图 outpainting**：画布外区域 + mask。
- **B6 智能移除 / 抠图升级**：现有 `VNGenerateForegroundInstanceMaskRequest`（`ObjectSelection.swift:40`）与 C 版 PatchMatch `ContentFill.swift:22` 保留为本地兜底，网关可用时走 AI 版本，二者在 UI 上标注「本地 / AI」。
- **B7 提示词助手**：文本模型读图层名/选区缩略图，产出可编辑 prompt（不自动提交）。
- **B8 任务队列**：并发上限、进度、取消、失败重试、结果对比（多张候选选一张落图）。
- **B9 视频生成**（P0，本期）：文本/图片→视频（`/v1/videos`），异步轮询 `/v1/videos/{task_id}`，产物落项目资源库（非图层，独立视频资产）。
- **B10 语音合成 TTS**（P0，本期）：文本→音频（`/v1/audio/speech`），产物可嵌入项目或导出。
- **B11 语音转写 STT**（P0，本期）：音频→文本（`/v1/audio/transcriptions`），产物可写进图层备注或项目元数据。

## 3. 模块 C：自然语言修图（P0，核心交互变革）

这是把 PhotoCompositor 从「图像编辑器」变成「会听人话的编辑器」的最大杠杆点。

- **C1 意图识别**：`/v1/chat/completions` 用结构化工具调用输出「操作意图 JSON」（调 Levels/Curves、加调整层、改图层顺序、建蒙版…）。
- **C2 执行引擎**：把意图 JSON 映射到现有 `CommandPaletteEntry` + 滤镜参数体系，在 `EditorSession` 上执行。
- **C3 确认机制**：高风险操作（删除图层、合并、批量修改）弹出确认对话框；低风险（调色、加蒙版）直接执行。
- **C4 历史回放**：自然语言操作记录进 `DocumentHistory`，可撤销/重做。
- **C5 学习模式**（可选）：记录用户偏好（"我喜欢暖色调"），下次自动应用。

## 4. 模块 D：更多 AI 功能策划（P1/P2）

### P1（高价值，改动可控）

1. **语义选区（文本→蒙版）**：输入"把猫抠出来"、"选天空"，调用 SAM 类能力（若目录有）或本地 Vision + 网关混合，输出蒙版层。
2. **风格迁移（参考图→色调）**：选一张参考图，自动匹配色调/风格到当前层（用 `/v1/images/edits` 或专用风格迁移模型）。
3. **批量 AI 处理**：多图层/多项目批量跑 AI（超分、去噪、调色），任务队列 + 进度面板。
4. **智能裁切/构图**：基于主体检测自动裁切（本地 Vision + 网关辅助），输出裁切建议或自动执行。
5. **OCR + 文字替换**：识别图中文字（本地 Vision），用 AI 生成替换文字并重新渲染（文本层 + 蒙版）。
6. **智能去水印**：检测并去除水印（`/v1/images/edits` + mask），保留背景。
7. **智能去模糊/去抖动**：老照片/手抖修复（`/v1/images/edits`，专用去模糊模型）。
8. **图像描述/OCR**：多模态理解，生成描述（写进 `.comp` 元数据，需 `ProjectManifest` bump 到 v14）。
9. **智能导出**：根据用途（社媒/打印/Web）AI 推荐尺寸和压缩参数（本地规则 + 网关辅助）。
10. **AI 生成背景**：基于 prompt 生成背景替换（`/v1/images/generations` + 蒙版合成）。
11. **智能对齐/排列**：多图层自动排版（本地规则 + 网关辅助，识别主体位置）。
12. **历史学习**：学习用户修图习惯，推荐参数（本地统计 + 网关辅助）。
13. **智能调色**：基于参考图自动匹配色调（`/v1/images/edits`，专用调色模型）。
14. **智能去雾/去霾**：风景照常用（`/v1/images/edits`，专用去雾模型）。
15. **智能去紫边/色差**：镜头校正（本地规则 + 网关辅助）。
16. **智能去压缩伪影**：JPEG 修复（`/v1/images/edits`，专用修复模型）。
17. **智能去马赛克**：模糊区域恢复（`/v1/images/edits`，专用修复模型）。
18. **智能去光晕/眩光**：逆光修复（`/v1/images/edits`，专用修复模型）。
19. **智能去反射/反光**：玻璃/水面修复（`/v1/images/edits`，专用修复模型）。
20. **智能去阴影**：阴影区域提亮（`/v1/images/edits`，专用修复模型）。
21. **智能去高光**：高光区域恢复（`/v1/images/edits`，专用修复模型）。
22. **智能去噪点**：高 ISO 降噪（`/v1/images/edits`，专用降噪模型）。
23. **智能去颗粒**：胶片颗粒去除（`/v1/images/edits`，专用降噪模型）。
24. **智能去尘**：传感器灰尘去除（`/v1/images/edits`，专用修复模型）。
25. **智能去雨**：雨天照片修复（`/v1/images/edits`，专用修复模型）。
26. **智能去雪**：雪天照片修复（`/v1/images/edits`，专用修复模型）。
27. **智能去光斑**：光斑去除（`/v1/images/edits`，专用修复模型）。
28. **智能去反光**：反光去除（`/v1/images/edits`，专用修复模型）。
29. **智能去水印**：水印去除（`/v1/images/edits`，专用修复模型）。
30. **智能去文字**：文字去除（`/v1/images/edits`，专用修复模型）。
31. **智能去背景**：背景去除（已有，可升级）。
32. **智能去物体**：物体去除（已有，可升级）。
33. **智能去人物**：人物去除（`/v1/images/edits`，专用修复模型）。
34. **智能去动物**：动物去除（`/v1/images/edits`，专用修复模型）。
35. **智能去车辆**：车辆去除（`/v1/images/edits`，专用修复模型）。
36. **智能去建筑**：建筑去除（`/v1/images/edits`，专用修复模型）。
37. **智能去风景**：风景去除（`/v1/images/edits`，专用修复模型）。
38. **智能去食物**：食物去除（`/v1/images/edits`，专用修复模型）。
39. **智能去植物**：植物去除（`/v1/images/edits`，专用修复模型）。
40. **Live 图生成** ★：基于静态图生成 3 秒短视频，打包成 Live Photos 格式（JPEG/HEIC + MOV），可导出到相册或嵌入项目。技术路径：`/v1/images/generations` → `/v1/videos` → AVFoundation 帧提取 → Live Photos 打包。产物为独立资产（非图层）。
41. **素材语义搜索**：`/v1/embeddings` 对 `.comp` 内资产与导入历史建本地向量索引，跨项目按语义找图（"暖色调逆光的海岸"）。
42. **决策模型（`/v1/systemone`）用于整理**：自动图层命名、分组、把散乱 PSD 导入结果归成文件夹结构。
43. **成本与用量面板**：catalog 的 `pricing`（`promptPerMillion`、`imagePricing.tiers`、`byResolution`、`awcoinRate`）做提交前预估 + 事后账单（用户说不显示用量，但预估可保留）。
44. **内容安全前置**：上传用户图像前可选 `moderations`。
45. **隐私/离线模式总开关** ★：一键禁止任何本地图像离开设备，所有 AI 菜单项灰化并说明原因。（这条建议 P0 就做，因为它决定其余功能能否对外发布。）

### P2

1. **风格一致性套图**：多参考图 `image[]` 批量出系列图，直接铺成图层文件夹。
2. **智能对齐/排列增强**：多图层自动排版（本地规则 + 网关辅助，识别主体位置）。
3. **历史学习增强**：学习用户修图习惯，推荐参数（本地统计 + 网关辅助）。
4. **智能调色增强**：基于参考图自动匹配色调（`/v1/images/edits`，专用调色模型）。
5. **智能去雾/去霾增强**：风景照常用（`/v1/images/edits`，专用去雾模型）。

## 5. 里程碑

- **M1 网关配置中心**（A1–A9，含 Keychain 与自检）→ 验收：填 AIPDD Key 后 8 个槽位全绿；断网/错 Key 有明确错误；Key 不出现在任何 plist/json 文件里。
- **M2 出图/修图端到端**（B1–B3、B8 基础）→ 验收：文生图落层、选区重绘落层、撤销/重做正常、`.comp` 存得进读得出。
- **M3 目录驱动 + 异步 + 视频/音频**（A7 完整化、B4–B7、B9–B11）→ 验收：新增上游模型无需改代码即可出现在选择器里；视频/音频产物可播放/导出。
- **M4 自然语言修图**（C1–C5）→ 验收：输入"把这张图调暖一点"，自动执行 Curves/Color Balance 调整层；可撤销。
- **M5 增量功能**（D 的 P1：语义选区、风格迁移、批量处理、智能裁切、OCR、去水印、去模糊、图像描述、智能导出、AI 背景、智能对齐、历史学习、智能调色、去雾、去紫边、去压缩伪影、去马赛克、去光晕、去反射、去阴影、去高光、去噪点、去颗粒、去尘、去雨、去雪、去光斑、去反光、去水印、去文字、去背景、去物体、去人物、去动物、去车辆、去建筑、去风景、去食物、去植物、Live 图、素材语义搜索、决策模型整理、成本预估、内容安全、隐私模式）。
