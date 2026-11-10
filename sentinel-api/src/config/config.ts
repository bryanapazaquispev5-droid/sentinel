import "dotenv/config";

export const config = {
  port: Number(process.env.PORT ?? 3000),
  jwtSecret: process.env.JWT_SECRET ?? "local-development-secret",
  clientOrigin: process.env.CLIENT_ORIGIN ?? "*",
  officialAlertsPollIntervalMs: Number(process.env.OFFICIAL_ALERTS_POLL_INTERVAL_MS ?? 10000)
};
