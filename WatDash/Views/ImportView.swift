//
//  ImportView.swift
//  WatDash
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File pickers and drag-and-drop, shared by the toolbar, menus and tiles.
@MainActor
enum ImportActions {
    static func pickICSFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "Choose calendar files: Quest's “Download Schedule”, a LEARN calendar export, anything .ics."
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    static func pickOutline() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "Choose a course outline saved from outline.uwaterloo.ca (File → Save As… → Web Page)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Router.shared.sheet = .outline(url)
    }

    static func importFiles(_ urls: [URL]) {
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "ics":
                do {
                    let summary = try ImportService.shared.importICSFile(url)
                    Router.shared.show("\(summary.title) — \(summary.detail)")
                } catch {
                    Router.shared.show("Couldn't import \(url.lastPathComponent): \(error.localizedDescription)")
                }
            case "html", "htm":
                Router.shared.sheet = .outline(url)
            default:
                Router.shared.show("WatDash imports .ics calendars and saved outline pages.")
            }
        }
    }

    static func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in importFiles([url]) }
            }
        }
    }
}

struct ImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import").font(.largeTitle.weight(.bold))
                    Text("Every source is remembered, so re-importing updates instead of duplicating, and removing a source removes exactly what it added.")
                        .foregroundStyle(.secondary)
                }
                ImportTileGrid(compact: false)

                if !store.proposedEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Inbox").font(.title3.weight(.semibold))
                            Spacer()
                            Button("Add All") { store.acceptAllProposed() }
                        }
                        Card {
                            VStack(spacing: 8) {
                                ForEach(store.proposedEvents) { InboxRow(event: $0) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sources").font(.title3.weight(.semibold))
                    if store.sources.isEmpty {
                        Card { Text("Nothing imported yet.").foregroundStyle(.secondary) }
                    } else {
                        Card(padding: 6) {
                            VStack(spacing: 0) {
                                ForEach(store.sources) { source in
                                    SourceRow(source: source)
                                    if source.id != store.sources.last?.id { Divider().padding(.leading, 44) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Import")
    }
}

/// The import "widgets": one tile per way data can get in.
struct ImportTileGrid: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var compact: Bool

    struct Tile: Identifiable {
        var id: String { title }
        var title: String
        var detail: String
        var symbol: String
        var action: () -> Void
    }

    var tiles: [Tile] {
        [
            Tile(title: "Course folders", detail: "Assessments, schemes and notes maps from each CLAUDE.md", symbol: "folder.badge.gearshape") { router.sheet = .courseFolders },
            Tile(title: "Quest schedule", detail: "Paste My Class Schedule (List View)", symbol: "list.clipboard") { router.sheet = .questPaste },
            Tile(title: "Calendar file", detail: "Quest's Download Schedule .ics, or any .ics", symbol: "doc.badge.clock") { ImportActions.pickICSFile() },
            Tile(title: "Calendar feed", detail: "Subscribe to LEARN, Google or course feeds", symbol: "antenna.radiowaves.left.and.right") { router.sheet = .feed },
            Tile(title: "Course outline", detail: "A saved outline.uwaterloo.ca page", symbol: "doc.richtext") { ImportActions.pickOutline() },
            Tile(title: "Apple Calendar", detail: "Calendars already on this Mac", symbol: "calendar") { router.sheet = .appleCalendar },
            Tile(title: "Waterloo Open Data", detail: "Class times, key dates, finals, seats", symbol: "building.columns") { router.sheet = .openData },
            Tile(title: "UW holidays", detail: "Cancel classes on stat holidays", symbol: "sun.max") {
                Task {
                    do {
                        let summary = try await ImportService.shared.importHolidays()
                        router.show("\(summary.title): \(summary.detail)")
                    } catch {
                        router.show("Holidays feed unavailable: \(error.localizedDescription)")
                    }
                }
            },
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 150 : 220), spacing: 10)], spacing: 10) {
            ForEach(tiles) { tile in
                Button(action: tile.action) {
                    HStack(alignment: compact ? .center : .top, spacing: 10) {
                        Image(systemName: tile.symbol)
                            .font(.system(size: compact ? 15 : 18, weight: .medium))
                            .foregroundStyle(Palette.accentDeep)
                            .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)
                            .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.title).font(compact ? .callout.weight(.medium) : .headline)
                            if !compact {
                                Text(tile.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(compact ? 8 : 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tile.detail)
            }
        }
    }
}

struct SourceRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var source: DataSource
    @State private var refreshing = false
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.kind.symbol)
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(source.name).font(.callout.weight(.medium))
                    Text(source.kind.label).font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }
                Group {
                    if let error = source.lastError {
                        Text(error).foregroundStyle(Palette.bad)
                    } else if let refreshed = source.lastRefresh {
                        Text("\(source.itemCount) items · updated \(refreshed.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("\(store.events.filter { $0.sourceID == source.id }.count + store.assessments.filter { $0.sourceID == source.id }.count) items")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            health
            if source.kind.isRefreshable {
                Button {
                    refresh()
                } label: {
                    if refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { var copy = source; copy.isEnabled = $0; store.updateSource(copy) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("Include in automatic refreshes")
            Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove source")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .confirmationDialog("Remove “\(source.name)”?", isPresented: $confirmRemove) {
            Button("Remove Source and Its Items", role: .destructive) { store.removeSource(source, removingItems: true) }
            Button("Remove Source, Keep Items") { store.removeSource(source, removingItems: false) }
        } message: {
            Text("Graded assessments are always kept.")
        }
    }

    @ViewBuilder
    private var health: some View {
        switch source.health {
        case .ok: EmptyView()
        case .stale: Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Palette.warn).help("Not refreshed in 3 days")
        case .failing: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.bad).help(source.lastError ?? "")
        }
    }

    private func refresh() {
        refreshing = true
        Task {
            switch source.kind {
            case .icsFeed, .holidays: _ = try? await ImportService.shared.refreshFeed(source)
            case .appleCalendar: CalendarSync.shared.importEvents(source: source, into: store)
            case .courseFolder:
                if let path = source.location {
                    let folder = URL(fileURLWithPath: path)
                    let scans = ImportService.shared.scanCourseFolders(root: folder.deletingLastPathComponent()).filter { $0.folder.path == path }
                    _ = ImportService.shared.importCourseFolders(scans, includeSelfStudy: true)
                }
            case .openData:
                _ = try? await ImportService.shared.importOpenDataClasses()
            default: break
            }
            refreshing = false
        }
    }
}
