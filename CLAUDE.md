# CLAUDE.md — HandController

## What This Is

iOS app that connects to **Meta Ray-Ban smart glasses** via the [Meta Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios) (DAT SDK), streams the glasses' camera feed, and detects hand gestures in real-time using Apple's Vision framework. Gesture events are sent to [Home Center](https://github.com/phdev/home-center) as notifications via its Cloudflare Worker API.

## Detected Gestures

| Gesture | Detection Method |
|---------|-----------------|
| Thumb Swipe Left / Right / Up / Down | Temporal thumb tip tracking over ~0.5s window (0.08 displacement, 6-frame window) |
| Index finger + thumb pinch | Spatial proximity (thumb tip to index tip < 0.06 normalized) |
| Middle finger + thumb pinch | Spatial proximity (thumb tip to middle tip < 0.06 normalized) |

## Architecture

```
HandControllerApp.swift              ← App entry, DAT SDK init (Wearables.configure()),
                                       URL callback for Meta AI OAuth
Models/
  HandLandmark.swift                 ← DetectedHand (chirality + 21 joints), HandGesture enum,
                                       HandSkeleton (bone connections for overlay drawing)
  GestureEvent.swift                 ← Event model with home-center notification payload format

Services/
  HandPoseDetector.swift             ← Vision VNDetectHumanHandPoseRequest, supports both
                                       UIImage and CVPixelBuffer input, 0.3 confidence threshold
  GestureClassifier.swift            ← Pinch detection (instantaneous) + thumb swipe detection
                                       (temporal, thumbTip) + wave detection (temporal, wrist),
                                       per-hand tracking, 1s cooldown between gestures
  HomeCenterClient.swift             ← Actor, POSTs to /api/notifications, 2s throttle per gesture
                                       type, auth token from Secrets.plist, wake word recording API

ViewModels/
  WearablesViewModel.swift           ← DAT SDK device registration/discovery, async streams
  StreamViewModel.swift              ← Pipeline: DAT frames → CVPixelBuffer → Vision → classify → UI + home-center

Views/
  ConnectionView.swift               ← Pre-registration screen (connect glasses button)
  NonStreamView.swift                ← Post-registration, pre-streaming (start button)
  StreamingView.swift                ← Camera feed + HUD (FPS, hand count, gesture chips)
  HandOverlayView.swift              ← Canvas-drawn skeleton (cyan = left, orange = right)
  DebugPanelView.swift               ← Event log, home-center settings, health check, tools
  WakeRecordView.swift               ← Wake word sample recording UI (controls Pi recording via worker API)
  EnrollmentListView.swift           ← Lists enrolled wake words with delete, entry point for new enrollments
  EnrollmentFlowView.swift           ← New enrollment flow: name/page setup → recording → success
  MockDeviceMenuView.swift           ← DEBUG-only mock device pairing UI (replaces removed MockDeviceKitView)
```

## Dependencies

Single SPM package: `https://github.com/facebook/meta-wearables-dat-ios` (v0.4.0)
- **MWDATCore** — `Wearables`, `WearablesInterface`, `Permission`, registration
- **MWDATCamera** — `StreamSession`, `VideoFrame`, `StreamSessionConfig`, `AutoDeviceSelector`
- **MWDATMockDevice** — Debug-only mock device for testing without physical glasses

## Build Requirements

- iOS 17.0+ (required for `VNHumanHandPoseObservation.chirality`)
- Xcode 15+, Swift 5
- Two user-defined build settings: `META_APP_ID` and `CLIENT_TOKEN` (from Meta Developer Portal)

## Info.plist Keys

- `MWDAT` dict: `AppLinkURLScheme` (handcontroller://), `MetaAppId`, `ClientToken`
- `NSBluetoothAlwaysUsageDescription` — glasses connect via Bluetooth
- `UISupportedExternalAccessoryProtocols` — `com.meta.ar.wearable`
- `UIBackgroundModes` — `bluetooth-peripheral`, `external-accessory`
- URL scheme: `handcontroller` (Meta AI OAuth callback)

## Home Center Integration

Gesture events are sent directly to the Pi's HTTP server over local WiFi:

```
POST http://192.168.1.162:8765/gesture
{
  "id": "gesture_a1b2c3d4",
  "type": "gesture",
  "category": "activities",
  "icon": "🤏",
  "title": "Right Hand: Index-Thumb Pinch",
  "from": "HandController",
  "timestamp": 1709312400000
}
```

No auth token needed (local network). Events send automatically on launch. Configure in the debug panel (ladybug icon → Home Center Integration section).

## Wake Word Recording

The app includes a wake word sample recording tool (Debug panel → Tools → Record Wake Word Samples) that controls the Pi's recording directly via its HTTP server (not the Cloudflare Worker):

```
Pi HTTP server: http://homecenter.local:8765
GET  /status                              → current state
POST /toggle  {"type": "positive"}        → start/stop recording
POST /reset                               → zero all counts
POST /clear                               → zero counts + delete saved audio files
→ All endpoints return: {"active", "type", "count", "totalPositive", "totalNegative"}
```

- Pi response is the single source of truth — no local state tracking or optimistic updates
- Segmented control sets sample type locally (used in /toggle POST body)
- Toggle button POSTs /toggle, updates all UI from response
- Polls every 2s while active via GET /status; stops when active is false
- On appear, one GET /status to initialize UI state
- Circular progress gauges show cumulative totals with a goal of 50 each
- Reset Totals zeroes counters only; Clear Recordings (destructive, with confirmation) also deletes audio
- Requires NSAllowsLocalNetworking in Info.plist for plain HTTP to local Pi
- Pi plays ascending chime on start, beep per saved clip, descending tone on stop

## Wake Word Enrollment

Custom wake word enrollment for family members (Debug panel → Tools → Wake Word Training):

```
Pi HTTP server: http://192.168.1.162:8765
POST /api/enrollments              → start enrollment {name, action, target}
GET  /api/enrollments              → list all enrolled wake words
GET  /api/enrollment-status        → poll recording state {state, name, elapsed, buffer_seconds}
POST /api/enrollments/{name}/delete → delete an enrollment
POST /api/enrollment-stop          → cancel in-progress enrollment
```

- States: idle → waiting (listening) → recording (speech detected) → processing (extracting embeddings) → idle (done)
- Pi microphone does all audio capture — app just triggers and monitors via HTTP
- Polls every 500ms during recording; auto-completes when Pi returns to idle
- 10s timeout if stuck in "waiting" with no speech detected
- Cancel button sends enrollment-stop to abort

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| Pinch threshold | 0.06 (normalized) | `GestureClassifier` |
| Thumb swipe min displacement | 0.08 (normalized) | `GestureClassifier` |
| Thumb swipe window | 6 frames | `GestureClassifier` |
| Thumb swipe direction ratio | 1.8 | `GestureClassifier` |
| Thumb swipe cooldown | 1.0s | `GestureClassifier` |
| Throttle interval | 2.0s per gesture type | `HomeCenterClient` |
| Stream resolution | Low | `StreamViewModel` |
| Frame rate | 7 fps | `StreamViewModel` |
| Joint confidence | 0.3 minimum | `HandPoseDetector` |
| Max event history | 50 events | `StreamViewModel` |
