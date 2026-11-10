import type {
  GDACSFeature,
  GDACSResponse,
  IGPFeature,
  IGPResponse,
  NormalizedOfficialAlert,
  OfficialAlertCategory,
  OfficialAlertSeverity
} from "../domain/officialAlertTypes.js";

const IGP_QUERY_URL = "https://ide.igp.gob.pe/arcgis/rest/services/monitoreocensis/UltimoSismo/MapServer/0/query";
const IGP_SOURCE_URL = "https://censis.igp.gob.pe/";
const GDACS_API_URL = "https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH";
const GDACS_SOURCE_URL = "https://www.gdacs.org/";
const REQUEST_TIMEOUT_MS = 12_000;

export async function fetchIGPAlerts(): Promise<NormalizedOfficialAlert[]> {
  const params = new URLSearchParams({
    where: "1=1",
    outFields: "*",
    returnGeometry: "true",
    outSR: "4326",
    f: "json",
    resultRecordCount: "50",
    orderByFields: "fecha_local DESC"
  });
  const response = await fetchJson<IGPResponse>(`${IGP_QUERY_URL}?${params}`);
  if (response.error) throw new Error(`IGP respondió con error: ${response.error.message ?? "desconocido"}`);
  return (response.features ?? []).map(normalizeIGPFeature).filter((alert): alert is NormalizedOfficialAlert => alert !== null);
}

export async function fetchGDACSAlerts(now = new Date()): Promise<NormalizedOfficialAlert[]> {
  const from = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const params = new URLSearchParams({
    eventlist: "EQ;FL;WF;VO;TC;DR",
    fromdate: dateOnly(from),
    todate: dateOnly(now),
    alertlevel: "green;orange;red",
    country: "PER"
  });
  const response = await fetchJson<GDACSResponse>(`${GDACS_API_URL}?${params}`);
  return (response.features ?? []).map(normalizeGDACSFeature).filter((alert): alert is NormalizedOfficialAlert => alert !== null);
}

type INDECIFeature = { geometry?: { coordinates?: [number, number] }; properties?: Record<string, unknown> };
type INDECIResponse = { features?: INDECIFeature[] };
type CENVULItem = { id: number; attributes?: Record<string, any> };
type CENVULResponse = { data?: CENVULItem[] };
type VolcanoResponse = { data?: Array<{ attributes?: { name?: string; latitude?: number; longitude?: number; latitud?: number; longitud?: number } }> };

const INDECI_QUERY_URL = "https://geosinpad.indeci.gob.pe/indeci/rest/services/Emergencias/EMERGENCIAS_SINPAD/MapServer/0/query";
const INDECI_SOURCE_URL = "https://geosinpad.indeci.gob.pe/";
const CENVUL_URL = "https://cenvul.igp.gob.pe/api/products/alerts";
const CENVUL_VOLCANO_URL = "https://cenvul.igp.gob.pe/api/volcanos/all";
const SENAMHI_URL = "https://www.senamhi.gob.pe/?p=aviso-meteorologico";
const ENFEN_API_URL = "https://enfen.imarpe.gob.pe/wp-json/wp/v2/posts";
const EONET_API_URL = "https://eonet.gsfc.nasa.gov/api/v3/events";

type EONETEvent = { id: string; title?: string; description?: string | null; link?: string; closed?: string | null; geometry?: Array<{ date?: string; type?: string; coordinates?: number[]; magnitudeValue?: number; magnitudeUnit?: string }>; sources?: Array<{ url?: string }> };
type EONETResponse = { events?: EONETEvent[] };

export async function fetchEONETWildfires(now = new Date()): Promise<NormalizedOfficialAlert[]> {
  const params = new URLSearchParams({ category: "wildfires", status: "open", days: "30", limit: "500" });
  const response = await fetchJson<EONETResponse>(`${EONET_API_URL}?${params}`);
  return (response.events ?? []).map((event): NormalizedOfficialAlert | null => {
    if (event.closed || !event.geometry?.length) return null;
    const point = [...event.geometry].reverse().find((item) => item.type === "Point" && item.coordinates?.length === 2);
    const [longitude, latitude] = point?.coordinates ?? [];
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude! < -18.5 || latitude! > 0 || longitude! < -82 || longitude! > -68) return null;
    const acres = Number(point?.magnitudeUnit?.toLowerCase().includes("acre") ? point.magnitudeValue : 0);
    return {
      externalId: `NASA:EONET:${event.id}`, source: "NASA EONET", title: event.title || "Incendio forestal detectado",
      description: `${event.description || "Evento de incendio forestal abierto registrado por NASA EONET."}${acres > 0 ? ` Área reportada: ${acres.toLocaleString("en-US")} acres.` : ""} La ubicación representa el punto del evento, no un perímetro de propagación.`,
      category: "INCENDIO", latitude: latitude!, longitude: longitude!, severity: acres >= 5000 ? "HIGH" : acres >= 500 ? "MEDIUM" : "LOW",
      sourceUrl: event.sources?.[0]?.url || event.link || "https://eonet.gsfc.nasa.gov/", publishedAt: validDate(point?.date) || now.toISOString()
    };
  }).filter((alert): alert is NormalizedOfficialAlert => alert !== null);
}

