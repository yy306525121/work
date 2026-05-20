//
//  ContentView.swift
//  work
//
//  Created by 杨忠洋 on 2026/5/19.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum SidebarSelection: Hashable {
    case entries
    case projects
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \WorkLogEntry.updatedAt, order: .reverse) private var entries: [WorkLogEntry]

    @State private var sidebarSelection: SidebarSelection? = .entries
    @State private var selectedEntry: WorkLogEntry?
    @State private var editingEntry: WorkLogEntry?
    @State private var isShowingEntryForm = false
    @State private var entryPendingDeletion: WorkLogEntry?

    @State private var filterProjectName = ""
    @State private var filterTypeRawValue = ""
    @State private var useStartDate = false
    @State private var useEndDate = false
    @State private var startDate = Date()
    @State private var endDate = Date()

    private var filteredEntries: [WorkLogEntry] {
        let filter = WorkLogFilter(
            startDate: useStartDate ? startDate : nil,
            endDate: useEndDate ? endDate : nil,
            projectName: filterProjectName.isEmpty ? nil : filterProjectName,
            type: WorkLogType(rawValue: filterTypeRawValue)
        )

        return entries.filter { filter.matches(entry: $0) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Label("工作记录", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.entries)
                Label("项目管理", systemImage: "folder")
                    .tag(SidebarSelection.projects)
            }
            .navigationTitle("工作台")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch sidebarSelection ?? .entries {
            case .entries:
                WorkEntriesView(
                    projects: projects,
                    entries: filteredEntries,
                    selectedEntry: $selectedEntry,
                    editingEntry: $editingEntry,
                    entryPendingDeletion: $entryPendingDeletion,
                    isShowingEntryForm: $isShowingEntryForm,
                    filterProjectName: $filterProjectName,
                    filterTypeRawValue: $filterTypeRawValue,
                    useStartDate: $useStartDate,
                    useEndDate: $useEndDate,
                    startDate: $startDate,
                    endDate: $endDate
                )
            case .projects:
                ProjectsView(projects: projects, entries: entries)
            }
        }
        .onAppear(perform: migrateLegacyEntriesIfNeeded)
        .sheet(isPresented: $isShowingEntryForm) {
            WorkLogEntryFormView(projects: projects, entry: nil) { draft in
                saveNewEntry(draft)
            }
        }
        .sheet(item: $editingEntry) { entry in
            WorkLogEntryFormView(projects: projects, entry: entry) { draft in
                update(entry: entry, with: draft)
            }
        }
        .alert("删除工作记录", isPresented: deletionAlertBinding) {
            Button("取消", role: .cancel) {
                entryPendingDeletion = nil
            }
            Button("删除", role: .destructive) {
                if let entryPendingDeletion {
                    delete(entryPendingDeletion)
                }
            }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { entryPendingDeletion != nil },
            set: { if !$0 { entryPendingDeletion = nil } }
        )
    }

    private func saveNewEntry(_ draft: WorkLogEntryDraft) {
        guard let project = projects.first(where: { $0.name == draft.projectName }),
              let firstDay = draft.dayItems.sorted(by: { $0.workDate < $1.workDate }).first else {
            return
        }

        let entry = WorkLogEntry(
            project: project,
            type: draft.type,
            title: draft.title,
            detail: firstDay.detail,
            workDate: firstDay.workDate,
            hours: firstDay.hours,
            agileNumber: draft.type == .requirement ? draft.agileNumber : "",
            ticketNumber: draft.type == .requirement ? draft.ticketNumber : ""
        )

        modelContext.insert(entry)
        replaceDayItems(for: entry, with: draft.dayItems, keepsAttachments: draft.type == .requirement)
        selectedEntry = entry
    }

    private func update(entry: WorkLogEntry, with draft: WorkLogEntryDraft) {
        guard let project = projects.first(where: { $0.name == draft.projectName }),
              let firstDay = draft.dayItems.sorted(by: { $0.workDate < $1.workDate }).first else {
            return
        }

        entry.project = project
        entry.type = draft.type
        entry.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.detail = firstDay.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.workDate = firstDay.workDate
        entry.hours = firstDay.hours
        entry.agileNumber = draft.type == .requirement ? draft.agileNumber.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        entry.ticketNumber = draft.type == .requirement ? draft.ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        entry.updatedAt = .now

        replaceDayItems(for: entry, with: draft.dayItems, keepsAttachments: draft.type == .requirement)
        selectedEntry = entry
    }

    private func replaceDayItems(for entry: WorkLogEntry, with dayItems: [WorkLogDayItemDraft], keepsAttachments: Bool) {
        for item in entry.dayItems {
            modelContext.delete(item)
        }

        entry.dayItems.removeAll()

        for draft in dayItems.sorted(by: { $0.workDate < $1.workDate }) {
            let dayItem = WorkLogDayItem(
                entry: entry,
                workDate: draft.workDate,
                detail: draft.detail,
                hours: draft.hours,
                createdAt: .now,
                updatedAt: .now
            )
            modelContext.insert(dayItem)
            entry.dayItems.append(dayItem)

            guard keepsAttachments else { continue }

            for attachmentDraft in draft.attachments {
                let attachment = WorkLogAttachment(
                    dayItem: dayItem,
                    fileName: attachmentDraft.fileName,
                    contentType: attachmentDraft.contentType,
                    data: attachmentDraft.data,
                    createdAt: attachmentDraft.createdAt
                )
                modelContext.insert(attachment)
                dayItem.attachments.append(attachment)
            }
        }
    }

    private func migrateLegacyEntriesIfNeeded() {
        for entry in entries where entry.dayItems.isEmpty {
            let dayItem = WorkLogDayItem(
                entry: entry,
                workDate: entry.workDate,
                detail: entry.detail,
                hours: entry.hours,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )

            modelContext.insert(dayItem)
            entry.dayItems.append(dayItem)

            for attachment in entry.legacyAttachments {
                attachment.legacyEntry = nil
                attachment.dayItem = dayItem
                dayItem.attachments.append(attachment)
            }
        }
    }

    private func delete(_ entry: WorkLogEntry) {
        if selectedEntry === entry {
            selectedEntry = nil
        }

        modelContext.delete(entry)
        entryPendingDeletion = nil
    }
}

