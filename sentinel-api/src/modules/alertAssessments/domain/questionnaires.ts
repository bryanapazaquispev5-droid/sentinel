export type AssessmentQuestion = {
  id: string;
  prompt: string;
  type: "singleChoice" | "text";
  options?: string[];
  required?: boolean;
};

export type EmergencyContact = {
  name: string;
  number: string;
  reason: string;
};

const intensityOptions = ["No siento nada", "Leve", "Moderada", "Fuerte", "Muy fuerte"];

const questionnaires: Record<string, AssessmentQuestion[]> = {
  SISMO: [
    { id: "intensity", prompt: "¿Qué intensidad estás sintiendo?", type: "singleChoice", options: intensityOptions, required: true },
    { id: "damage", prompt: "¿Observas daños en viviendas, vías o servicios?", type: "singleChoice", options: ["No", "Leves", "Graves"], required: true },
    { id: "injuredPeople", prompt: "¿Hay personas heridas o atrapadas?", type: "singleChoice", options: ["No", "Sí", "No puedo verificar"], required: true }
  ],
  INUNDACION: [
    { id: "waterLevel", prompt: "¿Hasta dónde llega el agua?", type: "singleChoice", options: ["Sin agua", "Calles", "Viviendas", "Techo o nivel peligroso"], required: true },
    { id: "waterRising", prompt: "¿El nivel del agua sigue subiendo?", type: "singleChoice", options: ["No", "Sí", "No sé"], required: true },
    { id: "evacuationNeeded", prompt: "¿Alguien necesita evacuar o ser rescatado?", type: "singleChoice", options: ["No", "Sí", "No puedo verificar"], required: true }
  ],
  INCENDIO: [
    { id: "fireStatus", prompt: "¿Qué observas?", type: "singleChoice", options: ["Humo", "Fuego pequeño", "Fuego extendido"], required: true },
    { id: "smokeRisk", prompt: "¿El humo afecta a personas o viviendas?", type: "singleChoice", options: ["No", "Sí", "No sé"], required: true },
    { id: "injuredPeople", prompt: "¿Hay personas heridas o atrapadas?", type: "singleChoice", options: ["No", "Sí", "No puedo verificar"], required: true }
  ],
  VOLCAN: [
    { id: "ashLevel", prompt: "¿Hay caída de ceniza en tu zona?", type: "singleChoice", options: ["No", "Leve", "Moderada", "Intensa"], required: true },
    { id: "airRisk", prompt: "¿El aire dificulta respirar o ver?", type: "singleChoice", options: ["No", "Sí", "No sé"], required: true },
    { id: "evacuationNeeded", prompt: "¿Necesitas evacuar?", type: "singleChoice", options: ["No", "Sí", "No puedo verificar"], required: true }
  ],
  CLIMA: [
    { id: "weatherIntensity", prompt: "¿Qué intensidad tiene el fenómeno?", type: "singleChoice", options: ["Leve", "Moderada", "Fuerte", "Muy fuerte"], required: true },
    { id: "roadAccess", prompt: "¿Las vías están transitables?", type: "singleChoice", options: ["Sí", "Parcialmente", "No"], required: true },
    { id: "evacuationNeeded", prompt: "¿Hay personas que necesitan ayuda?", type: "singleChoice", options: ["No", "Sí", "No puedo verificar"], required: true }
  ],
  OTRO: [
    { id: "impact", prompt: "¿Qué impacto observas?", type: "singleChoice", options: ["Bajo", "Moderado", "Alto", "Crítico"], required: true },
    { id: "peopleAtRisk", prompt: "¿Hay personas en riesgo inmediato?", type: "singleChoice", options: ["No", "Sí", "No puedo verificar"], required: true },
    { id: "details", prompt: "Añade un detalle útil para los equipos de emergencia", type: "text", required: false }
  ]
};

const defaultContacts: EmergencyContact[] = [
  { name: "Policía Nacional", number: "105", reason: "Riesgo para personas, evacuación o seguridad" },
  { name: "Bomberos", number: "116", reason: "Incendios, rescates y materiales peligrosos" },
  { name: "SAMU", number: "106", reason: "Urgencias y emergencias médicas" },
  { name: "Defensa Civil", number: "115", reason: "Desastres y coordinación de respuesta" }
];

export function questionnaireForCategory(category: string): AssessmentQuestion[] {
  return questionnaires[category] ?? questionnaires.OTRO;
}

export function emergencyContactsForCategory(category: string): EmergencyContact[] {
  const preferred = category === "INCENDIO" ? ["116", "105", "106"]
    : category === "SISMO" || category === "INUNDACION" ? ["105", "115", "116", "106"]
    : ["115", "106", "116", "105"];
  return preferred.map((number) => defaultContacts.find((contact) => contact.number === number)).filter((contact): contact is EmergencyContact => Boolean(contact));
}

export function allowedQuestionIds(category: string): Set<string> {
  return new Set(questionnaireForCategory(category).map((question) => question.id));
}
