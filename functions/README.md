# TrikeKoTo Cloud Functions

Server-side push notification for ride offers.

When a commuter creates a `rides/{rideId}` doc, the `onRideCreated` trigger
runs the same matching algorithm as the Flutter client and sends an FCM
push to the closest drivers (up to `MAX_OFFER_DEPTH = 10`). Dead tokens
are purged from `active_drivers/{email}.fcmToken` automatically.

## Prerequisites

1. **Blaze plan** — Cloud Functions v2 requires the pay-as-you-go plan.
   Free tier covers the expected usage of this thesis project (well
   under 2M invocations/month). Upgrade at:
   https://console.firebase.google.com/project/trikekoto/usage/details

2. **Node 20** — match the runtime declared in `package.json`.
   `node --version` should print `v20.x.x`.

3. **Firebase CLI** — already installed globally (`firebase --version`).
   If not: `npm i -g firebase-tools`.

## First-time setup

```bash
cd functions
npm install
```

## Deploy

From the repo root:

```bash
firebase deploy --only functions
```

The `predeploy` hook in `firebase.json` runs `npm run build` first, so
TypeScript is compiled to `functions/lib/` before the upload.

To deploy a single function (faster iteration):

```bash
firebase deploy --only functions:onRideCreated
```

## Watch logs

```bash
firebase functions:log
```

Or stream in real time from the console:
https://console.firebase.google.com/project/trikekoto/functions/logs

## Local emulation (optional)

```bash
cd functions
npm run serve
```

This starts the Functions emulator. To exercise the trigger you also
need the Firestore emulator running and a write to `rides/`. Easiest
path is just to deploy and test against the real project — the function
is small and free-tier friendly.

## File layout

```
functions/
├── src/
│   ├── index.ts        # Firestore trigger + FCM multicast
│   └── matching.ts     # Pure ranking — mirrors lib/services/matching_service.dart
├── package.json
├── tsconfig.json
└── README.md           # this file
```

## Why these constants must match the client

`functions/src/matching.ts` and `lib/core/constants.dart` both define
`PROXIMITY_KM = 5.0` and `MAX_OFFER_DEPTH = 10`. If they drift, the
server might push a notification to a driver whose on-device matcher
won't show the ride (or vice versa) — confusing for the driver and
hard to debug because nothing actually crashes.

If you tune the constants, change them in BOTH places in the same
commit.
