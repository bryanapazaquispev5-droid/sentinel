import { Router } from "express";
import { all, db, get, run } from "../../database/db.js";
import { randomUUID } from "node:crypto";
import { requireAdmin, requireAuth } from "../../middleware/authMiddleware.js";
import type { OfficialAlertsIngestion } from "../officialAlerts/services/officialAlertsIngestion.js";

export function createAdminRouter(officialAlertsIngestion: OfficialAlertsIngestion, onTestAlertChange: () => void = () => {}) {
  const router = Router();
  router.use(requireAuth, requireAdmin);

  const simulationTimers = new Map<string, NodeJS.Timeout>();
  const removeSimulation = (runId: string) => {
    const marker = `[SIMULACIÓN:${runId}]`;
    db.exec("BEGIN IMMEDIATE");
    try {
      run("DELETE FROM reports WHERE description LIKE ?", `${marker}%`);
      run("DELETE FROM users WHERE email LIKE ?", `sim-${runId}-%@sentinel.test`);
      run("DELETE FROM community_report_test_runs WHERE id = ?", runId);
      db.exec("COMMIT");
    } catch (error) { db.exec("ROLLBACK"); throw error; }
    const timer = simulationTimers.get(runId);
    if (timer) clearTimeout(timer);
    simulationTimers.delete(runId);
    onTestAlertChange();
  };
  for (const expired of all<{ id: string }>("SELECT id FROM community_report_test_runs WHERE expires_at <= ?", new Date().toISOString())) removeSimulation(expired.id);
  for (const activeRun of all<{ id: string; expires_at: string }>("SELECT id, expires_at FROM community_report_test_runs WHERE expires_at > ?", new Date().toISOString())) {
    simulationTimers.set(activeRun.id, setTimeout(() => removeSimulation(activeRun.id), Math.max(0, Date.parse(activeRun.expires_at) - Date.now())));
  }

  router.get("/dashboard", (_req, res) => {
    const count = (sql: string) => Number(get<{ count: number }>(sql)?.count ?? 0);
    return res.json({
      generatedAt: new Date().toISOString(),
      counts: {
        users: count("SELECT COUNT(*) AS count FROM users"),
        reports: count("SELECT COUNT(*) AS count FROM reports"),
        alerts: count("SELECT COUNT(*) AS count FROM official_alerts"),
        assessments: count("SELECT COUNT(*) AS count FROM alert_assessments"),
        pendingReports: count("SELECT COUNT(*) AS count FROM reports WHERE status = 'PENDING'"),
        verifiedReports: count("SELECT COUNT(*) AS count FROM reports WHERE status IN ('COMMUNITY_VERIFIED', 'OFFICIALLY_VERIFIED')")
      },
      sources: officialAlertsIngestion.status()
    });
  });

  router.get("/users", (_req, res) => res.json({ users: all(`
    SELECT id, name, email, role, reputation, gender, birth_year AS birthYear,
      CASE WHEN avatar_data IS NULL OR avatar_data = '' THEN 0 ELSE 1 END AS hasProfilePhoto,
      created_at AS createdAt, updated_at AS updatedAt
    FROM users ORDER BY created_at DESC LIMIT 500
  `) }));

  router.get("/reports", (_req, res) => res.json({ reports: all(`
    SELECT r.id, r.category, r.description, r.latitude, r.longitude, r.severity, r.status,
      r.confirmations, r.disputes, r.photo_url AS photoUrl, r.validation_radius_km AS validationRadiusKm,
      r.created_at AS createdAt, r.updated_at AS updatedAt, u.name AS userName, u.email AS userEmail
    FROM reports r JOIN users u ON u.id = r.user_id ORDER BY r.created_at DESC LIMIT 500
  `) }));

  router.get("/alerts", (_req, res) => {
    const yearAgo = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString();
    const alerts = all<{ id: string; externalId: string; source: string; title: string; description: string; category: string; latitude: number | null; longitude: number | null; severity: string; sourceUrl: string | null; publishedAt: string; expiresAt: string | null; createdAt: string }>(`
      SELECT id, external_id AS externalId, source, title, description, category, latitude, longitude,
        severity, source_url AS sourceUrl, published_at AS publishedAt, expires_at AS expiresAt, created_at AS createdAt
      FROM official_alerts WHERE published_at >= ? ORDER BY published_at DESC LIMIT 1000
    `, yearAgo);
    return res.json({ alerts: alerts.map((alert) => ({ ...alert, isActive: isOfficialAlertActive(alert.category, alert.publishedAt, alert.expiresAt) })) });
  });

  router.get("/assessments", (_req, res) => res.json({ assessments: all(`
    SELECT aa.id, aa.alert_id AS alertId, a.title AS alertTitle, a.category, a.source,
      u.name AS userName, u.email AS userEmail, aa.intensity, aa.answers_json AS answersJson,
      aa.latitude, aa.longitude, aa.distance_km AS distanceKm, aa.created_at AS createdAt, aa.updated_at AS updatedAt
    FROM alert_assessments aa
      JOIN official_alerts a ON a.id = aa.alert_id
      JOIN users u ON u.id = aa.user_id
    ORDER BY aa.created_at DESC LIMIT 500
  `) }));

  const testAlertTimers = new Map<string, NodeJS.Timeout>();
  run("DELETE FROM official_alerts WHERE source = 'SENTINEL_TEST'");

  const testFixtures = {
    LOW: { category: "SISMO", title: "PRUEBA · Sismo bajo", description: "Alerta ficticia para probar el nivel bajo.", lat: -12.0464, lon: -77.0428 },
    MEDIUM: { category: "INUNDACION", title: "PRUEBA · Inundación media", description: "Alerta ficticia para probar el nivel medio.", lat: -12.051, lon: -77.038 },
    HIGH: { category: "INCENDIO", title: "PRUEBA · Incendio alto", description: "Alerta ficticia para probar el nivel alto.", lat: -12.041, lon: -77.049 },
    CRITICAL: { category: "SISMO", title: "PRUEBA · Sismo crítico", description: "Alerta ficticia para probar el nivel crítico.", lat: -12.044, lon: -77.035 }
  } as const;

  router.get("/test-alerts", (_req, res) => res.json({ alerts: all(`
    SELECT id, external_id AS externalId, source, title, description, category, latitude, longitude,
      severity, published_at AS publishedAt
    FROM official_alerts WHERE source = 'SENTINEL_TEST'
    ORDER BY CASE severity WHEN 'CRITICAL' THEN 4 WHEN 'HIGH' THEN 3 WHEN 'MEDIUM' THEN 2 ELSE 1 END DESC
  `) }));

  router.post("/test-alerts/:severity", (req, res) => {
    const severity = String(req.params.severity).toUpperCase() as keyof typeof testFixtures;
    const fixture = testFixtures[severity];
    if (!fixture) return res.status(400).json({ error: "Nivel de prueba no válido" });

    const externalId = `SENTINEL_TEST:${severity}`;
    const id = randomUUID();
    const now = new Date().toISOString();
    run(`INSERT INTO official_alerts (id, external_id, source, title, description, category, latitude, longitude, severity, source_url, published_at, created_at)
      VALUES (?, ?, 'SENTINEL_TEST', ?, ?, ?, ?, ?, ?, NULL, ?, ?)
      ON CONFLICT(external_id) DO UPDATE SET id = excluded.id, title = excluded.title,
      description = excluded.description, category = excluded.category, latitude = excluded.latitude,
      longitude = excluded.longitude, severity = excluded.severity, published_at = excluded.published_at`,
      id, externalId, fixture.title, fixture.description, fixture.category, fixture.lat, fixture.lon, severity, now, now);

    const oldTimer = testAlertTimers.get(severity);
    if (oldTimer) clearTimeout(oldTimer);
    const timer = setTimeout(() => {
      run("DELETE FROM official_alerts WHERE external_id = ? AND source = 'SENTINEL_TEST'", externalId);
      testAlertTimers.delete(severity);
      onTestAlertChange();
    }, 10_000);
    testAlertTimers.set(severity, timer);
    onTestAlertChange();

    return res.status(201).json({ ok: true, expiresAt: new Date(Date.now() + 10_000).toISOString(), alert: get(
      "SELECT id, external_id AS externalId, source, title, description, category, latitude, longitude, severity, published_at AS publishedAt FROM official_alerts WHERE external_id = ?",
      externalId
    ) });
  });

  router.post("/community-simulation", (req, res, next) => {
    try {
      const category = String(req.body?.category ?? "SISMO").toUpperCase();
      const rules = category.includes("SISMO") ? { minimum: 5, radiusKm: 25 }
        : category.includes("INUND") ? { minimum: 4, radiusKm: 5 }
        : category.includes("HUAICO") ? { minimum: 4, radiusKm: 6 }
        : category.includes("INCEND") ? { minimum: 4, radiusKm: 3 }
        : category.includes("DERRUMB") ? { minimum: 3, radiusKm: 3 }
        : category.includes("VOLCAN") ? { minimum: 5, radiusKm: 20 }
        : category.includes("CLIMA") ? { minimum: 5, radiusKm: 15 } : null;
      if (!rules) return res.status(400).json({ error: "Tipo de desastre no válido para la simulación." });
      const runId = randomUUID();
      const now = new Date().toISOString();
      const expiresAt = new Date(Date.now() + 10 * 60_000).toISOString();
      const clusterId = randomUUID();
      const center = { latitude: -12.0464, longitude: -77.0428 };
      db.exec("BEGIN IMMEDIATE");
      try {
        run("INSERT INTO community_report_test_runs (id, category, created_at, expires_at) VALUES (?, ?, ?, ?)", runId, category, now, expiresAt);
        for (let index = 0; index < 15; index += 1) {
          const userId = randomUUID();
          const angle = 2 * Math.PI * index / 15;
          const radiusMeters = 100 + (index % 5) * 45;
          const latitude = center.latitude + Math.cos(angle) * radiusMeters / 111_320;
          const longitude = center.longitude + Math.sin(angle) * radiusMeters / (111_320 * Math.cos(center.latitude * Math.PI / 180));
          run("INSERT INTO users (id, name, email, password_hash, role, reputation, created_at, updated_at) VALUES (?, ?, ?, ?, 'USER', 0, ?, ?)", userId, `Simulación ${String(index + 1).padStart(2, "0")}`, `sim-${runId}-${index + 1}@sentinel.test`, "SIMULATION_ACCOUNT_DISABLED", now, now);
          run("INSERT INTO reports (id, user_id, category, description, latitude, longitude, severity, status, validation_radius_km, cluster_id, cluster_report_count, cluster_min_reporters, cluster_radius_km, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'MEDIUM', 'UNDER_REVIEW', 5, ?, 15, ?, ?, ?, ?)", randomUUID(), userId, category, `[SIMULACIÓN:${runId}] Persona ${index + 1} reporta el mismo evento desde una ubicación distinta.`, latitude, longitude, clusterId, rules.minimum, rules.radiusKm, now, now);
        }
        db.exec("COMMIT");
      } catch (error) { db.exec("ROLLBACK"); throw error; }
      simulationTimers.set(runId, setTimeout(() => removeSimulation(runId), 10 * 60_000));
      onTestAlertChange();
      return res.status(201).json({ runId, category, simulatedUsers: 15, reportsRequired: rules.minimum, radiusKm: rules.radiusKm, status: "UNDER_REVIEW", expiresAt });
    } catch (error) { next(error); }
  });

  router.delete("/community-simulation/:runId", (req, res) => {
    const runId = String(req.params.runId);
    if (!get("SELECT id FROM community_report_test_runs WHERE id = ?", runId)) return res.status(404).json({ error: "Simulación no encontrada." });
    removeSimulation(runId);
    return res.json({ ok: true });
  });

  router.post("/sync", async (_req, res) => {
    await officialAlertsIngestion.runOnce();
    return res.json({ ok: true, sources: officialAlertsIngestion.status() });
  });

  return router;
}

function isOfficialAlertActive(categoryValue: string, publishedAt: string, expiresAt: string | null = null, now = Date.now()): boolean {
  const published = Date.parse(publishedAt);
  if (!Number.isFinite(published)) return false;
  if (expiresAt && Number.isFinite(Date.parse(expiresAt))) return Date.parse(expiresAt) >= now;
  if (published > now) return true;
  const ageDays = (now - published) / 86_400_000;
  const category = categoryValue.toUpperCase();
  const activeWindowDays = category.includes("SISMO") || category.includes("EARTHQUAKE") ? 1
    : category.includes("INUND") || category.includes("FLOOD") || category.includes("HUAICO")
      || category.includes("INCEND") || category.includes("FIRE") || category.includes("VOLCAN")
      || category.includes("STORM") || category.includes("CYCLONE") || category.includes("LLUVIA")
      || category.includes("TORMENTA") || category.includes("FRIAJE") || category.includes("HELADA")
      || category.includes("NEVADA") || category.includes("OLA_CALOR") || category.includes("TSUNAMI")
      || category.includes("CENIZA") || category.includes("LAHAR") ? 7 : 2;
  return ageDays <= activeWindowDays;
}