export async function fetchINDECIAlerts(): Promise<NormalizedOfficialAlert[]> {
  const params = new URLSearchParams({
    where: "1=1", outFields: "IDE_SINPAD,FECHA,DEPARTAMENTO,PROVINCIA,DISTRITO,FENOMENO,FLG_SITUACION,SAFECTA,SFALLE,SLESI,SDESA",
    returnGeometry: "true", outSR: "4326", orderByFields: "FECHA DESC", resultRecordCount: "500", f: "geojson"
  });
  const response = await fetchJson<INDECIResponse>(`${INDECI_QUERY_URL}?${params}`);
  return (response.features ?? []).map((feature): NormalizedOfficialAlert | null => {
    const p = feature.properties ?? {};
    const id = p.IDE_SINPAD;
    const coords = feature.geometry?.coordinates;
    if (id === undefined || !coords || p.FLG_SITUACION === "C") return null;
    const [longitude, latitude] = coords;
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
    const phenomenon = String(p.FENOMENO ?? "").trim();
    const category = categoryFromPeruvianHazard(phenomenon);
    if (!category || ["ACCIDENTE", "INCENDIO_URBANO", "OTRO"].includes(category)) return null;
    const location = [p.DISTRITO, p.PROVINCIA, p.DEPARTAMENTO].filter(Boolean).map(String).join(", ").replace(/^(DIST|PROV|DEPA)\.\s*/gim, "");
    const date = parseArcGISDate(p.FECHA);
    const affected = Number(p.SAFECTA ?? 0);
    const deaths = Number(p.SFALLE ?? 0);
    const injured = Number(p.SLESI ?? 0);
    const displaced = Number(p.SDESA ?? 0);
    return {
      externalId: `INDECI:SINPAD:${id}`, source: "INDECI/SINPAD",
      title: `${phenomenon || "Emergencia"}${location ? ` · ${location}` : ""}`,
      description: `Emergencia registrada por INDECI (${p.FLG_SITUACION === "A" ? "en atención" : "registrada"}). Afectados: ${affected}; fallecidos: ${deaths}; heridos: ${injured}; damnificados: ${displaced}.`,
      category, latitude, longitude, severity: severityFromImpact(affected, deaths, injured), sourceUrl: INDECI_SOURCE_URL, publishedAt: date
    };
  }).filter((alert): alert is NormalizedOfficialAlert => alert !== null);
}

