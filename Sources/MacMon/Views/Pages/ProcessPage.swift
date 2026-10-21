import SwiftUI

/// 进程：全量列表，支持搜索与排序，可结束进程
struct ProcessPage: View {
    @EnvironmentObject private var model: AppModel

    enum SortMode: String, CaseIterable, Identifiable {
        case cpu, memory
        var id: String { rawValue }
        /// rawValue 是稳定标识（也用于 `id`），显示走 label
        var label: String { self == .cpu ? "CPU" : L.t("内存") }
    }

    @State private var query = ""
    @State private var sort: SortMode = .cpu
    @State private var pendingKill: ProcessRow?
    @State private var toast: String?

    private var rows: [ProcessRow] {
        var list = model.allProcesses
        let keyword = query.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(keyword)
                    || ($0.appName?.localizedCaseInsensitiveContains(keyword) ?? false)
                    || $0.user.localizedCaseInsensitiveContains(keyword)
            }
        }
        switch sort {
        case .cpu:
            return list.sorted { $0.cpu > $1.cpu }
        case .memory:
            return list.sorted { $0.memRssBytes > $1.memRssBytes }
        }
    }

    var body: some View {
        PageScaffold(page: .processes) {
            HStack(spacing: 10) {
                searchField
                sortToggle
                Text(L.f("共 %@ 个", model.processTotal))
                    .font(.system(size: TS.caption, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
        } content: { _ in
            Card(
                title: L.t("进程列表"),
                subtitle: L.f("%@ 个 · 右键可结束", rows.count),
                accent: Theme.orange
            ) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(rows) { row in
                                ProcessLine(row: row) { pendingKill = row }
                            }
                        } header: {
                            ProcessTableHeader()
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: TS.caption, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.surface2))
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .confirmationDialog(
            L.t("结束进程"),
            isPresented: Binding(
                get: { pendingKill != nil },
                set: { if !$0 { pendingKill = nil } }
            ),
            presenting: pendingKill
        ) { row in
            Button(L.f("结束 %@（SIGTERM）", row.name), role: .destructive) {
                runKill(pid: row.pid, force: false)
            }
            Button(L.t("强制结束（SIGKILL）"), role: .destructive) {
                runKill(pid: row.pid, force: true)
            }
            Button(L.t("取消"), role: .cancel) { pendingKill = nil }
        } message: { row in
            Text(L.f("PID %@ · 属于「%@」\n强制结束可能导致未保存的数据丢失。", row.pid, row.user))
        }
    }

    // MARK: - 工具条

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
            TextField(L.t("搜索进程 / 应用 / 属主"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: TS.caption))
                .foregroundStyle(Theme.text)
                .frame(width: 180)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }

    private var sortToggle: some View {
        HStack(spacing: 2) {
            ForEach(SortMode.allCases) { mode in
                Button {
                    sort = mode
                } label: {
                    Text(mode.label)
                        .font(.system(size: TS.micro, weight: sort == mode ? .semibold : .regular))
                        .foregroundStyle(sort == mode ? Theme.text : Theme.dim)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(sort == mode ? Theme.surface2 : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }

    private func runKill(pid: Int32, force: Bool) {
        let outcome = KillService.terminate(pid: pid, force: force)
        pendingKill = nil
        toast = outcome.message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if toast == outcome.message { toast = nil }
        }
    }
}
