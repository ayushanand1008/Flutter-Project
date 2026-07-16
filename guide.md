# Architecture Guide for Claude Code

Hello Claude! If you are reading this, you are working on the Secret Vault App transferred from a Windows development environment. 

This document serves as an architectural hand-off to explain how the app is structured, the physics engine mechanics, and the strict design choices requested by the developer.

## 1. Project Setup & Authentication (CRITICAL)
Before you build this project or run it, **you must configure the keystore**.
The Windows development machine generated a specific `debug.keystore` that is whitelisted by Firebase and Google Sign-in. That file has been copied to `android/app/debug.keystore`.
**ACTION REQUIRED:** Open `android/app/build.gradle` and explicitly set the debug `signingConfig` to use this local `debug.keystore` file (password is standard: `android`). If you do not do this, Google Sign-in will permanently fail with a platform exception.

## 2. Core Application Concept
The app is a **Secret Vault disguised as a standard Android Calculator**.
* **The Lock (Calculator Screen):** The `calculator_screen.dart` presents a completely innocent, flat teal material design calculator. If the user types the secret code (`123=`), the `HandshakeProvider` unlocks the app and routes to the dashboard.
* **The Vault (Dashboard Screen):** The `dashboard_screen.dart` displays the user's hidden Google Drive folders.

## 3. The Dashboard UI & "Boat" Aesthetic
The developer has very specific and refined UI/UX requirements for the vault:
* **The Background:** The screen background is dynamic. `_getDynamicBackgroundColor()` recalculates the exact time of day (24-hour cycle) every 60 seconds and smoothly lerps the background color to match the real-world time (Night -> Dawn -> Day -> Dusk).
* **The Folders:** The Google Drive folders are rendered as vertical rectangles (like "boats"). They do NOT stretch edge-to-edge; they are strictly constrained to exactly **40% of the screen width** and float in the center. Text overflows are handled gracefully with ellipses.
* **Thumbnails:** Folders display the first image found inside them as a thumbnail.

## 4. The Liquid Physics Engine (V4)
This is the most complex part of the UI. As the user scrolls the folder list, the folders ("boats") generate ripples ("wakes") in the background.
The developer explicitly rejected blurry, glowing "gas-like" effects. The ripples MUST look like sharp, high-contrast liquid surface tension.

**How it works (`RectWakePainter` in `dashboard_screen.dart`):**
1. **Global Tracking:** We use `GlobalKey` to track the exact screen coordinates of each folder.
2. **Procedural Geometry:** We do NOT use `MaskFilter.blur`. Instead, `_buildLiquidyPath()` uses `dart:math` to draw a Superellipse (squircle) matching the folder's shape.
3. **Sine-Wave Distortion:** As the ripple expands outward (`life` drops from 1.0 to 0), a heavy sine-wave math function distorts the lines. This physically warps and bends the stroke into chaotic liquid patterns.
4. **Caustic Highlights:** The ripples are drawn in two layers: a semi-transparent dark pink base stroke, and a razor-thin, bright pink highlight stroke directly on top to simulate light hitting water.

## 5. State Management & API
* **Provider Pattern:** We use `provider` for state injection.
* **HandshakeProvider:** Manages the locked/unlocked state.
* **VaultProvider:** Interfaces with the Google Drive v3 REST API. It handles folder fetching and recursive image thumbnail fetching.

Please respect these mathematical physics models and exact width constraints when modifying the UI!
