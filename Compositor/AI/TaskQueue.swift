import Foundation
import Combine

/// Represents an async task from the gateway (video generation, image generation, etc.).
struct GatewayTask: Identifiable, Codable, Equatable {
    let id: String
    var status: Status
    var progress: Double?
    var outputURLs: [URL]
    var error: String?
    var createdAt: Date
    var completedAt: Date?
    
    enum Status: String, Codable {
        case queued
        case inProgress = "in_progress"
        case completed
        case failed
    }
}

/// Response from task creation endpoints.
struct TaskCreationResponse: Codable {
    let id: String?
    let task_id: String?
    let status: String?
    
    var taskID: String {
        id ?? task_id ?? UUID().uuidString
    }
}

/// Response from task polling endpoints.
struct TaskStatusResponse: Codable {
    let id: String?
    let task_id: String?
    let status: String?
    let progress: Double?
    let output: [String]?
    let url: String?
    let error: TaskError?
    
    struct TaskError: Codable {
        let message: String?
        let code: String?
    }
    
    var taskID: String {
        id ?? task_id ?? ""
    }
    
    var outputURLs: [URL] {
        var urls: [URL] = []
        if let output = output {
            urls.append(contentsOf: output.compactMap { URL(string: $0) })
        }
        if let url = url, let parsed = URL(string: url) {
            urls.append(parsed)
        }
        return urls
    }
}

/// Manages async tasks with polling and progress tracking.
@MainActor
final class TaskQueue: ObservableObject {
    static let shared = TaskQueue()
    
    @Published private(set) var tasks: [GatewayTask] = []
    @Published private(set) var isProcessing: Bool = false
    
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private let maxConcurrentTasks = 3
    
    private init() {}
    
    /// Submits a new task and starts polling.
    func submitTask(
        endpoint: EndpointType,
        body: some Encodable,
        onCreate: @escaping (TaskCreationResponse) -> Void
    ) async throws -> String {
        // Check concurrency limit
        let activeCount = tasks.filter { $0.status == .queued || $0.status == .inProgress }.count
        if activeCount >= maxConcurrentTasks {
            throw TaskQueueError.concurrencyLimitReached
        }
        
        // Create the task
        let response: TaskCreationResponse = try await GatewayClient.shared.request(
            endpoint: endpoint,
            body: body,
            as: TaskCreationResponse.self
        )
        
        onCreate(response)
        
        let taskID = response.taskID
        let task = GatewayTask(
            id: taskID,
            status: .queued,
            progress: nil,
            outputURLs: [],
            error: nil,
            createdAt: Date()
        )
        
        tasks.append(task)
        isProcessing = true
        
        // Start polling
        startPolling(for: taskID, endpoint: endpoint)
        
        return taskID
    }
    
    /// Polls a task until completion or failure.
    private func startPolling(for taskID: String, endpoint: EndpointType) {
        let task = Task {
            var delay: UInt64 = 1_000_000_000  // 1 second
            let maxDelay: UInt64 = 30_000_000_000  // 30 seconds
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                
                do {
                    let status: TaskStatusResponse = try await pollTask(taskID: taskID, endpoint: endpoint)
                    
                    await MainActor.run {
                        updateTask(taskID, with: status)
                    }
                    
                    if status.status == "completed" || status.status == "failed" {
                        break
                    }
                    
                    // Exponential backoff
                    delay = min(delay * 2, maxDelay)
                } catch {
                    await MainActor.run {
                        failTask(taskID, error: error.localizedDescription)
                    }
                    break
                }
            }
            
            await MainActor.run {
                pollingTasks.removeValue(forKey: taskID)
                updateProcessingState()
            }
        }
        
        pollingTasks[taskID] = task
    }
    
    /// Polls a task status.
    private func pollTask(taskID: String, endpoint: EndpointType) async throws -> TaskStatusResponse {
        let store = GatewayConfigurationStore.shared
        let config = store.configuration
        
        guard let channel = config.channel(for: endpoint) else {
            throw GatewayClientError.noChannelAvailable
        }
        
        guard let apiKey = try KeychainStore.shared.retrieve(for: channel.id) else {
            throw GatewayClientError.missingAPIKey(channel.name)
        }
        
        // Construct polling URL
        let pollPath: String
        switch endpoint {
        case .video:
            pollPath = "/v1/videos/\(taskID)"
        case .imageGeneration:
            pollPath = "/v1/images/generations/\(taskID)"
        default:
            pollPath = "/v1/tasks/\(taskID)"
        }
        
        let url = channel.baseURL.appendingPathComponent(pollPath)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = channel.timeout
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TaskStatusResponse.self, from: data)
    }
    
    /// Updates a task with new status.
    private func updateTask(_ taskID: String, with status: TaskStatusResponse) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        
        var task = tasks[index]
        
        switch status.status {
        case "queued":
            task.status = .queued
        case "in_progress":
            task.status = .inProgress
            task.progress = status.progress
        case "completed":
            task.status = .completed
            task.progress = 1.0
            task.outputURLs = status.outputURLs
            task.completedAt = Date()
        case "failed":
            task.status = .failed
            task.error = status.error?.message ?? "Unknown error"
            task.completedAt = Date()
        default:
            break
        }
        
        tasks[index] = task
    }
    
    /// Marks a task as failed.
    private func failTask(_ taskID: String, error: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        
        var task = tasks[index]
        task.status = .failed
        task.error = error
        task.completedAt = Date()
        tasks[index] = task
    }
    
    /// Updates the processing state.
    private func updateProcessingState() {
        isProcessing = tasks.contains { $0.status == .queued || $0.status == .inProgress }
    }
    
    /// Cancels a task.
    func cancelTask(_ taskID: String) {
        pollingTasks[taskID]?.cancel()
        pollingTasks.removeValue(forKey: taskID)
        
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            var task = tasks[index]
            task.status = .failed
            task.error = "Cancelled"
            task.completedAt = Date()
            tasks[index] = task
        }
        
        updateProcessingState()
    }
    
    /// Removes a completed/failed task from the list.
    func removeTask(_ taskID: String) {
        tasks.removeAll { $0.id == taskID }
    }
    
    /// Clears all completed/failed tasks.
    func clearCompleted() {
        tasks.removeAll { $0.status == .completed || $0.status == .failed }
    }
}

enum TaskQueueError: Error, LocalizedError {
    case concurrencyLimitReached
    
    var errorDescription: String? {
        switch self {
        case .concurrencyLimitReached:
            return "Too many tasks in progress. Please wait for some to complete."
        }
    }
}
