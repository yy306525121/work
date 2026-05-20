//
//  workTests.swift
//  workTests
//
//  Created by 杨忠洋 on 2026/5/19.
//

import Foundation
import SwiftData
import Testing
@testable import work

struct WorkValidationTests {
    @Test func regularWorkRequiresCommonFieldsAndDayItems() throws {
        let day = WorkLogDayItemDraft(
            workDate: .now,
            detail: "处理登录接口参数",
            hours: 1.5
        )

        let errors = WorkLogValidation.entryErrors(
            projectName: "司乘项目",
            type: .regular,
            title: "接口联调",
            agileNumber: "",
            dayItems: [day]
        )

        #expect(errors.isEmpty)
    }

    @Test func requirementWorkRequiresAgileNumberButNotTicketNumber() {
        let day = WorkLogDayItemDraft(
            workDate: .now,
            detail: "实现工作记录筛选",
            hours: 2
        )

        let missingAgileErrors = WorkLogValidation.entryErrors(
            projectName: "司乘项目",
            type: .requirement,
            title: "新增筛选",
            agileNumber: "",
            dayItems: [day]
        )

        #expect(missingAgileErrors.contains("需求类工作必须填写敏捷编号"))

        let validErrors = WorkLogValidation.entryErrors(
            projectName: "司乘项目",
            type: .requirement,
            title: "新增筛选",
            agileNumber: "AGILE-1001",
            dayItems: [day]
        )

        #expect(validErrors.isEmpty)
    }

    @Test func dayItemsRequireContentHoursAndUniqueDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let may19 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))

        let errors = WorkLogValidation.dayItemErrors([
            WorkLogDayItemDraft(workDate: may19, detail: "", hours: 0),
            WorkLogDayItemDraft(workDate: may19, detail: "重复日期", hours: 1)
        ], calendar: calendar)

        #expect(errors.contains("第 1 天工作内容不能为空"))
        #expect(errors.contains("第 1 天工作时间必须大于 0 小时"))
        #expect(errors.contains("同一条工作记录内不能重复填写同一天"))
    }

    @Test func projectNameIsRequiredAndUniqueIgnoringCase() {
        #expect(WorkLogValidation.projectNameError("   ", existingNames: []) == "项目名不能为空")
        #expect(WorkLogValidation.projectNameError("sojourn", existingNames: ["Sojourn"]) == "项目名已存在")
        #expect(WorkLogValidation.projectNameError("giraffe", existingNames: ["Sojourn"]) == nil)
    }
}

struct WorkLogFilterTests {
    @Test func filterMatchesAnyDayItemDateProjectAndType() throws {
        let calendar = Calendar(identifier: .gregorian)
        let may18 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18)))
        let may19 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))
        let may20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))

        let project = Project(name: "司乘项目")
        let entry = WorkLogEntry(
            project: project,
            type: .requirement,
            title: "跨天需求",
            detail: "第一天",
            workDate: may18,
            hours: 1,
            agileNumber: "AGILE-1001"
        )
        entry.dayItems = [
            WorkLogDayItem(entry: entry, workDate: may18, detail: "第一天", hours: 1),
            WorkLogDayItem(entry: entry, workDate: may20, detail: "第三天", hours: 2)
        ]

        let filter = WorkLogFilter(
            startDate: may20,
            endDate: may20,
            projectName: "司乘项目",
            type: .requirement
        )

        #expect(filter.matches(entry: entry, calendar: calendar))
        #expect(!WorkLogFilter(startDate: may19, endDate: may19, projectName: "司乘项目", type: .requirement).matches(entry: entry, calendar: calendar))
        #expect(!WorkLogFilter(startDate: may20, endDate: may20, projectName: "其他项目", type: .requirement).matches(entry: entry, calendar: calendar))
        #expect(!WorkLogFilter(startDate: may20, endDate: may20, projectName: "司乘项目", type: .regular).matches(entry: entry, calendar: calendar))
    }
}

