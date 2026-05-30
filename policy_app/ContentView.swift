//
//  ContentView.swift
//  policy_app
//
//  Created by Gefei Lin on 5/21/26.
//

import SwiftUI

struct ContentView: View {
    @State private var engine: PolicyEngine?
    @State private var loadError: String?
    @State private var isShowingLaunch = true
    @State private var didStart = false

    var body: some View {
        ZStack {
            if isShowingLaunch {
                LaunchLoadingView()
                    .transition(.opacity)
                    .zIndex(1)
            } else if let engine {
                PolicyDashboardView(engine: engine)
                    .transition(.opacity)
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Policy model unavailable")
                        .font(.title2.weight(.bold))
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .transition(.opacity)
            } else {
                LaunchLoadingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isShowingLaunch)
        .task(startApp)
    }

    @MainActor
    private func startApp() async {
        guard !didStart else { return }
        didStart = true

        do {
            engine = try PolicyEngine.live()
        } catch {
            loadError = error.localizedDescription
        }

        try? await Task.sleep(nanoseconds: 2_450_000_000)
        withAnimation(.easeInOut(duration: 0.45)) {
            isShowingLaunch = false
        }
    }
}

private struct LaunchLoadingView: View {
    @State private var artworkScale = 1.04
    @State private var artworkOpacity = 0.0
    @State private var dotsAreActive = false

    var body: some View {
        ZStack {
            Color(red: 0.982, green: 0.988, blue: 0.986)
                .ignoresSafeArea()

            Image("LaunchArtwork")
                .resizable()
                .scaledToFill()
                .scaleEffect(artworkScale)
                .opacity(artworkOpacity)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LaunchSparkleArc()

            VStack {
                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(launchDotColor(for: index))
                            .frame(width: 7, height: 7)
                            .scaleEffect(dotsAreActive ? 1.0 : 0.62)
                            .opacity(dotsAreActive ? 0.95 : 0.45)
                            .animation(
                                .easeInOut(duration: 0.64)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                                value: dotsAreActive
                            )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.white.opacity(0.68), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.82), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.0, green: 0.34, blue: 0.42).opacity(0.08), radius: 18, x: 0, y: 10)
                .accessibilityLabel("Loading CardioStepRx")
                .padding(.bottom, 54)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.82)) {
                artworkScale = 1.0
                artworkOpacity = 1.0
            }
            dotsAreActive = true
        }
    }

    private func launchDotColor(for index: Int) -> Color {
        switch index {
        case 0:
            return Color(red: 0.05, green: 0.43, blue: 0.74)
        case 1:
            return Color(red: 0.18, green: 0.72, blue: 0.60)
        default:
            return Color(red: 0.27, green: 0.55, blue: 0.88)
        }
    }
}

private struct LaunchSparkleArc: View {
    @State private var progress = 0.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(1..<5, id: \.self) { index in
                    Circle()
                        .fill(trailColor(for: index))
                        .frame(width: trailSize(for: index), height: trailSize(for: index))
                        .position(point(for: max(0, progress - Double(index) * 0.052), in: proxy.size))
                        .opacity(progress > Double(index) * 0.052 ? trailOpacity(for: index) : 0)
                        .blur(radius: Double(index) * 0.18)
                }

                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 28, height: 28)
                    .blur(radius: 8)
                    .position(point(for: progress, in: proxy.size))

                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.52, green: 0.94, blue: 0.92),
                                Color(red: 0.05, green: 0.44, blue: 0.77)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 0.06, green: 0.58, blue: 0.72).opacity(0.38), radius: 9, x: 0, y: 2)
                    .rotationEffect(.degrees(progress * 58 - 18))
                    .scaleEffect(CGFloat(0.82 + 0.2 * sin(progress * .pi)))
                    .position(point(for: progress, in: proxy.size))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            progress = 0
            withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }

    private func point(for progress: Double, in size: CGSize) -> CGPoint {
        let clamped = min(max(progress, 0), 1)
        let start = 208.0 * .pi / 180.0
        let end = 332.0 * .pi / 180.0
        let angle = start + (end - start) * clamped
        let radiusX = min(size.width * 0.39, size.height * 0.21)
        let radiusY = radiusX * 0.58
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.32)

        return CGPoint(
            x: center.x + cos(angle) * radiusX,
            y: center.y + sin(angle) * radiusY
        )
    }

    private func trailColor(for index: Int) -> Color {
        index.isMultiple(of: 2)
            ? Color(red: 0.52, green: 0.94, blue: 0.92).opacity(0.9)
            : Color.white.opacity(0.94)
    }

    private func trailSize(for index: Int) -> CGFloat {
        CGFloat(max(4, 12 - index * 2))
    }

    private func trailOpacity(for index: Int) -> Double {
        max(0.16, 0.58 - Double(index) * 0.1)
    }
}

#Preview {
    ContentView()
}
