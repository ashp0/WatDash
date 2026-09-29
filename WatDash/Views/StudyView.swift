//
//  StudyView.swift
//  WatDash
//

import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

/// Study pages per course, and the Claude Code prompt builder for new ones.
struct StudyView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.isCompact) private var compact

    var body: some View {
        let upcoming = store.upcomingDeadlines(days: 28).filter { $0.kind == .quiz || $0.kind == .test || $0.kind == .exam }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    #if os(macOS)
                    Text("Study").font(.largeTitle.weight(.bold))
                    #endif
                    Text("Study pages are built by Claude Code on your subscription, using the quiz-prep skill in your classes folder. WatDash writes the prompt: assessment, sections, notes pages and the course's rules.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Coming up").font(.title3.weight(.semibold))
                    if upcoming.isEmpty {
                        Card { Text("No quizzes or exams in the next four weeks.").foregroundStyle(.secondary) }
                    }
                    ForEach(upcoming) { item in
                        if case let .assessment(id) = item.origin, let assessment = store.assessment(id: id) {
                            Card {
                                HStack(spacing: 12) {
                                    KindIcon(kind: item.kind, color: store.color(for: item.courseCode))
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            CourseChip(code: assessment.courseCode)
                                            Text(assessment.title).font(.headline)
                                        }
                                        Text("\(item.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · in \(item.start.compactCountdown(from: store.now))\(assessment.coverage.map { " · covers \($0)" } ?? "")")
                                            .font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        router.sheet = .studyPrompt(assessment.courseCode, assessment.id)
                                    } label: {
                                        if compact {
                                            Image(systemName: "terminal").accessibilityLabel("Claude Code Prompt")
                                        } else {
                                            Label("Claude Code Prompt…", systemImage: "terminal")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Study pages").font(.title3.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 280 : 320), spacing: 14)], spacing: 14) {
                        ForEach(store.courses) { course in
                            StudyLinksCard(course: course)
                        }
                    }
                }
            }
            .padding(compact ? 16 : 24)
        }
        .navigationTitle("Study")
    }
}

struct StudyLinksCard: View {
    @Environment(Router.self) private var router
    var course: Course

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CourseChip(code: course.code)
                    Text(course.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { router.sheet = .studyPrompt(course.code, nil) } label: { Image(systemName: "terminal") }
                        .buttonStyle(.borderless)
                        .help("Claude Code prompt for any sections")
                }
                if course.studyLinks.isEmpty {
                    Text("No study pages yet.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(course.studyLinks) { link in
                    StudyLinkRow(link: link)
                }
            }
        }
    }
}

struct StudyLinkRow: View {
    @State private var showViewer = false
    var link: StudyLink

    var body: some View {
        HStack {
            Image(systemName: link.isLocalFile ? "doc.richtext" : "safari")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(link.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(link.note ?? (link.isLocalFile ? URL(fileURLWithPath: link.url).lastPathComponent : link.url))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            // Local builds live in the Mac's course folders; iOS can only
            // open the web ones.
            if link.isLocalFile {
                #if os(macOS)
                Button("View") { showViewer = true }.controlSize(.small)
                #endif
            }
            if !link.isLocalFile || isMac {
                Button {
                    if let url = link.resolvedURL { Platform.open(url) }
                } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.borderless)
                .help("Open in browser")
            }
        }
        .sheet(isPresented: $showViewer) {
            if let url = link.resolvedURL {
                VStack(spacing: 0) {
                    HStack {
                        Text(link.title).font(.headline)
                        Spacer()
                        Button("Done") { showViewer = false }.keyboardShortcut(.defaultAction)
                    }
                    .padding(10)
                    Divider()
                    WebPageView(url: url)
                }
                #if os(macOS)
                .frame(width: 900, height: 700)
                #endif
            }
        }
    }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

struct WebPageView {
    var url: URL

    func makeWebView() -> WKWebView {
        let view = WKWebView()
        if url.isFileURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.load(URLRequest(url: url))
        }
        return view
    }
}

#if os(macOS)
extension WebPageView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
extension WebPageView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif

