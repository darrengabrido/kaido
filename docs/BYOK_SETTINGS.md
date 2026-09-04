# BYOK Settings — Scope

**Status:** Approved Sept 4, 2026 (Darren, via voice)
**Owner:** Fable

## Decision
- Build a dedicated **Settings** tab (not Profile).
- Full provider roster in v1: **Gemini, Grok, Anthropic, Ollama**, plus OpenAI and Off.
- Apply to both: the BYOK settings screen itself, and Spotify group listening routed through the AI companion.

## What to build
1. New Settings tab in the tab bar (or reachable from Profile → Settings).
2. **AI** card: provider picker (full roster), secure API key field, **Test** button (fires one tiny request, shows check or error), model picker per provider with free-text override.
3. Status line: "Free Ride is using {provider} · {model}" or "using built-in suggestions."
4. Storage: key in Keychain (generalize the existing Spotify token store), provider + model in UserDefaults. Nothing syncs via CloudKit. Key never leaves the device except to its own provider.
5. `AIRecommendationService`: user-configured key first, bundle key second, local fallback third.
6. Spotify group listening: synced playback routed through the existing AI companion — no standalone sync.

## Out of v1
- Live model listing
- Per-feature key overrides
- Sharing the key to Supabase for other apps (Big Idea question, separate conversation)

## Size estimate
~400 lines, one PR, no schema or backend changes. Unit tests for the store and provider selection logic.
