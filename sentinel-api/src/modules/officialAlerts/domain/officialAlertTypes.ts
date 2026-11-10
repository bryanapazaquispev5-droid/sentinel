export type OfficialAlertCategory =
  | "SISMO" | "INUNDACION" | "INCENDIO" | "VOLCAN" | "CLIMA" | "OTRO"
  | "TSUNAMI" | "HUAICO" | "DERRUMBE" | "DESLIZAMIENTO" | "ALUVION" | "PELIGRO_GLACIAR"
  | "CENIZA_VOLCANICA" | "LAHAR" | "FLUJO_PIROCLASTICO" | "LLUVIA_INTENSA" | "TORMENTA"
  | "SEQUIA" | "FRIAJE" | "HELADA" | "GRANIZADA" | "NEVADA" | "OLA_CALOR"
  | "OLEAJE" | "CICLON_TROPICAL" | "EL_NINO";
export type OfficialAlertSeverity = "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
export type OfficialRecordType = "ALERT" | "PREDICTION";

export type NormalizedOfficialAlert = {
  externalId: string;
  source: string;
  title: string;
  description: string;
  category: OfficialAlertCategory;
  latitude: number | null;
  longitude: number | null;
  severity: OfficialAlertSeverity;
  sourceUrl: string | null;
  publishedAt: string;
  expiresAt?: string | null;
  recordType?: OfficialRecordType;
};

export type IGPFeature = {
  attributes?: {
    objectid?: number;
    magnitud?: number;
    profundidad?: number;
    fecha_local?: string;
    hora_local?: string;
    latitud?: number;
    longitud?: number;
    intensidad?: string;
    referencia?: string;
  };
  geometry?: { x?: number; y?: number };
};

export type IGPResponse = { features?: IGPFeature[]; error?: { message?: string } };

export type GDACSFeature = {
  geometry?: { coordinates?: [number, number] };
  properties?: {
    eventtype?: string;
    eventid?: number | string;
    episodeid?: number | string;
    name?: string;
    description?: string;
    htmldescription?: string;
    alertlevel?: string;
    country?: string;
    fromdate?: string;
    todate?: string;
    datemodified?: string;
    url?: { report?: string };
    severitydata?: { severity?: number; severitytext?: string };
  };
};

export type GDACSResponse = { features?: GDACSFeature[] };
