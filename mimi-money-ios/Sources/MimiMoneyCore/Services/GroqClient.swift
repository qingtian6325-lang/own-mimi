import Foundation

// MARK: - Groq Settings（Key 只进 Keychain）

public enum GroqSettings {
    /// 官方视觉模型：支持图片输入 + JSON mode（console.groq.com/docs/vision）
    public static let defaultModelName = "qwen/qwen3.8-27b"

    private static let keychainService = "com.jinghao.mimimoney.groq"
    private static let keychainAccount = "groq_api_key"
    private static let modelUserDefaultsKey = "mimi_groq_model_name"
    private static let statusUserDefaultsKey = "mimi_groq_last_call_status"
    private static let statusDateUserDefaultsKey = "mimi_groq_last_call_status_date"

    public static var modelName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: modelUserDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (saved?.isEmpty == false) ? saved! : defaultModelName
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? defaultModelName : trimmed, forKey: modelUserDefaultsKey)
        }
    }

    public static var apiKey: String? {
        MimiKeychain.read(service: keychainService, account: keychainAccount)
    }

    public static var hasAPIKey: Bool { apiKey != nil }

    public static func saveAPIKey(_ key: String?) {
        MimiKeychain.save(service: keychainService, account: keychainAccount, value: key)
    }

    public static func recordCallStatus(success: Bool, message: String) {
        let prefix = success ? "成功" : "失败"
        UserDefaults.standard.set("\(prefix)：\(message)", forKey: statusUserDefaultsKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: statusDateUserDefaultsKey)
    }

    public static var lastCallStatusText: String? {
        guard let text = UserDefaults.standard.string(forKey: statusUserDefaultsKey) else { return nil }
        let ts = UserDefaults.standard.double(forKey: statusDateUserDefaultsKey)
        guard ts > 0 else { return text }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return "\(text)（\(formatter.string(from: Date(timeIntervalSince1970: ts)))）"
    }
}

// MARK: - Groq REST Client（OpenAI 兼容 + 图片 data URL）

public enum GroqClient {
    public static let recognitionTimeoutSeconds: TimeInterval = 30
    public static let chatTimeoutSeconds: TimeInterval = 60
    public static let testConnectionProbeTimeoutSeconds: TimeInterval = 30

    private static let chatCompletionsURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    /// 单测可替换。
    static var singleRequestExecutor: @Sendable ([String: Any], TimeInterval) async throws -> [String: Any] = { body, timeout in
        try await performNetworkRequest(body: body, timeout: timeout)
    }

    static var retryBackoffSeconds: @Sendable () -> TimeInterval = {
        1.0 + Double.random(in: 0...0.5)
    }

    static func isRetryable(_ error: GeminiError) -> Bool {
        switch error {
        case .httpStatus(let code, _):
            return code == 429 || (500...599).contains(code)
        case .transport:
            return true
        case .missingAPIKey, .emptyResponse, .decodingFailed:
            return false
        }
    }

    static func performRequest(body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        do {
            return try await singleRequestExecutor(body, timeout)
        } catch let error as GeminiError {
            guard isRetryable(error) else { throw error }
            let backoff = retryBackoffSeconds()
            if backoff > 0 {
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
            return try await singleRequestExecutor(body, timeout)
        }
    }

    private static func performNetworkRequest(body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard let apiKey = GroqSettings.apiKey else {
            throw GeminiError.missingAPIKey
        }
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GeminiError.httpStatus(http.statusCode, extractErrorMessage(from: data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decodingFailed("响应不是 JSON")
        }
        return json
    }

    private static func extractErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "无详细信息"
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return String(message.prefix(160))
        }
        if let message = json["message"] as? String {
            return String(message.prefix(160))
        }
        return "无详细信息"
    }

    private static func extractText(from responseJSON: [String: Any]) throws -> String {
        guard let choices = responseJSON["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.emptyResponse
        }
        return content
    }

