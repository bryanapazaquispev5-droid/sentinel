import express from "express";
import { createServer } from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { join } from "node:path";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import bcrypt from "bcryptjs";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { config } from "./config/config.js";
import { all, get, run } from "./database/db.js";
import { signToken } from "./shared/auth.js";
import { requireAdmin, requireAuth } from "./middleware/authMiddleware.js";
import { distanceKmBetween, isPeruCoordinate, PERU_BOUNDS, REGION_RADIUS_KM, REPORT_VALIDATION_RADIUS_KM } from "./shared/geography.js";
import { passwordSchema, profileSchema } from "./modules/profile/profileSchemas.js";
import { OfficialAlertsIngestion } from "./modules/officialAlerts/services/officialAlertsIngestion.js";
import { allowedQuestionIds, emergencyContactsForCategory, questionnaireForCategory } from "./modules/alertAssessments/domain/questionnaires.js";
import { createAdminRouter } from "./modules/admin/adminRouter.js";

type UserRow = { id: string; name: string; email: string; password_hash: string; role: "USER" | "ADMIN"; reputation: number; gender: string | null; birth_year: number | null; avatar_data: string | null; created_at: string };
type ReportRow = { id: string; user_id: string; category: string; description: string; latitude: number; longitude: number; severity: string; status: string; photo_url: string | null; validation_radius_km: number; cluster_id: string | null; cluster_report_count: number; cluster_min_reporters: number; cluster_radius_km: number; confirmations: number; disputes: number; created_at: string; updated_at: string };
type EnrichedReportRow = ReportRow & { user_name?: string; user_reputation?: number; distance_km?: number };
type AlertRow = { id: string; external_id: string; source: string; title: string; description: string; category: string; latitude: number | null; longitude: number | null; severity: string; source_url: string | null; published_at: string; expires_at?: string | null; record_type?: string };
type AssessmentRow = { id: string; alert_id: string; user_id: string; intensity: number | null; answers_json: string; latitude: number; longitude: number; distance_km: number; created_at: string; updated_at: string };

const app = express();
app.use(helmet());
app.use(cors({ origin: config.clientOrigin === "*" ? true : config.clientOrigin }));
app.use(express.json({ limit: "2mb" }));
// The app refreshes several read-only endpoints in parallel; 300 requests per
// 15 minutes was exhausted by normal live synchronization on a single device.
app.use(rateLimit({ windowMs: 15 * 60 * 1000, limit: 3000 }));
app.use("/api", (_req, res, next) => {
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
  res.setHeader("Pragma", "no-cache");
  res.setHeader("Expires", "0");
  next();
});

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20 });
const server = createServer(app);
const alertSockets = new WebSocketServer({
  server,
  path: "/api/v1/alerts/live",
  maxPayload: 1024
});
const alertsUpdated = JSON.stringify({ type: "alerts.updated" });
function broadcastUpdate(type: "alerts.updated" | "reports.updated") {
  const message = type === "alerts.updated" ? alertsUpdated : JSON.stringify({ type });
  for (const socket of alertSockets.clients) {
    if (socket.readyState === WebSocket.OPEN && socket.bufferedAmount === 0) socket.send(message);
  }
}
function broadcastAlertsUpdated() { broadcastUpdate("alerts.updated"); }
function broadcastReportsUpdated() { broadcastUpdate("reports.updated"); }

alertSockets.on("connection", (socket) => {
  socket.on("error", () => socket.terminate());
  socket.send(alertsUpdated);
});

const officialAlertsIngestion = new OfficialAlertsIngestion(() => {
  broadcastAlertsUpdated();
});
const registerSchema = z.object({ name: z.string().trim().min(2).max(80), email: z.string().trim().email().transform((v) => v.toLowerCase()), password: z.string().min(8).max(100) });
const loginSchema = z.object({ email: z.string().email().transform((v) => v.toLowerCase()), password: z.string().min(1) });
const reportSchema = z.object({ incidentType: z.enum(["NATURAL_DISASTER", "OTHER_INCIDENT"]).default("NATURAL_DISASTER"), category: z.string().trim().min(2).max(40), description: z.string().trim().min(5).max(1000), latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180), severity: z.enum(["LOW", "MEDIUM", "HIGH", "CRITICAL"]).default("MEDIUM"), photoUrl: z.string().url().nullable().optional(), photoData: z.string().max(1_600_000).regex(/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/).optional() });
const voteSchema = z.object({ type: z.enum(["CONFIRM", "DISPUTE"]), latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) });
const assessmentSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  intensity: z.number().int().min(1).max(5).optional(),
  answers: z.record(z.string(), z.string()).default({})
});
type ImpactPolygon = { id: string; label: string | null; coordinates: { longitude: number; latitude: number }[] };
const impactGeometryCache = new Map<string, { expiresAt: number; polygons: ImpactPolygon[] }>();

