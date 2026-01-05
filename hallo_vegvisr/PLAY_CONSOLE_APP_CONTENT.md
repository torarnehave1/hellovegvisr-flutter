    Play Console App Content (Step 2)

    1) Privacy policy
    - URL: https://www.vegvisr.org/privacy (if different, replace with your live policy URL).
    - Notes to ensure the policy covers:
    - Data collected: phone number (login), user ID, AI chat prompts/responses, knowledge graph content, image uploads, voice recordings/transcripts, device identifiers for push notifications.
    - Data use: authentication, syncing graphs, AI features, image generation/analysis, voice transcription, push notifications.
    - Data sharing: service providers (Firebase, OpenAI, xAI/Grok, storage/CDN), only as needed to deliver features.
    - Retention/deletion: describe how users can request deletion and how long data is stored.

    2) Data safety
    - Data collected (best-effort based on current app features):
    - Personal info: phone number (for login).
    - User content: knowledge graph content, AI chat messages, image prompts/results, uploaded images.
    - Audio: voice recordings and transcripts (when using voice input).
    - Device/diagnostics: device identifiers for push notifications, crash/diagnostic data (Firebase).
    - Data shared:
    - Yes. With service providers to deliver features:
        - Firebase (messaging/notifications, possibly analytics/crash reporting if enabled).
        - OpenAI and xAI/Grok for AI/image features (when selected by user).
        - Storage/CDN for uploaded images and audio files.
    - Data required vs optional:
    - Required: phone number (login), knowledge graph content (core feature), device token (push notifications).
    - Optional: AI prompts, image generation, voice input, image analysis.
    - Data processing:
    - In transit is encrypted (HTTPS).
    - No sale of personal data.
    - If any of the above is not accurate, adjust to match production behavior.

    3) Ads declaration
    - App contains ads: No.
    - Families policy: Not applicable (no ads, not targeting children).

    4) Target audience and content
    - Target age groups: 18+ (or 13+ if you want teen access; avoid under 13 unless required).
    - App content: user-generated notes, AI-generated text/images, and voice input.
    - If targeting 13–17: confirm no restricted content and add appropriate safeguards.

    5) Content rating
    - Likely rating: Everyone / PEGI 3 (adjust if you allow user-generated content or image generation without moderation).
    - IARC questionnaire guidance:
    - No violence, sexual content, gambling, or profanity by default.
    - User-generated content: Yes (AI chat + notes), so answer accordingly.
    - Online interaction: Yes (user data stored, AI services).
    - Location sharing: No (unless you add it).
