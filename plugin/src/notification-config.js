import { readFileSync } from "node:fs";
import { join } from "node:path";

// Mercurio ships no relay, and the app refuses Heeler's (NotificationRelayEndpoint.swift),
// so there is no default: an unset relay_url means no push is sent.
export const DEFAULT_RELAY_URL = null;

// Upstream Heeler's relays, which carried the default before. A config still
// naming one is treated as unset, matching what the app accepts, instead of
// being honoured as a deliberate override.
export const LEGACY_DEFAULT_RELAY_URLS = new Set([
  "https://herdr-push-relay.69709991236.workers.dev",
  "https://herdr-apns.bybee.dev",
  "https://heeler-apns.bybee.dev",
]);
const DEFAULT_DEBOUNCE_MS = 5000;
const DEFAULT_ACTIVITY_DEBOUNCE_MS = 1500;
const DEFAULT_RETRY_DELAY_MS = 1000;

function normalizeRelayURL(value) {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(/\/+$/, "");
  if (normalized.length === 0 || LEGACY_DEFAULT_RELAY_URLS.has(normalized)) {
    return null;
  }
  return normalized;
}

/**
 * Read the plugin-side `notify.json`. A missing relay URL is null (no push is
 * sent); an explicit URL is for a relay you run for an app you signed yourself.
 */
export function readNotificationConfig(configDir) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(join(configDir, "notify.json"), "utf8"));
  } catch {
    parsed = {};
  }
  const positiveInt = (value, fallback) =>
    Number.isInteger(value) && value >= 0 ? value : fallback;
  return {
    relayUrl: normalizeRelayURL(parsed.relay_url) ?? DEFAULT_RELAY_URL,
    debounceMs: positiveInt(parsed.debounce_ms, DEFAULT_DEBOUNCE_MS),
    activityDebounceMs: positiveInt(parsed.activity_debounce_ms, DEFAULT_ACTIVITY_DEBOUNCE_MS),
    retryDelayMs: positiveInt(parsed.retry_delay_ms, DEFAULT_RETRY_DELAY_MS),
  };
}