// A point-only provider (for example IGP/CENSIS) has no official perimeter.
// Return a deliberately labelled reference radius so the map can still show
// approximate context without presenting it as provider-confirmed geography.
function estimateImpactRadiusKm(alert: Pick<AlertRow, "category" | "title" | "description" | "severity">): number {
  const severityFactor: Record<string, number> = { LOW: 0.7, MEDIUM: 1, HIGH: 1.3, CRITICAL: 1.6 };
  const category = alert.category.toUpperCase();
  let baseRadiusKm = 5;
  if (category.includes("SISMO") || category.includes("EARTHQUAKE")) {
    const text = `${alert.title} ${alert.description}`;
    const magnitudeMatch = text.match(/(?:magnitud|magnitude)\s*(?:de\s*)?(\d+(?:[.,]\d+)?)/i)
      ?? text.match(/\bM\s*(\d+(?:[.,]\d+)?)/i);
    const depthMatch = text.match(/(?:profundidad|depth)\s*:?\s*(\d+(?:[.,]\d+)?)\s*km/i);
    const magnitude = magnitudeMatch ? Number(magnitudeMatch[1].replace(",", ".")) : 4;
    const depth = depthMatch ? Number(depthMatch[1].replace(",", ".")) : 0;
    baseRadiusKm = Math.min(200, Math.max(5, 10 ** (0.5 * magnitude - 1) * (1 + Math.min(depth, 200) / 200)));
  } else if (category.includes("INUND") || category.includes("FLOOD")) baseRadiusKm = 8;
  else if (category.includes("HUAICO") || category.includes("DERRUMBE") || category.includes("LANDSLIDE")) baseRadiusKm = 6;
  else if (category.includes("INCEND") || category.includes("FIRE")) baseRadiusKm = 4;
  else if (category.includes("VOLCAN") || category.includes("VOLCANO")) baseRadiusKm = 12;
  else if (category.includes("CLIMA") || category.includes("STORM") || category.includes("CYCLONE")) baseRadiusKm = 20;
  const publishedRadiusMatch = alert.description.match(/alcance publicado:\s*(\d+(?:[.,]\d+)?)\s*km/i);
  if (publishedRadiusMatch) baseRadiusKm = Number(publishedRadiusMatch[1].replace(",", "."));
  const factor = severityFactor[alert.severity.toUpperCase()] ?? 1;
  return Math.round(Math.min(250, Math.max(1, baseRadiusKm * factor)) * 10) / 10;
}

app.use("/admin", express.static(join(process.cwd(), "public/admin"), { index: "index.html" }));
app.use("/api/v1/admin", createAdminRouter(officialAlertsIngestion, broadcastAlertsUpdated));

app.get("/", (_req, res) => res.redirect("/admin/"));
app.get("/health", (_req, res) => res.json({ ok: true, service: "sentinel-api", time: new Date().toISOString() }));

app.post("/api/v1/auth/register", authLimiter, async (req, res, next) => {
  try {
    const input = registerSchema.parse(req.body);
    if (get("SELECT id FROM users WHERE email = ?", input.email)) return res.status(409).json({ error: "Este correo ya está registrado. Inicia sesión o usa otro correo." });
    const now = new Date().toISOString();
    const user: UserRow = { id: randomUUID(), name: input.name, email: input.email, password_hash: await bcrypt.hash(input.password, 12), role: "USER", reputation: 0, gender: null, birth_year: null, avatar_data: null, created_at: now };
    run("INSERT INTO users (id, name, email, password_hash, role, reputation, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", user.id, user.name, user.email, user.password_hash, user.role, user.reputation, now, now);
    return res.status(201).json({ user: publicUser(user), accessToken: signToken({ userId: user.id, role: user.role }) });
  } catch (error) { next(error); }
});

app.post("/api/v1/auth/login", authLimiter, async (req, res, next) => {
  try {
    const input = loginSchema.parse(req.body);
    const user = get<UserRow>("SELECT * FROM users WHERE email = ?", input.email);
    if (!user || !(await bcrypt.compare(input.password, user.password_hash))) return res.status(401).json({ error: "Correo o contraseña incorrectos" });
    return res.json({ user: publicUser(user), accessToken: signToken({ userId: user.id, role: user.role }) });
  } catch (error) { next(error); }
});

app.get("/api/v1/me", requireAuth, (req, res) => {
  const user = get<UserRow>("SELECT * FROM users WHERE id = ?", req.auth!.userId);
  if (!user) return res.status(404).json({ error: "Usuario no encontrado" });
  return res.json({ user: publicUser(user) });
});

app.get("/api/v1/me/avatar", requireAuth, (req, res) => {
  const user = get<Pick<UserRow, "avatar_data">>("SELECT avatar_data FROM users WHERE id = ?", req.auth!.userId);
  if (!user) return res.status(404).json({ error: "Usuario no encontrado" });
  return res.json({ avatarBase64: user.avatar_data });
});

app.patch("/api/v1/me/profile", requireAuth, (req, res, next) => {
  try {
    const input = profileSchema.parse(req.body);
    const updates: string[] = [];
    const values: unknown[] = [];
    if (input.name !== undefined) { updates.push("name = ?"); values.push(input.name); }
    if (input.gender !== undefined) { updates.push("gender = ?"); values.push(input.gender); }
    if (input.birthYear !== undefined) { updates.push("birth_year = ?"); values.push(input.birthYear); }
    if (input.avatarBase64 !== undefined) { updates.push("avatar_data = ?"); values.push(input.avatarBase64); }
    updates.push("updated_at = ?"); values.push(new Date().toISOString(), req.auth!.userId);
    run(`UPDATE users SET ${updates.join(", ")} WHERE id = ?`, ...values);
    const user = get<UserRow>("SELECT * FROM users WHERE id = ?", req.auth!.userId);
    return res.json({ user: user ? publicUser(user) : null });
  } catch (error) { next(error); }
});

app.post("/api/v1/me/password", authLimiter, requireAuth, async (req, res, next) => {
  try {
    const input = passwordSchema.parse(req.body);
    const user = get<UserRow>("SELECT * FROM users WHERE id = ?", req.auth!.userId);
    if (!user || !(await bcrypt.compare(input.currentPassword, user.password_hash))) return res.status(401).json({ error: "La contraseña actual no es correcta." });
    if (input.currentPassword === input.newPassword) return res.status(400).json({ error: "La nueva contraseña debe ser diferente." });
    const passwordHash = await bcrypt.hash(input.newPassword, 12);
    run("UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?", passwordHash, new Date().toISOString(), req.auth!.userId);
    return res.status(204).send();
  } catch (error) { next(error); }
});