export async function fetchCENVULAlerts(): Promise<NormalizedOfficialAlert[]> {
  const [products, volcanoes] = await Promise.all([
    fetchJson<CENVULResponse>(CENVUL_URL),
    fetchJson<VolcanoResponse>(CENVUL_VOLCANO_URL).catch((): VolcanoResponse => ({ data: [] }))
  ]);
  return (products.data ?? []).map((item): NormalizedOfficialAlert | null => {
    const a = item.attributes ?? {};
    if (a.simulacrum || a.locale && a.locale !== "es") return null;
    const titleText = `${a.type ?? ""} ${a.eventType ?? ""}`.toLowerCase();
    const category: OfficialAlertCategory = /lahar|lodo volc[aá]nico/.test(titleText) ? "LAHAR"
      : /ceniz/.test(titleText) ? "CENIZA_VOLCANICA"
        : /pirocl[aá]st/.test(titleText) ? "FLUJO_PIROCLASTICO" : "VOLCAN";
    const volcanoName = a.volcano?.data?.attributes?.name ?? "Volcán peruano";
    const volcano = (volcanoes.data ?? []).find((row) => row.attributes?.name?.toLowerCase() === String(volcanoName).toLowerCase())?.attributes;
    const latitude = finiteOrNull(volcano?.latitud ?? volcano?.latitude);
    const longitude = finiteOrNull(volcano?.longitud ?? volcano?.longitude);
    const publishedAt = validDate(a.publishedAt) || validDate(a.date) || new Date().toISOString();
    const target = [a.possibleImpact, a.location].filter(Boolean).join(". ");
    const direction = a.dispersionDirection ? ` Dirección de dispersión: ${a.dispersionDirection}.` : "";
    const radius = a.dispersionRadius ? ` Alcance publicado: ${a.dispersionRadius}.` : "";
    const observations = stripHtml(String(a.observations ?? ""));
    const recommendation = stripHtml(String(a.recommendations ?? ""));
    const expiry = new Date(Date.parse(publishedAt) + 24 * 60 * 60_000).toISOString();
    return {
      externalId: `IGP:CENVUL:${a.uid ?? item.id}`, source: "IGP/CENVUL", title: `${a.eventType || a.type || "Alerta volcánica"} · ${volcanoName}`,
      description: [observations, target ? `Zona/posible impacto: ${target}` : "", direction.trim(), radius.trim(), recommendation ? `Recomendación: ${recommendation}` : ""].filter(Boolean).join(" "),
      category, latitude, longitude, severity: "HIGH", sourceUrl: a.media?.data?.attributes?.url ? `https://cenvul.igp.gob.pe${a.media.data.attributes.url}` : "https://cenvul.igp.gob.pe/",
      publishedAt, expiresAt: expiry
    };
  }).filter((alert): alert is NormalizedOfficialAlert => alert !== null);
}