struct CourseStudyTab: View {
    @Environment(Router.self) private var router
    var course: Course

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StudyLinksCard(course: course)
                if !course.pageMap.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            CardHeader(title: "Notes page map", symbol: "book.pages", trailing: course.notesFile)
                            ForEach(course.pageMap) { section in
                                HStack {
                                    Text("§\(section.section)").font(.callout.monospacedDigit()).frame(width: 60, alignment: .leading)
                                    Text(section.title).font(.callout)
                                    Spacer()
                                    Text("p. \(section.page)\(section.problemsPage.map { " · problems p. \($0)" } ?? "")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Prompt sheet

struct StudyPromptSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isCompact) private var compact
    var courseCode: String
    var assessmentID: UUID?

    @State private var selected: Set<String> = []
    @State private var options = StudyPrompt.Options()
    @State private var copied: String?

    var body: some View {
        let assessment = assessmentID.flatMap { store.assessment(id: $0) }
        let code = assessment?.courseCode ?? courseCode
        let course = store.course(code: code) ?? Course(code: code)
        let sections = course.pageMap.filter { selected.contains($0.section) }
        let prompt = StudyPrompt(course: course, sections: sections, assessment: assessment,
                                 classesRoot: store.settings.classesFolderPath, options: options)

        SheetScaffold(
            title: "Claude Code prompt",
            subtitle: "Paste it into Claude Code (opened in your classes folder). It uses the quiz-prep skill and its agents, so the page gets past-paper research and every answer checked.",
            width: 820, height: 640
        ) {
            // Side by side on a wide sheet; options above the prompt on iPhone.
            let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                                 : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sections").font(.headline)
                    if course.pageMap.isEmpty {
                        Text("No notes page map for \(course.code). Scan its course folder, or describe the topics under “Also”.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        List(course.pageMap) { section in
                            Toggle(isOn: Binding(
                                get: { selected.contains(section.section) },
                                set: { if $0 { selected.insert(section.section) } else { selected.remove(section.section) } }
                            )) {
                                HStack {
                                    Text("§\(section.section)").monospacedDigit().frame(width: 44, alignment: .leading)
                                    Text(section.title).lineLimit(1)
                                    Spacer()
                                    Text("p. \(section.page)").foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                        .frame(minHeight: 200)
                    }
                    Stepper("Practice problems per section: \(options.practicePerSection)", value: $options.practicePerSection, in: 2...10)
                    Toggle("Timed mock quiz in the real format", isOn: $options.mockQuiz)
                    Toggle("Research past papers (past-paper-scout)", isOn: $options.pastPapers)
                    Toggle("Extend the existing study page", isOn: $options.extendExisting)
                        .disabled(prompt.existingArtifact == nil)
                    TextField("Also…", text: $options.extraInstructions, prompt: Text("e.g. focus on ε–N proofs"), axis: .vertical)
                        .lineLimit(2...4)
                }
                .frame(width: compact ? nil : 330)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt").font(.headline)
                    ScrollView {
                        Text(prompt.text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    if let copied {
                        Label(copied, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good).font(.callout)
                    }
                }
            }
        } actions: {
            #if os(macOS)
            Button("Show Classes Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.settings.classesFolderPath)])
            }
            #endif
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(compact ? "Copy Command" : "Copy as Terminal Command") {
                copy(prompt.terminalCommand)
                copied = "Copied. Paste into Terminal to start Claude Code in the classes folder."
            }
            Button("Copy Prompt") {
                copy(prompt.text)
                copied = "Copied. Paste it into Claude Code."
            }
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            let assessment = assessmentID.flatMap { store.assessment(id: $0) }
            let course = store.course(code: assessment?.courseCode ?? courseCode)
            if let assessment, let course {
                selected = Set(StudyPrompt.sections(for: assessment.coverage, in: course.pageMap).map(\.section))
            }
            if let course, !course.studyLinks.contains(where: { $0.url.contains("claude.ai/") }) {
                options.extendExisting = false
            }
        }
    }

    private func copy(_ text: String) {
        Platform.copy(text)
    }
}