app.get("/api/v1/reports", (req, res) => {
  const category = typeof req.query.category === "string" ? req.query.category : undefined;
  const status = typeof req.query.status === "string" ? req.query.status : undefined;
  const reports = all<ReportRow & { user_name: string; user_reputation: number }>("SELECT r.*, u.name AS user_name, u.reputation AS user_reputation FROM reports r JOIN users u ON u.id = r.user_id WHERE (? IS NULL OR r.category = ?) AND (? IS NULL OR r.status = ?) ORDER BY r.created_at DESC LIMIT 100", category ?? null, category ?? null, status ?? null, status ?? null);
  return res.json({ reports: reports.map(publicReport) });
});

app.get("/api/v1/reports/nearby", (req, res) => {
  const latitude = Number(req.query.latitude);
  const longitude = Number(req.query.longitude);
  const radiusKm = Math.min(Math.max(Number(req.query.radiusKm ?? 100), 1), 100);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return res.status(400).json({ error: "latitude y longitude son requeridos" });
  const reports = all<ReportRow & { user_name: string; user_reputation: number; distance_km: number }>(
    `SELECT r.*, u.name AS user_name, u.reputation AS user_reputation,
      (6371 * acos(cos(radians(?)) * cos(radians(r.latitude)) * cos(radians(r.longitude) - radians(?)) + sin(radians(?)) * sin(radians(r.latitude)))) AS distance_km
     FROM reports r JOIN users u ON u.id = r.user_id
     WHERE r.created_at >= ? AND (6371 * acos(cos(radians(?)) * cos(radians(r.latitude)) * cos(radians(r.longitude) - radians(?)) + sin(radians(?)) * sin(radians(r.latitude)))) <= ?
     ORDER BY distance_km ASC LIMIT 200`,
    latitude, longitude, latitude,
    new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
    latitude, longitude, latitude, radiusKm
  );
  const nearbyReports = reports
    .filter((report) => report.distance_km <= Math.min(radiusKm, attentionRadiusKm(report.category)))
    .sort((a, b) => a.distance_km - b.distance_km || severityRank(b.severity) - severityRank(a.severity));
  return res.json({ reports: nearbyReports.map((report) => ({ ...publicReport(report), distanceKm: report.distance_km })) });
});

// Consulta global para el mapa/listado. No debe reutilizarse para notificaciones:
// la app consulta /nearby para decidir qué merece una alerta local.
app.get("/api/v1/reports/peru", (_req, res) => {
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const reports = all<ReportRow & { user_name: string; user_reputation: number }>(
    `SELECT r.*, u.name AS user_name, u.reputation AS user_reputation
     FROM reports r JOIN users u ON u.id = r.user_id
     WHERE r.latitude BETWEEN ? AND ? AND r.longitude BETWEEN ? AND ?
       AND r.status != 'DISMISSED' AND r.created_at >= ?
     ORDER BY r.created_at DESC LIMIT 500`,
    PERU_BOUNDS.minLatitude, PERU_BOUNDS.maxLatitude, PERU_BOUNDS.minLongitude, PERU_BOUNDS.maxLongitude, dayAgo
  );
  return res.json({ scope: "PERU", reports: reports.map(publicReport) });
});


app.get("/api/v1/reports/history", (_req, res) => {
  const yearAgo = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString();
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const reports = all<ReportRow & { user_name: string; user_reputation: number }>(
    `SELECT r.*, u.name AS user_name, u.reputation AS user_reputation
     FROM reports r JOIN users u ON u.id = r.user_id
     WHERE r.latitude BETWEEN ? AND ? AND r.longitude BETWEEN ? AND ?
       AND r.status != 'DISMISSED' AND r.created_at >= ? AND r.created_at < ?
     ORDER BY r.created_at DESC LIMIT 1000`,
    PERU_BOUNDS.minLatitude, PERU_BOUNDS.maxLatitude, PERU_BOUNDS.minLongitude, PERU_BOUNDS.maxLongitude, yearAgo, dayAgo
  );
  return res.json({ scope: "HISTORY", reports: reports.map(publicReport) });
});

