# Zero-Knowledge Photo Vault

A private, end-to-end encrypted shared photo vault built with Flutter. Externally disguised as a fully functional calculator on the home screen.

## Architecture

- **Encryption:** AES-256-GCM with PBKDF2-HMAC-SHA256 key derivation (100,000 iterations, unique 12-byte IV per file)
- **Storage:** Google Drive API — only encrypted binary blobs are uploaded; no plaintext ever leaves the device
- **Sync:** Firebase Firestore for zero-knowledge cryptographic handshake — the shared password is never transmitted
- **State:** Provider pattern (`SessionProvider`, `VaultProvider`, `HandshakeProvider`) with volatile in-memory key lifecycle
- **Concurrency:** Dart Isolates for non-blocking AES-GCM decryption during image rendering

## Key Features

- **Decoy UI** — app opens as a working calculator; vault is unlocked by entering the couple password followed by `=`
- **Zero-knowledge design** — the shared encryption key is derived locally via PBKDF2; only a cryptographic salt is synced via Firestore
- **Session auto-lock** — Master Key is destroyed from volatile memory on OS lock or after 3 minutes in the background
- **Cryptographic handshake** — 6-digit pairing code flow for initial device linking; full state rehydration on reinstall
- **Non-destructive exit pipeline** — bulk decryption + Firestore tombstone flag for graceful partner unpairing before account deletion
- **Input sanitization** — folder names sanitized via regex before Drive API calls to prevent injection

## Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Material 3) |
| Cryptography | PointyCastle (AES-256-GCM, PBKDF2) |
| Auth | Firebase Auth + Google Sign-In |
| Database | Firebase Firestore |
| Storage | Google Drive API v3 |
| State | Provider |
| Routing | go_router |
| UI | Google Fonts, custom GLSL shader |

## Security Notes

- `google-services.json` and signing keystores are excluded from this repository
- The shared couple password is never stored, logged, or transmitted — it exists only in volatile memory for PBKDF2 derivation
- Firestore security rules restrict document access strictly to the two paired UIDs
