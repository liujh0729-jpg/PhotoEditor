import Foundation

/// Request body for /v1/images/generations.
struct ImageGenerationRequest: Codable {
    let model: String
    let prompt: String
    var negative_prompt: String?
    var n: Int?
    var size: String?
    var quality: String?
    var response_format: String?
    var style: String?
    var background: String?
    var moderation: String?
    var output_format: String?
    var output_compression: Int?
    var watermark: String?
    var watermark_enabled: Bool?
}

/// Request body for /v1/images/edits (JSON mode).
struct ImageEditRequest: Codable {
    let model: String
    let prompt: String
    var image: String?  // base64
    var images: [String]?  // base64 array
    var mask: String?  // base64
    var n: Int?
    var size: String?
    var response_format: String?
}

/// Response from image generation/edit endpoints.
struct ImageResponse: Codable {
    let data: [ImageData]
    let created: Int?
    
    struct ImageData: Codable {
        let url: String?
        let b64_json: String?
        let revised_prompt: String?
    }
}

/// Request body for /v1/videos.
struct VideoGenerationRequest: Codable {
    let model: String
    let prompt: String
    var image: String?  // base64 for image-to-video
    var duration: Int?
    var width: Int?
    var height: Int?
    var fps: Int?
    var seed: Int?
    var n: Int?
    var resolution: String?
    var ratio: String?
    var generate_audio: Bool?
    var watermark: String?
    var output_format: String?
    var callback_url: String?
}

/// Request body for /v1/audio/speech.
struct SpeechRequest: Codable {
    let model: String
    let input: String
    let voice: String
    var response_format: String?
    var speed: Double?
}

/// Request body for /v1/audio/transcriptions (multipart).
struct TranscriptionRequest {
    let model: String
    var language: String?
    var prompt: String?
    var response_format: String?
    var temperature: Double?
}

/// Response from transcription endpoint.
struct TranscriptionResponse: Codable {
    let text: String
    let task: String?
    let language: String?
    let duration: Double?
    let segments: [TranscriptionSegment]?
    
    struct TranscriptionSegment: Codable {
        let id: Int?
        let seek: Int?
        let start: Double?
        let end: Double?
        let text: String?
        let tokens: [Int]?
    }
}

/// Request body for /v1/chat/completions.
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    var stream: Bool?
    var max_tokens: Int?
    var temperature: Double?
    var top_p: Double?
    var n: Int?
    var tools: [Tool]?
    var tool_choice: ToolChoice?
    
    struct ChatMessage: Codable {
        let role: String
        let content: Content
        
        /// Plain text, or OpenAI-compatible parts — text next to images — as a vision request carries.
        enum Content: Codable {
            case text(String)
            case parts([Part])
            
            enum Part: Codable {
                case text(String)
                case imageURL(String)
                
                private enum CodingKeys: String, CodingKey {
                    case type, text, imageURL = "image_url"
                }
                
                private struct ImageURL: Codable { let url: String }
                
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    switch try container.decode(String.self, forKey: .type) {
                    case "image_url":
                        self = .imageURL(try container.decode(ImageURL.self, forKey: .imageURL).url)
                    default:
                        self = .text(try container.decode(String.self, forKey: .text))
                    }
                }
                
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                    case .text(let text):
                        try container.encode("text", forKey: .type)
                        try container.encode(text, forKey: .text)
                    case .imageURL(let url):
                        try container.encode("image_url", forKey: .type)
                        try container.encode(ImageURL(url: url), forKey: .imageURL)
                    }
                }
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .text(text)
                } else {
                    self = .parts(try container.decode([Part].self))
                }
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text): try container.encode(text)
                case .parts(let parts): try container.encode(parts)
                }
            }
        }
        
        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
        }
        
        init(role: String, parts: [Content.Part]) {
            self.role = role
            self.content = .parts(parts)
        }
    }
    
    struct Tool: Codable {
        let type: String
        let function: Function
        
        struct Function: Codable {
            let name: String
            let description: String
            let parameters: [String: AnyCodable]
        }
    }
    
    enum ToolChoice: Codable {
        case auto
        case none
        case function(String)
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .auto:
                try container.encode("auto")
            case .none:
                try container.encode("none")
            case .function(let name):
                try container.encode(AnyCodable(["type": "function", "function": ["name": name]]))
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                switch string {
                case "auto": self = .auto
                case "none": self = .none
                default: self = .auto
                }
            } else {
                self = .auto
            }
        }
    }
}

/// Response from chat completion endpoint.
struct ChatCompletionResponse: Codable {
    let id: String?
    let choices: [Choice]
    let usage: Usage?
    
    struct Choice: Codable {
        let index: Int
        let message: Message
        let finish_reason: String?
        
        struct Message: Codable {
            let role: String
            let content: String?
            let tool_calls: [ToolCall]?
        }
        
        struct ToolCall: Codable {
            let id: String?
            let type: String?
            let function: FunctionCall
        }
        
        struct FunctionCall: Codable {
            let name: String
            let arguments: String
        }
    }
    
    struct Usage: Codable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}

/// Request body for /v1/embeddings.
struct EmbeddingRequest: Codable {
    let model: String
    let input: [String]
    var encoding_format: String?
    var dimensions: Int?
}

/// Response from embeddings endpoint.
struct EmbeddingResponse: Codable {
    let data: [EmbeddingData]
    let model: String?
    let usage: Usage?
    
    struct EmbeddingData: Codable {
        let object: String?
        let index: Int
        let embedding: [Float]
    }
    
    struct Usage: Codable {
        let prompt_tokens: Int?
        let total_tokens: Int?
    }
}

/// Request body for /v1/systemone.
struct SystemOneRequest: Codable {
    let model: String
    let state: [String: AnyCodable]
    let questions: [String]
}

/// Response from systemone endpoint.
struct SystemOneResponse: Codable {
    let answers: [String: AnyCodable]?
    let reasoning: String?
}

/// Type-erased Codable wrapper for arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
