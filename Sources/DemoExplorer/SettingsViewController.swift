import AppKit
import Combine

/// Settings detail page: appearance card with the theme segmented control.
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

        let pageTitle = NSTextField(labelWithString: l10n("Settings"))
        pageTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        pageTitle.textColor = .labelColor

        let heading = NSTextField(labelWithString: l10n("Appearance"))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let card = NSBox()
        card.boxType = .custom
        card.borderWidth = 1
        card.borderColor = .separatorColor
        card.cornerRadius = 10
        card.fillColor = .controlBackgroundColor
        card.contentViewMargins = NSSize(width: 16, height: 14)

        let icon = NSImageView(image: symbolImage("circle.lefthalf.filled", pointSize: 15, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        let themeLabel = NSTextField(labelWithString: l10n("Theme"))
        themeLabel.font = .systemFont(ofSize: 13, weight: .medium)

        segmented.segmentCount = ThemePreference.allCases.count
        for (index, theme) in ThemePreference.allCases.enumerated() {
            segmented.setLabel(l10n(theme.labelKey), forSegment: index)
        }
        segmented.trackingMode = .selectOne
        segmented.segmentStyle = .automatic
        segmented.target = self
        segmented.action = #selector(themeChanged)
        segmented.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let row = NSStackView()
        row.addView(icon, in: .leading)
        row.addView(themeLabel, in: .leading)
        row.addView(segmented, in: .trailing)
        row.spacing = 12
        card.contentView = row

        let cardHost = ShadowContainer(content: card)
        pageTitle.translatesAutoresizingMaskIntoConstraints = false
        heading.translatesAutoresizingMaskIntoConstraints = false
        cardHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageTitle)
        view.addSubview(heading)
        view.addSubview(cardHost)
        NSLayoutConstraint.activate([
            pageTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            pageTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            heading.topAnchor.constraint(equalTo: pageTitle.bottomAnchor, constant: 16),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            cardHost.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            cardHost.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardHost.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            cardHost.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
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
