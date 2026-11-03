import SwiftUI

/// Sidebar pane listing the workspace's recent commits in a single-lane
/// graph: dot rail, subject, short hash and relative time, with the branch
/// name badge on refs. Clicking a commit opens its merged diff in a tab.
struct GitGraphView: View {
    let git: GitStatusStore
    let onSelect: (GitCommit) -> Void

    var body: some View {
        Group {
            if !git.hasRepository {
                statusView(
                    icon: "point.3.filled.connected.trianglepath.dotted",
                    message: "This workspace is not a Git repository"
                )
            } else if git.commits.isEmpty {
                statusView(icon: "tray", message: "No commits yet")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(git.commits) { commit in
                            GitGraphRowView(commit: commit, onSelect: onSelect)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func statusView(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            l10n(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GitGraphRowView: View {
    let commit: GitCommit
    let onSelect: (GitCommit) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            graphRail
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(commit.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    Text(commit.hash.prefix(7))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.75))
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let refName = commit.refName {
                Text(refName)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect(commit)
        }
        .help(commit.hash)
    }

    /// One vertical rail segment with a dot: the list is linear here, so a
    /// plain lane matches `git log`'s first-parent history. The dot aligns
    /// with the subject line (top row), not the row's vertical center.
    private var graphRail: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 1)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
                // Center of the subject line: in the 36pt row the 12pt
                // subject + 10pt hash stack sits ~10.5pt down, so the dot
                // starts 7pt from the top.
                .padding(.top, 7)
        }
    }

    private var relativeDate: String {
        guard let date = commit.date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.launchLanguage == .simplifiedChinese
            ? Locale(identifier: "zh_CN")
            : Locale(identifier: "en_US")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