export async function fetchSENAMHIAlerts(now = new Date()): Promise<NormalizedOfficialAlert[]> {
  const html = await fetchText(SENAMHI_URL);
  const rows = html.match(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi) ?? [];
  const alerts: NormalizedOfficialAlert[] = [];
  for (const row of rows) {
    const href = row.match(/href=["']([^"']*aviso-meteorologico-(?:vigente|detalle)[^"']*)["']/i)?.[1];
    if (!href) continue;
    const cells = [...row.matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map((match) => decodeHtml(stripHtml(match[1])));
    if (cells.length < 7) continue;
    const title = cells[0].replace(/\s*\(vigente\)/i, "").trim();
    const issueDate = cells[2];
    const startDate = cells[3];
    const endDate = cells[4];
    const level = cells[6].toUpperCase();
    const expiresAt = endOfPeruDay(endDate);
    if (!title || /cancelado|anulado/i.test(title) || !validDate(`${issueDate}T12:00:00-05:00`) || Date.parse(expiresAt) < now.getTime() - 24 * 60 * 60_000) continue;
    const category = categoryFromPeruvianHazard(title) ?? "CLIMA";
    alerts.push({
      externalId: `SENAMHI:AVISO:${href.match(/[?&]b=([^&]+)/)?.[1] ?? href}`,
      source: "SENAMHI", title, description: `Aviso meteorológico oficial vigente. Nivel ${level || "sin nivel"}. Emisión: ${issueDate}. Vigencia: ${startDate} al ${endDate}. El aviso puede abarcar varias regiones del Perú; consulta la fuente para ver el detalle geográfico.`,
      category, latitude: null, longitude: null, severity: severityFromWeatherLevel(level), sourceUrl: new URL(href, SENAMHI_URL).toString(),
      publishedAt: new Date(`${issueDate}T12:00:00-05:00`).toISOString(), expiresAt
    });
  }
  return alerts;
}

type ENFENPost = { id: number; date_gmt?: string; modified_gmt?: string; link?: string; title?: { rendered?: string }; content?: { rendered?: string } };
export async function fetchENFENPredictions(): Promise<NormalizedOfficialAlert[]> {
  const params = new URLSearchParams({ per_page: "10", _fields: "id,date_gmt,modified_gmt,link,title,content" });
  const posts = await fetchJson<ENFENPost[]>(`${ENFEN_API_URL}?${params}`);
  return posts.filter((post) => /comunicado oficial enfen/i.test(decodeHtml(stripHtml(post.title?.rendered ?? ""))))
    .slice(0, 6)
    .map((post): NormalizedOfficialAlert => {
      const title = decodeHtml(stripHtml(post.title?.rendered ?? "Comunicado oficial ENFEN"));
      const content = decodeHtml(stripHtml(post.content?.rendered ?? ""));
      const state = content.match(/estado (?:del )?sistema de alerta\s*:?\s*([^.]{0,100})/i)?.[1]?.trim();
      const publishedAt = wordpressDate(post.date_gmt ?? post.modified_gmt);
      const statusText = state ? ` Estado comunicado por ENFEN: ${state}.` : " Consulta el comunicado para el estado oficial y sus perspectivas.";
      const summary = content.slice(0, 1800);
      const alertState = /alerta de el ni[nñ]o|alerta ante el ni[nñ]o/i.test(content);
      return {
        externalId: `ENFEN:${post.id}`, source: "ENFEN", title, description: `${summary}${summary.length >= 1800 ? "…" : ""}${statusText}`,
        category: "EL_NINO", latitude: null, longitude: null,
        severity: /extraordinaria|muy fuerte|alerta de el ni[nñ]o/i.test(content) ? "HIGH" : "MEDIUM",
        sourceUrl: post.link || "https://enfen.imarpe.gob.pe/comunicados/", publishedAt,
        expiresAt: new Date(Date.parse(publishedAt) + (alertState ? 30 : 14) * 24 * 60 * 60_000).toISOString(), recordType: "PREDICTION"
      };
    });
}

export async function fetchFIRMSAlerts(now = new Date()): Promise<NormalizedOfficialAlert[]> {
  const mapKey = process.env.FIRMS_MAP_KEY?.trim();
  if (!mapKey) return [];
  const source = process.env.FIRMS_SOURCE?.trim() || "VIIRS_SNPP_NRT";
  const area = process.env.FIRMS_BBOX?.trim() || "-85,-18,-68,1";
  const url = `https://firms.modaps.eosdis.nasa.gov/api/area/csv/${encodeURIComponent(mapKey)}/${encodeURIComponent(source)}/${area}/2`;
  const csv = await fetchText(url);
  return parseFIRMSCsv(csv, now);
}

async function fetchJson<T>(url: string): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { accept: "application/json", "user-agent": "Sentinel-API/1.0" }
    });
    if (!response.ok) throw new Error(`Fuente externa HTTP ${response.status}`);
    return await response.json() as T;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchText(url: string): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, { signal: controller.signal, headers: { accept: "text/csv, text/html, text/plain, */*", "user-agent": "Sentinel-API/1.0" } });
    if (!response.ok) throw new Error(`Fuente externa HTTP ${response.status}`);
    return await response.text();
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeIGPFeature(feature: IGPFeature): NormalizedOfficialAlert | null {
  const attributes = feature.attributes;
  if (!attributes) return null;
  const latitude = finiteOrNull(attributes.latitud ?? feature.geometry?.y);
  const longitude = finiteOrNull(attributes.longitud ?? feature.geometry?.x);
  if (latitude === null || longitude === null) return null;
  const magnitude = finiteOrNull(attributes.magnitud) ?? 0;
  const depth = finiteOrNull(attributes.profundidad);
  const publishedAt = parseIGPDate(attributes.fecha_local, attributes.hora_local);
  const reference = attributes.referencia?.trim() || "Ubicación no especificada";
  const intensity = attributes.intensidad?.trim();
  const intensityText = intensity ? ` Intensidad reportada: ${intensity}.` : "";
  const depthText = depth === null ? "" : ` Profundidad: ${depth} km.`;
  return {
    externalId: `IGP:CENSIS:${attributes.fecha_local ?? "unknown"}:${attributes.hora_local ?? "unknown"}:${latitude}:${longitude}`,
    source: "IGP/CENSIS",
    title: `Sismo M${magnitude.toFixed(1)} — ${reference}`,
    description: `Reporte sísmico oficial del IGP. Magnitud ${magnitude.toFixed(1)}.${depthText}${intensityText}`,
    category: "SISMO",
    latitude,
    longitude,
    severity: severityFromMagnitude(magnitude),
    sourceUrl: IGP_SOURCE_URL,
    publishedAt
  };
}