app.post("/api/v1/reports", requireAuth, (req, res, next) => {
  try {
    const input = reportSchema.parse(req.body);
    if (!isPeruCoordinate(input.latitude, input.longitude)) return res.status(400).json({ error: "El reporte debe estar ubicado en Perú." });
    const now = new Date().toISOString();
    const cooldownMs = 15 * 60 * 1000;
    const lastReport = get<{ created_at: string }>("SELECT created_at FROM reports WHERE user_id = ? ORDER BY created_at DESC LIMIT 1", req.auth!.userId);
    const remainingSeconds = lastReport ? Math.ceil((Date.parse(lastReport.created_at) + cooldownMs - Date.now()) / 1000) : 0;
    if (remainingSeconds > 0) return res.status(429).json({ error: `Ya enviaste un reporte. Podrás enviar otro en ${Math.ceil(remainingSeconds / 60)} min.`, retryAfterSeconds: remainingSeconds });
    const rules = disasterRules(input.category);
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const candidates = all<ReportRow>("SELECT * FROM reports WHERE category = ? AND created_at >= ? AND status NOT IN ('DISMISSED','CLOSED')", input.category, cutoff);
    const connected: ReportRow[] = [];
    const frontier = [{ latitude: input.latitude, longitude: input.longitude }];
    const remaining = new Map(candidates.map((report) => [report.id, report]));
    while (frontier.length) {
      const point = frontier.shift()!;
      for (const [id, candidate] of remaining) {
        const distance = distanceKmBetween(point.latitude, point.longitude, candidate.latitude, candidate.longitude);
        if (distance < 0.001) return res.status(409).json({ error: "Ya existe un reporte prácticamente en este punto (menos de 1 m). No se contará como otro reporte." });
        if (distance <= rules.radiusKm) {
          connected.push(candidate);
          remaining.delete(id);
          frontier.push({ latitude: candidate.latitude, longitude: candidate.longitude });
        }
      }
    }
    if (connected.some((report) => report.user_id === req.auth!.userId)) return res.status(409).json({ error: "Ya reportaste este mismo evento desde esta zona." });
    const clusterId = connected.find((report) => report.cluster_id)?.cluster_id ?? randomUUID();
    const mergedIds = [...new Set(connected.map((report) => report.cluster_id).filter((value): value is string => Boolean(value)))];
    for (const mergedId of mergedIds) if (mergedId !== clusterId) run("UPDATE reports SET cluster_id = ? WHERE cluster_id = ?", clusterId, mergedId);
    for (const report of connected) if (!report.cluster_id) run("UPDATE reports SET cluster_id = ? WHERE id = ?", clusterId, report.id);
    const count = connected.length + 1;
    const status = count >= rules.minimum ? "UNDER_REVIEW" : "COLLECTING";
    const id = randomUUID();
    run("INSERT INTO reports (id, user_id, category, description, latitude, longitude, severity, status, photo_url, validation_radius_km, cluster_id, cluster_report_count, cluster_min_reporters, cluster_radius_km, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", id, req.auth!.userId, input.category, input.description, input.latitude, input.longitude, input.severity, status, input.photoData ?? input.photoUrl ?? null, REPORT_VALIDATION_RADIUS_KM, clusterId, count, rules.minimum, rules.radiusKm, now, now);
    run("UPDATE reports SET cluster_report_count = ?, cluster_min_reporters = ?, cluster_radius_km = ?, status = CASE WHEN status IN ('COLLECTING','PENDING') AND ? >= ? THEN 'UNDER_REVIEW' ELSE status END, updated_at = ? WHERE cluster_id = ?", count, rules.minimum, rules.radiusKm, count, rules.minimum, now, clusterId);
    broadcastReportsUpdated();
    const report = get<EnrichedReportRow>("SELECT r.*, u.name AS user_name, u.reputation AS user_reputation FROM reports r JOIN users u ON u.id = r.user_id WHERE r.id = ?", id);
    return res.status(201).json({ report: report ? publicReport(report) : null });
  } catch (error) { next(error); }
});

app.get("/api/v1/reports/:id", (req, res) => {
  const report = get<ReportRow & { user_name: string; user_reputation: number }>("SELECT r.*, u.name AS user_name, u.reputation AS user_reputation FROM reports r JOIN users u ON u.id = r.user_id WHERE r.id = ?", String(req.params.id));
  if (!report) return res.status(404).json({ error: "Reporte no encontrado" });
  return res.json({ report: publicReport(report) });
});

app.get("/api/v1/reports/:id/photo", (req, res) => {
  const report = get<{ photo_url: string | null }>("SELECT photo_url FROM reports WHERE id = ?", String(req.params.id));
  const match = report?.photo_url?.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+={0,2})$/);
  if (!match) return res.status(404).json({ error: "Este reporte no tiene una foto disponible." });
  res.setHeader("Cache-Control", "public, max-age=86400");
  res.type(match[1]).send(Buffer.from(match[2], "base64"));
});

app.post("/api/v1/reports/:id/vote", requireAuth, (req, res, next) => {
  try {
    const input = voteSchema.parse(req.body);
    const reportId = String(req.params.id);
    const report = get<ReportRow>("SELECT * FROM reports WHERE id = ?", reportId);
    if (!report) return res.status(404).json({ error: "Reporte no encontrado" });
    if (["DISMISSED", "CLOSED"].includes(report.status)) return res.status(409).json({ error: "Este reporte ya no admite validaciones." });
    const distanceKm = distanceKmBetween(report.latitude, report.longitude, input.latitude, input.longitude);
    if (distanceKm > report.validation_radius_km) {
      return res.status(403).json({ error: `Solo puedes confirmar o desmentir este reporte dentro de ${report.validation_radius_km} km.`, distanceKm, validationRadiusKm: report.validation_radius_km });
    }
    const id = randomUUID();
    run("INSERT INTO report_votes (id, report_id, user_id, type, created_at) VALUES (?, ?, ?, ?, ?)", id, reportId, req.auth!.userId, input.type, new Date().toISOString());
    const confirmations = Number(get<{ count: number }>("SELECT COUNT(*) AS count FROM report_votes WHERE report_id = ? AND type = 'CONFIRM'", reportId)?.count ?? 0);
    const disputes = Number(get<{ count: number }>("SELECT COUNT(*) AS count FROM report_votes WHERE report_id = ? AND type = 'DISPUTE'", reportId)?.count ?? 0);
    const status = confirmations >= 3 && confirmations > disputes ? "COMMUNITY_VERIFIED" : disputes >= 3 && disputes > confirmations ? "UNDER_REVIEW" : report.status;
    run("UPDATE reports SET confirmations = ?, disputes = ?, status = ?, updated_at = ? WHERE id = ?", confirmations, disputes, status, new Date().toISOString(), reportId);
    broadcastReportsUpdated();
    const updatedReport = get<EnrichedReportRow>("SELECT r.*, u.name AS user_name, u.reputation AS user_reputation FROM reports r JOIN users u ON u.id = r.user_id WHERE r.id = ?", reportId);
    return res.status(201).json({ vote: { id, type: input.type, distanceKm }, report: updatedReport ? publicReport({ ...updatedReport, distance_km: distanceKm }) : null });
  } catch (error) { next(error); }
});