    /// 从模型输出里抽出 JSON 对象（兼容 ```json 围栏）。
    public static func extractJSONObjectText(from raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") , start < end {
            return String(trimmed[start...end])
        }
        throw GeminiError.decodingFailed("未找到 JSON 对象")
    }

    // MARK: 测试连接

    public static func testConnectionProbeBody(model: String) -> [String: Any] {
        [
            "model": model,
            "temperature": 0,
            "max_completion_tokens": 64,
            "reasoning_effort": "none",
            "messages": [
                ["role": "user", "content": "请只回复：OK"]
            ]
        ]
    }

    public static func testConnection() async -> (success: Bool, message: String) {
        guard GroqSettings.hasAPIKey else {
            return (false, "尚未填写 Groq API Key")
        }
        let model = GroqSettings.modelName
        do {
            let json = try await performRequest(
                body: testConnectionProbeBody(model: model),
                timeout: testConnectionProbeTimeoutSeconds
            )
            _ = try extractText(from: json)
            GroqSettings.recordCallStatus(success: true, message: "测试连接成功（\(model)，已实际生成验证）")
            return (true, "连接成功，模型 \(model) 可用（已实际生成验证，支持图片输入）")
        } catch let error as GeminiError {
            GroqSettings.recordCallStatus(success: false, message: "测试连接失败：\(error.description)")
            return (false, error.description)
        } catch {
            GroqSettings.recordCallStatus(success: false, message: "测试连接失败：\(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    // MARK: 截图识别（图片 data URL + JSON mode）

    public static func recognizeBill(imageData: Data, now: Date = Date()) async throws -> ParsedDraftBill {
        let model = GroqSettings.modelName
        let uploadData = GeminiImagePreprocessor.prepareForUpload(imageData)
        let mimeType = uploadData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
        let dataURL = "data:\(mimeType);base64,\(uploadData.base64EncodedString())"
        let system = GeminiClient.recognitionSystemPrompt(now: now)
        let schemaHint = """
请严格输出一个 JSON 对象，字段如下（不要其它文字、不要 markdown 围栏以外的任何说明）：
type(expense|income|transfer), amount(number), counterparty(string), counterpartyKind(merchant|person),
account(string), targetAccount(string|null), primaryCategory(string), subCategory(string|null),
occurredAt("yyyy-MM-dd HH:mm"), note(string)。
primaryCategory 与 subCategory 必须严格配对使用上方分类表中列出的名称，不能混搭；无二级分类或无转账对方账户时对应字段填 null；occurredAt 绝不能抄手机状态栏时间或编造日期。
"""

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_completion_tokens": 1024,
            "reasoning_effort": "none",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system + "\n\n" + schemaHint],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "请仔细阅读整张付款/收款/转账截图正文并核对最终实付 RM 金额与交易时间，严格按系统规则输出 JSON。"],
                        ["type": "image_url", "image_url": ["url": dataURL]]
                    ] as [[String: Any]]
                ]
            ]
        ]

        let json = try await performRequest(body: body, timeout: recognitionTimeoutSeconds)
        let text = try extractJSONObjectText(from: try extractText(from: json))
        guard let data = text.data(using: .utf8) else {
            throw GeminiError.decodingFailed("文本编码失败")
        }
        do {
            let dto = try JSONDecoder().decode(GeminiBillDTO.self, from: data)
            return dto.toDraftBill(now: now)
        } catch {
            throw GeminiError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: 问账

    @MainActor
    public static func answerQuestion(_ question: String, store: MimiStore, now: Date = Date()) async throws -> String {
        let model = GroqSettings.modelName
        let context = LedgerContextBuilder.buildContext(store: store, question: question, now: now)
        let system = LedgerContextBuilder.questionSystemPrompt()
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_completion_tokens": 2048,
            "reasoning_effort": "none",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "【账目数据】\n\(context)\n\n【我的问题】\n\(question)"]
            ]
        ]
        let json = try await performRequest(body: body, timeout: chatTimeoutSeconds)
        return try extractText(from: json).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
