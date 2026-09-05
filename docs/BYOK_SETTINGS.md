# BYOK Settings Screen — Scope

**Status:** Approved by Darren, Sept 4 2026. Built & verified.
**Branch:** `claude/notion-big-idea-page-40ncza`

## Decisions (locked)

| Question | Answer |
|---|---|
| Providers in v1 | **All of them** — OpenAI, Anthropic, Gemini, Grok, Ollama, plus Off (local heuristics). Picker is a full list, not a binary. |
| Home | A real **Settings** tab — not the Profile tab. Profile = identity; Settings = configuration. |
| Timing | Built immediately alongside the Free Ride fix. |
| Spotify group listening | Synced playback routed through the existing AI companion — no standalone sync. |

## What it is

A dedicated Settings tab containing:
1. **Companion AI** card:
   - Provider picker: OpenAI, Anthropic, Gemini, Grok, Ollama, Off.
   - API key field, secure entry, with a **Test** button that fires one tiny request and shows check or error text.
   - Base URL field for Ollama (defaults to `http://localhost:11434`), hidden for cloud providers.
   - Model picker, populated per provider from a curated list with a free-text override.
   - Status summary: "Active Brain: {provider} · {model}" or "Active Brain: Built-in rules".
2. **Ride Together** quick replies configuration.
3. **Music** connection status (Spotify / Apple Music).
4. **Debug Log** and **About** version info.

## Storage

- Key → Keychain (`CompanionSettingsStore`).
- Provider + model + baseURL → UserDefaults.
- Nothing syncs via CloudKit. A pasted key never leaves the device except to its own provider.

## How Free Ride uses it

`AIRecommendationService` resolution order: user-configured key → bundle key → local fallback.
Discover panel footer in fallback mode: "Using built-in picks. Add an AI key in Settings for smarter ones."

## Out of v1

- Live model listing from provider endpoints.
- Per-feature key overrides.
- Sharing the key to Supabase for other apps (Big Idea question — separate conversation).