function normalizeGDACSFeature(feature: GDACSFeature): NormalizedOfficialAlert | null {
  const properties = feature.properties;
  const coordinates = feature.geometry?.coordinates;
  if (!properties?.eventtype || properties.eventid === undefined || !coordinates || coordinates.length < 2) return null;
  const [longitude, latitude] = coordinates;
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  const eventId = `${properties.eventtype}:${properties.eventid}:${properties.episodeid ?? "0"}`;
  const level = properties.alertlevel?.toLowerCase() ?? "green";
  const category = categoryFromGDACSType(properties.eventtype);
  const severity = severityFromGDACSLevel(level);
  const description = stripHtml(properties.description || properties.htmldescription || "Alerta automática de GDACS.");
  return {
    externalId: `GDACS:${eventId}`,
    source: "GDACS",
    title: properties.name || `${category} detectado por GDACS`,
    description: `${description} Nivel ${properties.alertlevel ?? "Green"}.`,
    category,
    latitude,
    longitude,
    severity,
    sourceUrl: properties.url?.report || GDACS_SOURCE_URL,
    publishedAt: validDate(properties.datemodified) || validDate(properties.fromdate) || new Date().toISOString()
  };
}

function categoryFromGDACSType(eventType: string): OfficialAlertCategory {
  switch (eventType.toUpperCase()) {
    case "EQ": return "SISMO";
    case "FL": return "INUNDACION";
    case "WF": return "INCENDIO";
    case "VO": return "VOLCAN";
    case "TC": return "CICLON_TROPICAL";
    case "DR": return "SEQUIA";
    default: return "OTRO";
  }
}

function categoryFromPeruvianHazard(raw: string): OfficialAlertCategory | null {
  const value = normalizeText(raw);
  if (/tsunami|maremoto/.test(value)) return "TSUNAMI";
  if (/huaico|huayco|flujo de detritos|flujo de lodo/.test(value)) return "HUAICO";
  if (/derrumbe|caida de rocas|desprendimiento de rocas/.test(value)) return "DERRUMBE";
  if (/deslizamiento|movimiento en masa|reptacion/.test(value)) return "DESLIZAMIENTO";
  if (/aluvion|alud/.test(value)) return "ALUVION";
  if (/glaciar|laguna glaciar|desglaciacion|desborde de laguna/.test(value)) return "PELIGRO_GLACIAR";
  if (/ceniza|emision de ceniza/.test(value)) return "CENIZA_VOLCANICA";
  if (/lahar|lodo volcanico/.test(value)) return "LAHAR";
  if (/piroclast/.test(value)) return "FLUJO_PIROCLASTICO";
  if (/volcan|erupcion|lava|gases volcanicos/.test(value)) return "VOLCAN";
  if (/lluvia|precipitacion|inundacion|desborde de rio/.test(value)) return /inundacion|desborde de rio/.test(value) ? "INUNDACION" : "LLUVIA_INTENSA";
  if (/viento|tormenta electrica|tormenta|ciclon|huracan/.test(value)) return /ciclon|huracan/.test(value) ? "CICLON_TROPICAL" : "TORMENTA";
  if (/sequia|deficit hidrico/.test(value)) return "SEQUIA";
  if (/friaje/.test(value)) return "FRIAJE";
  if (/helada|descenso de temperatura|ola de frio/.test(value)) return "HELADA";
  if (/granizada|granizo/.test(value)) return "GRANIZADA";
  if (/nevadas?|nieve/.test(value)) return "NEVADA";
  if (/temperatura diurna|ola de calor|temperaturas altas|incremento de temperatura/.test(value)) return "OLA_CALOR";
  if (/oleaje|marejada|oleajes anomalos|erosion costera/.test(value)) return "OLEAJE";
  if (/incendio forestal|fuego forestal/.test(value)) return "INCENDIO";
  if (/sismo|terremoto/.test(value)) return "SISMO";
  if (/inundacion|desborde/.test(value)) return "INUNDACION";
  if (/clima|meteorolog/.test(value)) return "CLIMA";
  return null;
}

