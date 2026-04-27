# Cadence

A SwiftUI iOS app that reads your prompts back to you.

Cadence is a consumer of [PromptFlow](https://github.com/MartinW/promptflow) / Langfuse-managed prompts. The app's behaviour is controlled remotely — edit a `voice:*` tagged prompt in PromptFlow, reopen Cadence, the spoken response changes. No App Store resubmission required.

> 🚧 In active development. The foundation (project, settings, prompt list) is up; the run flow (Claude reasoning + OpenAI audio synthesis via OpenRouter) is the next iteration.

## Requirements

- Xcode 26+, iOS 18+
- A Langfuse project with prompts tagged `voice` or `voice:*`
- An OpenRouter API key

## Setup

```bash
git clone https://github.com/MartinW/cadence.git
cd cadence
xcodegen generate
open Cadence.xcodeproj
```

The first launch prompts for credentials (Langfuse public + secret keys, OpenRouter API key). They're stored in iOS Keychain.

## Architecture

| Layer | Files |
|---|---|
| App entry / routing | `CadenceApp.swift` |
| Settings (creds + Keychain) | `Settings/` + `PromptFlowKit/SecretsStore.swift` |
| PromptFlowKit (Swift port of @promptflow/core) | `PromptFlowKit/LangfuseClient.swift`, `PromptShape.swift`, `TagNamespace.swift`, `TemplateRenderer.swift` |
| Features | `Features/PromptList/` |

## Roadmap

- [x] Project scaffold + Swift 6 strict concurrency build
- [x] Keychain-backed settings
- [x] Langfuse REST client (read-only)
- [x] Voice-namespaced prompt list
- [ ] Run flow — fill variables, call Claude via OpenRouter, stream response
- [ ] Audio synthesis — `openai/gpt-4o-audio-preview` via OpenRouter, AVAudioPlayer playback
- [ ] History (SwiftData) — replay past invocations
- [ ] TestFlight build

## License

MIT.