app.delete("/api/v1/reports/:id", requireAuth, (req, res) => {
  const reportId = String(req.params.id);
  const report = get<ReportRow>("SELECT * FROM reports WHERE id = ?", reportId);
  if (!report) return res.status(404).json({ error: "Reporte no encontrado" });
  if (report.user_id !== req.auth!.userId && req.auth!.role !== "ADMIN") return res.status(403).json({ error: "No puedes eliminar este reporte" });
  run("DELETE FROM reports WHERE id = ?", reportId);
  broadcastReportsUpdated();
  return res.status(204).send();
});

app.get("/api/v1/alerts", (_req, res) => {
  return res.json({ scope: "PERU", alerts: all<AlertRow>("SELECT * FROM official_alerts ORDER BY published_at DESC LIMIT 500").map(publicAlert) });
});

app.get("/api/v1/alerts/peru", (_req, res) => {
  const yearAgo = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString();
  const alerts = all<AlertRow>("SELECT * FROM official_alerts WHERE published_at >= ? ORDER BY published_at DESC LIMIT 1000", yearAgo);
  return res.json({ scope: "PERU", alerts: alerts.filter((alert) => alert.record_type !== "PREDICTION" && isAlertActive(alert)).map(publicAlert) });
});

app.get("/api/v1/alerts/history", (_req, res) => {
  const yearAgo = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString();
  const alerts = all<AlertRow>("SELECT * FROM official_alerts WHERE published_at >= ? ORDER BY published_at DESC LIMIT 1000", yearAgo);
  return res.json({ scope: "HISTORY", alerts: alerts.filter((alert) => alert.record_type !== "PREDICTION" && !isAlertActive(alert)).map(publicAlert) });
});

app.get("/api/v1/alerts/:id/geometry", async (req, res) => {
  const alert = get<{ source: string; external_id: string; category: string; title: string; description: string; severity: string }>("SELECT source, external_id, category, title, description, severity FROM official_alerts WHERE id = ?", String(req.params.id));
  if (!alert) return res.status(404).json({ error: "Alerta no encontrada." });
  const estimatedRadiusKm = estimateImpactRadiusKm(alert);
  const estimatedArea = { source: alert.source, polygons: [], geometryAvailable: false, areaType: "ESTIMATED", estimatedRadiusKm };
  if (alert.source !== "GDACS") return res.json(estimatedArea);
  const [, eventType, eventId, episodeId] = alert.external_id.split(":");
  if (!eventType || !["EQ", "TC", "FL", "WF", "DR", "VO"].includes(eventType) || !/^\d+$/.test(eventId ?? "")) {
    return res.json(estimatedArea);
  }

  const cacheKey = `${eventType}:${eventId}:${episodeId ?? ""}`;
  const cached = impactGeometryCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return res.json(cached.polygons.length
    ? { source: alert.source, polygons: cached.polygons, geometryAvailable: true, areaType: "OFFICIAL", estimatedRadiusKm: null }
    : estimatedArea);

  const params = new URLSearchParams({ eventtype: eventType, eventid: eventId });
  if (episodeId && /^\d+$/.test(episodeId)) params.set("episodeid", episodeId);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetch(`https://www.gdacs.org/gdacsapi/api/polygons/getgeometry?${params}`, {
      signal: controller.signal,
      headers: { accept: "application/json", "user-agent": "Sentinel-API/1.0" }
    });
    if (!response.ok) throw new Error(`GDACS respondió HTTP ${response.status}`);
    const payload: unknown = await response.json();
    const polygons = extractImpactPolygons(payload, { eventType, eventId, episodeId });
    impactGeometryCache.set(cacheKey, { expiresAt: Date.now() + 6 * 60 * 60 * 1000, polygons });
    return res.json(polygons.length
      ? { source: alert.source, polygons, geometryAvailable: true, areaType: "OFFICIAL", estimatedRadiusKm: null }
      : estimatedArea);
  } catch (error) {
    console.warn("[official-alerts] No se pudo cargar el perímetro GDACS:", error instanceof Error ? error.message : error);
    return res.json({ ...estimatedArea, areaType: "ESTIMATED", geometryError: "No se pudo cargar el polígono oficial de GDACS." });
  } finally {
    clearTimeout(timeout);
  }
});

app.get("/api/v1/predictions/peru", (_req, res) => {
  const yearAgo = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString();
  const predictions = all<AlertRow>("SELECT * FROM official_alerts WHERE record_type = 'PREDICTION' AND published_at >= ? ORDER BY published_at DESC LIMIT 100", yearAgo)
    .filter((prediction) => isAlertActive(prediction)).map(publicAlert);
  return res.json({
    scope: "PERU",
    predictions,
    available: predictions.length > 0,
    sources: [...new Set(predictions.map((prediction) => prediction.source))]
  });
});

