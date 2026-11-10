import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

const dataDirectory = join(process.cwd(), "data");
mkdirSync(dataDirectory, { recursive: true });

export const db = new DatabaseSync(join(dataDirectory, "sentinel.db"));
db.exec("PRAGMA foreign_keys = ON;");
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'USER' CHECK (role IN ('USER', 'ADMIN')),
    reputation INTEGER NOT NULL DEFAULT 0,
    gender TEXT,
    birth_year INTEGER,
    avatar_data TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS reports (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    severity TEXT NOT NULL DEFAULT 'MEDIUM',
    status TEXT NOT NULL DEFAULT 'PENDING',
    cluster_id TEXT,
    cluster_report_count INTEGER NOT NULL DEFAULT 1,
    cluster_min_reporters INTEGER NOT NULL DEFAULT 4,
    cluster_radius_km REAL NOT NULL DEFAULT 5,
    photo_url TEXT,
    validation_radius_km REAL NOT NULL DEFAULT 5,
    confirmations INTEGER NOT NULL DEFAULT 0,
    disputes INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS report_votes (
    id TEXT PRIMARY KEY,
    report_id TEXT NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('CONFIRM', 'DISPUTE')),
    created_at TEXT NOT NULL,
    UNIQUE(report_id, user_id)
  );
  CREATE TABLE IF NOT EXISTS community_report_test_runs (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS official_alerts (
    id TEXT PRIMARY KEY,
    external_id TEXT NOT NULL UNIQUE,
    source TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    latitude REAL,
    longitude REAL,
    severity TEXT NOT NULL DEFAULT 'MEDIUM',
    source_url TEXT,
    record_type TEXT NOT NULL DEFAULT 'ALERT',
    published_at TEXT NOT NULL,
    expires_at TEXT,
    created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS alert_assessments (
    id TEXT PRIMARY KEY,
    alert_id TEXT NOT NULL REFERENCES official_alerts(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    intensity INTEGER,
    answers_json TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    distance_km REAL NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(alert_id, user_id)
  );
`);

// Migración idempotente para instalaciones locales creadas antes del radio de validación.
try { db.exec("ALTER TABLE users ADD COLUMN gender TEXT"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE users ADD COLUMN birth_year INTEGER"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE users ADD COLUMN avatar_data TEXT"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE reports ADD COLUMN validation_radius_km REAL NOT NULL DEFAULT 5"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE reports ADD COLUMN cluster_id TEXT"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE reports ADD COLUMN cluster_report_count INTEGER NOT NULL DEFAULT 1"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE reports ADD COLUMN cluster_min_reporters INTEGER NOT NULL DEFAULT 4"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE reports ADD COLUMN cluster_radius_km REAL NOT NULL DEFAULT 5"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE official_alerts ADD COLUMN expires_at TEXT"); } catch { /* La columna ya existe. */ }
try { db.exec("ALTER TABLE official_alerts ADD COLUMN record_type TEXT NOT NULL DEFAULT 'ALERT'"); } catch { /* La columna ya existe. */ }
db.exec("CREATE INDEX IF NOT EXISTS idx_reports_user_id ON reports(user_id)");
db.exec("CREATE INDEX IF NOT EXISTS idx_reports_coordinates ON reports(latitude, longitude)");
db.exec("CREATE INDEX IF NOT EXISTS idx_reports_status_created_at ON reports(status, created_at)");
db.exec("CREATE INDEX IF NOT EXISTS idx_report_votes_report_user ON report_votes(report_id, user_id)");
db.exec("CREATE INDEX IF NOT EXISTS idx_alerts_coordinates ON official_alerts(latitude, longitude)");
db.exec("CREATE INDEX IF NOT EXISTS idx_alert_assessments_alert ON alert_assessments(alert_id, created_at)");

export function get<T = Record<string, unknown>>(sql: string, ...params: any[]) {
  return db.prepare(sql).get(...params) as T | undefined;
}

export function all<T = Record<string, unknown>>(sql: string, ...params: any[]) {
  return db.prepare(sql).all(...params) as T[];
}

export function run(sql: string, ...params: any[]) {
  return db.prepare(sql).run(...params);
}
