//
//  WebDAVSupport.swift
//  work
//
//  Created by Codex on 2026/5/20.
//

import Foundation
import Security
import SwiftData

enum WebDAVAuthMode: String, CaseIterable, Identifiable {
    case basic = "Basic"
    case bearer = "Bearer Token"

    var id: String { rawValue }
}

struct WebDAVConfiguration: Equatable {
    var serverURL: String
    var remotePath: String
    var username: String
    var authMode: WebDAVAuthMode

    var isReady: Bool {
        URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }
}

enum WebDAVError: LocalizedError, Equatable {
    case invalidServerURL
    case missingSecret
    case invalidResponse
    case httpStatus(Int, String)
    case missingBackup

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "WebDAV 服务地址不正确"
        case .missingSecret:
            "请先保存 WebDAV 密码或 Token"
        case .invalidResponse:
            "WebDAV 服务返回了无效响应"
        case let .httpStatus(statusCode, path):
            "WebDAV 请求失败：\(statusCode) \(path)"
        case .missingBackup:
            "WebDAV 上没有找到可恢复的备份数据"
        }
    }
}

struct WorkLogBackupManifest: Codable, Equatable {
    let version: Int
    let generatedAt: Date
    let projectCount: Int
    let entryCount: Int
    let attachmentCount: Int
    let dataPath: String
}

struct WorkLogBackupDocument: Codable, Equatable {
    var projects: [ProjectBackupDTO]
    var entries: [EntryBackupDTO]
}

struct ProjectBackupDTO: Codable, Equatable {
    var id: String
    var name: String
    var createdAt: Date
}

struct EntryBackupDTO: Codable, Equatable {
    var id: String
    var projectID: String
    var typeRawValue: String
    var title: String
    var agileNumber: String
    var ticketNumber: String
    var createdAt: Date
    var updatedAt: Date
    var dayItems: [DayItemBackupDTO]
}

struct DayItemBackupDTO: Codable, Equatable {
    var id: String
    var workDate: Date
    var detail: String
    var hours: Double
    var createdAt: Date
    var updatedAt: Date
    var attachments: [AttachmentBackupDTO]
}

struct AttachmentBackupDTO: Codable, Equatable {
    var id: String
    var fileName: String
    var contentType: String
    var createdAt: Date
    var path: String
}

struct WorkLogBackupPackage: Equatable {
    var manifest: WorkLogBackupManifest
    var document: WorkLogBackupDocument
    var attachments: [String: Data]
}

enum WorkLogBackupCodec {
    static let manifestPath = "manifest.json"
    static let dataPath = "data/worklog.json"
    static let friendlyDateFormat = "yyyy-MM-dd HH:mm:ss"