app.get("/api/v1/alerts/nearby", (req, res) => {
  const latitude = Number(req.query.latitude);
  const longitude = Number(req.query.longitude);
  const radiusKm = Math.min(Math.max(Number(req.query.radiusKm ?? REGION_RADIUS_KM), 1), 100);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return res.status(400).json({ error: "latitude y longitude son requeridos" });
  const since = typeof req.query.since === "string" ? new Date(req.query.since) : null;
  if (since && Number.isNaN(since.getTime())) return res.status(400).json({ error: "since debe ser una fecha ISO válida" });
  const alerts = all<AlertRow>("SELECT * FROM official_alerts WHERE published_at >= ? ORDER BY published_at DESC LIMIT 1000",
      new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString())
    .map((alert) => ({ alert, distanceKm: alert.latitude === null || alert.longitude === null ? null : distanceKmBetween(latitude, longitude, alert.latitude, alert.longitude) }))
    // Sin coordenadas no existe forma segura de saber si el usuario está en el
    // radio; por eso nunca se envían a la bandeja de alertas locales.
    .filter(({ alert, distanceKm }) => alert.record_type !== "PREDICTION" && isAlertActive(alert) && distanceKm !== null
      && distanceKm <= Math.min(radiusKm, attentionRadiusKm(alert.category))
      && (!since || new Date(alert.published_at) > since))
    .sort((first, second) => (first.distanceKm ?? 0) - (second.distanceKm ?? 0))
    .slice(0, 100)
    .map(({ alert, distanceKm }) => ({ ...publicAlert(alert), distanceKm }));
  return res.json({ scope: "NEARBY", latitude, longitude, radiusKm, alerts });
});

app.post("/api/v1/alerts/:id/assessment", requireAuth, (req, res, next) => {
  try {
    const input = assessmentSchema.parse(req.body);
    if (!isPeruCoordinate(input.latitude, input.longitude)) return res.status(400).json({ error: "La evaluación debe enviarse desde una ubicación en Perú." });
    const alert = get<AlertRow>("SELECT * FROM official_alerts WHERE id = ?", String(req.params.id));
    if (!alert) return res.status(404).json({ error: "Alerta no encontrada" });
    const allowedIds = allowedQuestionIds(alert.category);
    const unknownAnswer = Object.keys(input.answers).find((key) => !allowedIds.has(key));
    if (unknownAnswer) return res.status(400).json({ error: `Pregunta no válida para este tipo de desastre: ${unknownAnswer}` });
    if (alert.latitude === null || alert.longitude === null) return res.status(409).json({ error: "Esta alerta no tiene una ubicación verificable para evaluar proximidad." });
    const distanceKm = distanceKmBetween(input.latitude, input.longitude, alert.latitude, alert.longitude);
    if (distanceKm > REGION_RADIUS_KM) return res.status(403).json({ error: `Solo puedes evaluar esta alerta dentro de ${REGION_RADIUS_KM} km.`, distanceKm, radiusKm: REGION_RADIUS_KM });
    const now = new Date().toISOString();
    const existing = get<AssessmentRow>("SELECT id FROM alert_assessments WHERE alert_id = ? AND user_id = ?", String(req.params.id), req.auth!.userId);
    const id = existing?.id ?? randomUUID();
    run(`INSERT INTO alert_assessments (id, alert_id, user_id, intensity, answers_json, latitude, longitude, distance_km, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(alert_id, user_id) DO UPDATE SET intensity = excluded.intensity, answers_json = excluded.answers_json,
           latitude = excluded.latitude, longitude = excluded.longitude, distance_km = excluded.distance_km, updated_at = excluded.updated_at`,
      id, String(req.params.id), req.auth!.userId, input.intensity ?? null, JSON.stringify(input.answers), input.latitude, input.longitude, distanceKm, existing ? get<AssessmentRow>("SELECT created_at FROM alert_assessments WHERE id = ?", id)?.created_at ?? now : now, now);
    return res.status(existing ? 200 : 201).json({ assessment: { id, alertId: String(req.params.id), intensity: input.intensity ?? null, answers: input.answers, distanceKm, updatedAt: now } });
  } catch (error) { next(error); }
});

app.get("/api/v1/alerts/:id/questionnaire", (req, res) => {
  const alert = get<AlertRow>("SELECT * FROM official_alerts WHERE id = ?", String(req.params.id));
  if (!alert) return res.status(404).json({ error: "Alerta no encontrada" });
  return res.json({ alert: publicAlert(alert), questions: questionnaireForCategory(alert.category), emergencyContacts: emergencyContactsForCategory(alert.category) });
});

app.get("/api/v1/alerts/sources", (_req, res) => {
  return res.json({ sources: officialAlertsIngestion.status() });
});

app.post("/api/v1/admin/alerts", requireAuth, requireAdmin, (req, res, next) => {
  try {
    const input = z.object({ externalId: z.string().min(1), source: z.string().min(1), title: z.string().min(1), description: z.string().min(1), category: z.string().min(1), latitude: z.number().optional(), longitude: z.number().optional(), severity: z.enum(["LOW", "MEDIUM", "HIGH", "CRITICAL"]).default("MEDIUM"), sourceUrl: z.string().url().optional(), publishedAt: z.string().datetime().optional() }).parse(req.body);
    const id = randomUUID();
    run("INSERT INTO official_alerts (id, external_id, source, title, description, category, latitude, longitude, severity, source_url, published_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", id, input.externalId, input.source, input.title, input.description, input.category, input.latitude ?? null, input.longitude ?? null, input.severity, input.sourceUrl ?? null, input.publishedAt ?? new Date().toISOString(), new Date().toISOString());
    return res.status(201).json({ alert: get("SELECT * FROM official_alerts WHERE id = ?", id) });
  } catch (error) { next(error); }
});