struct WorkLogSummaryTests {
    @Test func entryComputesDateRangeHoursAndAttachmentCount() throws {
        let calendar = Calendar(identifier: .gregorian)
        let may19 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))
        let may20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))

        let project = Project(name: "司乘项目")
        let entry = WorkLogEntry(
            project: project,
            type: .requirement,
            title: "跨天需求",
            detail: "第一天",
            workDate: may19,
            hours: 1,
            agileNumber: "AGILE-1001"
        )
        let firstDay = WorkLogDayItem(entry: entry, workDate: may19, detail: "第一天", hours: 1.5)
        let secondDay = WorkLogDayItem(entry: entry, workDate: may20, detail: "第二天", hours: 2)
        firstDay.attachments = [
            WorkLogAttachment(dayItem: firstDay, fileName: "第一天.pdf", contentType: "application/pdf", data: Data([1]))
        ]
        secondDay.attachments = [
            WorkLogAttachment(dayItem: secondDay, fileName: "第二天.docx", contentType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", data: Data([2]))
        ]
        entry.dayItems = [secondDay, firstDay]

        #expect(entry.totalHours == 3.5)
        #expect(entry.startDate == may19)
        #expect(entry.endDate == may20)
        #expect(entry.totalAttachmentCount == 2)
    }
}

struct WorkLogAttachmentTests {
    @Test func attachmentStoresDailyArtifactMetadataAndContent() {
        let dayItem = WorkLogDayItem(workDate: .now, detail: "当天内容", hours: 1)
        let attachment = WorkLogAttachment(
            dayItem: dayItem,
            fileName: "交付文档.pdf",
            contentType: "application/pdf",
            data: Data([0x25, 0x50, 0x44, 0x46])
        )

        #expect(attachment.dayItem === dayItem)
        #expect(attachment.fileName == "交付文档.pdf")
        #expect(attachment.contentType == "application/pdf")
        #expect(attachment.data == Data([0x25, 0x50, 0x44, 0x46]))
    }
}

struct WorkLogDateFormatterTests {
    @Test func dayDetailTextUsesChineseWeekdayFormat() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))

        #expect(WorkLogDateFormatter.dayDetailText(for: date) == "2026-05-20(星期三)")
    }
}

struct DailyReportTests {
    @Test func templateReplacesDateHoursWeekdayAndGroupedWorkItems() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let may20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let input = DailyReportInput(
            date: may20,
            items: [
                DailyReportSourceItem(
                    projectName: "司乘项目",
                    title: "接口联调",
                    type: .requirement,
                    detail: "处理登录接口参数",
                    hours: 1.5,
                    agileNumber: "AGILE-1001",
                    ticketNumber: "T-1001"
                )
            ]
        )

        let rendered = DailyReportTemplate.render(
            "日期：{date} {weekday}\n总计：{totalHours}\n{workItems}",
            input: input,
            calendar: calendar
        )

        #expect(rendered.contains("日期：2026-05-20 星期三"))
        #expect(rendered.contains("总计：1.5"))
        #expect(rendered.contains("【司乘项目】"))
        #expect(rendered.contains("敏捷编号：AGILE-1001"))
        #expect(rendered.contains("工单编号：T-1001"))
    }

    @Test func collectorOnlyUsesSelectedDayAndGroupsSourceFields() throws {
        let calendar = Calendar(identifier: .gregorian)
        let may19 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 19)))
        let may20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let project = Project(name: "司乘项目")
        let entry = WorkLogEntry(
            project: project,
            type: .requirement,
            title: "跨天需求",
            detail: "第一天",
            workDate: may19,
            hours: 1,
            agileNumber: "AGILE-1",
            ticketNumber: "T-1"
        )
        entry.dayItems = [
            WorkLogDayItem(entry: entry, workDate: may19, detail: "第一天", hours: 1),
            WorkLogDayItem(entry: entry, workDate: may20, detail: "第二天", hours: 2)
        ]

        let input = DailyReportCollector.input(for: may20, entries: [entry], calendar: calendar)

        #expect(input.items.count == 1)
        #expect(input.items.first?.projectName == "司乘项目")
        #expect(input.items.first?.detail == "第二天")
        #expect(input.items.first?.hours == 2)
        #expect(input.items.first?.agileNumber == "AGILE-1")
        #expect(input.totalHours == 2)
    }

    @Test func emptyCollectorInputHasMissingWorkItemsError() throws {
        let input = DailyReportCollector.input(for: .now, entries: [])

        #expect(input.items.isEmpty)
        #expect(DailyReportError.missingWorkItems.localizedDescription == "当天没有工作记录")
    }
}

