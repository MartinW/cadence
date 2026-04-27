# Cadence

A SwiftUI iOS app that reads your prompts back to you.

Cadence is a consumer of [PromptFlow](https://github.com/MartinW/promptflow) / Langfuse-managed prompts. The app's behaviour is controlled remotely — edit a `voice:*` tagged prompt in PromptFlow, reopen Cadence, the spoken response changes. No App Store resubmission required.

## Status

Working end-to-end on the iOS Simulator: foundation, voice-namespaced prompt list, run flow with streamed audio playback. TestFlight build is the next step.

## Requirements

- Xcode 26+, iOS 18+
- A Langfuse project with at least one prompt tagged `voice` or `voice:*`
- An OpenRouter API key (gives access to `openai/gpt-4o-audio-preview`)

## Setup

```bash
git clone https://github.com/MartinW/cadence.git
cd cadence

# Fill in the build-time secrets file (gitignored).
cp Cadence/Cadence-Secrets.xcconfig.example Cadence/Cadence-Secrets.xcconfig
$EDITOR Cadence/Cadence-Secrets.xcconfig

# Generate the Xcode project.
xcodegen generate
open Cadence.xcodeproj
```

Bundle id: `com.eva.cadence` (set in `project.yml`; change for your own builds).

## How secrets work

Cadence is a personal-use TestFlight-style app, not a multi-user product. Credentials live in `Cadence/Cadence-Secrets.xcconfig` (gitignored), flow into `Info.plist` via `$(VAR)` substitution at build time, and are read at runtime via `AppConfig.shared`. There is no in-app onboarding or Keychain — keys are baked into the build, and the xcconfig keeps them out of source control.

If the build is missing the secrets file, the app shows a "Build-time config missing" screen at launch with instructions for the developer.

## Voice run flow

When you tap a `voice:*` prompt and hit **Speak**, Cadence:

1. Renders the prompt's template (`{{vars}}` substituted, `config.defaults` pre-filled — including PromptFlow's `user_context` convention).
2. Sends the rendered messages to **`openai/gpt-4o-audio-preview`** via OpenRouter, with `modalities: ["text", "audio"]` + `audio: { voice: "alloy", format: "pcm16" }` + `stream: true`.
3. Consumes the SSE stream, accumulating both transcript text and PCM audio chunks. They're produced together by the same call, so transcript and audio are aligned by construction.
4. Wraps the raw PCM bytes in a 44-byte WAV header (so AVAudioPlayer can play them directly without AVAudioEngine plumbing) and plays.

The **Replay** button replays the cached audio without another LLM call.

> **Note:** the original architecture had Claude reasoning + a separate audio-out step. Live testing showed chat models don't have a verbatim-read mode — the audio model always re-thinks rather than narrates Claude's text. So voice runs use a single audio-completion call. Claude remains the choice for non-voice paths in the wider PromptFlow ecosystem.

## Architecture

| Layer | Files |
|---|---|
| App entry | `Cadence/CadenceApp.swift` |
| Build-time config | `Cadence/AppConfig.swift`, `Cadence-Secrets.xcconfig`, `Info.plist` |
| PromptFlowKit (Swift port of `@promptflow/core`) | `PromptFlowKit/LangfuseClient.swift`, `PromptShape.swift`, `TagNamespace.swift`, `TemplateRenderer.swift` |
| Networking | `Networking/OpenRouterClient.swift`, `WAVPacker.swift` |
| Features | `Features/PromptList/`, `Features/Run/` |

## Roadmap

- [x] Project scaffold + Swift 6 strict concurrency build
- [x] Build-time secrets via xcconfig + Info.plist
- [x] Langfuse REST client (read-only)
- [x] Voice-namespaced prompt list with refresh + empty/error states
- [x] PromptRunView — variable form auto-generated from `{{vars}}`, with `config.defaults` pre-fill
- [x] Streaming audio synthesis through OpenRouter; transcript displayed alongside playback
- [x] Replay
- [ ] SwiftData history — list of past invocations, tap to replay
- [ ] App icon
- [ ] TestFlight build

## License

MIT.
