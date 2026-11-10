export const REGION_RADIUS_KM = 50;
export const REPORT_VALIDATION_RADIUS_KM = 5;

// Bounding box amplio de Perú continental e insular. Se usa como primera
// validación de producto; la distancia geodésica sigue siendo la autoridad
// para decidir si un evento puede generar una alerta local.
export const PERU_BOUNDS = {
  minLatitude: -18.7,
  maxLatitude: 0.2,
  minLongitude: -81.5,
  maxLongitude: -68.5
};

export function distanceKmBetween(firstLatitude: number, firstLongitude: number, secondLatitude: number, secondLongitude: number) {
  const earthRadiusKm = 6371;
  const latitudeDelta = toRadians(secondLatitude - firstLatitude);
  const longitudeDelta = toRadians(secondLongitude - firstLongitude);
  const firstLatitudeRadians = toRadians(firstLatitude);
  const secondLatitudeRadians = toRadians(secondLatitude);
  const haversine = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(firstLatitudeRadians) * Math.cos(secondLatitudeRadians) * Math.sin(longitudeDelta / 2) ** 2;
  return earthRadiusKm * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
}

export function isWithinRadius(firstLatitude: number, firstLongitude: number, secondLatitude: number, secondLongitude: number, radiusKm: number) {
  return distanceKmBetween(firstLatitude, firstLongitude, secondLatitude, secondLongitude) <= radiusKm;
}

export function isPeruCoordinate(latitude: number, longitude: number) {
  return latitude >= PERU_BOUNDS.minLatitude
    && latitude <= PERU_BOUNDS.maxLatitude
    && longitude >= PERU_BOUNDS.minLongitude
    && longitude <= PERU_BOUNDS.maxLongitude;
}

function toRadians(value: number) { return value * Math.PI / 180; }
