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

    var body: some View {
        Group {
            if let engine {
                PolicyDashboardView(engine: engine)
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
            } else {
                ProgressView("Loading CardioStepRx")
                    .task(loadEngine)
            }
        }
    }

    private func loadEngine() async {
        do {
            engine = try PolicyEngine.live()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
