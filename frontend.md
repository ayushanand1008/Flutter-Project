# Flutter E2EE Scrapbook: Frontend UI & Architecture Blueprint (Final)

## 1. Project Overview & Stealth Architecture
This document outlines the frontend implementation for a private, serverless, E2EE shared photo vault[cite: 1]. To maintain absolute privacy on the host device, the app employs a strict "Decoy UI" strategy. 

* **Launcher Disguise:** Externally, the app must be packaged as a calculator. The agent must configure the Android build statically at build time via `AndroidManifest.xml` (setting `android:label="Calculator"` and applying a generic calculator `.ico`/`.png` asset). No dynamic activity-aliases are required.
* **Internal Decoy:** The primary route is a fully functional calculator that acts as a stealth gatekeeper to the hidden vault.

## 2. Tech Stack & State Management
* **Framework:** Flutter (Material 3, Custom Warm Theme)
* **Routing:** `go_router` (for strict route guarding and clearing the navigation stack upon session lock)
* **State Management:** `Provider`[cite: 1]
    * `SessionProvider`: Manages the volatile Master Key, Google Auth state, app lifecycle timers, and active UID[cite: 1].
    * `HandshakeProvider`: Listens to Firestore streams for pairing status[cite: 1].
    * `VaultProvider`: Manages the Drive API file lists, folder navigation, and upload queues[cite: 1].
* **Image Rendering:** strictly using `Image.memory()` passing `Uint8List` decrypted bytes[cite: 1]. **Crucial Rule:** The implementation must ensure these byte buffers are promptly eligible for Garbage Collection when widgets dispose. Avoid any image-loading plugins that default to disk caching.

## 3. The Decoy, Auth & Session Lifecycle (Screens 0 & 1)

### **Screen 0: The Setup & Decoy Calculator**
* **First Launch (Setup):** On the very first run (no local preferences saved), the app routes to a standard, non-decoy "Set Password" screen. The user inputs a numeric sequence to act as the couple password.
* **Normal Launch (The Decoy):** On subsequent cold starts, the app opens immediately into the `CalculatorScreen`. It must be a fully functional calculator (Numpad, operators, display).
* **The Unlock Sequence:** To bypass the decoy, the user types their specific numeric password followed by the equal sign (`=`).
    * *Loading State:* Upon hitting `=`, the app triggers the PBKDF2 function alongside the Firestore salt to derive the volatile Master Key[cite: 1]. The UI must show a brief loading indicator during this CPU-intensive re-derivation before transitioning to the vault.

### **Session Gating & Lifecycle Timing**
The app must utilize a `WidgetsBindingObserver` to manage the in-memory Master Key state[cite: 1]:
* **Backgrounding:** If the app is sent to the background, it remains unlocked in memory.
* **Timeout/Lock Triggers:** The app must automatically lock (destroy the Master Key and push back to the Decoy screen) if:
    1. The OS is locked.
    2. The app remains in the background without usage for strictly **3 minutes**.
* **Return State:** Resuming an unlocked app within the 3-minute window drops the user right back into the vault without a password prompt.

### **Screen 1: Google Sign-In & Rehydration**
* Once the decoy is bypassed initially, the app checks Google Auth[cite: 1].
    * If no account: Show "Sign in with Google" (with instructions to accept the "Unverified App" warning)[cite: 1].
    * If signed in: Query the Firestore `couples` collection[cite: 1].
        * `handshake_status == "ready"` -> Vault Dashboard[cite: 1].
        * `handshake_status == "pending_folder"` -> Handshake Screen[cite: 1].

## 4. Design System & Aesthetic Core
The vault's interior abandons standard sterile UI in favor of a highly personalized, warm, and comforting environment.
* **Palette:** Background is `#FDE3C6` (warm peachy cream). Text and icons use earthy browns (`#5D4037`). Call-to-action buttons use high-contrast warm accents (e.g., vibrant burnt orange `#E64A19`).
* **Typography:** Main headings and folder titles strictly use a blocky, "Peachy Vibes" font (Agent: utilize *Titan One*, *Fredoka One*, or *Sniglet*). Body text is a legible, rounded sans-serif.

