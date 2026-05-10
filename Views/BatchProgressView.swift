import SwiftUI

// MARK: - Keyframe-Animated Ring Values

/// Holds animatable values for the completion-burst `KeyframeAnimator`.
private struct RingBurstValues {
    var scale: CGFloat    = 1.0
    var glowRadius: CGFloat = 4.0
}

// MARK: - Confetti Particle

private struct ConfettiParticleData: Identifiable {
    let id     = UUID()
    let color:  Color
    let isRect: Bool
    let angle:  Double   // radians
    let radius: CGFloat  // flight distance from centre
    let size:   CGFloat
}

private extension ConfettiParticleData {
    static func makeParticles(count: Int = 38) -> [ConfettiParticleData] {
        let palette: [Color] = [
            .blue, .purple, .pink, .yellow, .mint, .orange, .green, .cyan, .indigo,
        ]
        return (0..<count).map { i in
            ConfettiParticleData(
                color:  palette[i % palette.count],
                isRect: i % 3 == 0,
                angle:  (Double(i) / Double(count)) * 2 * .pi,
                radius: CGFloat.random(in: 70...140),
                size:   CGFloat.random(in: 6...11)
            )
        }
    }
}

// MARK: - Confetti Burst View

/// Expanding burst of coloured shapes centred on the progress ring.
private struct ConfettiBurst: View {
    @State private var expanded = false
    @State private var faded    = false

    private let particles = ConfettiParticleData.makeParticles()

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Group {
                    if p.isRect {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(p.color)
                            .frame(width: p.size, height: p.size * 0.55)
                    } else {
                        Circle()
                            .fill(p.color)
                            .frame(width: p.size, height: p.size)
                    }
                }
                .offset(
                    x: expanded ? cos(p.angle) * p.radius : 0,
                    y: expanded ? sin(p.angle) * p.radius : 0
                )
                .rotationEffect(.degrees(expanded ? p.angle * (180 / .pi) * 2 : 0))
                .opacity(faded ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                expanded = true
            }
            withAnimation(.easeIn(duration: 0.65).delay(0.55)) {
                faded = true
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Batch Progress View

/// Full-screen progress sheet for long-running batch operations.
///
/// ## Visual design (Liquid Glass & Animation Bible)
///
/// - **Circular progress ring**: `Circle().trim()` + `stroke` arc that grows
///   from 0 → 1 as `metadataActor.batchCompleted` increases.  A rotating
///   leading-edge dot gives instant "activity" feedback even before the first
///   completed item.
///
/// - **Completion burst**: a `KeyframeAnimator` scale/glow bounce on the ring
///   fires when the operation finishes, followed by a `ConfettiBurst`.
///
/// - **Live counter**: `contentTransition(.numericText())` makes the fraction
///   numbers roll like an odometer.
///
/// - **Cancellation**: the `Cancel` button calls `metadataActor.cancelBatch()`.
struct BatchProgressView: View {
    @Binding var isPresented: Bool
    @Environment(MetadataActor.self) private var metadataActor

    // MARK: Derived

    private var progress: Double {
        guard metadataActor.batchTotal > 0 else { return 0 }
        return min(Double(metadataActor.batchCompleted) / Double(metadataActor.batchTotal), 1.0)
    }

    private var isComplete: Bool {
        metadataActor.batchTotal > 0
            && metadataActor.batchCompleted >= metadataActor.batchTotal
            && !metadataActor.isBatchRunning
    }

    // MARK: Animation State

    @State private var showConfetti   = false
    @State private var ringRotation: Double = 0
    @State private var previousComplete = false

    // Unified spring
    private let spring = Animation.spring(response: 0.28, dampingFraction: 0.82)

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 28) {
                headerRow
                ringSection
                counterText
                fileNameRow
                actionButtons
            }
            .padding(36)
            .frame(width: 420)

            if showConfetti {
                ConfettiBurst()
                    .frame(width: 320, height: 320)
                    .allowsHitTesting(false)
            }
        }
        .glassBackgroundEffect()
        // Rotate the leading-edge dot continuously while running
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
        // Trigger confetti exactly once when the operation completes
        .onChange(of: isComplete) { _, complete in
            if complete && !previousComplete {
                showConfetti = true
                previousComplete = true
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                .font(.title)
                .foregroundStyle(isComplete ? .green : .blue)
                .symbolEffect(.bounce, value: isComplete)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text("Batch Export")
                    .font(.headline)
                Text(
                    isComplete ? "Export Complete"
                    : metadataActor.isBatchRunning ? "Processing…"
                    : "Preparing…"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(spring, value: isComplete)
            }
            Spacer()
        }
    }

    // MARK: - Ring Section

    private var ringSection: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(.quaternary, lineWidth: 10)
                .frame(width: 130, height: 130)

            // Progress arc with KeyframeAnimator burst on completion
            KeyframeAnimator(
                initialValue: RingBurstValues(),
                trigger: isComplete
            ) { values in
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .fill(AngularGradient(
                        colors: [.blue, .purple, .accentColor],
                        center: .center
                    ))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 130, height: 130)
                    .scaleEffect(values.scale)
                    .shadow(color: .accentColor.opacity(0.6), radius: values.glowRadius)
                    .animation(spring, value: progress)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1.0,  duration: 0.00)
                    SpringKeyframe(1.18, duration: 0.22, spring: .bouncy)
                    SpringKeyframe(0.96, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1.04, duration: 0.14, spring: .bouncy)
                    SpringKeyframe(1.0,  duration: 0.12, spring: .smooth)
                }
                KeyframeTrack(\.glowRadius) {
                    LinearKeyframe(4,  duration: 0.00)
                    LinearKeyframe(22, duration: 0.35)
                    LinearKeyframe(4,  duration: 0.35)
                }
            }

            // Rotating leading-edge dot (visible while running)
            if !isComplete {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .offset(y: -65)
                    .rotationEffect(.degrees(ringRotation + CGFloat(progress) * 360 - 90))
                    .shadow(color: .accentColor.opacity(0.8), radius: 6)
            }

            // Centre label
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(spring, value: progress)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Counter Text

    private var counterText: some View {
        HStack(spacing: 4) {
            Text("\(metadataActor.batchCompleted)")
                .font(.body.bold().monospacedDigit())
                .contentTransition(.numericText())
                .animation(spring, value: metadataActor.batchCompleted)

            Text("of \(metadataActor.batchTotal) images")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File Name Row

    private var fileNameRow: some View {
        Group {
            if !metadataActor.currentProcessingFile.isEmpty && !isComplete {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse)
                    Text(metadataActor.currentProcessingFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .animation(spring, value: metadataActor.currentProcessingFile)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if isComplete {
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button("Cancel") {
                    Task { await metadataActor.cancelBatch() }
                }
                .buttonStyle(.glass)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(spring, value: isComplete)
    }
}

// MARK: - Preview

#Preview {
    BatchProgressView(isPresented: .constant(true))
        .environment(MetadataActor())
        .padding()
}
