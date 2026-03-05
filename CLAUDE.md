# CLAUDE.md — HandController

## What This Is

iOS app that connects to **Meta Ray-Ban smart glasses** via the [Meta Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios) (DAT SDK), streams the glasses' camera feed, and detects hand gestures in real-time using Apple's Vision framework. Gesture events are sent to [Home Center](https://github.com/phdev/home-center) as notifications via its Cloudflare Worker API.

## Detected Gestures

| Gesture | Detection Method |
|---------|-----------------|
| Wave Left / Right / Up / Down | Temporal wrist position tracking over ~0.6s window |
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
  GestureClassifier.swift            ← Pinch detection (instantaneous) + wave detection (temporal),
                                       per-hand tracking, 1s cooldown between waves
  HomeCenterClient.swift             ← Actor, POSTs to /api/notifications, 2s throttle per gesture
                                       type, configurable auth token

ViewModels/
  WearablesViewModel.swift           ← DAT SDK device registration/discovery, async streams
  StreamViewModel.swift              ← Pipeline: DAT frames → CVPixelBuffer → Vision → classify → UI + home-center

Views/
  ConnectionView.swift               ← Pre-registration screen (connect glasses button)
  NonStreamView.swift                ← Post-registration, pre-streaming (start button)
  StreamingView.swift                ← Camera feed + HUD (FPS, hand count, gesture chips)
  HandOverlayView.swift              ← Canvas-drawn skeleton (cyan = left, orange = right)
  DebugPanelView.swift               ← Event log, home-center settings, health check
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

Gesture events are sent as notifications to the Cloudflare Worker at `home-center-api.phhowell.workers.dev`:

```
POST /api/notifications
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

Auth: `Authorization: Bearer <AUTH_TOKEN>` (same token as worker's `AUTH_TOKEN` secret). Enable and configure in the debug panel (ladybug icon → Home Center Integration section).

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| Pinch threshold | 0.06 (normalized) | `GestureClassifier` |
| Wave min displacement | 0.15 (normalized) | `GestureClassifier` |
| Wave window | 8 frames | `GestureClassifier` |
| Wave cooldown | 1.0s | `GestureClassifier` |
| Throttle interval | 2.0s per gesture type | `HomeCenterClient` |
| Stream resolution | Low | `StreamViewModel` |
| Frame rate | 15 fps | `StreamViewModel` |
| Joint confidence | 0.3 minimum | `HandPoseDetector` |
| Max event history | 50 events | `StreamViewModel` |