private struct WorkEntriesView: View {
    let projects: [Project]
    let entries: [WorkLogEntry]

    @Binding var selectedEntry: WorkLogEntry?
    @Binding var editingEntry: WorkLogEntry?
    @Binding var entryPendingDeletion: WorkLogEntry?
    @Binding var isShowingEntryForm: Bool

    @Binding var filterProjectName: String
    @Binding var filterTypeRawValue: String
    @Binding var useStartDate: Bool
    @Binding var useEndDate: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        VStack(spacing: 0) {
            WorkLogFilterBar(
                projects: projects,
                filterProjectName: $filterProjectName,
                filterTypeRawValue: $filterTypeRawValue,
                useStartDate: $useStartDate,
                useEndDate: $useEndDate,
                startDate: $startDate,
                endDate: $endDate
            )

            Divider()

            HSplitView {
                List {
                    ForEach(entries) { entry in
                        WorkLogRow(entry: entry, isSelected: selectedEntry === entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEntry = entry
                            }
                            .onTapGesture(count: 2) {
                                editingEntry = entry
                            }
                            .contextMenu {
                                Button("编辑") {
                                    editingEntry = entry
                                }
                                Button("删除", role: .destructive) {
                                    entryPendingDeletion = entry
                                }
                            }
                    }
                }
                .frame(minWidth: 540, maxHeight: .infinity)

                WorkLogDetailView(entry: selectedEntry)
                    .frame(minWidth: 360, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("工作记录")
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingEntryForm = true
                } label: {
                    Label("新增工作记录", systemImage: "plus")
                }
                .disabled(projects.isEmpty)
                .help(projects.isEmpty ? "请先新增项目" : "新增工作记录")
            }
        }
    }
}

private struct WorkLogFilterBar: View {
    let projects: [Project]

