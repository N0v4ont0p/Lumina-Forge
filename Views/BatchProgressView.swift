import SwiftUI

// MARK: - Batch Progress View

struct BatchProgressView: View {
    @Binding var isPresented: Bool
    let totalCount: Int
    @State private var completedCount = 0
    @State private var currentFileName = ""
    @State private var isCancelled = false

    var progress: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }

    var body: some View {
        VStack(spacing: 24) {
            header
            progressSection
            statusText
            actionButtons
        }
        .padding(32)
        .frame(width: 480)
        .glassBackgroundEffect()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title)
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text("Batch Export")
                    .font(.headline)
                Text(isCancelled ? "Cancelled" : "Processing images…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)

            HStack {
                Text("\(completedCount) of \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Status Text

    private var statusText: some View {
        Group {
            if !currentFileName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                    Text(currentFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if completedCount < totalCount && !isCancelled {
                Button("Cancel") {
                    isCancelled = true
                }
                .buttonStyle(.glass)
            } else {
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Preview

#Preview {
    BatchProgressView(
        isPresented: .constant(true),
        totalCount: 42
    )
    .padding()
}