app.patch("/api/v1/admin/reports/:id/status", requireAuth, requireAdmin, (req, res, next) => {
  try {
    const status = z.enum(["PENDING", "UNDER_REVIEW", "COMMUNITY_VERIFIED", "OFFICIALLY_VERIFIED", "DISMISSED", "CLOSED"]).parse(req.body.status);
    const reportId = String(req.params.id);
    const result = run("UPDATE reports SET status = ?, updated_at = ? WHERE id = ?", status, new Date().toISOString(), reportId);
    if (result.changes === 0) return res.status(404).json({ error: "Reporte no encontrado" });
    broadcastReportsUpdated();
    return res.json({ report: get("SELECT * FROM reports WHERE id = ?", reportId) });
  } catch (error) { next(error); }
});

app.get("/api/v1/analytics/summary", requireAuth, (_req, res) => {
  const count = (sql: string) => Number(get<{ count: number }>(sql)?.count ?? 0);
  return res.json({ users: count("SELECT COUNT(*) AS count FROM users"), reports: count("SELECT COUNT(*) AS count FROM reports"), verifiedReports: count("SELECT COUNT(*) AS count FROM reports WHERE status = 'COMMUNITY_VERIFIED'"), pendingReports: count("SELECT COUNT(*) AS count FROM reports WHERE status = 'PENDING'"), byCategory: all("SELECT category, COUNT(*) AS count FROM reports GROUP BY category ORDER BY count DESC") });
});

app.get("/api/v1/admin/reports", requireAuth, requireAdmin, (_req, res) => res.json({ reports: all("SELECT r.*, u.name AS user_name, u.email AS user_email FROM reports r JOIN users u ON u.id = r.user_id ORDER BY r.created_at DESC") }));

app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (error instanceof z.ZodError) return res.status(400).json({ error: "Datos inválidos", details: error.flatten() });
  if (error instanceof Error && error.message.includes("UNIQUE constraint failed")) return res.status(409).json({ error: "Ya existe un registro para esta acción" });
  console.error(error);
  return res.status(500).json({ error: "Error interno del servidor" });
});

function publicUser(user: Pick<UserRow, "id" | "name" | "email" | "role" | "reputation" | "gender" | "birth_year" | "avatar_data" | "created_at">) {
  return { id: user.id, name: user.name, email: user.email, role: user.role, reputation: user.reputation, gender: user.gender, birthYear: user.birth_year, hasProfilePhoto: Boolean(user.avatar_data), createdAt: user.created_at };
}

function disasterRules(categoryValue: string) {
  const category = categoryValue.toUpperCase();
  if (category.includes("SISMO") || category.includes("EARTHQUAKE")) return { minimum: 5, radiusKm: 25 };
  if (category.includes("TSUNAMI")) return { minimum: 5, radiusKm: 30 };
  if (category.includes("INUND") || category.includes("FLOOD")) return { minimum: 4, radiusKm: 5 };
  if (category.includes("HUAICO") || category.includes("ALUVION")) return { minimum: 4, radiusKm: 6 };
  if (category.includes("INCEND") || category.includes("FIRE")) return { minimum: 4, radiusKm: 3 };
  if (category.includes("DERRUMB") || category.includes("DESLIZ") || category.includes("GLACIAR") || category.includes("LANDSLIDE")) return { minimum: 3, radiusKm: 3 };
  if (category.includes("VOLCAN") || category.includes("LAHAR") || category.includes("PIROCLAST")) return { minimum: 5, radiusKm: 20 };
  if (category.includes("CLIMA") || category.includes("STORM") || category.includes("LLUVIA") || category.includes("TORMENTA") || category.includes("CICLON")) return { minimum: 5, radiusKm: 15 };
  if (category.includes("SEQUIA") || category.includes("FRIAJE") || category.includes("HELADA") || category.includes("NEVADA") || category.includes("GRANIZADA") || category.includes("OLA_CALOR") || category.includes("OLEAJE") || category.includes("NINO")) return { minimum: 5, radiusKm: 15 };
  return { minimum: 5, radiusKm: 5 };
}

function extractImpactPolygons(payload: unknown, eventKey: { eventType: string; eventId: string; episodeId?: string }): ImpactPolygon[] {
  if (!payload || typeof payload !== "object" || !("features" in payload) || !Array.isArray(payload.features)) return [];
  const polygons: ImpactPolygon[] = [];
  for (const [featureIndex, rawFeature] of payload.features.entries()) {
    if (!rawFeature || typeof rawFeature !== "object" || !("geometry" in rawFeature)) continue;
    const feature = rawFeature as { geometry?: { type?: unknown; coordinates?: unknown }; properties?: { polygonlabel?: unknown; eventtype?: unknown; eventid?: unknown; episodeid?: unknown; Class?: unknown } };
    const geometry = feature.geometry;
    if (!geometry || !Array.isArray(geometry.coordinates)) continue;
    const properties = feature.properties;
    if (properties?.eventtype !== undefined && String(properties.eventtype).toUpperCase() !== eventKey.eventType.toUpperCase()) continue;
    if (properties?.eventid !== undefined && String(properties.eventid) !== eventKey.eventId) continue;
    if (eventKey.episodeId && properties?.episodeid !== undefined && String(properties.episodeid) !== eventKey.episodeId) continue;
    const label = typeof feature.properties?.polygonlabel === "string" ? feature.properties.polygonlabel : null;
    const polygonClass = typeof properties?.Class === "string" ? properties.Class : "";
    if (label?.trim().toLowerCase() === "global area" || polygonClass.toLowerCase() === "poly_global") continue;
    const rings: unknown[] = geometry.type === "Polygon"
      ? [geometry.coordinates[0]]
      : geometry.type === "MultiPolygon"
        ? geometry.coordinates.map((polygon) => Array.isArray(polygon) ? polygon[0] : null)
        : [];
    for (const [ringIndex, rawRing] of rings.entries()) {
      if (!Array.isArray(rawRing) || rawRing.length < 4) continue;
      const step = Math.max(1, Math.ceil(rawRing.length / 800));
      const sampled = rawRing.filter((_point, index) => index % step === 0 || index === rawRing.length - 1);
      const coordinates: ImpactPolygon["coordinates"] = [];
      for (const rawPosition of sampled) {
        if (!Array.isArray(rawPosition) || rawPosition.length < 2) continue;
        const longitude = Number(rawPosition[0]);
        const latitude = Number(rawPosition[1]);
        if (!Number.isFinite(longitude) || !Number.isFinite(latitude) || Math.abs(longitude) > 180 || Math.abs(latitude) > 90) continue;
        coordinates.push({ longitude, latitude });
      }
      if (coordinates.length >= 4) polygons.push({ id: `${featureIndex}-${ringIndex}`, label, coordinates });
      if (polygons.length >= 16) return polygons;
    }
  }
  return polygons;
}