    @Binding var filterProjectName: String
    @Binding var filterTypeRawValue: String
    @Binding var useStartDate: Bool
    @Binding var useEndDate: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        HStack(spacing: 12) {
            Picker("项目", selection: $filterProjectName) {
                Text("全部项目").tag("")
                ForEach(projects) { project in
                    Text(project.name).tag(project.name)
                }
            }
            .frame(width: 220)

            Picker("类型", selection: $filterTypeRawValue) {
                Text("全部类型").tag("")
                ForEach(WorkLogType.allCases) { type in
                    Text(type.rawValue).tag(type.rawValue)
                }
            }
            .frame(width: 180)

            Toggle("开始日期", isOn: $useStartDate)
            DatePicker("", selection: $startDate, displayedComponents: .date)
                .labelsHidden()
                .disabled(!useStartDate)

            Toggle("结束日期", isOn: $useEndDate)
            DatePicker("", selection: $endDate, displayedComponents: .date)
                .labelsHidden()
                .disabled(!useEndDate)

            Spacer()

            Button {
                filterProjectName = ""
                filterTypeRawValue = ""
                useStartDate = false
                useEndDate = false
            } label: {
                Label("清空筛选", systemImage: "xmark.circle")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WorkLogRow: View {
    let entry: WorkLogEntry
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(entry.type.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Text("\(entry.totalHours, specifier: "%.1f") 小时")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(entry.projectName, systemImage: "folder")
                Label(entry.dateRangeText, systemImage: "calendar")

                if entry.type == .requirement {
                    Label(entry.agileNumber, systemImage: "number")

                    if !entry.ticketNumber.isEmpty {
                        Label(entry.ticketNumber, systemImage: "ticket")
                    }

                    if entry.totalAttachmentCount > 0 {
                        Label("\(entry.totalAttachmentCount) 个附件", systemImage: "paperclip")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct WorkLogDetailView: View {
    let entry: WorkLogEntry?

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title)
                                .font(.title2.weight(.semibold))
                            Text(entry.type.rawValue)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        DetailGrid(entry: entry)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("每日明细")
                                .font(.headline)

                            ForEach(entry.sortedDayItems) { item in
                                DayItemDetailSection(dayItem: item, showsAttachments: entry.type == .requirement)
                            }
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("选择一条工作记录", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct DetailGrid: View {
    let entry: WorkLogEntry

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
            GridRow {
                DetailLabel("项目")
                Text(entry.projectName)
            }
            GridRow {
                DetailLabel("日期范围")
                Text(entry.dateRangeText)
            }
            GridRow {
                DetailLabel("工作时间")
                Text("\(entry.totalHours, specifier: "%.1f") 小时")
            }
            if entry.type == .requirement {
                GridRow {
                    DetailLabel("敏捷编号")
                    Text(entry.agileNumber)
                }
                GridRow {
                    DetailLabel("工单编号")
                    Text(entry.ticketNumber.isEmpty ? "未填写" : entry.ticketNumber)
                }
                GridRow {
                    DetailLabel("成果物")
                    Text(entry.totalAttachmentCount == 0 ? "未添加" : "\(entry.totalAttachmentCount) 个附件")
                }
            }
        }
    }
}

private struct DayItemDetailSection: View {
    let dayItem: WorkLogDayItem
    let showsAttachments: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(WorkLogDateFormatter.dayDetailText(for: dayItem.workDate))
                    .font(.headline)

                Spacer()

                Text("\(dayItem.hours, specifier: "%.1f") 小时")
                    .foregroundStyle(.secondary)
            }

            Text(dayItem.detail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsAttachments {
                AttachmentDetailSection(attachments: dayItem.attachments)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AttachmentDetailSection: View {
    let attachments: [WorkLogAttachment]
    @State private var exportError: String?

    private var sortedAttachments: [WorkLogAttachment] {
        attachments.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sortedAttachments.isEmpty {
                Text("未添加成果物")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedAttachments) { attachment in
                    HStack(spacing: 10) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.fileName)
                                .lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            export(attachment)
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }

            if let exportError {
                Text(exportError)
                    .foregroundStyle(.red)
            }
        }
    }

    private func export(_ attachment: WorkLogAttachment) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = attachment.fileName
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            try attachment.data.write(to: url)
            exportError = nil
        } catch {
            exportError = "导出失败：\(error.localizedDescription)"
        }
    }
}

private struct DetailLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
    }
}

private struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext

    let projects: [Project]
    let entries: [WorkLogEntry]

    @State private var newProjectName = ""
    @State private var projectError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TextField("项目名", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(addProject)

                Button {
                    addProject()
                } label: {
                    Label("新增项目", systemImage: "plus")
                }

                if let projectError {
                    Text(projectError)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            List {
                ForEach(projects) { project in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.headline)
                            Text("\(entryCount(for: project)) 条工作记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("删除", role: .destructive) {
                            delete(project)
                        }
                        .disabled(entryCount(for: project) > 0)
                        .help(entryCount(for: project) > 0 ? "该项目已有工作记录，不能删除" : "删除项目")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("项目管理")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addProject() {
        if let error = WorkLogValidation.projectNameError(newProjectName, existingNames: projects.map(\.name)) {
            projectError = error
            return
        }

        modelContext.insert(Project(name: newProjectName))
        newProjectName = ""
        projectError = nil
    }

    private func delete(_ project: Project) {
        guard entryCount(for: project) == 0 else { return }
        modelContext.delete(project)
    }

    private func entryCount(for project: Project) -> Int {
        entries.filter { $0.project === project }.count
    }
}

struct WorkLogEntryDraft {
    var projectName: String
    var type: WorkLogType
    var title: String
    var agileNumber: String
    var ticketNumber: String
    var dayItems: [WorkLogDayItemDraft]
}

private struct WorkLogEntryFormView: View {
    @Environment(\.dismiss) private var dismiss

    let projects: [Project]
    let entry: WorkLogEntry?
    let onSave: (WorkLogEntryDraft) -> Void

    @State private var projectName: String
    @State private var type: WorkLogType
    @State private var title: String
    @State private var agileNumber: String
    @State private var ticketNumber: String
    @State private var dayItems: [WorkLogDayItemDraft]
    @State private var errors: [String] = []
    @State private var importingDayID: UUID?

    init(projects: [Project], entry: WorkLogEntry?, onSave: @escaping (WorkLogEntryDraft) -> Void) {
        self.projects = projects
        self.entry = entry
        self.onSave = onSave

        _projectName = State(initialValue: entry?.projectName ?? projects.first?.name ?? "")
        _type = State(initialValue: entry?.type ?? .regular)
        _title = State(initialValue: entry?.title ?? "")
        _agileNumber = State(initialValue: entry?.agileNumber ?? "")
        _ticketNumber = State(initialValue: entry?.ticketNumber ?? "")

        let existingItems = entry?.sortedDayItems ?? []
        if existingItems.isEmpty {
            _dayItems = State(initialValue: [
                WorkLogDayItemDraft(workDate: .now, detail: "", hours: 1)
            ])
        } else {
            _dayItems = State(initialValue: existingItems.map {
                WorkLogDayItemDraft(
                    workDate: $0.workDate,
                    detail: $0.detail,
                    hours: $0.hours,
                    attachments: $0.attachments.sorted { $0.createdAt < $1.createdAt }.map {
                        WorkLogAttachmentDraft(
                            fileName: $0.fileName,
                            contentType: $0.contentType,
                            data: $0.data,
                            createdAt: $0.createdAt
                        )
                    }
                )
            })
        }
    }

    private var isImportingAttachments: Binding<Bool> {
        Binding(
            get: { importingDayID != nil },
            set: { if !$0 { importingDayID = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(entry == nil ? "新增工作记录" : "编辑工作记录")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button("保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            Form {
                Picker("项目", selection: $projectName) {
                    ForEach(projects) { project in
                        Text(project.name).tag(project.name)
                    }
                }

                Picker("工作类型", selection: $type) {
                    ForEach(WorkLogType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                TextField("工作标题", text: $title)

                if type == .requirement {
                    TextField("敏捷编号", text: $agileNumber)
                    TextField("工单编号", text: $ticketNumber)
                }

                Section("每日明细") {
                    ForEach($dayItems) { $dayItem in
                        DayItemFormSection(
                            dayItem: $dayItem,
                            showsAttachments: type == .requirement,
                            canDelete: dayItems.count > 1,
                            onDelete: {
                                dayItems.removeAll { $0.id == dayItem.id }
                            },
                            onAddAttachments: {
                                importingDayID = dayItem.id
                            }
                        )
                    }

                    Button {
                        addDayItem()
                    } label: {
                        Label("添加一天", systemImage: "plus.circle")
                    }
                }

                if !errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errors, id: \.self) { error in
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(18)
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: type) { _, newValue in
            if newValue == .regular {
                agileNumber = ""
                ticketNumber = ""
                for index in dayItems.indices {
                    dayItems[index].attachments = []
                }
            }
        }
        .fileImporter(
            isPresented: isImportingAttachments,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            importAttachments(result)
        }
    }

    private func addDayItem() {
        let nextDate = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: dayItems.map(\.workDate).max() ?? .now
        ) ?? .now

        dayItems.append(WorkLogDayItemDraft(workDate: nextDate, detail: "", hours: 1))
    }

    private func importAttachments(_ result: Result<[URL], Error>) {
        guard let importingDayID,
              let index = dayItems.firstIndex(where: { $0.id == importingDayID }) else {
            return
        }

        defer {
            self.importingDayID = nil
        }

        do {
            for url in try result.get() {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let contentType = UTType(filenameExtension: url.pathExtension)?.identifier ?? "application/octet-stream"
                dayItems[index].attachments.append(
                    WorkLogAttachmentDraft(
                        fileName: url.lastPathComponent,
                        contentType: contentType,
                        data: data,
                        createdAt: .now
                    )
                )
            }
        } catch {
            errors = ["附件导入失败：\(error.localizedDescription)"]
        }
    }

    private func save() {
        errors = WorkLogValidation.entryErrors(
            projectName: projectName,
            type: type,
            title: title,
            agileNumber: agileNumber,
            dayItems: type == .requirement ? dayItems : dayItems.map {
                var item = $0
                item.attachments = []
                return item
            }
        )

        guard errors.isEmpty else { return }

        onSave(
            WorkLogEntryDraft(
                projectName: projectName,
                type: type,
                title: title,
                agileNumber: agileNumber,
                ticketNumber: ticketNumber,
                dayItems: type == .requirement ? dayItems : dayItems.map {
                    var item = $0
                    item.attachments = []
                    return item
                }
            )
        )
        dismiss()
    }
}

private struct DayItemFormSection: View {
    @Binding var dayItem: WorkLogDayItemDraft
    let showsAttachments: Bool
    let canDelete: Bool
    let onDelete: () -> Void
    let onAddAttachments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DatePicker("工作日期", selection: $dayItem.workDate, displayedComponents: .date)

                HStack {
                    TextField("工作时间", value: $dayItem.hours, format: .number)
                        .frame(width: 90)
                    Stepper("小时", value: $dayItem.hours, in: 0.5...24, step: 0.5)
                        .labelsHidden()
                    Text("小时")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除这天", systemImage: "trash")
                }
                .disabled(!canDelete)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("当天工作内容")
                    .foregroundStyle(.secondary)
                TextEditor(text: $dayItem.detail)
                    .font(.body)
                    .frame(minHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor))
                    )
            }

            if showsAttachments {
                AttachmentPickerSection(
                    attachments: $dayItem.attachments,
                    onAddAttachments: onAddAttachments
                )
            }
        }
        .padding(.vertical, 8)
    }
}

private struct AttachmentPickerSection: View {
    @Binding var attachments: [WorkLogAttachmentDraft]
    let onAddAttachments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当天成果物")
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onAddAttachments()
                } label: {
                    Label("添加成果物", systemImage: "paperclip")
                }
            }

            if attachments.isEmpty {
                Text("未添加成果物")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.fileName)
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, WorkLogEntry.self, WorkLogDayItem.self, WorkLogAttachment.self], inMemory: true)
}
