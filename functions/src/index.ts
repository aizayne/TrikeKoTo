/**
 * TrikeKoTo Cloud Functions — push-notification side of ride matching.
 *
 * The Flutter client already does in-app matching: when a driver is on the
 * dashboard with the app open, they see new ride requests via a Firestore
 * stream and the on-device matcher decides whether to surface the offer.
 *
 * This function fills the gap when the driver's app is in the background
 * or terminated. On `rides/{rideId}` create, we mirror the client-side
 * matcher to pick the same top-N drivers, then push an FCM message so
 * the OS wakes the device and shows a notification.
 *
 * Deliberately NOT done here:
 *   - Reassigning a ride. The driver still has to tap "Accept" inside
 *     the app, and Firestore rules + the acceptRide transaction remain
 *     the single source of truth for who actually got the ride.
 *   - Re-pushing as the offer window expands. The first push covers
 *     MAX_OFFER_DEPTH drivers up front; the on-device matcher handles
 *     the time-based widening for everyone else who is already in-app.
 *     Re-pushing on every tick would burn FCM quota for marginal gain.
 *   - Webpush. The mobile app is the only push surface for v1; admin
 *     and commuter web flows poll Firestore in real time already.
 */

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging, MulticastMessage } from 'firebase-admin/messaging';

import {
  MAX_OFFER_DEPTH,
  OnlineDriver,
  rankDriversForRide,
} from './matching';

initializeApp();

/** Firestore region for this project. Matches the client config. */
const REGION = 'asia-southeast1';

/**
 * Triggered the moment a commuter creates a ride. We only act when the
 * doc lands in its initial state (`status == 'searching'`, no driver
 * assigned) — defensive in case some future migration backfills rides
 * and replays the create event.
 */
export const onRideCreated = onDocumentCreated(
  {
    document: 'rides/{rideId}',
    region: REGION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn('onRideCreated fired with no snapshot', {
        rideId: event.params.rideId,
      });
      return;
    }
    const ride = snap.data() as Record<string, unknown>;
    const rideId = event.params.rideId;

    if (ride.status !== 'searching') {
      logger.info('Skipping ride: status is not searching', {
        rideId,
        status: ride.status,
      });
      return;
    }
    if (ride.assignedDriver) {
      logger.info('Skipping ride: already has a driver', {
        rideId,
        assignedDriver: ride.assignedDriver,
      });
      return;
    }

    const pickupCoords = ride.pickupCoords as
      | { lat?: number; lng?: number }
      | undefined;
    if (
      !pickupCoords ||
      typeof pickupCoords.lat !== 'number' ||
      typeof pickupCoords.lng !== 'number'
    ) {
      // Without coords we can't rank — fall through to a fan-out to every
      // online driver with a token. This degraded mode mirrors what the
      // on-device matcher does (Flutter calls it "show to everyone").
      logger.info('Ride has no pickupCoords — broadcasting to all online', {
        rideId,
      });
      return await pushToAllOnline(ride, rideId);
    }

    // Pull the current online roster.
    const db = getFirestore();
    const snapDrivers = await db
      .collection('active_drivers')
      .where('isOnline', '==', true)
      .get();

    const online: OnlineDriver[] = [];
    for (const d of snapDrivers.docs) {
      const data = d.data();
      const loc = data.location;
      if (
        !loc ||
        typeof loc.lat !== 'number' ||
        typeof loc.lng !== 'number'
      ) {
        continue;
      }
      const email = (data.email as string | undefined) ?? d.id;
      if (!email) continue;
      online.push({
        email,
        lat: loc.lat,
        lng: loc.lng,
        fcmToken: (data.fcmToken as string | null | undefined) ?? null,
      });
    }

    if (online.length === 0) {
      logger.info('No online drivers — nothing to push', { rideId });
      return;
    }

    const ranked = rankDriversForRide(
      { lat: pickupCoords.lat, lng: pickupCoords.lng },
      online,
    );

    // Trim to the offer-depth cap and drop any without a token.
    const targets = ranked
      .slice(0, MAX_OFFER_DEPTH)
      .filter((r) => !!r.fcmToken);

    if (targets.length === 0) {
      logger.info('No nearby drivers with FCM tokens', {
        rideId,
        rankedCount: ranked.length,
      });
      return;
    }

    logger.info('Pushing ride offer', {
      rideId,
      targetCount: targets.length,
      closestKm: targets[0].km,
    });

    await sendMulticastWithCleanup(
      targets.map((t) => ({ email: t.email, token: t.fcmToken as string })),
      buildMessage(ride, rideId),
    );
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Helpers

/** Builds the FCM payload — title varies for scheduled vs immediate rides. */
function buildMessage(
  ride: Record<string, unknown>,
  rideId: string,
): MulticastMessage {
  const pickup = (ride.pickup as string | undefined) ?? 'Unknown pickup';
  const dropoff = (ride.dropoff as string | undefined) ?? 'Unknown dropoff';
  const isScheduled = !!ride.scheduledFor;
  const title = isScheduled ? 'Scheduled ride request' : 'New ride request';
  const body = `${pickup} → ${dropoff}`;

  return {
    tokens: [], // populated by caller
    notification: { title, body },
    // `data` lets the Flutter app deep-link straight to the ride if the
    // user taps the notification. Strings only — FCM payload requirement.
    data: {
      rideId,
      type: 'ride_offer',
      isScheduled: isScheduled ? '1' : '0',
    },
    android: {
      priority: 'high',
      notification: {
        // Channel must already be created on the device; the Flutter
        // FCM plugin auto-creates a default channel on first message.
        channelId: 'ride_offers',
        sound: 'default',
      },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          sound: 'default',
          'content-available': 1,
        },
      },
    },
  };
}

