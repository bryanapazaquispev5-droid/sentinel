(() => {
  const state = { token: sessionStorage.getItem("sentinel_admin_token"), section: "dashboard", alertsView: "active", alertRows: [], alertSources: [] };
  const $ = (selector) => document.querySelector(selector);
  const escapeHtml = (value) => String(value ?? "—").replace(/[&<>'"]/g, (char) => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[char]));
  const formatDate = (value) => value ? new Date(value).toLocaleString("es-PE", { dateStyle:"short", timeStyle:"short" }) : "—";
  const formatSyncDate = (value) => value
    ? new Date(value).toLocaleString("es-PE", { dateStyle: "short", timeStyle: "medium", timeZone: "America/Lima" })
    : "Sin sincronización exitosa";
  const badge = (value) => `<span class="pill ${String(value).includes("DISMISSED") ? "danger" : String(value).includes("PENDING") ? "warn" : ""}">${escapeHtml(value)}</span>`;
  const show = (element, visible) => element.classList.toggle("hidden", !visible);
  const toast = (message) => { $("#toast").textContent = message; window.setTimeout(() => { $("#toast").textContent = ""; }, 3500); };

  async function api(path, options = {}) {
    const headers = { "Content-Type":"application/json", ...(options.headers || {}) };
    if (state.token) headers.Authorization = `Bearer ${state.token}`;
    const response = await fetch(path, { cache: "no-store", ...options, headers });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) { if (response.status === 401 || response.status === 403) logout(); throw new Error(body.error || "No se pudo completar la operación"); }
    return body;
  }

  function logout() { state.token = null; sessionStorage.removeItem("sentinel_admin_token"); show($("#appView"), false); show($("#loginView"), true); }
  function setLoggedIn(user) { $("#adminIdentity").textContent = user?.name || "Administrador"; show($("#loginView"), false); show($("#appView"), true); loadSection(); }

  $("#loginForm").addEventListener("submit", async (event) => {
    event.preventDefault(); $("#loginError").textContent = "";
    try {
      const loginValue = $("#email").value.trim();
      const email = loginValue === "admin" ? "admin@sentinel.local" : loginValue;
      const body = await api("/api/v1/auth/login", { method:"POST", body:JSON.stringify({ email, password:$("#password").value }) });
      if (body.user?.role !== "ADMIN") throw new Error("Esta cuenta no tiene permisos de administrador.");
      state.token = body.accessToken; sessionStorage.setItem("sentinel_admin_token", state.token); setLoggedIn(body.user);
    } catch (error) { $("#loginError").textContent = error.message; }
  });
  $("#logoutButton").addEventListener("click", logout);
  $("#refreshButton").addEventListener("click", () => loadSection(true));
  $("#syncButton").addEventListener("click", async () => { try { $("#syncButton").disabled = true; await api("/api/v1/admin/sync", { method:"POST" }); toast("Fuentes sincronizadas correctamente."); await loadSection(true); } catch (error) { toast(error.message); } finally { $("#syncButton").disabled = false; } });
  document.querySelectorAll("#menu button").forEach((button) => button.addEventListener("click", () => { state.section = button.dataset.section; if (state.section === "alerts") state.alertsView = "active"; document.querySelectorAll("#menu button").forEach((item) => item.classList.toggle("active", item === button)); loadSection(); }));

  let pendingLoads = 0;
  setInterval(() => {
    if (!document.hidden && pendingLoads === 0 &&
        (state.section === "dashboard" || state.section === "alerts")) {
      void loadSection();
    }
  }, 15_000);

  async function loadSection(refresh = false) {
    if (!state.token) return;
    pendingLoads += 1;
    const titles = { dashboard:"Resumen", users:"Usuarios", reports:"Reportes comunitarios", alerts:"Alertas oficiales", assessments:"Evaluaciones locales", tests:"Pruebas de alertas" };
    $("#sectionTitle").textContent = titles[state.section];
    try { const renderers = { dashboard:renderDashboard, users:renderUsers, reports:renderReports, alerts:renderAlerts, assessments:renderAssessments, tests:renderTests }; await renderers[state.section](refresh); $("#lastUpdated").textContent = `Actualizado ${new Date().toLocaleTimeString("es-PE", { hour:"2-digit", minute:"2-digit", second:"2-digit" })}`; } catch (error) { $("#sectionContent").innerHTML = `<div class="panel empty">${escapeHtml(error.message)}</div>`; } finally { pendingLoads -= 1; }
  }

  async function renderDashboard() {
    const body = await api("/api/v1/admin/dashboard"); const counts = body.counts;
    $("#sectionContent").innerHTML = `<div class="cards">${[["Usuarios",counts.users],["Reportes",counts.reports],["Alertas oficiales",counts.alerts],["Evaluaciones",counts.assessments],["Pendientes",counts.pendingReports],["Verificados",counts.verifiedReports]].map(([label,value]) => `<article class="card"><div class="card-label">${label}</div><div class="card-value">${value}</div></article>`).join("")}</div><div class="grid-two"><section class="panel"><div class="panel-head"><h3>Estado de fuentes oficiales</h3><span class="pill">Sincronización automática</span></div><div class="source-list">${(body.sources || []).map((source) => `<div class="source"><div><div class="source-name">${escapeHtml(source.source)}</div><div class="source-meta">Última sincronización exitosa: ${formatSyncDate(source.lastSuccessAt)} (hora de Perú) · Importadas: ${source.imported}</div>${source.lastError ? `<div class="source-meta" style="color:var(--danger)">${escapeHtml(source.lastError)}</div>` : ""}</div><span class="status-dot ${source.lastError ? "off" : ""}"></span></div>`).join("") || `<div class="empty">Aún no hay ejecuciones registradas.</div>`}</div></section><section class="panel"><div class="panel-head"><h3>Reglas del sistema</h3></div><div class="source-list"><div class="source"><div><div class="source-name">Visibilidad global</div><div class="source-meta">Todos los datos de Perú aparecen en el panel.</div></div><span class="pill">PERÚ</span></div><div class="source"><div><div class="source-name">Alertas locales</div><div class="source-meta">Solo eventos geolocalizados dentro del radio del usuario.</div></div><span class="pill">50 km</span></div><div class="source"><div><div class="source-name">Seguridad</div><div class="source-meta">Contraseñas hash; nunca se muestran en tablas.</div></div><span class="pill">PROTEGIDO</span></div></div></section></div>`;
  }

  async function renderUsers() { const body = await api("/api/v1/admin/users"); renderTable(["Nombre","Correo","Rol","Reputación","Perfil","Registro"], (body.users || []).map((item) => [escapeHtml(item.name),escapeHtml(item.email),badge(item.role),item.reputation,item.hasProfilePhoto ? "Sí" : "No",formatDate(item.createdAt)])); }
  async function renderReports() { const body = await api("/api/v1/admin/reports"); renderTable(["Tipo / descripción","Usuario","Estado","Gravedad","Confirmaciones","Ubicación","Fecha"], (body.reports || []).map((item) => [`<strong>${escapeHtml(item.category)}</strong><div class="source-meta truncate">${escapeHtml(item.description)}</div>`,`${escapeHtml(item.userName)}<div class="source-meta">${escapeHtml(item.userEmail)}</div>`,badge(item.status),badge(item.severity),`${item.confirmations} / ${item.disputes}`,`${Number(item.latitude).toFixed(4)}, ${Number(item.longitude).toFixed(4)}`,formatDate(item.createdAt)])); }
  async function renderAlerts() { const [body, status] = await Promise.all([
      api("/api/v1/admin/alerts"),
      api("/api/v1/alerts/sources")
    ]);
    state.alertRows = body.alerts || [];
    state.alertSources = status.sources || [];
    drawAlerts();
  }
  function drawAlerts() {
    const active = state.alertRows.filter((item) => item.isActive);
    const past = state.alertRows.filter((item) => !item.isActive);
    const rows = state.alertsView === "active" ? active : past;
    const sources = state.alertSources.map((source) =>
      `<div class="source-meta">${escapeHtml(source.source)}: ${escapeHtml(formatSyncDate(source.lastSuccessAt))}${source.lastError ? " · Último intento fallido" : ""}</div>`
    ).join("");
    const alertTable = rows.map((item) => `<tr><td><strong>${escapeHtml(item.source)}</strong><div class="source-meta">${escapeHtml(item.category)}</div></td><td><div class="truncate">${escapeHtml(item.title)}</div></td><td>${badge(item.severity)}</td><td>${item.latitude === null ? "Sin ubicación" : `${Number(item.latitude).toFixed(4)}, ${Number(item.longitude).toFixed(4)}`}</td><td>${formatDate(item.publishedAt)}</td><td>${item.sourceUrl ? `<a href="${escapeHtml(item.sourceUrl)}" target="_blank" rel="noreferrer">Abrir</a>` : "—"}</td></tr>`).join("");
    $("#sectionContent").innerHTML = `
      <section class="panel"><div class="panel-head"><h3>Última sincronización exitosa (hora de Perú)</h3></div><div class="source-list">${sources || "Sin sincronizaciones registradas"}</div></section>
      <section class="panel alerts-panel"><div class="panel-head"><div><h3>${state.alertsView === "active" ? "Alertas actuales" : "Alertas pasadas"}</h3><p class="source-meta">${state.alertsView === "active" ? "Eventos que siguen dentro de su periodo activo." : "Eventos finalizados, hasta un año de antigüedad."}</p></div><div class="segmented-filter"><button data-alert-view="active" class="${state.alertsView === "active" ? "selected" : ""}">Activas <span>${active.length}</span></button><button data-alert-view="past" class="${state.alertsView === "past" ? "selected" : ""}">Pasadas <span>${past.length}</span></button></div></div><div class="table-wrap"><table><thead><tr><th>Fuente / tipo</th><th>Título</th><th>Severidad</th><th>Coordenadas</th><th>Publicado</th><th>Enlace</th></tr></thead><tbody>${alertTable || `<tr><td colspan="6" class="empty">${state.alertsView === "active" ? "No hay alertas activas." : "No hay alertas pasadas en el último año."}</td></tr>`}</tbody></table></div></section>`;
    document.querySelectorAll("[data-alert-view]").forEach((button) => button.addEventListener("click", () => {
      state.alertsView = button.dataset.alertView;
      drawAlerts();
    }));
  }
  async function renderTests() {
    const body = await api("/api/v1/admin/test-alerts");
    const fixtures = [
      ["LOW", "PRUEBA · Sismo bajo", "SISMO", "-12.0464, -77.0428"],
      ["MEDIUM", "PRUEBA · Inundación media", "INUNDACION", "-12.0510, -77.0380"],
      ["HIGH", "PRUEBA · Incendio alto", "INCENDIO", "-12.0410, -77.0490"],
      ["CRITICAL", "PRUEBA · Sismo crítico", "SISMO", "-12.0440, -77.0350"]
    ];
    const active = new Map((body.alerts || []).map((alert) => [alert.severity, alert]));
    $("#sectionContent").innerHTML = `<section class="panel"><div class="panel-head"><div><h3>Pruebas temporales de alertas</h3><p class="source-meta">Activa cada escenario por separado. Se elimina solo a los 10 segundos.</p></div></div><div class="table-wrap"><table><thead><tr><th>Escenario</th><th>Tipo</th><th>Nivel</th><th>Coordenadas</th><th>Estado</th><th>Acción</th></tr></thead><tbody>${fixtures.map(([severity,title,category,coordinates]) => {
      const isActive = active.has(severity);
      return `<tr><td>${title}</td><td>${category}</td><td>${badge(severity)}</td><td>${coordinates}</td><td>${isActive ? "Activa · desaparece en 10 s" : "Inactiva"}</td><td><button class="${isActive ? "outline" : "primary compact"}" data-test-severity="${severity}" ${isActive ? "disabled" : ""}>${isActive ? "Activa" : "Activar 10 s"}</button></td></tr>`;
    }).join("")}</tbody></table></div></section><section class="panel"><div class="panel-head"><div><h3>Validación comunitaria · 15 personas</h3><p class="source-meta">Crea 15 cuentas de prueba independientes y reportes separados alrededor de Lima. Se eliminan automáticamente en 10 minutos.</p></div></div><div class="panel-head"><label>Desastre<select id="communitySimulationCategory"><option>SISMO</option><option>INUNDACION</option><option>HUAICO</option><option>INCENDIO</option><option>DERRUMBE</option><option>VOLCAN</option><option>CLIMA</option></select></label><button id="communitySimulationButton" class="primary">Simular 15 reportes</button></div><div id="communitySimulationResult" class="source-list"></div></section>`;
    document.querySelectorAll("[data-test-severity]").forEach((button) => button.addEventListener("click", async () => {
      button.disabled = true;
      try {
        await api(`/api/v1/admin/test-alerts/${button.dataset.testSeverity}`, { method: "POST" });
        toast(`Escenario ${button.dataset.testSeverity} activo durante 10 segundos.`);
        await renderTests();
        window.setTimeout(() => { if (state.section === "tests") void renderTests(); }, 10_200);
      } catch (error) { toast(error.message); button.disabled = false; }
    }));
    $("#communitySimulationButton").addEventListener("click", async (buttonEvent) => {
      const button = buttonEvent.currentTarget;
      button.disabled = true;
      try {
        const result = await api("/api/v1/admin/community-simulation", { method: "POST", body: JSON.stringify({ category: $("#communitySimulationCategory").value }) });
        $("#communitySimulationResult").innerHTML = `<div class="source"><div><strong>${result.simulatedUsers} personas independientes</strong><div class="source-meta">${escapeHtml(result.category)} · mínimo ${result.reportsRequired} · radio ${result.radiusKm} km · estado EN EVALUACIÓN · vence ${formatDate(result.expiresAt)}</div></div><button id="removeCommunitySimulation" class="outline">Eliminar prueba</button></div>`;
        $("#removeCommunitySimulation").addEventListener("click", async () => { await api(`/api/v1/admin/community-simulation/${result.runId}`, { method: "DELETE" }); $("#communitySimulationResult").innerHTML = ""; toast("Simulación eliminada."); });
        toast("15 reportes de prueba ya están disponibles en la app.");
      } catch (error) { toast(error.message); }
      finally { button.disabled = false; }
    });
  }
  async function renderAssessments() { const body = await api("/api/v1/admin/assessments"); renderTable(["Alerta","Usuario","Intensidad","Respuestas","Distancia","Fecha"], (body.assessments || []).map((item) => [escapeHtml(item.alertTitle),`${escapeHtml(item.userName)}<div class="source-meta">${escapeHtml(item.userEmail)}</div>`,item.intensity || "—",`<div class="truncate">${escapeHtml(item.answersJson)}</div>`,`${Number(item.distanceKm).toFixed(1)} km`,formatDate(item.createdAt)])); }
  function renderTable(headers, rows) { $("#sectionContent").innerHTML = `<section class="panel"><div class="table-wrap"><table><thead><tr>${headers.map((header) => `<th>${header}</th>`).join("")}</tr></thead><tbody>${rows.length ? rows.map((row) => `<tr>${row.map((cell) => `<td>${cell}</td>`).join("")}</tr>`).join("") : `<tr><td colspan="${headers.length}" class="empty">No hay registros.</td></tr>`}</tbody></table></div></section>`; }

  if (state.token) { setLoggedIn(); } else { show($("#loginView"), true); show($("#appView"), false); }
})();
