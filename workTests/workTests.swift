//
//  workTests.swift
//  workTests
//
//  Created by 杨忠洋 on 2026/5/19.
//

import Foundation
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
