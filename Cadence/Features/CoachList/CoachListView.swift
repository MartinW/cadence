import SwiftUI

/// Home screen — the user picks a coach.
///
/// Coaches are static (CoachRoster). Their prompts live in Langfuse and are
/// fetched lazily when the user drills into a coach. We don't pre-fetch any
/// prompts here so the app starts up snappy regardless of network state.
struct CoachListView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                ForEach(CoachRoster.all) { coach in
                    NavigationLink(value: coach) {
                        CoachCard(coach: coach)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .navigationTitle("Cadence")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Coach.self) { coach in
            CoachDetailView(coach: coach)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose a coach")
                .font(.title2.weight(.semibold))
            Text("Each coach has a different style and a roster of prompts you can pull up whenever you need them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct CoachCard: View {
    let coach: Coach

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            iconBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(coach.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(coach.role)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(coach.accentColor)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(coach.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.callout.weight(.semibold))
                .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(coach.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(coach.accentColor.opacity(0.15))
            Image(systemName: coach.systemImage)
                .font(.title2)
                .foregroundStyle(coach.accentColor)
        }
        .frame(width: 56, height: 56)
    }
}
