# BYOK Settings Screen — Scope

**Status:** Approved by Darren, Sept 4 2026. Build now.
**Branch:** `claude/notion-big-idea-page-40ncza` (same as Free Ride fix)

## Decisions (locked)

| Question | Answer |
|---|---|
| Providers in v1 | **All of them** — OpenAI, Anthropic, Gemini, Grok, Ollama, plus Off (local heuristics). Picker is a full list, not a binary. |
| Home | A real **Settings** tab — not the Profile tab. Profile = identity; Settings = configuration. |
| Timing | Build **now**, alongside the Free Ride fix. Don't wait on device testing. |

## What it is

A Settings tab containing an **AI** card:
1. **Provider** picker: OpenAI, Anthropic, Gemini, Grok, Ollama, Off.
2. **API key** field, secure entry, with a **Test** button that fires one tiny request and shows check or error text.
3. **Model** picker, populated per provider from a short hard-coded list with a free-text override. No live model listing in v1.
4. One-line status: "Free Ride is using OpenAI · gpt-4o-mini" or "Free Ride is using built-in suggestions."

## Storage

- Key → Keychain (generalize the existing Spotify token store).
- Provider + model → UserDefaults.
- Nothing syncs via CloudKit. A pasted key never leaves the device except to its own provider.

## How Free Ride uses it

`AIRecommendationService` resolution order: user-configured key → bundle key → local fallback.
Discover panel footer in fallback mode: "Using built-in picks. Add an AI key in Settings for smarter ones."

## Size estimate

One settings view, one Keychain wrapper, one settings store, a provider enum, edits to the recommendation service and panel. Roughly 400–500 lines (grows with the full roster), one PR, no schema or backend changes. Unit tests for the store and provider selection logic.

## Out of v1

- Live model listing
- Per-feature key overrides
- Sharing the key to Supabase for other apps (Big Idea question — separate conversation)

## Open follow-ups

- Ollama needs a base-URL field (local endpoint), unlike cloud providers.
- Grok and Gemini auth shapes differ slightly from OpenAI — confirm request builders per provider.
