//
//  WorkLogValidation.swift
//  work
//
//  Created by Codex on 2026/5/19.
//

import Foundation

enum WorkLogValidation {
    static func projectNameError(_ name: String, existingNames: [String]) -> String? {
        let normalized = ProjectNameNormalizer.normalize(name)

        if normalized.isEmpty {
            return "项目名不能为空"
        }

        let exists = existingNames.contains {
            ProjectNameNormalizer.normalize($0).localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }

        return exists ? "项目名已存在" : nil
    }

    static func entryErrors(
        projectName: String,
        type: WorkLogType,
        title: String,
        agileNumber: String,
        dayItems: [WorkLogDayItemDraft]
    ) -> [String] {
        var errors: [String] = []

        if ProjectNameNormalizer.normalize(projectName).isEmpty {
            errors.append("请选择项目")
        }

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("工作标题不能为空")
        }

        if type == .requirement && agileNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("需求类工作必须填写敏捷编号")
        }

        errors.append(contentsOf: dayItemErrors(dayItems))

        return errors
    }

    static func dayItemErrors(_ dayItems: [WorkLogDayItemDraft], calendar: Calendar = .current) -> [String] {
        var errors: [String] = []

        if dayItems.isEmpty {
            errors.append("至少需要填写一天的工作明细")
            return errors
        }

        var seenDays: Set<Date> = []

        for (index, item) in dayItems.enumerated() {
            let label = "第 \(index + 1) 天"

            if item.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(label)工作内容不能为空")
            }

            if item.hours <= 0 {
                errors.append("\(label)工作时间必须大于 0 小时")
            }

            let day = calendar.startOfDay(for: item.workDate)
            if seenDays.contains(day) {
                errors.append("同一条工作记录内不能重复填写同一天")
            } else {
                seenDays.insert(day)
            }
        }

        return errors
    }
}

struct WorkLogFilter {
    var startDate: Date?
    var endDate: Date?
    var projectName: String?
    var type: WorkLogType?

    func matches(entry: WorkLogEntry, calendar: Calendar = .current) -> Bool {
        if let projectName, projectName != entry.projectName {
            return false
        }

        if let type, type != entry.type {
            return false
        }

        guard startDate != nil || endDate != nil else {
            return true
        }

        return entry.dayItems.contains {
            matchesDate(workDate: $0.workDate, calendar: calendar)
        }
    }

    func matches(
        workDate: Date,
        projectName entryProjectName: String,
        type entryType: WorkLogType,
        calendar: Calendar = .current
    ) -> Bool {
        if !matchesDate(workDate: workDate, calendar: calendar) {
            return false
        }

        if let projectName, projectName != entryProjectName {
            return false
        }

        if let type, type != entryType {
            return false
        }

        return true
    }

    private func matchesDate(workDate: Date, calendar: Calendar) -> Bool {
        if let startDate, workDate < calendar.startOfDay(for: startDate) {
            return false
        }

        if let endDate, workDate >= calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))! {
            return false
        }

        return true
    }
}

struct WorkLogDayItemDraft: Identifiable {
    var id = UUID()
    var workDate: Date
    var detail: String
    var hours: Double
    var attachments: [WorkLogAttachmentDraft] = []
}

struct WorkLogAttachmentDraft: Identifiable {
    var id = UUID()
    var fileName: String
    var contentType: String
    var data: Data
    var createdAt: Date
}