/** Degraded path used when pickupCoords is missing — push to every online
 * driver who has a token. The on-device matcher will still decide what
 * actually shows in the dashboard, so the worst case is a few extra
 * notifications, not a wrongly assigned ride. */
async function pushToAllOnline(
  ride: Record<string, unknown>,
  rideId: string,
): Promise<void> {
  const db = getFirestore();
  const snap = await db
    .collection('active_drivers')
    .where('isOnline', '==', true)
    .get();

  const targets: { email: string; token: string }[] = [];
  for (const d of snap.docs) {
    const data = d.data();
    const token = data.fcmToken as string | null | undefined;
    if (!token) continue;
    const email = (data.email as string | undefined) ?? d.id;
    targets.push({ email, token });
  }

  if (targets.length === 0) {
    logger.info('Degraded broadcast: no eligible tokens', { rideId });
    return;
  }

  logger.info('Degraded broadcast push', {
    rideId,
    targetCount: targets.length,
  });

  await sendMulticastWithCleanup(targets, buildMessage(ride, rideId));
}

/**
 * Sends a multicast FCM message and cleans up dead tokens. FCM caps a
 * single multicast at 500 tokens — we batch defensively even though
 * MAX_OFFER_DEPTH is 10, in case the degraded broadcast path fans out
 * to a much larger online set.
 */
async function sendMulticastWithCleanup(
  targets: { email: string; token: string }[],
  template: MulticastMessage,
): Promise<void> {
  const messaging = getMessaging();
  const db = getFirestore();
  const CHUNK = 500;

  for (let i = 0; i < targets.length; i += CHUNK) {
    const chunk = targets.slice(i, i + CHUNK);
    const message: MulticastMessage = {
      ...template,
      tokens: chunk.map((t) => t.token),
    };

    let response;
    try {
      response = await messaging.sendEachForMulticast(message);
    } catch (err) {
      logger.error('FCM multicast send failed', { error: String(err) });
      continue;
    }

    if (response.failureCount === 0) continue;

    const cleanups: Promise<unknown>[] = [];
    response.responses.forEach((r, idx) => {
      if (r.success) return;
      const code = r.error?.code ?? 'unknown';
      const target = chunk[idx];
      logger.warn('FCM send failed for one token', {
        email: target.email,
        code,
      });
      // Only purge tokens FCM tells us are permanently dead. Other
      // failures (network blips, quota) should not orphan a real device.
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/invalid-argument'
      ) {
        cleanups.push(
          db
            .collection('active_drivers')
            .doc(target.email)
            .update({
              fcmToken: FieldValue.delete(),
              fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
            })
            .catch((e) =>
              logger.warn('Failed to purge dead FCM token', {
                email: target.email,
                error: String(e),
              }),
            ),
        );
      }
    });

    if (cleanups.length > 0) {
      await Promise.all(cleanups);
    }
  }
}
