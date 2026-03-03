# HandController

iOS app that detects hand gestures in real-time using Meta Ray-Ban smart glasses and Apple's Vision framework, then sends gesture events to [Home Center](https://github.com/phdev/home-center) for home automation control.

## What This Project Does

1. Connects to Meta Ray-Ban glasses via the [Meta Device Access Toolkit (DAT) SDK](https://github.com/facebook/meta-wearables-dat-ios)
2. Streams live video frames from the glasses camera
3. Processes each frame with `VNDetectHumanHandPoseRequest` to detect up to 2 hands (21 joints each)
4. Classifies gestures from joint positions using spatial (pinch) and temporal (wave) analysis
5. Sends gesture events to the Home Center REST API as notifications
6. Supports TV Dashboard navigation — wave to move between sections, pinch to select/back

## Architecture

```
HandController/
├── HandControllerApp.swift              # App entry, DAT SDK init, URL callback
├── Models/
│   ├── HandLandmark.swift               # DetectedHand, HandGesture enum, HandSkeleton
│   ├── GestureEvent.swift               # Gesture event + home-center payload
│   └── DashboardSection.swift           # TV Dashboard section definitions
├── Services/
│   ├── HandPoseDetector.swift           # Vision framework hand pose detection
│   ├── GestureClassifier.swift          # Temporal wave + spatial pinch classification
│   └── HomeCenterClient.swift           # REST client for home-center API
├── ViewModels/
│   ├── WearablesViewModel.swift         # DAT SDK device registration/discovery
│   ├── StreamViewModel.swift            # Streaming pipeline: frames → detect → classify
│   └── TVDashboardController.swift      # Gesture → TV dashboard navigation mapping
└── Views/
    ├── ConnectionView.swift             # Glasses pairing screen
    ├── NonStreamView.swift              # Pre-stream ready state
    ├── StreamingView.swift              # Camera feed + skeleton overlay + HUD
    ├── HandOverlayView.swift            # Skeletal bone rendering (Canvas)
    └── DebugPanelView.swift             # Event log + home-center settings
```

## Supported Gestures

| Gesture | Detection Method | TV Dashboard Action |
|---------|-----------------|-------------------|
| Wave Left | Wrist displacement tracking over ~0.6s | Move selector to previous section |
| Wave Right | Wrist displacement tracking over ~0.6s | Move selector to next section |
| Wave Up/Down | Wrist displacement tracking over ~0.6s | (Reserved) |
| Index + Thumb Pinch | Thumb-tip to index-tip distance < 0.06 | Open full screen view of selected section |
| Middle + Thumb Pinch | Thumb-tip to middle-tip distance < 0.06 | Go back to dashboard / Turn on TV if off |

## Tech Stack

- **Language:** Swift, **UI:** SwiftUI
- **Hand Detection:** Apple Vision framework (`VNDetectHumanHandPoseRequest`)
- **Glasses Connection:** Meta DAT SDK (`MWDATCore`, `MWDATCamera`)
- **API Integration:** `URLSession` REST client → Home Center Cloudflare Worker
- **Min Target:** iOS 17+

## Building

1. Register at [wearables.developer.meta.com](https://wearables.developer.meta.com) for Meta App ID + Client Token
2. Open `HandController.xcodeproj` in Xcode
3. Add `META_APP_ID` and `CLIENT_TOKEN` as user-defined build settings
4. Set your signing team, build & run on device
5. Enable Developer Mode in the Meta AI app on your iPhone

## Home Center Integration

The app sends gesture events as `POST /api/notifications` to the Home Center Cloudflare Worker API at `https://home-center-api.phhowell.workers.dev`. Enable in the Debug panel (ladybug icon) during streaming.

For TV Dashboard navigation, the app sends structured navigation commands:
- `select_section` — moves the dashboard selector between sections
- `open_fullscreen` — opens a section's full screen view
- `close_fullscreen` — returns to the dashboard from a full screen view
- `power_on` — turns the TV on when it's off

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Vision framework over DAT hand tracking | DAT SDK provides camera frames only, no hand tracking |
| Temporal wave detection (0.6s window) | Distinguishes deliberate waves from hand movement noise |
| 2s throttle per gesture type | Prevents flooding the home-center API |
| 1s wave cooldown | Prevents repeated wave fires from single gesture |
| Local dashboard state tracking | iOS app maintains section index to send correct navigation commands |
