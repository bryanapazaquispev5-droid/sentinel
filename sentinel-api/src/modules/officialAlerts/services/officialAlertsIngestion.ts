import { randomUUID } from "node:crypto";
import { all, run } from "../../../database/db.js";
import { fetchCENVULAlerts, fetchENFENPredictions, fetchEONETWildfires, fetchFIRMSAlerts, fetchGDACSAlerts, fetchIGPAlerts, fetchINDECIAlerts, fetchSENAMHIAlerts } from "../data/sourceClients.js";
import type { NormalizedOfficialAlert } from "../domain/officialAlertTypes.js";

type AlertSourceStatus = { source: string; lastSuccessAt: string | null; lastError: string | null; imported: number };

const DEFAULT_POLL_INTERVAL_MS = 10_000;
const sourceStatuses = new Map<string, AlertSourceStatus>();
const lastSourceFetchAt = new Map<string, number>();

export class OfficialAlertsIngestion {
  private timer: NodeJS.Timeout | undefined;
  private running = false;

  constructor(private readonly onSynced: () => void = () => {}) {}

  start(intervalMs = DEFAULT_POLL_INTERVAL_MS) {
    void this.runOnce();
    this.timer = setInterval(() => void this.runOnce(), intervalMs);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
  }

  async runOnce() {
    if (this.running) return;
    this.running = true;
    const sources = [
      this.importSource("IGP/CENSIS", fetchIGPAlerts, 10_000),
      this.importSource("GDACS", fetchGDACSAlerts, 60_000),
      this.importSource("INDECI/SINPAD", fetchINDECIAlerts, 5 * 60_000),
      this.importSource("IGP/CENVUL", fetchCENVULAlerts, 5 * 60_000),
      this.importSource("SENAMHI", fetchSENAMHIAlerts, 5 * 60_000),
      this.importSource("ENFEN", fetchENFENPredictions, 15 * 60_000),
      this.importSource("NASA EONET", fetchEONETWildfires, 5 * 60_000),
      ...(process.env.FIRMS_MAP_KEY ? [this.importSource("NASA FIRMS", fetchFIRMSAlerts, 5 * 60_000)] : [])
    ];
    try {
      const results = await Promise.all(sources);
      if (results.some(Boolean)) this.onSynced();
    } finally {
      this.running = false;
    }
  }

  status(): AlertSourceStatus[] {
    return [...sourceStatuses.values()];
  }

  private async importSource(source: string, fetchAlerts: () => Promise<NormalizedOfficialAlert[]>, minIntervalMs: number) {
    const now = Date.now();
    if (now - (lastSourceFetchAt.get(source) ?? 0) < minIntervalMs) return false;
    lastSourceFetchAt.set(source, now);
    try {
      const alerts = await fetchAlerts();
      for (const alert of alerts) upsertOfficialAlert(alert);
      sourceStatuses.set(source, { source, lastSuccessAt: new Date().toISOString(), lastError: null, imported: alerts.length });
      console.log(`[official-alerts] ${source}: ${alerts.length} alertas sincronizadas`);
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Error desconocido";
      // Reintenta pronto tras un fallo transitorio sin volver a consultar en cada tick.
      lastSourceFetchAt.set(source, Date.now() - minIntervalMs + Math.min(60_000, minIntervalMs));
      const previous = sourceStatuses.get(source);
      sourceStatuses.set(source, { source, lastSuccessAt: previous?.lastSuccessAt ?? null, lastError: message, imported: previous?.imported ?? 0 });
      console.error(`[official-alerts] ${source}: ${message}`);
      return false;
    }
  }
}

function upsertOfficialAlert(alert: NormalizedOfficialAlert) {
  const now = new Date().toISOString();
  run(
    `INSERT INTO official_alerts (id, external_id, source, title, description, category, latitude, longitude, severity, source_url, published_at, expires_at, record_type, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(external_id) DO UPDATE SET
       source = excluded.source,
       title = excluded.title,
       description = excluded.description,
       category = excluded.category,
       latitude = excluded.latitude,
       longitude = excluded.longitude,
       severity = excluded.severity,
       source_url = excluded.source_url,
       published_at = excluded.published_at,
       expires_at = excluded.expires_at,
       record_type = excluded.record_type`,
    randomUUID(), alert.externalId, alert.source, alert.title, alert.description, alert.category,
    alert.latitude, alert.longitude, alert.severity, alert.sourceUrl, alert.publishedAt, alert.expiresAt ?? null, alert.recordType ?? "ALERT", now
  );
}

export function getOfficialAlertsSourceStatus(): AlertSourceStatus[] {
  return [...sourceStatuses.values()];
}

export function countOfficialAlerts() {
  return Number(all<{ count: number }>("SELECT COUNT(*) AS count FROM official_alerts")[0]?.count ?? 0);
}
