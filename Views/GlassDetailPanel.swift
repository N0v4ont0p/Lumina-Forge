import SwiftUI

// MARK: - Glass Detail Panel

struct GlassDetailPanel: View {
    let asset: ImageAsset?
    /// Namespace shared with `GlassGridView` / `GlassCard` for hero thumbnail transitions.
    var heroNamespace: Namespace.ID

    @Environment(MetadataActor.self) private var metadataActor

    // MARK: Edit mode state
    @State private var isEditing       = false
    @State private var editedMetadata  = MetadataModel()

    // MARK: Alerts
    @State private var showStripAlert  = false
    @State private var showErrorAlert  = false
    @State private var errorMessage    = ""

    // Unified spring per master plan
    private let spring = Animation.spring(response: 0.28, dampingFraction: 0.82)

    // MARK: - Body

    var body: some View {
        Group {
            if let asset {
                detailContent(for: asset)
                    .id(asset.id)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .top)
                                .combined(with: .opacity),
                            removal: .opacity.animation(.easeOut(duration: 0.14))
                        )
                    )
                    // Keyboard shortcut: ⌘Z to undo last metadata write
                    .background(
                        Button("") {
                            Task { try? await metadataActor.undo(for: asset) }
                        }
                        .keyboardShortcut("z", modifiers: .command)
                        .hidden()
                    )
            } else {
                placeholderView
            }
        }
        .animation(spring, value: asset?.id)
        .glassBackgroundEffect()
        // Strip-metadata confirmation
        .alert("Strip All Metadata?", isPresented: $showStripAlert) {
            Button("Strip", role: .destructive) {
                guard let a = asset else { return }
                Task {
                    do    { try await metadataActor.stripAllMetadata(from: a) }
                    catch {
                        errorMessage  = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all EXIF, IPTC, and XMP data from the file on disk. " +
                 "An in-session undo entry will be pushed, but the original data cannot be recovered " +
                 "after the app quits.")
        }
        // Write-error alert
        .alert("Metadata Write Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(for asset: ImageAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                thumbnailHeader(for: asset)
                metadataSection(for: asset)
                if isEditing {
                    editIPTCSection(for: asset)
                } else {
                    exifSection(for: asset)
                    iptcSection(for: asset)
                    actionButtons(for: asset)
                }
            }
            .padding(20)
        }
        .navigationTitle(asset.fileName)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Undo button (⌘Z also bound below)
                Button {
                    Task { try? await metadataActor.undo(for: asset) }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .help("Undo last metadata write (⌘Z)")
                .keyboardShortcut("z", modifiers: .command)

                // Edit / Done toggle
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        // Commit edits
                        let snapshot = editedMetadata
                        Task {
                            do    { try await metadataActor.writeMetadata(snapshot, to: asset) }
                            catch {
                                errorMessage   = error.localizedDescription
                                showErrorAlert = true
                            }
                        }
                    } else {
                        // Snapshot current metadata for editing
                        editedMetadata = asset.metadata ?? MetadataModel()
                    }
                    withAnimation(spring) { isEditing.toggle() }
                }
                .buttonStyle(.borderedProminent)
                .tint(isEditing ? .green : .accentColor)
            }
        }
    }

    // MARK: - Thumbnail Header

    private func thumbnailHeader(for asset: ImageAsset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
            if let thumbnail = asset.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(8)
                    .matchedGeometryEffect(
                        id: "thumb_\(asset.id)",
                        in: heroNamespace,
                        isSource: false
                    )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 240)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metadata Section (File Info)

    private func metadataSection(for asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("File Info")
            metadataRow("File Name",     value: asset.fileName)
            metadataRow("File Size",     value: asset.formattedFileSize)
            metadataRow("Dimensions",    value: asset.formattedDimensions)
            metadataRow("Date Modified", value: asset.formattedDate)
        }
    }

    // MARK: - EXIF Section

    private func exifSection(for asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("EXIF Data")
            if let m = asset.metadata {
                metadataRow("Camera",        value: [m.cameraMake, m.cameraModel].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? "—")
                metadataRow("Lens",          value: m.lensModel ?? "—")
                metadataRow("ISO",           value: m.formattedISO)
                metadataRow("Aperture",      value: m.formattedAperture)
                metadataRow("Shutter Speed", value: m.formattedShutterSpeed)
                metadataRow("Focal Length",  value: m.formattedFocalLength)
                metadataRow("White Balance", value: m.whiteBalance ?? "—")
                metadataRow("Flash",         value: m.flash ?? "—")
                metadataRow("Exposure Mode", value: m.exposureMode ?? "—")
                if m.formattedGPS != "—" {
                    metadataRow("GPS", value: m.formattedGPS)
                }
            } else {
                Text("No EXIF data available.")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            }
        }
    }

    // MARK: - IPTC Section (read-only view)

    private func iptcSection(for asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("IPTC / XMP")
            if let m = asset.metadata {
                metadataRow("Title",     value: m.title ?? "—")
                metadataRow("Headline",  value: m.headline ?? "—")
                metadataRow("Caption",   value: m.caption ?? m.imageDescription ?? "—")
                metadataRow("Copyright", value: m.copyright ?? "—")
                metadataRow("Creator",   value: m.creator ?? "—")
                metadataRow("Credit",    value: m.credit ?? "—")
                metadataRow("Source",    value: m.source ?? "—")
                metadataRow("Keywords",  value: m.keywords?.joined(separator: ", ") ?? "—")
                metadataRow("Rating",    value: m.rating.map { "\($0) ★" } ?? "—")
                if let city = m.city { metadataRow("City", value: city) }
                if let country = m.country { metadataRow("Country", value: country) }
            } else {
                Text("No IPTC/XMP data available.")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            }
        }
    }

    // MARK: - Edit IPTC Section

    @ViewBuilder
    private func editIPTCSection(for asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Edit IPTC / XMP")

            editField("Title",     text: Binding(
                get: { editedMetadata.title ?? "" },
                set: { editedMetadata.title = $0.isEmpty ? nil : $0 }
            ))
            editField("Caption", text: Binding(
                get: { editedMetadata.caption ?? "" },
                set: { editedMetadata.caption = $0.isEmpty ? nil : $0 }
            ))
            editField("Copyright", text: Binding(
                get: { editedMetadata.copyright ?? "" },
                set: { editedMetadata.copyright = $0.isEmpty ? nil : $0 }
            ))
            editField("Creator", text: Binding(
                get: { editedMetadata.creator ?? "" },
                set: { editedMetadata.creator = $0.isEmpty ? nil : $0 }
            ))
            editField("Credit", text: Binding(
                get: { editedMetadata.credit ?? "" },
                set: { editedMetadata.credit = $0.isEmpty ? nil : $0 }
            ))
            editField("Keywords (comma-separated)", text: Binding(
                get: { editedMetadata.keywords?.joined(separator: ", ") ?? "" },
                set: {
                    let kws = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    editedMetadata.keywords = kws.isEmpty ? nil : kws
                }
            ))
            editField("City", text: Binding(
                get: { editedMetadata.city ?? "" },
                set: { editedMetadata.city = $0.isEmpty ? nil : $0 }
            ))
            editField("Country", text: Binding(
                get: { editedMetadata.country ?? "" },
                set: { editedMetadata.country = $0.isEmpty ? nil : $0 }
            ))

            // Rating stepper
            HStack {
                Text("Rating")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Stepper("\(editedMetadata.rating ?? 0) ★", value: Binding(
                    get: { editedMetadata.rating ?? 0 },
                    set: { editedMetadata.rating = $0 == 0 ? nil : $0 }
                ), in: 0...5)
            }

            // Destructive strip button at the bottom of edit mode
            Divider()

            Button(role: .destructive) {
                isEditing = false
                showStripAlert = true
            } label: {
                Label("Strip All Metadata…", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .foregroundStyle(.red)
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    // MARK: - Action Buttons (read-only mode)

    private func actionButtons(for asset: ImageAsset) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await metadataActor.toggleFavorite(asset) }
                } label: {
                    Label(
                        asset.isFavorite ? "Remove Favorite" : "Add Favorite",
                        systemImage: asset.isFavorite ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.glass)

                Button {
                    Task { await metadataActor.addToExportQueue(asset) }
                } label: {
                    Label("Export", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.glass)
            }

            // Strip button in read-only mode too (less prominent)
            Button(role: .destructive) {
                showStripAlert = true
            } label: {
                Label("Strip All Metadata…", systemImage: "trash")
                    .font(.callout)
            }
            .buttonStyle(.glass)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.bottom, 2)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func editField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse)
            Text("Select an Image")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            Text("Choose an image from the grid to view its metadata.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Private Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