## 5. Layout, Navigation & The Vault (Screens 3 & 4)

### **Global Navigation**
* A "Hamburger Menu" (3 horizontal lines) sits top-left on a transparent `AppBar` (zero elevation).
* The sliding `Drawer` contains: Settings, Sync Status, **Export & Disconnect**, and **Lock Vault**.
* **Lock Vault Button:** Immediately destroys the `volatileMasterKey`, wipes the router stack, and returns the user to the Decoy Calculator screen[cite: 1].

### **Dashboard & Interactive Mechanics**
* **Centered Folders:** The main dashboard features centered folders in a neatly padded list or grid, prioritizing the blocky typography. 
* **Folder Creation:** A FAB triggers an "Add Album" dialog. The user inputs a location. **Agent Rule:** The input must pass through the `YYYY-MM-DD_location_name` sanitization regex before hitting the Drive API[cite: 1].
* **The Hazy Pink Scroll Ripples:** Scrolling the main folder list triggers custom visual physics. Scrolling generates soft, hazy pink ripples (`#F48FB1`, low opacity, high `ImageFilter.blur`) that bloom behind the folders and slowly fade into the `#FDE3C6` background based on scroll velocity.

### **Album View & Upload Flow**
* **Lazy Decryption:** A responsive grid of thumbnails. Images fetch as encrypted blobs, decrypt via AES-GCM in an `Isolate`, and yield a `MemoryImage`[cite: 1].
* **Upload Queue:** When uploading via `image_picker`, a localized `BottomSheet` tracks the encryption and Drive API upload progress sequentially[cite: 1].

## 6. Safe Exit Strategy (Drawer Option)
* **Trigger:** "Export & Disconnect" button[cite: 1]. Requires re-entering the numeric password to confirm intent.
* **UI State:** Shows a full-screen, un-dismissible loading overlay tracking the non-destructive exit pipeline: "Downloading -> Decrypting -> Saving to Decrypted Drive Folder -> Unpairing"[cite: 1]. 

## 7. IDE Agent Scaffold Instructions (Antigravity Guide)

1. **Manifest & Theme Scaffold:** Set `android:label="Calculator"` and apply a dummy calculator icon asset. Define the global `ThemeData` with the `#FDE3C6` background and earthy brown text colors. Load a blocky web font for the primary text theme.
2. **Decoy & Setup Routes:** Build the `SetPasswordScreen` (First run only, writes securely to local storage). Build the `CalculatorScreen` with standard math logic. Catch the `[password] + "="` sequence to trigger PBKDF2 derivation (with a loading spinner) and route to `AuthGuard`[cite: 1].
3. **Lifecycle Observer:** Implement the `WidgetsBindingObserver` in `SessionProvider`. Track background entry timestamps. If background time exceeds 3 minutes or the OS locks, invoke `.clear()` on the volatile key and pop the router to `CalculatorScreen`[cite: 1].
4. **Drawer & Dashboard UI:** Scaffold the hamburger drawer for secondary actions. Build the main folder `ListView.builder` ensuring items are `Center` wrapped.
5. **Interactive Scroll Physics:** Wrap the main folder list in a `NotificationListener<ScrollNotification>`. Extract scroll delta/velocity to drive a background `CustomPainter` layered behind the folders. Draw hazy pink circles that expand and fade out based on that velocity.
6. **E2EE Memory Renderer:** Build `E2EEImageWidget`. Handle Drive API blob fetching, spawn an `Isolate` for AES decryption, and render the resulting `Uint8List` via `Image.memory()`[cite: 1]. Ensure proper widget `dispose()` overrides to allow garbage collection of the bytes[cite: 1].
7. **Upload/Folder Service:** Attach the regex sanitization rule to the "New Album" dialog controller before executing Drive API calls[cite: 1]. Assemble the sequential upload progress `BottomSheet`.