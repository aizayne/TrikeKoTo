/**
 * Server-side mirror of the Flutter `matching_service.dart`. Kept as a
 * pure module (no Firebase or network calls) so the ranking is unit-
 * testable and the function file stays focused on I/O.
 *
 * The constants must match `lib/core/constants.dart` byte-for-byte so
 * the server-pushed offer set agrees with what the on-device matcher
 * computes — otherwise drivers might see a notification for a ride
 * that never appears on their dashboard, or vice versa.
 */

/** Drivers further than this from the pickup are excluded entirely. */
export const PROXIMITY_KM = 5.0;

/** Hard cap on offer depth — at most this many drivers ever get pushed. */
export const MAX_OFFER_DEPTH = 10;

export interface OnlineDriver {
  email: string;
  lat: number;
  lng: number;
  /** Most recent FCM registration token for this driver, if any. */
  fcmToken?: string | null;
}

export interface RankedDriver {
  email: string;
  km: number;
  fcmToken?: string | null;
}

/**
 * Great-circle distance in kilometres between two lat/lng pairs.
 * Mirrors `lib/core/utils/haversine.dart` so the eligibility cutoff is
 * computed identically on both sides.
 */
export function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371; // Earth radius in km
  const toRad = (x: number) => (x * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * Pure ranking: filter to within proximity, sort by distance ascending,
 * tiebreak alphabetically by email. Returns the deterministic priority
 * list — the function itself decides how many of those to actually push
 * to via [MAX_OFFER_DEPTH].
 */
export function rankDriversForRide(
  pickup: { lat: number; lng: number },
  online: OnlineDriver[],
): RankedDriver[] {
  const ranked: RankedDriver[] = [];
  for (const d of online) {
    if (!d.email) continue;
    const km = haversineKm(d.lat, d.lng, pickup.lat, pickup.lng);
    if (km > PROXIMITY_KM) continue;
    ranked.push({ email: d.email, km, fcmToken: d.fcmToken });
  }
  ranked.sort((a, b) => {
    const c = a.km - b.km;
    if (c !== 0) return c;
    return a.email.localeCompare(b.email);
  });
  return ranked;
}