struct WorkLogBackupCodecTests {
    @Test func exportCreatesJSONDocumentAndAttachmentFiles() throws {
        let calendar = Calendar(identifier: .gregorian)
        let may20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let project = Project(name: "司乘项目")
        let entry = WorkLogEntry(
            project: project,
            type: .requirement,
            title: "需求交付",
            detail: "整理材料",
            workDate: may20,
            hours: 2,
            agileNumber: "AGILE-1",
            ticketNumber: "T-1"
        )
        let dayItem = WorkLogDayItem(entry: entry, workDate: may20, detail: "整理材料", hours: 2)
        let attachment = WorkLogAttachment(
            dayItem: dayItem,
            fileName: "交付/文档?.pdf",
            contentType: "application/pdf",
            data: Data([1, 2, 3])
        )
        dayItem.attachments = [attachment]
        entry.dayItems = [dayItem]

        let package = WorkLogBackupCodec.export(projects: [project], entries: [entry], generatedAt: may20)

        #expect(package.manifest.version == 1)
        #expect(package.manifest.projectCount == 1)
        #expect(package.manifest.entryCount == 1)
        #expect(package.manifest.attachmentCount == 1)
        #expect(package.document.projects.first?.name == "司乘项目")
        #expect(package.document.entries.first?.dayItems.first?.attachments.first?.fileName == "交付/文档?.pdf")

        let manifestJSON = String(data: try WorkLogBackupCodec.encodedManifest(package.manifest), encoding: .utf8)
        let documentJSON = String(data: try WorkLogBackupCodec.encodedDocument(package.document), encoding: .utf8)
        #expect(manifestJSON?.contains("\"generatedAt\" : \"2026-05-20 00:00:00\"") == true)
        #expect(documentJSON?.contains("\"createdAt\" : \"") == true)
        #expect(documentJSON?.contains("T00:00:00Z") == false)

        let path = try #require(package.attachments.keys.first)
        #expect(path.contains("attachments/2026/05/20"))
        #expect(path.contains("交付_文档_.pdf"))
        #expect(package.attachments[path] == Data([1, 2, 3]))
    }

    @Test func decodeSupportsFriendlyAndLegacyISODateFormats() throws {
        let friendlyManifest = Data("""
        {
          "version": 1,
          "generatedAt": "2026-05-20 13:08:54",
          "projectCount": 0,
          "entryCount": 0,
          "attachmentCount": 0,
          "dataPath": "data/worklog.json"
        }
        """.utf8)
        let legacyManifest = Data("""
        {
          "version": 1,
          "generatedAt": "2026-05-20T05:08:54Z",
          "projectCount": 0,
          "entryCount": 0,
          "attachmentCount": 0,
          "dataPath": "data/worklog.json"
        }
        """.utf8)

        #expect(try WorkLogBackupCodec.decodedManifest(from: friendlyManifest).version == 1)
        #expect(try WorkLogBackupCodec.decodedManifest(from: legacyManifest).version == 1)
    }

    @Test func restoreRebuildsProjectsEntriesDaysAndAttachments() throws {
        let schema = Schema([Project.self, WorkLogEntry.self, WorkLogDayItem.self, WorkLogAttachment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let may20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let attachmentPath = "attachments/2026/05/20/a.txt"
        let package = WorkLogBackupPackage(
            manifest: WorkLogBackupManifest(version: 1, generatedAt: may20, projectCount: 1, entryCount: 1, attachmentCount: 1, dataPath: WorkLogBackupCodec.dataPath),
            document: WorkLogBackupDocument(
                projects: [ProjectBackupDTO(id: "p1", name: "司乘项目", createdAt: may20)],
                entries: [
                    EntryBackupDTO(
                        id: "e1",
                        projectID: "p1",
                        typeRawValue: WorkLogType.requirement.rawValue,
                        title: "需求交付",
                        agileNumber: "AGILE-1",
                        ticketNumber: "T-1",
                        createdAt: may20,
                        updatedAt: may20,
                        dayItems: [
                            DayItemBackupDTO(
                                id: "d1",
                                workDate: may20,
                                detail: "整理材料",
                                hours: 2,
                                createdAt: may20,
                                updatedAt: may20,
                                attachments: [
                                    AttachmentBackupDTO(id: "a1", fileName: "a.txt", contentType: "text/plain", createdAt: may20, path: attachmentPath)
                                ]
                            )
                        ]
                    )
                ]
            ),
            attachments: [attachmentPath: Data([7, 8, 9])]
        )

        WorkLogBackupCodec.restore(package, into: context)

        let projects = try context.fetch(FetchDescriptor<Project>())
        let entries = try context.fetch(FetchDescriptor<WorkLogEntry>())

        #expect(projects.count == 1)
        #expect(entries.count == 1)
        #expect(entries.first?.projectName == "司乘项目")
        #expect(entries.first?.sortedDayItems.first?.attachments.first?.data == Data([7, 8, 9]))
    }
}

@Suite(.serialized)
struct ClientRequestTests {
    @Test func requestUsesMethodPathAndBasicAuthorization() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: .ephemeralWithRecorder(recorder))
        let client = WebDAVClient(
            configuration: WebDAVConfiguration(
                serverURL: "https://example.com/dav",
                remotePath: "worklog",
                username: "yangzy",
                authMode: .basic
            ),
            secret: "secret",
            session: session
        )

        try await client.upload(Data([1]), path: "data/worklog.json", contentType: "application/json")

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://example.com/dav/worklog/data/worklog.json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("yangzy:secret".utf8).base64EncodedString())")
    }