function normalizeText(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

function parseArcGISDate(value: unknown): string {
  const date = typeof value === "number" ? new Date(value) : new Date(String(value ?? ""));
  return Number.isNaN(date.getTime()) ? new Date().toISOString() : date.toISOString();
}

function wordpressDate(value?: string): string {
  if (!value) return new Date().toISOString();
  const parsed = new Date(value.endsWith("Z") ? value : `${value}Z`);
  return Number.isNaN(parsed.getTime()) ? new Date().toISOString() : parsed.toISOString();
}

function severityFromImpact(affected: number, deaths: number, injured: number): OfficialAlertSeverity {
  if (deaths >= 1 || affected >= 100) return "CRITICAL";
  if (injured >= 1 || affected >= 20) return "HIGH";
  if (affected >= 1) return "MEDIUM";
  return "LOW";
}

function severityFromWeatherLevel(level: string): OfficialAlertSeverity {
  if (level.includes("ROJO")) return "CRITICAL";
  if (level.includes("NARANJA")) return "HIGH";
  if (level.includes("AMARILLO")) return "MEDIUM";
  return "LOW";
}

function endOfPeruDay(value: string): string {
  const parsed = new Date(`${value}T23:59:59-05:00`);
  return Number.isNaN(parsed.getTime()) ? new Date(0).toISOString() : parsed.toISOString();
}

function decodeHtml(value: string): string {
  const entities: Record<string, string> = { "&aacute;": "á", "&eacute;": "é", "&iacute;": "í", "&oacute;": "ó", "&uacute;": "ú", "&ntilde;": "ñ", "&Aacute;": "Á", "&Eacute;": "É", "&Iacute;": "Í", "&Oacute;": "Ó", "&Uacute;": "Ú", "&Ntilde;": "Ñ", "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'" };
  return value.replace(/&(?:aacute|eacute|iacute|oacute|uacute|ntilde|Aacute|Eacute|Iacute|Oacute|Uacute|Ntilde|nbsp|amp|quot|#39);/g, (entity) => entities[entity] ?? entity);
}

function severityFromGDACSLevel(level: string): OfficialAlertSeverity {
  if (level === "red") return "CRITICAL";
  if (level === "orange") return "HIGH";
  if (level === "green") return "MEDIUM";
  return "LOW";
}

function severityFromMagnitude(magnitude: number): OfficialAlertSeverity {
  if (magnitude >= 6) return "CRITICAL";
  if (magnitude >= 5) return "HIGH";
  if (magnitude >= 4) return "MEDIUM";
  return "LOW";
}

function parseIGPDate(date?: string, time?: string): string {
  if (!date || !time) return new Date().toISOString();
  const [day, month, year] = date.split("/").map(Number);
  const [hour, minute, second] = time.split(":").map(Number);
  const parsed = new Date(`${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:${String(second).padStart(2, "0")}-05:00`);
  return Number.isNaN(parsed.getTime()) ? new Date().toISOString() : parsed.toISOString();
}

function parseFIRMSCsv(csv: string, now: Date): NormalizedOfficialAlert[] {
  const lines = csv.split(/\r?\n/).filter(Boolean);
  if (lines.length < 2) return [];
  const headers = lines[0].split(",").map((header) => header.trim());
  const index = (name: string) => headers.indexOf(name);
  const latitudeIndex = index("latitude");
  const longitudeIndex = index("longitude");
  if (latitudeIndex < 0 || longitudeIndex < 0) return [];
  return lines.slice(1, 201).map((line): NormalizedOfficialAlert | null => {
    const values = line.split(",");
    const latitude = Number(values[latitudeIndex]);
    const longitude = Number(values[longitudeIndex]);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
    const date = values[index("acq_date")] || dateOnly(now);
    const time = values[index("acq_time")] || "0000";
    const confidence = values[index("confidence")] || "n/d";
    const satellite = values[index("satellite")] || "unknown";
    return {
      externalId: `NASA:FIRMS:${date}:${time}:${latitude}:${longitude}:${satellite}`,
      source: "NASA FIRMS",
      title: "Posible incendio detectado",
      description: `Detección satelital preliminar de NASA FIRMS. Confianza: ${confidence}. Requiere verificación en tierra.`,
      category: "INCENDIO",
      latitude,
      longitude,
      severity: "LOW",
      sourceUrl: "https://firms.modaps.eosdis.nasa.gov/",
      publishedAt: parseFIRMSDate(date, time)
    };
  }).filter((alert): alert is NormalizedOfficialAlert => alert !== null);
}

function parseFIRMSDate(date: string, time: string): string {
  const compactTime = time.padStart(4, "0");
  const parsed = new Date(`${date}T${compactTime.slice(0, 2)}:${compactTime.slice(2, 4)}:00Z`);
  return Number.isNaN(parsed.getTime()) ? new Date().toISOString() : parsed.toISOString();
}

function validDate(value?: string): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function dateOnly(value: Date): string { return value.toISOString().slice(0, 10); }
function finiteOrNull(value: number | undefined): number | null { return value !== undefined && Number.isFinite(value) ? value : null; }
function stripHtml(value: string): string { return value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim(); }
