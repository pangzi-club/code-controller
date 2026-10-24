import AppKit
import Combine

/// Settings window content: the appearance section with the theme segmented
/// control. Laid out like a native settings pane — rows pinned to the top
/// edge, no card chrome — so future sections stack below without surgery.
@MainActor
final class SettingsViewController: NSViewController {
    private let settings: SettingsStore
    private var cancellable: AnyCancellable?
    private let segmented = NSSegmentedControl()

    init(settings: SettingsStore) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = NSView()

        let heading = NSTextField(labelWithString: l10n("Appearance"))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let icon = NSImageView(image: symbolImage("circle.lefthalf.filled", pointSize: 15, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        let themeLabel = NSTextField(labelWithString: l10n("Theme"))
        themeLabel.font = .systemFont(ofSize: 13)

        segmented.segmentCount = ThemePreference.allCases.count
        for (index, theme) in ThemePreference.allCases.enumerated() {
            segmented.setLabel(l10n(theme.labelKey), forSegment: index)
        }
        segmented.trackingMode = .selectOne
        segmented.segmentStyle = .automatic
        segmented.target = self
        segmented.action = #selector(themeChanged)
        segmented.widthAnchor.constraint(equalToConstant: 240).isActive = true

        // Leading group hugs left, trailing group hugs right — label left,
        // control right, the classic settings-row alignment.
        let row = NSStackView()
        row.addView(icon, in: .leading)
        row.addView(themeLabel, in: .leading)
        row.addView(segmented, in: .trailing)
        row.spacing = 12

        heading.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heading)
        view.addSubview(row)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            row.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        cancellable = settings.$theme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in self?.syncSegments(theme) }
        syncSegments(settings.theme)
    }

    @objc private func themeChanged() {
        let index = segmented.selectedSegment
        guard ThemePreference.allCases.indices.contains(index) else { return }
        settings.theme = ThemePreference.allCases[index]
    }

    private func syncSegments(_ theme: ThemePreference) {
        let index = ThemePreference.allCases.firstIndex(of: theme) ?? 0
        segmented.setSelected(true, forSegment: index)
    }
}
