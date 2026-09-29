//
//  DashboardView.swift
//  WatDash
//

import SwiftUI

/// The Today screen answers one question: what should I be working on right
/// now? Work due in the next 48 hours comes first, then where to be for the
/// rest of the day. Grades live on the Grades screen and the sidebar, never
/// here.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.isCompact) private var compact

    var body: some View {
        let focus = store.focus()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.courses.isEmpty && store.events.isEmpty {
                    OnboardingCard()
                } else {
                    SetupNotice()
                    InboxNotice()
                    FocusCard(entries: focus)
                    RestOfTodayCard()
                    laterThisWeek(excluding: focus)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(compact ? 16 : 24)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: focus)
        }
        .navigationTitle("Today")
        .inlineNavigationTitle()
    }

    private var header: some View {
        let calendar = Calendar.current
        let week = max(1, calendar.dateComponents([.weekOfYear], from: calendar.startOfWeek(for: store.settings.termStart), to: store.now).weekOfYear.map { $0 + 1 } ?? 1)
        return VStack(alignment: .leading, spacing: 2) {
            Text(store.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.largeTitle.weight(.bold))
            Text("Week \(min(week, 16)) of \(store.settings.termName)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    /// Everything else due this week is one click away, not on screen.
    @ViewBuilder
    private func laterThisWeek(excluding focus: [Focus.Entry]) -> some View {
        let shown = Set(focus.map(\.id))
        let later = store.upcomingDeadlines(days: 7).filter { !shown.contains($0.id) }
        if !later.isEmpty {
            Button {
                router.selection = .deadlines
            } label: {
                HStack(spacing: 4) {
                    Text("\(later.count) more due in the next 7 days")
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }
}
