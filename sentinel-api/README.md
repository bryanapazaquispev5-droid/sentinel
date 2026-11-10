# Sentinel API

Backend monolítico modular para Sentinel.

## Ejecutar localmente

```bash
npm install
npm run dev
```

La API queda disponible en `http://localhost:3000`.

El panel privado de operaciones queda disponible en `http://localhost:3000/admin/`. Inicia sesión con una cuenta cuyo rol sea `ADMIN`; en el entorno local se habilitó `ivan@test.local` como administrador usando su contraseña existente.

## Endpoints disponibles

```text
GET  /health
POST /api/v1/auth/register
POST /api/v1/auth/login
GET  /api/v1/me
GET  /api/v1/reports
GET  /api/v1/reports/peru
GET  /api/v1/reports/nearby?latitude=-12.04&longitude=-77.04&radiusKm=10
POST /api/v1/reports
GET  /api/v1/reports/:id
POST /api/v1/reports/:id/vote
DELETE /api/v1/reports/:id
GET  /api/v1/alerts
GET  /api/v1/alerts/peru
GET  /api/v1/alerts/nearby?latitude=-12.04&longitude=-77.04&radiusKm=50
GET  /api/v1/alerts/:id/questionnaire
POST /api/v1/alerts/:id/assessment
GET  /api/v1/alerts/sources
GET  /api/v1/analytics/summary
GET  /api/v1/admin/reports
GET  /api/v1/admin/dashboard
GET  /api/v1/admin/users
GET  /api/v1/admin/alerts
GET  /api/v1/admin/assessments
POST /api/v1/admin/sync
POST /api/v1/admin/alerts
PATCH /api/v1/admin/reports/:id/status
```

## Seguridad

- Las contraseñas se almacenan como hash con bcrypt; nunca se guardan en texto plano.
- El token de sesión se firma con JWT.
- La app iOS lo almacena en Keychain.
- Las entradas se validan con Zod.
- Se aplican Helmet, CORS y rate limiting.
- El panel `/admin` no entrega datos sin un JWT válido con rol `ADMIN`; no muestra hashes de contraseñas ni avatares privados.
- Las evaluaciones de alertas se aceptan únicamente dentro de 50 km del evento y se guardan con la ubicación y respuestas del usuario.
- El backend sincroniza automáticamente IGP/CENSIS y GDACS cada 5 minutos, con deduplicación por `externalId`.
- NASA FIRMS queda disponible de forma opcional al configurar `FIRMS_MAP_KEY`; sus detecciones se marcan como preliminares.
- `.env`, base de datos local y `node_modules` están excluidos de Git.

El entorno local usa SQLite nativo de Node 24 para poder arrancar sin instalar un servidor de base de datos. El modelo Prisma permanece como referencia para migrar a PostgreSQL/PostGIS en el despliegue.
