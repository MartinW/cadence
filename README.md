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

# Fill in the build-time secrets file. The committed copy has empty
# placeholders; mark it skip-worktree so your real keys don't get pushed.
git update-index --skip-worktree Cadence/Cadence-Secrets.xcconfig
$EDITOR Cadence/Cadence-Secrets.xcconfig

# Generate the Xcode project.
xcodegen generate
open Cadence.xcodeproj
```

Bundle id: `com.eva.cadence` (set in `project.yml`; change for your own builds).

## How secrets work

Cadence is a personal-use TestFlight-style app, not a multi-user product. Credentials live in `Cadence/Cadence-Secrets.xcconfig` (committed with empty placeholders; local copy is `skip-worktree`'d so real keys stay off GitHub), flow into `Info.plist` via `$(VAR)` substitution at build time, and are read at runtime via `AppConfig.shared`. There is no in-app onboarding or Keychain — keys are baked into the build.

If the build is missing the secrets file, the app shows a "Build-time config missing" screen at launch with instructions for the developer.

### Why this pattern (and its sharp edge)

The xcconfig file is **committed**, not gitignored. The earlier `.example`-template pattern was structurally safer (template committed, real file gitignored, no way to leak), but it required a `cp` step on every clone. We collapsed it to a single committed file with empty placeholders + `skip-worktree` for the local edit.

Trade-off: `skip-worktree` is local-only metadata. It does not propagate. Anyone cloning fresh has the flag unset by default, and one `git add -A` (or any tool that bypasses status, like some IDE auto-commit features) can stage real keys. Mitigations:

- After populating real keys, **always** run `git update-index --skip-worktree Cadence/Cadence-Secrets.xcconfig` before any `git add`.
- Verify with `git ls-files -v | grep '^S'` — the `S` prefix means skip-worktree is set.
- To temporarily un-skip (e.g. to commit a structural change to the file like a new key):
  ```bash
  git update-index --no-skip-worktree Cadence/Cadence-Secrets.xcconfig
  # edit the placeholder template, commit
  git update-index --skip-worktree Cadence/Cadence-Secrets.xcconfig
  ```
- Treat the keys as **rotatable**. If they ever surface in `git status` or a transcript, rotate at the provider (Langfuse / OpenRouter dashboards) rather than trying to scrub history.

### Adding a new secret key

1. Un-skip-worktree the file.
2. Add `NEW_KEY =` (empty) to `Cadence/Cadence-Secrets.xcconfig`.
3. Add a corresponding `<key>CadenceNewKey</key><string>$(NEW_KEY)</string>` entry to `Cadence/Info.plist`.
4. Add the `let newKey: String` field + `read(info, "CadenceNewKey")` line to `AppConfig.swift`. Add it to `isConfigured`'s required-keys list if it must be non-empty.
5. Commit (with the empty placeholder).
6. Re-skip-worktree the file and paste the real value locally.

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
