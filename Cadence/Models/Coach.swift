import SwiftUI

/// A motivational coach persona surfaced on the home screen.
///
/// Coaches are hardcoded in the app rather than fetched from Langfuse. Their
/// prompts ARE in Langfuse (tagged `coach:<id>`), but the persona — display
/// name, blurb, icon, accent — is content the app owns. That keeps the UI
/// stable when prompts come and go.
struct Coach: Identifiable, Hashable, Sendable {
    /// Slug used as the tag identifier. Prompts for this coach carry the
    /// tag `coach:<id>` (e.g. `coach:marcus`).
    let id: String
    let displayName: String
    let role: String
    let blurb: String
    let systemImage: String
    let accentColor: Color

    /// Tag string used to filter prompts that belong to this coach.
    var tag: String { "coach:\(id)" }
}

/// Hardcoded roster. To add a coach, append here and tag prompts with the
/// matching `coach:<id>` in Langfuse.
enum CoachRoster {
    static let all: [Coach] = [
        Coach(
            id: "marcus",
            displayName: "Marcus",
            role: "Fitness coach",
            blurb: "High-energy, direct, demanding. Pushes you to push yourself.",
            systemImage: "figure.strengthtraining.traditional",
            accentColor: Color(red: 0.95, green: 0.39, blue: 0.18) // warm orange
        ),
        Coach(
            id: "maya",
            displayName: "Maya",
            role: "Meditation guide",
            blurb: "Calm, grounded, breath-paced. Helps you slow down and tune in.",
            systemImage: "leaf",
            accentColor: Color(red: 0.20, green: 0.66, blue: 0.55) // tranquil teal
        ),
    ]
}