    private static let friendlyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = friendlyDateFormat
        return formatter
    }()

    private static let legacyISO8601Formatter = ISO8601DateFormatter()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(friendlyDateFormatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = friendlyDateFormatter.date(from: value) {
                return date
            }

            if let date = legacyISO8601Formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "日期格式不正确，应为 \(friendlyDateFormat)"
            )
        }
        return decoder
    }()

    static func export(projects: [Project], entries: [WorkLogEntry], generatedAt: Date = .now) -> WorkLogBackupPackage {
        let sortedProjects = projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let projectIDs = Dictionary(uniqueKeysWithValues: sortedProjects.map { project in
            (ObjectIdentifier(project), stableID(prefix: "project", parts: [project.name, project.createdAt.ISO8601Format()]))
        })

        var attachments: [String: Data] = [:]
        let projectDTOs = sortedProjects.map {
            ProjectBackupDTO(id: projectIDs[ObjectIdentifier($0)]!, name: $0.name, createdAt: $0.createdAt)
        }

        let entryDTOs = entries.sorted { $0.createdAt < $1.createdAt }.map { entry in
            let projectID = entry.project.map { projectIDs[ObjectIdentifier($0)] } ?? nil
            let entryID = stableID(prefix: "entry", parts: [projectID ?? "missing-project", entry.title, entry.createdAt.ISO8601Format()])

            let dayDTOs = entry.sortedDayItems.enumerated().map { dayIndex, dayItem in
                let dayID = stableID(prefix: "day", parts: [entryID, "\(dayIndex)", dayItem.workDate.ISO8601Format()])

                let attachmentDTOs = dayItem.attachments.sorted { $0.createdAt < $1.createdAt }.enumerated().map { attachmentIndex, attachment in
                    let attachmentID = stableID(prefix: "attachment", parts: [dayID, "\(attachmentIndex)", attachment.fileName, attachment.createdAt.ISO8601Format()])
                    let path = attachmentPath(dayDate: dayItem.workDate, id: attachmentID, fileName: attachment.fileName)
                    attachments[path] = attachment.data

                    return AttachmentBackupDTO(
                        id: attachmentID,
                        fileName: attachment.fileName,
                        contentType: attachment.contentType,
                        createdAt: attachment.createdAt,
                        path: path
                    )
                }

                return DayItemBackupDTO(
                    id: dayID,
                    workDate: dayItem.workDate,
                    detail: dayItem.detail,
                    hours: dayItem.hours,
                    createdAt: dayItem.createdAt,
                    updatedAt: dayItem.updatedAt,
                    attachments: attachmentDTOs
                )
            }

            return EntryBackupDTO(
                id: entryID,
                projectID: projectID ?? "",
                typeRawValue: entry.typeRawValue,
                title: entry.title,
                agileNumber: entry.agileNumber,
                ticketNumber: entry.ticketNumber,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                dayItems: dayDTOs
            )
        }

        let manifest = WorkLogBackupManifest(
            version: 1,
            generatedAt: generatedAt,
            projectCount: projectDTOs.count,
            entryCount: entryDTOs.count,
            attachmentCount: attachments.count,
            dataPath: dataPath
        )

        return WorkLogBackupPackage(
            manifest: manifest,
            document: WorkLogBackupDocument(projects: projectDTOs, entries: entryDTOs),
            attachments: attachments
        )
    }

    static func restore(_ package: WorkLogBackupPackage, into modelContext: ModelContext) {
        try? modelContext.delete(model: WorkLogAttachment.self)
        try? modelContext.delete(model: WorkLogDayItem.self)
        try? modelContext.delete(model: WorkLogEntry.self)
        try? modelContext.delete(model: Project.self)

        var projectsByID: [String: Project] = [:]
        for projectDTO in package.document.projects {
            let project = Project(name: projectDTO.name, createdAt: projectDTO.createdAt)
            modelContext.insert(project)
            projectsByID[projectDTO.id] = project
        }

        for entryDTO in package.document.entries {
            guard let project = projectsByID[entryDTO.projectID],
                  let firstDay = entryDTO.dayItems.sorted(by: { $0.workDate < $1.workDate }).first else {
                continue
            }

            let entry = WorkLogEntry(
                project: project,
                type: WorkLogType(rawValue: entryDTO.typeRawValue) ?? .regular,
                title: entryDTO.title,
                detail: firstDay.detail,
                workDate: firstDay.workDate,
                hours: firstDay.hours,
                agileNumber: entryDTO.agileNumber,
                ticketNumber: entryDTO.ticketNumber,
                createdAt: entryDTO.createdAt,
                updatedAt: entryDTO.updatedAt
            )
            modelContext.insert(entry)

            for dayDTO in entryDTO.dayItems.sorted(by: { $0.workDate < $1.workDate }) {
                let dayItem = WorkLogDayItem(
                    entry: entry,
                    workDate: dayDTO.workDate,
                    detail: dayDTO.detail,
                    hours: dayDTO.hours,
                    createdAt: dayDTO.createdAt,
                    updatedAt: dayDTO.updatedAt
                )
                modelContext.insert(dayItem)
                entry.dayItems.append(dayItem)

                for attachmentDTO in dayDTO.attachments.sorted(by: { $0.createdAt < $1.createdAt }) {
                    let attachmentData = package.attachments[attachmentDTO.path] ?? Data()
                    let attachment = WorkLogAttachment(
                        dayItem: dayItem,
                        fileName: attachmentDTO.fileName,
                        contentType: attachmentDTO.contentType,
                        data: attachmentData,
                        createdAt: attachmentDTO.createdAt
                    )
                    modelContext.insert(attachment)
                    dayItem.attachments.append(attachment)
                }
            }
        }
    }

    static func encodedManifest(_ manifest: WorkLogBackupManifest) throws -> Data {
        try encoder.encode(manifest)
    }

    static func encodedDocument(_ document: WorkLogBackupDocument) throws -> Data {
        try encoder.encode(document)
    }

    static func decodedManifest(from data: Data) throws -> WorkLogBackupManifest {
        try decoder.decode(WorkLogBackupManifest.self, from: data)
    }

    static func decodedDocument(from data: Data) throws -> WorkLogBackupDocument {
        try decoder.decode(WorkLogBackupDocument.self, from: data)
    }

    static func attachmentPath(dayDate: Date, id: String, fileName: String, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: dayDate)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "attachments/\(year)/\(String(format: "%02d", month))/\(String(format: "%02d", day))/\(id)-\(sanitizedFileName(fileName))"
    }

    static func sanitizedFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "attachment" : trimmed
        let blocked = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return fallback.components(separatedBy: blocked).joined(separator: "_")
    }

    private static func stableID(prefix: String, parts: [String]) -> String {
        let raw = parts.joined(separator: "-")
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let compact = String(scalars).split(separator: "-").joined(separator: "-").lowercased()
        return "\(prefix)-\(compact.prefix(80))"
    }
}

