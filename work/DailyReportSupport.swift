//
//  DailyReportSupport.swift
//  work
//
//  Created by Codex on 2026/5/20.
//

import Foundation
import Security

struct DailyReportAIConfiguration: Equatable {
    var baseURL: String
    var model: String

    var isReady: Bool {
        URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil &&
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum DailyReportError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingAPIKey
    case missingWorkItems
    case invalidResponse
    case emptyResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "AI 服务地址不正确"
        case .missingAPIKey:
            "请先保存 AI API Key"
        case .missingWorkItems:
            "当天没有工作记录"
        case .invalidResponse:
            "AI 服务返回了无效响应"
        case .emptyResponse:
            "AI 没有返回日报内容"
        case let .httpStatus(statusCode, message):
            message.isEmpty ? "AI 请求失败：\(statusCode)" : "AI 请求失败：\(statusCode) \(message)"
        }
    }
}

struct DailyReportSourceItem: Equatable {
    var projectName: String
    var title: String
    var type: WorkLogType
    var detail: String
    var hours: Double
    var agileNumber: String
    var ticketNumber: String
}

struct DailyReportInput: Equatable {
    var date: Date
    var items: [DailyReportSourceItem]

    var totalHours: Double {
        items.reduce(0) { $0 + $1.hours }
    }
}

enum DailyReportTemplate {
    static let defaultText = """
    请根据以下工作内容生成一份中文日报，要求格式清晰、表达简洁，保留项目和关键编号。

    日期：{date}（{weekday}）
    总工时：{totalHours} 小时

    工作内容：
    {workItems}
    """

    static func render(_ template: String, input: DailyReportInput, calendar: Calendar = .current) -> String {
        template
            .replacingOccurrences(of: "{date}", with: dateText(for: input.date, calendar: calendar))
            .replacingOccurrences(of: "{weekday}", with: weekdayText(for: input.date, calendar: calendar))
            .replacingOccurrences(of: "{workItems}", with: workItemsText(for: input.items))
            .replacingOccurrences(of: "{totalHours}", with: String(format: "%.1f", input.totalHours))
    }

    static func workItemsText(for items: [DailyReportSourceItem]) -> String {
        let grouped = Dictionary(grouping: items) { $0.projectName }
        let projectNames = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        return projectNames.map { projectName in
            let lines = (grouped[projectName] ?? []).map { item in
                var parts = [
                    "标题：\(item.title)",
                    "类型：\(item.type.rawValue)",
                    "内容：\(item.detail)",
                    "工时：\(String(format: "%.1f", item.hours)) 小时"
                ]

                if item.type == .requirement {
                    if !item.agileNumber.isEmpty {
                        parts.append("敏捷编号：\(item.agileNumber)")
                    }
                    if !item.ticketNumber.isEmpty {
                        parts.append("工单编号：\(item.ticketNumber)")
                    }
                }

                return "- " + parts.joined(separator: "；")
            }

            return "【\(projectName)】\n" + lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private static func dateText(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func weekdayText(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

enum DailyReportCollector {
    static func input(for date: Date, entries: [WorkLogEntry], calendar: Calendar = .current) -> DailyReportInput {
        var items: [DailyReportSourceItem] = []

        for entry in entries {
            for dayItem in entry.sortedDayItems where calendar.isDate(dayItem.workDate, inSameDayAs: date) {
                items.append(
                    DailyReportSourceItem(
                        projectName: entry.projectName,
                        title: entry.title,
                        type: entry.type,
                        detail: dayItem.detail,
                        hours: dayItem.hours,
                        agileNumber: entry.agileNumber,
                        ticketNumber: entry.ticketNumber
                    )
                )
            }
        }

        items.sort {
            if $0.projectName != $1.projectName {
                return $0.projectName.localizedStandardCompare($1.projectName) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        return DailyReportInput(date: date, items: items)
    }
}

struct DailyReportAIClient {
    var configuration: DailyReportAIConfiguration
    var apiKey: String
    var session: URLSession = .shared

    func generateReport(prompt: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DailyReportError.missingAPIKey
        }

        var request = URLRequest(url: try chatCompletionsURL())
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
                messages: [
                    ChatMessage(role: "system", content: "你是一个帮助用户整理工作日报的中文助手。请严格按照用户给出的模板和工作内容生成日报，不要编造不存在的工作。"),
                    ChatMessage(role: "user", content: prompt)
                ],
                temperature: 0.2
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DailyReportError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(ChatCompletionErrorResponse.self, from: data).error.message) ?? ""
            throw DailyReportError.httpStatus(httpResponse.statusCode, message)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            throw DailyReportError.emptyResponse
        }

        return content
    }

    private func chatCompletionsURL() throws -> URL {
        guard var url = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DailyReportError.invalidBaseURL
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            url.appendPathComponent("v1")
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
        } else if path == "v1" || path.hasSuffix("/v1") {
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
        } else if !(path.hasSuffix("chat/completions") || path.hasSuffix("chat/completions/")) {
            url.appendPathComponent("v1")
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
        }

        return url
    }
}

private struct ChatCompletionRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Codable {
    var choices: [Choice]

    struct Choice: Codable {
        var message: ChatMessage
    }
}

private struct ChatCompletionErrorResponse: Codable {
    var error: ErrorDetail

    struct ErrorDetail: Codable {
        var message: String
    }
}

final class DailyReportCredentialStore {
    static let shared = DailyReportCredentialStore()

    private let service = "cn.codeyang.work.daily-report-ai"
    private let account = "api-key"

    func saveAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var createQuery = query
            createQuery[kSecValueData as String] = data
            let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard createStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(createStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return String(data: data, encoding: .utf8)
    }
}
