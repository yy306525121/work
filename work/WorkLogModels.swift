//
//  WorkLogModels.swift
//  work
//
//  Created by Codex on 2026/5/19.
//

import Foundation
import SwiftData

enum WorkLogType: String, CaseIterable, Identifiable, Codable {
    case regular = "常规工作"
    case requirement = "需求类工作"

    var id: String { rawValue }
}

@Model
final class Project {
    @Attribute(.unique) var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \WorkLogEntry.project)
    var entries: [WorkLogEntry] = []

    init(name: String, createdAt: Date = .now) {
        self.name = ProjectNameNormalizer.normalize(name)
        self.createdAt = createdAt
    }
}

@Model
final class WorkLogEntry {
    var project: Project?
    var typeRawValue: String

    // Legacy single-day fields kept so existing local data can be folded into day items.
    var title: String
    var detail: String
    var workDate: Date
    var hours: Double
    var agileNumber: String
    var ticketNumber: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \WorkLogDayItem.entry)
    var dayItems: [WorkLogDayItem] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkLogAttachment.legacyEntry)
    var legacyAttachments: [WorkLogAttachment] = []

    var type: WorkLogType {
        get { WorkLogType(rawValue: typeRawValue) ?? .regular }
        set { typeRawValue = newValue.rawValue }
    }

    var projectName: String {
        project?.name ?? "未选择项目"
    }

    var sortedDayItems: [WorkLogDayItem] {
        dayItems.sorted { $0.workDate < $1.workDate }
    }

    var totalHours: Double {
        dayItems.reduce(0) { $0 + $1.hours }
    }

    var totalAttachmentCount: Int {
        dayItems.reduce(0) { $0 + $1.attachments.count }
    }

    var startDate: Date? {
        sortedDayItems.first?.workDate
    }

    var endDate: Date? {
        sortedDayItems.last?.workDate
    }

    var dateRangeText: String {
        guard let startDate else {
            return "未填写日期"
        }

        guard let endDate, !Calendar.current.isDate(startDate, inSameDayAs: endDate) else {
            return startDate.formatted(date: .numeric, time: .omitted)
        }

        return "\(startDate.formatted(date: .numeric, time: .omitted)) - \(endDate.formatted(date: .numeric, time: .omitted))"
    }

    init(
        project: Project,
        type: WorkLogType,
        title: String,
        detail: String,
        workDate: Date,
        hours: Double,
        agileNumber: String = "",
        ticketNumber: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.project = project
        self.typeRawValue = type.rawValue
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workDate = workDate
        self.hours = hours
        self.agileNumber = agileNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ticketNumber = ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class WorkLogDayItem {
    var entry: WorkLogEntry?
    var workDate: Date
    var detail: String
    var hours: Double
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \WorkLogAttachment.dayItem)
    var attachments: [WorkLogAttachment] = []

    init(
        entry: WorkLogEntry? = nil,
        workDate: Date,
        detail: String,
        hours: Double,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.entry = entry
        self.workDate = workDate
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hours = hours
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class WorkLogAttachment {
    var dayItem: WorkLogDayItem?
    var legacyEntry: WorkLogEntry?
    var fileName: String
    var contentType: String
    var createdAt: Date

    @Attribute(.externalStorage)
    var data: Data

    init(
        dayItem: WorkLogDayItem? = nil,
        legacyEntry: WorkLogEntry? = nil,
        fileName: String,
        contentType: String,
        data: Data,
        createdAt: Date = .now
    ) {
        self.dayItem = dayItem
        self.legacyEntry = legacyEntry
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
        self.createdAt = createdAt
    }
}

enum ProjectNameNormalizer {
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WorkLogDateFormatter {
    private static let dayDetailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd(EEEE)"
        return formatter
    }()

    static func dayDetailText(for date: Date) -> String {
        dayDetailFormatter.string(from: date)
    }
}