final class WebDAVCredentialStore {
    static let shared = WebDAVCredentialStore()

    private let service = "cn.codeyang.work.webdav"
    private let account = "webdav-secret"

    func saveSecret(_ secret: String) throws {
        let data = Data(secret.utf8)
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

    func loadSecret() throws -> String? {
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

struct WebDAVClient {
    var configuration: WebDAVConfiguration
    var secret: String
    var session: URLSession = .shared

    func testConnection() async throws {
        _ = try await request(method: "PROPFIND", path: "", body: nil, headers: ["Depth": "0"])
    }

    func createDirectory(_ path: String) async throws {
        do {
            _ = try await request(method: "MKCOL", path: path, body: nil)
        } catch WebDAVError.httpStatus(let code, _) where code == 405 || code == 409 {
            return
        }
    }

    func upload(_ data: Data, path: String, contentType: String = "application/octet-stream") async throws {
        _ = try await request(method: "PUT", path: path, body: data, headers: ["Content-Type": contentType])
    }

    func download(_ path: String) async throws -> Data {
        try await request(method: "GET", path: path, body: nil)
    }

    func request(method: String, path: String, body: Data?, headers: [String: String] = [:]) async throws -> Data {
        guard var url = baseURL() else {
            throw WebDAVError.invalidServerURL
        }

        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        applyAuthorization(to: &request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 else {
            throw WebDAVError.httpStatus(httpResponse.statusCode, path)
        }

        return data
    }

    private func baseURL() -> URL? {
        guard var url = URL(string: configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        for component in configuration.remotePath.split(separator: "/") {
            url.appendPathComponent(String(component))
        }

        return url
    }

    private func applyAuthorization(to request: inout URLRequest) {
        switch configuration.authMode {
        case .basic:
            let raw = "\(configuration.username):\(secret)"
            request.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        case .bearer:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
    }
}

struct WebDAVBackupService {
    var client: WebDAVClient

    func upload(_ package: WorkLogBackupPackage) async throws {
        try await ensureDirectories(for: package)
        try await client.upload(try WorkLogBackupCodec.encodedDocument(package.document), path: WorkLogBackupCodec.dataPath, contentType: "application/json")

        for (path, data) in package.attachments.sorted(by: { $0.key < $1.key }) {
            try await client.upload(data, path: path)
        }

        try await client.upload(try WorkLogBackupCodec.encodedManifest(package.manifest), path: WorkLogBackupCodec.manifestPath, contentType: "application/json")
    }

    func download() async throws -> WorkLogBackupPackage {
        let manifestData = try await client.download(WorkLogBackupCodec.manifestPath)
        let manifest = try WorkLogBackupCodec.decodedManifest(from: manifestData)
        let documentData = try await client.download(manifest.dataPath)
        let document = try WorkLogBackupCodec.decodedDocument(from: documentData)

        var attachments: [String: Data] = [:]
        for entry in document.entries {
            for dayItem in entry.dayItems {
                for attachment in dayItem.attachments {
                    attachments[attachment.path] = try await client.download(attachment.path)
                }
            }
        }

        return WorkLogBackupPackage(manifest: manifest, document: document, attachments: attachments)
    }

    private func ensureDirectories(for package: WorkLogBackupPackage) async throws {
        var directories = Set(["data"])
        for path in package.attachments.keys {
            let parts = path.split(separator: "/").dropLast()
            var current = ""
            for part in parts {
                current = current.isEmpty ? String(part) : "\(current)/\(part)"
                directories.insert(current)
            }
        }

        for directory in directories.sorted(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }) {
            try await client.createDirectory(directory)
        }
    }
}
