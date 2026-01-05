# AGENTS.md

## Runbook: last error image from knowledge graph

Trigger: CTLIMG

1) Fetch the node info and extract the image URL (developer error graph):
```
curl -s "https://knowledge.vegvisr.org/getknowgraph?id=graph_1767334024408" | jq '.nodes[].info'
```

2) Download the image to a local file:
```
curl -L -o /tmp/vegvisr_error.jpg "<IMAGE_URL>"
```

3) Read the image to extract the error text:
- Open the image locally and read the visible error message.

## Runbook: Flutter AI image errors (Gemini/OpenAI/Grok)

1) Confirm the AI provider in Settings:
- Settings → Enable AI Chat = ON
- Settings → AI Provider = OpenAI, Gemini, or Grok

2) Confirm the AI Assistant panel exists in both screens:
- Create Graph: `hallo_vegvisr/lib/screens/create_graph_screen.dart`
- Edit Graph: `hallo_vegvisr/lib/screens/edit_graph_screen.dart`
- Look for the "Generate image" button.

3) OpenAI image flow (worker):
- Endpoint: `https://openai.vegvisr.org/images`
- Code: `hallo_vegvisr/lib/services/ai_chat_service.dart` → `generateOpenAiImage()`

4) Gemini image flow (Firebase AI):
- Use Imagen model, not `generateContent`.
- Code: `hallo_vegvisr/lib/screens/create_graph_screen.dart` and
  `hallo_vegvisr/lib/screens/edit_graph_screen.dart`
- Model: `imagen-3.0-generate-002`

5) Grok image flow (worker):
- Endpoint: `https://grok.vegvisr.org/images`
- Code: `hallo_vegvisr/lib/services/ai_chat_service.dart` → `generateGrokImage()`
- Model: `grok-2-image`
- Returns JPG format from `imgen.x.ai`

## Runbook: upload APK to R2

Trigger: UPLOADAPK

Command:
```
cd /Users/torarnehave/Documents/GitHub/vegvisr-frontend && npx wrangler r2 object put mobile-apps/hallo-vegvisr-v1.1.0-push-notifications.apk --file=/Users/torarnehave/Documents/GitHub/hellovegvisr-flutte/hallo_vegvisr/build/app/outputs/flutter-apk/app-release.apk --remote
```
