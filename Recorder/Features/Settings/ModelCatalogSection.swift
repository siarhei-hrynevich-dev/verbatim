import SwiftUI

/// The wording that tells one catalog from another.
struct ModelCatalogTexts {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let noModelTitle: String
    /// What a model is for, shown when there is nothing to recommend.
    let purpose: String
    let footnote: String
}

/// One catalog of models in the AI Models tab: its notices, its rows, and the removal confirmation. Only reads state;
/// it never performs file or network work and never loads a model.
struct ModelCatalogSection<Model: InstallableModel>: View {
    @Bindable var viewModel: ModelSettingsViewModel<Model>
    let texts: ModelCatalogTexts

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(texts.title)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text(texts.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
            .padding(.horizontal, 2)

            if let notice = viewModel.notice {
                noticeCard(for: notice)
            }
            if let issue = viewModel.storageIssue {
                ModelNoticeCard(icon: .alert, title: issue.title, message: issue.message)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        VerbatimColor.separator
                            .frame(height: 0.5)
                            .padding(.horizontal, 12)
                    }
                    ModelCatalogRow(row: row, viewModel: viewModel)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .groupedBackground()

            SettingsFootnote(text: footnote)
        }
        .sheet(item: $viewModel.removalRequest) { request in
            RemoveModelSheet(request: request, cancel: viewModel.cancelRemoval, remove: viewModel.confirmRemoval)
        }
        .alert(
            viewModel.actionIssue?.title ?? "",
            isPresented: Binding(get: { viewModel.actionIssue != nil }, set: { _ in viewModel.dismissIssue() }),
            presenting: viewModel.actionIssue
        ) { _ in
            Button("OK", action: viewModel.dismissIssue)
        } message: { issue in
            Text(issue.message)
        }
    }

    private var footnote: String {
        guard viewModel.isCatalogOutdated else {
            return texts.footnote
        }
        return String(localized: "Couldn’t reach the model repository, so sizes may be out of date. \(texts.footnote)")
    }

    @ViewBuilder
    private func noticeCard(for notice: ModelSettingsViewModel<Model>.Notice) -> some View {
        switch notice {
        case .noModelInstalled(let recommended):
            ModelNoticeCard(
                icon: .sparkles,
                title: texts.noModelTitle,
                message: noModelMessage(recommended: recommended),
                actionTitle: recommended.map { "Download \($0.name)" },
                action: {
                    if let recommended {
                        viewModel.download(recommended.id)
                    }
                }
            )
        case .noModelSelected:
            ModelNoticeCard(
                icon: .info,
                title: String(localized: "No model selected"),
                message: String(localized: "Choose Select on an installed model.")
            )
        case .selectedModelUnavailable(let model):
            ModelNoticeCard(
                icon: .alert,
                title: String(localized: "“\(model.name)” isn’t available"),
                message: String(
                    localized: """
                        It’s still selected, but its files are missing or damaged. Download it again, or choose \
                        another installed model.
                        """
                ),
                actionTitle: "Repair",
                action: { viewModel.download(model.id) }
            )
        }
    }

    private func noModelMessage(recommended: Model?) -> String {
        guard let recommended else {
            return texts.purpose
        }
        return String(localized: "Nothing downloads until you ask. For this Mac, \(recommended.name) is a good start.")
    }
}

/// Something about a catalog as a whole that needs attention, with at most one action.
struct ModelNoticeCard: View {
    let icon: VerbatimIcon
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(icon, size: 15)
                .foregroundStyle(VerbatimColor.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .lineSpacing(1.5)
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let actionTitle {
                DownloadButton(title: LocalizedStringKey(actionTitle), action: action)
                    .fixedSize()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .groupedBackground()
    }
}