function publicReport(report: EnrichedReportRow) {
  return {
    id: report.id,
    category: report.category,
    description: report.description,
    latitude: report.latitude,
    longitude: report.longitude,
    severity: report.severity,
    status: report.status,
    photoUrl: report.photo_url?.startsWith("data:image/") ? `/api/v1/reports/${report.id}/photo` : report.photo_url,
    validationRadiusKm: report.validation_radius_km,
    clusterId: report.cluster_id,
    clusterReportCount: report.cluster_report_count,
    clusterMinimumReports: report.cluster_min_reporters,
    clusterRadiusKm: report.cluster_radius_km,
    distanceKm: report.distance_km,
    confirmations: report.confirmations,
    disputes: report.disputes,
    createdAt: report.created_at,
    updatedAt: report.updated_at,
    user: report.user_name ? { name: report.user_name, reputation: report.user_reputation } : undefined
  };
}
function publicAlert(alert: AlertRow) {
  return { id: alert.id, externalId: alert.external_id, source: alert.source, title: alert.title, description: alert.description, category: alert.category, latitude: alert.latitude, longitude: alert.longitude, severity: alert.severity, sourceUrl: alert.source_url, publishedAt: alert.published_at, expiresAt: alert.expires_at ?? null, isActive: isAlertActive(alert), recordType: alert.record_type === "PREDICTION" ? "PREDICTION" as const : "ALERT" as const };
}

function isAlertActive(alert: AlertRow, now = Date.now()): boolean {
  const published = Date.parse(alert.published_at);
  if (!Number.isFinite(published)) return false;
  if (alert.expires_at && Number.isFinite(Date.parse(alert.expires_at))) return Date.parse(alert.expires_at) >= now;
  if (published > now) return true;
  const ageDays = (now - published) / 86_400_000;
  const category = alert.category.toUpperCase();
  const activeWindowDays = category.includes("SISMO") || category.includes("EARTHQUAKE") ? 1
    : category.includes("INUND") || category.includes("FLOOD") || category.includes("HUAICO")
      || category.includes("INCEND") || category.includes("FIRE") || category.includes("VOLCAN")
      || category.includes("STORM") || category.includes("CYCLONE") || category.includes("LLUVIA")
      || category.includes("TORMENTA") || category.includes("FRIAJE") || category.includes("HELADA")
      || category.includes("NEVADA") || category.includes("OLA_CALOR") || category.includes("TSUNAMI")
      || category.includes("CENIZA") || category.includes("LAHAR") || category.includes("DERRUMBE")
      || category.includes("DESLIZ") || category.includes("ALUVION") || category.includes("GLACIAR")
      || category.includes("GRANIZADA") || category.includes("OLEAJE") || category.includes("SEQUIA") ? 7 : 2;
  return ageDays <= activeWindowDays;
}

function attentionRadiusKm(category: string): number {
  const value = category.toUpperCase();
  if (value.includes("SISMO") || value.includes("EARTHQUAKE")) return 100;
  if (value.includes("TSUNAMI")) return 100;
  if (value.includes("INUND") || value.includes("FLOOD") || value.includes("HUAICO")) return 30;
  if (value.includes("ALUVION") || value.includes("DERRUMBE") || value.includes("DESLIZ") || value.includes("GLACIAR")) return 25;
  if (value.includes("OLEAJE")) return 40;
  if (value.includes("LLUVIA") || value.includes("TORMENTA") || value.includes("CICLON")) return 50;
  if (value.includes("FRIAJE") || value.includes("HELADA") || value.includes("NEVADA") || value.includes("OLA_CALOR")) return 50;
  if (value.includes("INCEND") || value.includes("FIRE")) return 25;
  if (value.includes("VOLCAN")) return 50;
  if (value.includes("CLIMA") || value.includes("STORM") || value.includes("CYCLONE")) return 50;
  return 20;
}

function severityRank(value: string): number {
  switch (value.toUpperCase()) {
    case "CRITICAL": return 4;
    case "HIGH": return 3;
    case "MEDIUM": return 2;
    default: return 1;
  }
}

server.listen(config.port, () => {
  console.log(`Sentinel API escuchando en http://localhost:${config.port}`);
  officialAlertsIngestion.start(config.officialAlertsPollIntervalMs);
});
function shutdown() {
  officialAlertsIngestion.stop();
  for (const socket of alertSockets.clients) socket.terminate();
  alertSockets.close();
  server.close();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