    @Test func testConnectionUsesPropfindDepthZeroAndBearerAuthorization() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: .ephemeralWithRecorder(recorder))
        let client = WebDAVClient(
            configuration: WebDAVConfiguration(
                serverURL: "https://example.com/dav",
                remotePath: "worklog",
                username: "",
                authMode: .bearer
            ),
            secret: "token",
            session: session
        )

        try await client.testConnection()

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.value(forHTTPHeaderField: "Depth") == "0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }
    @Test func requestUsesOpenAICompatibleChatCompletionsShape() async throws {
        let recorder = RequestRecorder()
        recorder.responseData = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "今日完成接口联调。"
              }
            }
          ]
        }
        """.utf8)
        let session = URLSession(configuration: .ephemeralWithRecorder(recorder))
        let client = DailyReportAIClient(
            configuration: DailyReportAIConfiguration(baseURL: "https://example.com/v1", model: "daily-model"),
            apiKey: "secret",
            session: session
        )

        let report = try await client.generateReport(prompt: "请生成日报")

        #expect(report == "今日完成接口联调。")
        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "daily-model")
        #expect((json["temperature"] as? NSNumber)?.doubleValue == 0.2)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.contains { $0["role"] as? String == "user" && $0["content"] as? String == "请生成日报" })
    }

    @Test func emptyAIContentThrowsReadableError() async throws {
        let recorder = RequestRecorder()
        recorder.responseData = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "   "
              }
            }
          ]
        }
        """.utf8)
        let session = URLSession(configuration: .ephemeralWithRecorder(recorder))
        let client = DailyReportAIClient(
            configuration: DailyReportAIConfiguration(baseURL: "https://example.com", model: "daily-model"),
            apiKey: "secret",
            session: session
        )

        do {
            _ = try await client.generateReport(prompt: "请生成日报")
            Issue.record("Expected empty response error")
        } catch let error as DailyReportError {
            #expect(error == .emptyResponse)
        }
    }

    @Test func httpErrorReturnsReadableMessage() async throws {
        let recorder = RequestRecorder()
        recorder.statusCode = 401
        recorder.responseData = Data("""
        {
          "error": {
            "message": "invalid api key"
          }
        }
        """.utf8)
        let session = URLSession(configuration: .ephemeralWithRecorder(recorder))
        let client = DailyReportAIClient(
            configuration: DailyReportAIConfiguration(baseURL: "https://example.com", model: "daily-model"),
            apiKey: "secret",
            session: session
        )

        do {
            _ = try await client.generateReport(prompt: "请生成日报")
            Issue.record("Expected HTTP status error")
        } catch let error as DailyReportError {
            #expect(error == .httpStatus(401, "invalid api key"))
        }
    }
}

private final class RequestRecorder: @unchecked Sendable {
    var requests: [URLRequest] = []
    var responseData = Data()
    var statusCode = 200
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var recorder: RequestRecorder?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var recordedRequest = request
        if recordedRequest.httpBody == nil, let bodyStream = request.httpBodyStream {
            recordedRequest.httpBody = Data(reading: bodyStream)
        }
        MockURLProtocol.recorder?.requests.append(recordedRequest)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.recorder?.statusCode ?? 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.recorder?.responseData ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading inputStream: InputStream) {
        self.init()
        inputStream.open()
        defer { inputStream.close() }

        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while inputStream.hasBytesAvailable {
            let count = inputStream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

private extension URLSessionConfiguration {
    static func ephemeralWithRecorder(_ recorder: RequestRecorder) -> URLSessionConfiguration {
        MockURLProtocol.recorder = recorder
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }
}
