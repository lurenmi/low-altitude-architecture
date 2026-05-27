const API = "/api/v1";

const DEFAULT_RULE_CONFIG = {
  max_altitude_high_m: 120,
  max_altitude_warn_m: 100,
  route_required_score: 45,
  zone_intersect_high_score: 40,
  zone_intersect_medium_score: 20,
  peak_window_score: 12,
  peak_windows_utc: [[6, 8], [14, 16]],
  risk_level_thresholds: { medium: 30, high: 60 },
};

const state = {
  map: {
    summary: null,
    layers: [],
    objects: [],
    aircraft: [],
    editLogs: [],
    selectedObjectCode: "",
  },
  flight: {
    plans: [],
    approvals: [],
    statusFilter: "",
    lastRisk: null,
    rules: null,
    replay: {
      planId: null,
      planNo: "",
      points: [],
      cursor: 0,
      speed: 1,
      timer: null,
    },
  },
  airspace: {
    zones: [],
    grids: [],
    facilities: [],
    weather: [],
    capacity: null,
    sources: [],
    visual: {
      scene: null,
      zones: [],
      grids: [],
      facilities: [],
      weather: [],
    },
    ui: {
      altitude: 120,
      timeSlice: "day",
      layers: { zones: true, grids: true, facilities: true, weather: true },
    },
    runtime3d: {
      renderer: null,
      scene: null,
      camera: null,
      frameId: null,
      resizeBound: false,
    },
  },
};

async function parseResponse(res) {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return { ok: false, message: text || `${res.status} ${res.statusText}` };
  }
}

async function apiGet(path) {
  const res = await fetch(path);
  const data = await parseResponse(res);
  if (!res.ok || data.ok === false) throw new Error(data.message || `${res.status} ${res.statusText}`);
  return data;
}

async function apiPost(path, body) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  const data = await parseResponse(res);
  if (!res.ok || data.ok === false) throw new Error(data.message || `${res.status} ${res.statusText}`);
  return data;
}

async function apiPut(path, body) {
  const res = await fetch(path, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  const data = await parseResponse(res);
  if (!res.ok || data.ok === false) throw new Error(data.message || `${res.status} ${res.statusText}`);
  return data;
}

async function apiDelete(path, operator) {
  const res = await fetch(path, {
    method: "DELETE",
    headers: { "X-Operator": operator || "map_operator" },
  });
  const data = await parseResponse(res);
  if (!res.ok || data.ok === false) throw new Error(data.message || `${res.status} ${res.statusText}`);
  return data;
}

function setHealth(text, ok = true) {
  const el = document.getElementById("health");
  el.textContent = text;
  el.style.color = ok ? "#16a34a" : "#dc2626";
}

function initTabs() {
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
      document.querySelectorAll(".view").forEach((v) => v.classList.remove("active"));
      btn.classList.add("active");
      document.getElementById(`view-${btn.dataset.tab}`).classList.add("active");
    });
  });
}

function statusTag(status) {
  return `<span class="status ${status}">${status}</span>`;
}

function riskColor(level) {
  if (level === "high") return "#ef4444";
  if (level === "medium") return "#f59e0b";
  return "#16a34a";
}

function zoneTypeColor(zoneType) {
  if (zoneType === "no_fly") return "#dc2626";
  if (zoneType === "temporary_control") return "#7c3aed";
  return "#2563eb";
}

function latLngToXY(lat, lng, bounds, width, height) {
  const x = ((lng - bounds.minLng) / (bounds.maxLng - bounds.minLng || 0.0001)) * width;
  const y = height - ((lat - bounds.minLat) / (bounds.maxLat - bounds.minLat || 0.0001)) * height;
  return [x, y];
}

function findMapObject(code) {
  return state.map.objects.find((x) => x.object_code === code) || null;
}

function renderMapSummary() {
  const s = state.map.summary;
  if (!s) return;
  document.getElementById("map-summary").innerHTML = `
    <span class="chip-btn">航线 ${s.routes}</span>
    <span class="chip-btn">禁限飞区 ${s.zones}</span>
    <span class="chip-btn">设施 ${s.facilities}</span>
    <span class="chip-btn">在线目标 ${s.aircraft_online}</span>
  `;
}

function renderLayerList() {
  document.getElementById("layer-list").innerHTML = state.map.layers
    .map((x) => `<div class="layer-item"><span>${x.layer_name}</span><input type="checkbox" checked data-layer="${x.layer_code}"></div>`)
    .join("");
}

function renderObjectList() {
  const keyword = document.getElementById("map-filter").value.trim().toLowerCase();
  const filtered = state.map.objects.filter((x) => x.object_name.toLowerCase().includes(keyword));
  document.getElementById("object-list").innerHTML = filtered
    .map(
      (x) => `
      <div class="list-item object-item ${x.object_code === state.map.selectedObjectCode ? "selected" : ""}" data-code="${x.object_code}">
        <strong>${x.object_name}</strong>
        <div>类型：${x.object_type} | 区域：${x.district}</div>
        <div>风险：${x.risk_level} | 状态：${x.status}</div>
      </div>`,
    )
    .join("");
}

function renderAircraftList() {
  document.getElementById("aircraft-list").innerHTML = state.map.aircraft
    .map(
      (a) => `
      <div class="list-item">
        <strong>${a.aircraft_code}</strong>
        <div>${a.aircraft_type}</div>
        <div>高度 ${a.altitude_m}m | 速度 ${a.speed_ms}m/s | 航向 ${a.heading_deg}°</div>
        <div>状态：${a.status} ${a.plan_no ? `| 计划 ${a.plan_no}` : ""}</div>
      </div>`,
    )
    .join("");
}

function renderMapEditLog() {
  document.getElementById("map-edit-log").innerHTML = state.map.editLogs
    .slice(0, 20)
    .map((x) => `<div class="list-item"><strong>${x.object_code}</strong><div>${x.action} / ${x.operator}</div><div>${x.edited_at_utc.replace("T", " ").slice(0, 19)}</div></div>`)
    .join("");
}

function renderMapObjectSelect() {
  const sel = document.getElementById("map-object-select");
  sel.innerHTML =
    `<option value="">新建对象（不选现有对象）</option>` +
    state.map.objects.map((x) => `<option value="${x.object_code}">${x.object_name} (${x.object_code})</option>`).join("");
  if (state.map.selectedObjectCode) sel.value = state.map.selectedObjectCode;
}

function showMapPopup(html) {
  const popup = ensurePopupNode("map-canvas", "map-popup", true);
  if (!popup) return;
  if (!html) {
    popup.classList.add("hidden");
    popup.innerHTML = "";
    return;
  }
  popup.classList.remove("hidden");
  popup.innerHTML = html;
}

function ensurePopupNode(containerId, popupId, hiddenDefault = false) {
  const container = document.getElementById(containerId);
  if (!container) return null;
  let popup = document.getElementById(popupId);
  if (!(popup instanceof HTMLElement)) {
    popup = document.createElement("div");
    popup.id = popupId;
    popup.className = "map-popup";
    if (hiddenDefault) popup.classList.add("hidden");
  }
  if (popup.parentElement !== container) container.appendChild(popup);
  return popup;
}

function computeMainMapBounds() {
  const points = [];
  state.map.objects.forEach((obj) => {
    if (obj.geometry_type === "point") points.push([obj.geometry.lat, obj.geometry.lng]);
    if (obj.geometry_type === "polyline" || obj.geometry_type === "polygon") (obj.geometry || []).forEach((p) => points.push(p));
  });
  state.map.aircraft.forEach((a) => points.push([a.latitude, a.longitude]));
  if (points.length < 2) return { minLat: 30.15, maxLat: 30.31, minLng: 120.05, maxLng: 120.45 };
  const lats = points.map((p) => p[0]);
  const lngs = points.map((p) => p[1]);
  return {
    minLat: Math.min(...lats) - 0.02,
    maxLat: Math.max(...lats) + 0.02,
    minLng: Math.min(...lngs) - 0.03,
    maxLng: Math.max(...lngs) + 0.03,
  };
}

function renderMapCanvas() {
  const canvas = document.getElementById("map-canvas");
  const width = canvas.clientWidth || 760;
  const height = canvas.clientHeight || 560;
  const bounds = computeMainMapBounds();
  const svg = [];
  svg.push(`<svg viewBox="0 0 ${width} ${height}" width="100%" height="100%">`);
  svg.push(`<defs><filter id="glow"><feGaussianBlur stdDeviation="2.2" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>`);
  state.map.objects.forEach((obj) => {
    const color = riskColor(obj.risk_level);
    const selected = obj.object_code === state.map.selectedObjectCode;
    if (obj.geometry_type === "polyline") {
      const pts = (obj.geometry || []).map((p) => latLngToXY(p[0], p[1], bounds, width, height).join(",")).join(" ");
      svg.push(`<polyline points="${pts}" stroke="${color}" stroke-width="${selected ? 4.8 : 3}" fill="none" filter="url(#glow)"/>`);
    } else if (obj.geometry_type === "polygon") {
      const pts = (obj.geometry || []).map((p) => latLngToXY(p[0], p[1], bounds, width, height).join(",")).join(" ");
      svg.push(`<polygon points="${pts}" stroke="${color}" stroke-width="${selected ? 3 : 2}" fill="${color}${selected ? "55" : "33"}"/>`);
    } else if (obj.geometry_type === "point") {
      const [x, y] = latLngToXY(obj.geometry.lat, obj.geometry.lng, bounds, width, height);
      svg.push(`<circle cx="${x}" cy="${y}" r="${selected ? 8 : 5.5}" fill="${color}"/>`);
    }
  });
  state.map.aircraft.forEach((a) => {
    const [x, y] = latLngToXY(a.latitude, a.longitude, bounds, width, height);
    const color = a.status === "unauthorized" ? "#dc2626" : a.status === "warn" ? "#f59e0b" : "#2563eb";
    svg.push(`<circle cx="${x}" cy="${y}" r="6.5" fill="${color}" stroke="#fff" stroke-width="2"/>`);
    svg.push(`<text x="${x + 8}" y="${y - 7}" font-size="11" fill="#1f2937">${a.aircraft_code}</text>`);
  });
  svg.push(`</svg>`);
  canvas.innerHTML = svg.join("");
  ensurePopupNode("map-canvas", "map-popup", true);
}

function fillMapEditorByObject(code) {
  const obj = findMapObject(code);
  if (!obj) return;
  const form = document.getElementById("map-edit-form");
  state.map.selectedObjectCode = obj.object_code;
  document.getElementById("map-object-select").value = obj.object_code;
  form.elements.object_code.value = obj.object_code;
  form.elements.object_name.value = obj.object_name;
  form.elements.object_type.value = obj.object_type;
  form.elements.geometry_type.value = obj.geometry_type;
  form.elements.district.value = obj.district;
  form.elements.risk_level.value = obj.risk_level;
  form.elements.status.value = obj.status;
  form.elements.geometry_json.value = JSON.stringify(obj.geometry);
  renderObjectList();
  showMapPopup(`<div class="popup-title">${obj.object_name}</div><div>编码：${obj.object_code}</div><div>风险：${obj.risk_level}</div>`);
}

function resetMapEditor() {
  const form = document.getElementById("map-edit-form");
  state.map.selectedObjectCode = "";
  form.elements.object_code.value = "";
  form.elements.object_name.value = "";
  form.elements.object_type.value = "";
  form.elements.geometry_type.value = "polyline";
  form.elements.district.value = "Hangzhou";
  form.elements.risk_level.value = "medium";
  form.elements.status.value = "enabled";
  form.elements.geometry_json.value = "[[30.2068,120.1828],[30.2198,120.1964],[30.2335,120.2128]]";
  renderObjectList();
  showMapPopup("");
}

function readMapEditorPayload() {
  const form = document.getElementById("map-edit-form");
  return {
    operator: form.elements.operator.value || "map_operator",
    object_code: form.elements.object_code.value.trim(),
    object_name: form.elements.object_name.value.trim(),
    object_type: form.elements.object_type.value.trim(),
    geometry_type: form.elements.geometry_type.value,
    district: form.elements.district.value.trim(),
    risk_level: form.elements.risk_level.value,
    status: form.elements.status.value,
    geometry: JSON.parse(form.elements.geometry_json.value),
  };
}

async function loadMapModule() {
  const [summary, layers, objects, aircraft, logs] = await Promise.all([
    apiGet(`${API}/map/summary`),
    apiGet(`${API}/map/layers`),
    apiGet(`${API}/map/objects`),
    apiGet(`${API}/map/aircraft`),
    apiGet(`${API}/map/edit-records`),
  ]);
  state.map.summary = summary.summary;
  state.map.layers = layers.items;
  state.map.objects = objects.items;
  state.map.aircraft = aircraft.items;
  state.map.editLogs = logs.items;
  renderMapSummary();
  renderLayerList();
  renderMapObjectSelect();
  renderObjectList();
  renderAircraftList();
  renderMapEditLog();
  renderMapCanvas();
}

function planActionButtons(plan) {
  const buttons = [`<button class="btn btn-risk" data-id="${plan.id}">风险校验</button>`, `<button class="btn btn-replay" data-id="${plan.id}" data-plan-no="${plan.plan_no}">回放</button>`];
  if (plan.status === "draft") buttons.push(`<button class="btn btn-submit" data-id="${plan.id}">提交</button>`);
  if (plan.status === "pending_review") {
    buttons.push(`<button class="btn btn-approve" data-id="${plan.id}">通过</button>`);
    buttons.push(`<button class="btn btn-reject" data-id="${plan.id}">退回</button>`);
  }
  if (plan.status === "approved") buttons.push(`<button class="btn btn-release" data-id="${plan.id}">放行</button>`);
  return buttons.join(" ");
}

function renderPlanTable() {
  document.getElementById("plan-table").innerHTML = state.flight.plans
    .map(
      (p) => `<tr>
      <td>${p.plan_no}</td>
      <td>${p.task_name}<br><small>${p.task_type}</small></td>
      <td>${p.org_name}</td>
      <td>${p.pilot_name}<br><small>${p.aircraft_code}</small></td>
      <td>${p.start_time_utc.replace("T", " ").slice(0, 16)} ~ ${p.end_time_utc.replace("T", " ").slice(0, 16)}</td>
      <td>${statusTag(p.status)}</td>
      <td>${planActionButtons(p)}</td>
    </tr>`,
    )
    .join("");
}

function renderApprovalList() {
  document.getElementById("approval-list").innerHTML = state.flight.approvals
    .slice(0, 12)
    .map((x) => `<div class="list-item"><strong>${x.plan_no}</strong><div>${x.approver} / ${x.result}</div><div>${x.comment}</div><div>${x.approved_at_utc.replace("T", " ").slice(0, 19)}</div></div>`)
    .join("");
}

function renderRiskPanel() {
  const r = state.flight.lastRisk;
  if (!r) return;
  document.getElementById("risk-panel").innerHTML = `
  <div class="list-item"><strong>风险等级：${r.risk_level}</strong><div>风险得分：${r.risk_score}</div><div>规则集：${r.rule_set?.rule_name || "-"}</div></div>
  ${(r.issues || []).map((x) => `<div class="list-item"><strong>${x.level} / ${x.code}</strong><div>${x.message}</div></div>`).join("")}
  ${(r.rule_logs || []).map((x) => `<div class="list-item muted"><strong>规则：${x.rule_code}</strong><div>命中：${x.matched === 1 ? "是" : "否"}</div></div>`).join("")}
  `;
}

function renderRuleForm() {
  const cfg = state.flight.rules || DEFAULT_RULE_CONFIG;
  const f = document.getElementById("rule-form").elements;
  f.max_altitude_high_m.value = cfg.max_altitude_high_m;
  f.max_altitude_warn_m.value = cfg.max_altitude_warn_m;
  f.route_required_score.value = cfg.route_required_score;
  f.zone_intersect_high_score.value = cfg.zone_intersect_high_score;
  f.zone_intersect_medium_score.value = cfg.zone_intersect_medium_score;
  f.peak_window_score.value = cfg.peak_window_score;
  f.peak_windows_utc.value = JSON.stringify(cfg.peak_windows_utc);
  f.risk_level_thresholds.value = JSON.stringify(cfg.risk_level_thresholds);
}

function clearReplayTimer() {
  if (state.flight.replay.timer) {
    clearInterval(state.flight.replay.timer);
    state.flight.replay.timer = null;
  }
}

function renderReplayMeta() {
  const replay = state.flight.replay;
  const box = document.getElementById("replay-meta");
  if (!replay.planId) {
    box.innerHTML = "请选择计划并点击“回放”";
    return;
  }
  box.innerHTML = `<div>计划：<strong>${replay.planNo}</strong></div><div>轨迹点：<strong>${replay.points.length}</strong></div><div>当前位置：<strong>${replay.cursor + 1}</strong> / ${replay.points.length}</div>`;
}

function renderReplayCanvas() {
  const replay = state.flight.replay;
  const el = document.getElementById("replay-canvas");
  if (!replay.points.length) {
    el.innerHTML = "<div class='muted'>暂无轨迹点</div>";
    document.getElementById("replay-time").textContent = "-";
    return;
  }
  const width = el.clientWidth || 320;
  const height = el.clientHeight || 220;
  const lats = replay.points.map((x) => x.latitude);
  const lngs = replay.points.map((x) => x.longitude);
  const bounds = { minLat: Math.min(...lats) - 0.01, maxLat: Math.max(...lats) + 0.01, minLng: Math.min(...lngs) - 0.01, maxLng: Math.max(...lngs) + 0.01 };
  const track = replay.points.map((p) => latLngToXY(p.latitude, p.longitude, bounds, width, height).join(",")).join(" ");
  const done = replay.points.slice(0, replay.cursor + 1).map((p) => latLngToXY(p.latitude, p.longitude, bounds, width, height).join(",")).join(" ");
  const current = replay.points[Math.min(replay.cursor, replay.points.length - 1)];
  const [cx, cy] = latLngToXY(current.latitude, current.longitude, bounds, width, height);
  el.innerHTML = `<svg viewBox="0 0 ${width} ${height}" width="100%" height="100%"><polyline points="${track}" stroke="#64748b" stroke-width="2" fill="none"/><polyline points="${done}" stroke="#7c3aed" stroke-width="3" fill="none"/><circle cx="${cx}" cy="${cy}" r="6" fill="#ef4444" stroke="#fff" stroke-width="2"/></svg>`;
  document.getElementById("replay-time").textContent = `${current.event_time_utc.replace("T", " ").slice(0, 19)} | ${current.event_type} | ${current.altitude_m}m`;
}

function setReplayCursor(index) {
  const replay = state.flight.replay;
  if (!replay.points.length) return;
  replay.cursor = Math.max(0, Math.min(index, replay.points.length - 1));
  document.getElementById("replay-slider").value = String(replay.cursor);
  renderReplayMeta();
  renderReplayCanvas();
}

function playReplay() {
  const replay = state.flight.replay;
  if (!replay.points.length) return;
  clearReplayTimer();
  const speed = Number(document.getElementById("replay-speed").value || "1");
  replay.speed = speed;
  replay.timer = setInterval(() => {
    if (replay.cursor >= replay.points.length - 1) {
      clearReplayTimer();
      return;
    }
    setReplayCursor(replay.cursor + 1);
  }, Math.max(120, 800 / speed));
}

async function loadReplay(planId, planNo) {
  clearReplayTimer();
  const data = await apiGet(`${API}/flight/plans/${planId}/replay`);
  state.flight.replay.planId = Number(planId);
  state.flight.replay.planNo = planNo || data.plan.plan_no;
  state.flight.replay.points = data.points || [];
  state.flight.replay.cursor = 0;
  document.getElementById("replay-slider").max = String(Math.max(state.flight.replay.points.length - 1, 0));
  document.getElementById("replay-slider").value = "0";
  renderReplayMeta();
  renderReplayCanvas();
}

async function loadFlightModule() {
  const status = state.flight.statusFilter;
  const [plans, approvals, rules] = await Promise.all([
    apiGet(`${API}/flight/plans${status ? `?status=${encodeURIComponent(status)}` : ""}`),
    apiGet(`${API}/flight/approvals`),
    apiGet(`${API}/flight/approval-rules`),
  ]);
  state.flight.plans = plans.items;
  state.flight.approvals = approvals.items;
  state.flight.rules = rules.active_rule?.config || DEFAULT_RULE_CONFIG;
  renderPlanTable();
  renderApprovalList();
  renderRuleForm();
}

async function createPlanFromForm(formEl) {
  const fd = new FormData(formEl);
  await apiPost(`${API}/flight/plans`, {
    task_name: fd.get("task_name"),
    task_type: fd.get("task_type"),
    org_code: fd.get("org_code"),
    pilot_code: fd.get("pilot_code"),
    aircraft_code: fd.get("aircraft_code"),
    district: fd.get("district"),
    start_time_utc: fd.get("start_time_utc"),
    end_time_utc: fd.get("end_time_utc"),
    min_altitude_m: Number(fd.get("min_altitude_m")),
    max_altitude_m: Number(fd.get("max_altitude_m")),
    route: JSON.parse(fd.get("route")),
  });
  await loadFlightModule();
}

async function saveRuleForm() {
  const f = document.getElementById("rule-form").elements;
  await apiPost(`${API}/flight/approval-rules`, {
    updated_by: f.updated_by.value || "rule_admin",
    config: {
      max_altitude_high_m: Number(f.max_altitude_high_m.value),
      max_altitude_warn_m: Number(f.max_altitude_warn_m.value),
      route_required_score: Number(f.route_required_score.value),
      zone_intersect_high_score: Number(f.zone_intersect_high_score.value),
      zone_intersect_medium_score: Number(f.zone_intersect_medium_score.value),
      peak_window_score: Number(f.peak_window_score.value),
      peak_windows_utc: JSON.parse(f.peak_windows_utc.value),
      risk_level_thresholds: JSON.parse(f.risk_level_thresholds.value),
    },
  });
  await loadFlightModule();
}

function renderCapacity() {
  const c = state.airspace.capacity;
  if (!c) return;
  document.getElementById("capacity-box").innerHTML = `<div>总容量：<strong>${c.total}</strong></div><div>当前负载：<strong>${c.load}</strong></div><div>占用率：<strong>${c.occupancy_percent}%</strong></div>`;
}

function renderSimpleTable(id, rows, mapFn) {
  document.getElementById(id).innerHTML = rows.map(mapFn).join("");
}

function renderAirspaceKpis() {
  const v = state.airspace.visual;
  document.getElementById("airspace-kpis").innerHTML = `
    <span class="chip-btn">管制区 ${v.zones.length}</span>
    <span class="chip-btn">网格 ${v.grids.length}</span>
    <span class="chip-btn">设施 ${v.facilities.length}</span>
    <span class="chip-btn">气象单元 ${v.weather.length}</span>
  `;
}

function renderAirspaceViews() {
  renderSimpleTable("zone-table", state.airspace.zones, (z) => `<tr><td>${z.zone_name}</td><td>${z.zone_type}</td><td>${z.min_altitude_m}-${z.max_altitude_m}</td><td>${z.status}</td></tr>`);
  renderSimpleTable("grid-table", state.airspace.grids, (g) => `<tr><td>${g.grid_code}</td><td>${g.district}</td><td>${g.current_load}/${g.capacity_limit}</td><td>${g.risk_level}</td></tr>`);
  renderSimpleTable("facility-table", state.airspace.facilities, (f) => `<tr><td>${f.facility_name}</td><td>${f.facility_type}</td><td>${f.district}</td><td>${f.capacity}</td><td>${f.status}</td></tr>`);
  document.getElementById("weather-list").innerHTML = state.airspace.weather
    .map((w) => `<div class="list-item"><strong>${w.cell_code} / ${w.district}</strong><div>风速 ${w.wind_speed_ms}m/s | 能见度 ${w.visibility_km}km | 降雨 ${w.rainfall_mm}mm</div><div>风险：${w.risk_level}</div></div>`)
    .join("");
  document.getElementById("source-list").innerHTML = state.airspace.sources
    .map((s) => `<div class="list-item"><strong>${s.source_name}</strong><div>${s.source_type}</div><div><a href="${s.source_url}" target="_blank" rel="noopener noreferrer">${s.source_url}</a></div></div>`)
    .join("");
  renderCapacity();
}

function computeAirspaceBounds() {
  const points = [];
  state.airspace.visual.zones.forEach((z) => (z.polygon || []).forEach((p) => points.push(p)));
  state.airspace.visual.grids.forEach((g) => (g.polygon || []).forEach((p) => points.push(p)));
  state.airspace.visual.facilities.forEach((f) => points.push([f.latitude, f.longitude]));
  state.airspace.visual.weather.forEach((w) => points.push([w.center_lat, w.center_lng]));
  if (points.length < 2) return { minLat: 30.15, maxLat: 30.31, minLng: 120.05, maxLng: 120.45 };
  const lats = points.map((p) => p[0]);
  const lngs = points.map((p) => p[1]);
  return {
    minLat: Math.min(...lats) - 0.02,
    maxLat: Math.max(...lats) + 0.02,
    minLng: Math.min(...lngs) - 0.03,
    maxLng: Math.max(...lngs) + 0.03,
  };
}

function toWorldPoint(lat, lng, bounds) {
  const nx = (lng - bounds.minLng) / (bounds.maxLng - bounds.minLng || 0.0001);
  const nz = (lat - bounds.minLat) / (bounds.maxLat - bounds.minLat || 0.0001);
  return { x: (nx - 0.5) * 200, z: (nz - 0.5) * 200 };
}

function clearAirspace3D() {
  const rt = state.airspace.runtime3d;
  if (rt.frameId) cancelAnimationFrame(rt.frameId);
  rt.frameId = null;
  if (rt.renderer) {
    rt.renderer.dispose();
    if (rt.renderer.domElement && rt.renderer.domElement.parentNode) rt.renderer.domElement.parentNode.removeChild(rt.renderer.domElement);
  }
  rt.renderer = null;
  rt.scene = null;
  rt.camera = null;
}

function createOrbitController(canvas) {
  const rt = state.airspace.runtime3d;
  const target = new THREE.Vector3(0, 0, 0);
  let radius = 240;
  let theta = 0.72;
  let phi = 1.12;
  let dragging = false;
  let prevX = 0;
  let prevY = 0;
  const updateCamera = () => {
    phi = Math.max(0.35, Math.min(Math.PI / 2.1, phi));
    rt.camera.position.set(
      target.x + radius * Math.sin(phi) * Math.sin(theta),
      target.y + radius * Math.cos(phi),
      target.z + radius * Math.sin(phi) * Math.cos(theta),
    );
    rt.camera.lookAt(target);
  };
  canvas.addEventListener("mousedown", (e) => {
    dragging = true;
    prevX = e.clientX;
    prevY = e.clientY;
  });
  window.addEventListener("mouseup", () => {
    dragging = false;
  });
  window.addEventListener("mousemove", (e) => {
    if (!dragging) return;
    const dx = e.clientX - prevX;
    const dy = e.clientY - prevY;
    prevX = e.clientX;
    prevY = e.clientY;
    theta -= dx * 0.006;
    phi -= dy * 0.006;
    updateCamera();
  });
  canvas.addEventListener("wheel", (e) => {
    e.preventDefault();
    radius += e.deltaY * 0.08;
    radius = Math.max(90, Math.min(420, radius));
    updateCamera();
  });
  updateCamera();
}

function buildAirspace3DScene() {
  const canvas = document.getElementById("airspace-canvas");
  if (!window.THREE || !canvas) return false;
  clearAirspace3D();
  const width = canvas.clientWidth || 760;
  const height = canvas.clientHeight || 560;
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setSize(width, height);
  canvas.innerHTML = "";
  canvas.appendChild(renderer.domElement);
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf4f7ff);
  const camera = new THREE.PerspectiveCamera(52, width / Math.max(height, 1), 0.1, 2000);
  scene.add(new THREE.HemisphereLight(0xdbeafe, 0xb0bec5, 0.9));
  const dir = new THREE.DirectionalLight(0xffffff, 0.7);
  dir.position.set(120, 220, 110);
  scene.add(dir);
  scene.add(new THREE.GridHelper(240, 24, 0x94a3b8, 0xcbd5e1));
  state.airspace.runtime3d.renderer = renderer;
  state.airspace.runtime3d.scene = scene;
  state.airspace.runtime3d.camera = camera;
  createOrbitController(renderer.domElement);
  if (!state.airspace.runtime3d.resizeBound) {
    window.addEventListener("resize", () => {
      const rt = state.airspace.runtime3d;
      if (!rt.renderer || !rt.camera) return;
      const c = document.getElementById("airspace-canvas");
      if (!c) return;
      const w = c.clientWidth || 760;
      const h = c.clientHeight || 560;
      rt.camera.aspect = w / Math.max(h, 1);
      rt.camera.updateProjectionMatrix();
      rt.renderer.setSize(w, h);
    });
    state.airspace.runtime3d.resizeBound = true;
  }
  return true;
}

function addExtrudedPolygon(points, height, color, opacity, yBase, bounds) {
  const rt = state.airspace.runtime3d;
  if (!rt.scene || !points || points.length < 3) return;
  const shape = new THREE.Shape();
  points.forEach((p, idx) => {
    const w = toWorldPoint(p[0], p[1], bounds);
    if (idx === 0) shape.moveTo(w.x, w.z);
    else shape.lineTo(w.x, w.z);
  });
  const geometry = new THREE.ExtrudeGeometry(shape, { depth: Math.max(height, 0.6), bevelEnabled: false });
  geometry.rotateX(-Math.PI / 2);
  geometry.translate(0, yBase, 0);
  const mesh = new THREE.Mesh(
    geometry,
    new THREE.MeshStandardMaterial({ color, transparent: true, opacity, roughness: 0.58, metalness: 0.08 }),
  );
  rt.scene.add(mesh);
}

function renderAirspaceCanvas2D() {
  const canvas = document.getElementById("airspace-canvas");
  if (!canvas) return;
  const width = canvas.clientWidth || 760;
  const height = canvas.clientHeight || 560;
  const bounds = computeAirspaceBounds();
  const altitude = state.airspace.ui.altitude;
  const show = state.airspace.ui.layers;
  const weatherWeight = { morning: 1.0, day: 1.1, evening: 1.2, night: 0.9 }[state.airspace.ui.timeSlice] || 1.0;
  const svg = [];
  svg.push(`<svg viewBox="0 0 ${width} ${height}" width="100%" height="100%">`);
  svg.push(`<defs><linearGradient id="bgAir" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#eef2ff"/><stop offset="100%" stop-color="#f8fafc"/></linearGradient><filter id="airGlow"><feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>`);
  svg.push(`<rect x="0" y="0" width="${width}" height="${height}" fill="url(#bgAir)"/>`);
  if (show.zones) {
    state.airspace.visual.zones.forEach((z) => {
      if (altitude < z.min_altitude_m || altitude > z.max_altitude_m) return;
      const pts = (z.polygon || []).map((p) => latLngToXY(p[0], p[1], bounds, width, height).join(",")).join(" ");
      const color = zoneTypeColor(z.zone_type);
      svg.push(`<polygon points="${pts}" stroke="${color}" stroke-width="2.2" fill="${color}33" filter="url(#airGlow)"/>`);
    });
  }
  if (show.grids) {
    state.airspace.visual.grids.forEach((g) => {
      if (altitude < g.min_altitude_m || altitude > g.max_altitude_m) return;
      const pts = (g.polygon || []).map((p) => latLngToXY(p[0], p[1], bounds, width, height).join(",")).join(" ");
      const color = riskColor(g.risk_level);
      const alpha = Math.max(0.15, Math.min(0.55, (g.occupancy_percent || 0) / 140));
      svg.push(`<polygon points="${pts}" stroke="${color}" stroke-width="1.1" fill="${color}${Math.round(alpha * 255).toString(16).padStart(2, "0")}"/>`);
    });
  }
  if (show.weather) {
    state.airspace.visual.weather.forEach((w) => {
      const [x, y] = latLngToXY(w.center_lat, w.center_lng, bounds, width, height);
      const r = 14 + Math.round((w.heat_value || 0.2) * 36 * weatherWeight);
      const color = riskColor(w.risk_level);
      svg.push(`<circle cx="${x}" cy="${y}" r="${r}" fill="${color}22" stroke="${color}55" stroke-width="1.2"/>`);
    });
  }
  if (show.facilities) {
    state.airspace.visual.facilities.forEach((f) => {
      const [x, y] = latLngToXY(f.latitude, f.longitude, bounds, width, height);
      svg.push(`<circle cx="${x}" cy="${y}" r="5.5" fill="#2563eb" stroke="#fff" stroke-width="2"/>`);
    });
  }
  svg.push(`</svg>`);
  canvas.innerHTML = svg.join("");
  ensurePopupNode("airspace-canvas", "airspace-popup", false);
}

function renderAirspaceCanvas() {
  const popup = ensurePopupNode("airspace-canvas", "airspace-popup", false);
  if (!popup) return;
  const altitude = state.airspace.ui.altitude;
  const show = state.airspace.ui.layers;
  popup.innerHTML = `<div class="popup-title">空域态势浮窗</div><div>高度切片：${altitude}m</div><div>时段：${state.airspace.ui.timeSlice}</div><div>图层：${Object.keys(show).filter((k) => show[k]).join(" / ")}</div>`;
  const bounds = computeAirspaceBounds();

  if (!buildAirspace3DScene()) {
    renderAirspaceCanvas2D();
    return;
  }
  const rt = state.airspace.runtime3d;
  const scene = rt.scene;
  const altitudeScale = 0.42;

  if (show.zones) {
    state.airspace.visual.zones.forEach((z) => {
      if (altitude < z.min_altitude_m || altitude > z.max_altitude_m) return;
      const h = Math.max((z.max_altitude_m - z.min_altitude_m) * altitudeScale, 2);
      addExtrudedPolygon(z.polygon || [], h, zoneTypeColor(z.zone_type), 0.26, z.min_altitude_m * altitudeScale, bounds);
    });
  }
  if (show.grids) {
    state.airspace.visual.grids.forEach((g) => {
      if (altitude < g.min_altitude_m || altitude > g.max_altitude_m) return;
      const h = Math.max((g.occupancy_percent || 0) * 0.3, 2.2);
      addExtrudedPolygon(g.polygon || [], h, riskColor(g.risk_level), 0.56, g.min_altitude_m * altitudeScale, bounds);
    });
  }
  if (show.facilities) {
    state.airspace.visual.facilities.forEach((f) => {
      const pos = toWorldPoint(f.latitude, f.longitude, bounds);
      const h = Math.max(Math.min((f.capacity || 8) * 0.42, 16), 3);
      const geo = new THREE.CylinderGeometry(1.1, 1.1, h, 12);
      const mat = new THREE.MeshStandardMaterial({ color: 0x2563eb, roughness: 0.35, metalness: 0.12 });
      const m = new THREE.Mesh(geo, mat);
      m.position.set(pos.x, h / 2 + 0.1, pos.z);
      scene.add(m);
    });
  }
  if (show.weather) {
    const timeFactor = { morning: 1.0, day: 1.1, evening: 1.18, night: 0.92 }[state.airspace.ui.timeSlice] || 1.0;
    state.airspace.visual.weather.forEach((w) => {
      const pos = toWorldPoint(w.center_lat, w.center_lng, bounds);
      const radius = 2.2 + Math.max(0.8, (w.heat_value || 0.15) * 11 * timeFactor);
      const geo = new THREE.SphereGeometry(radius, 16, 14);
      const mat = new THREE.MeshStandardMaterial({ color: riskColor(w.risk_level), transparent: true, opacity: 0.26, roughness: 0.32 });
      const s = new THREE.Mesh(geo, mat);
      s.position.set(pos.x, radius + 2.2, pos.z);
      scene.add(s);
    });
  }

  const renderLoop = () => {
    if (!state.airspace.runtime3d.renderer) return;
    state.airspace.runtime3d.renderer.render(state.airspace.runtime3d.scene, state.airspace.runtime3d.camera);
    state.airspace.runtime3d.frameId = requestAnimationFrame(renderLoop);
  };
  renderLoop();
  ensurePopupNode("airspace-canvas", "airspace-popup", false);
}

async function loadAirspaceModule() {
  const [zones, grids, facilities, weather, capacity, sources, visual] = await Promise.all([
    apiGet(`${API}/airspace/zones`),
    apiGet(`${API}/airspace/grids`),
    apiGet(`${API}/airspace/facilities`),
    apiGet(`${API}/airspace/weather`),
    apiGet(`${API}/airspace/capacity`),
    apiGet(`${API}/data/sources`),
    apiGet(`${API}/airspace/visualization`),
  ]);
  state.airspace.zones = zones.items;
  state.airspace.grids = grids.items;
  state.airspace.facilities = facilities.items;
  state.airspace.weather = weather.items;
  state.airspace.capacity = capacity.capacity;
  state.airspace.sources = sources.items;
  state.airspace.visual.scene = visual.scene;
  state.airspace.visual.zones = visual.zones || [];
  state.airspace.visual.grids = visual.grids || [];
  state.airspace.visual.facilities = visual.facilities || [];
  state.airspace.visual.weather = visual.weather || [];
  renderAirspaceViews();
  renderAirspaceKpis();
  renderAirspaceCanvas();
}

function bindMapEvents() {
  document.getElementById("refresh-map").addEventListener("click", () => loadMapModule().catch((err) => alert(err.message)));
  document.getElementById("map-filter").addEventListener("input", renderObjectList);
  document.getElementById("object-list").addEventListener("click", (e) => {
    const item = e.target.closest(".object-item");
    if (!item) return;
    fillMapEditorByObject(item.dataset.code);
    renderMapCanvas();
  });
  document.getElementById("map-object-select").addEventListener("change", (e) => {
    if (!e.target.value) {
      resetMapEditor();
      return;
    }
    fillMapEditorByObject(e.target.value);
    renderMapCanvas();
  });
  document.getElementById("btn-map-create").addEventListener("click", async () => {
    try {
      const payload = readMapEditorPayload();
      await apiPost(`${API}/map/objects`, payload);
      await loadMapModule();
      alert("地图对象新建成功");
    } catch (err) {
      alert(`新建失败: ${err.message}`);
    }
  });
  document.getElementById("btn-map-update").addEventListener("click", async () => {
    try {
      const payload = readMapEditorPayload();
      const code = payload.object_code || state.map.selectedObjectCode;
      if (!code) throw new Error("请先选择对象或填写对象编码");
      await apiPut(`${API}/map/objects/${encodeURIComponent(code)}`, payload);
      await loadMapModule();
      state.map.selectedObjectCode = code;
      fillMapEditorByObject(code);
      renderMapCanvas();
      alert("地图对象更新成功");
    } catch (err) {
      alert(`更新失败: ${err.message}`);
    }
  });
  document.getElementById("btn-map-delete").addEventListener("click", async () => {
    try {
      const form = document.getElementById("map-edit-form");
      const code = form.elements.object_code.value.trim() || state.map.selectedObjectCode;
      if (!code) throw new Error("请先选择待删除对象");
      await apiDelete(`${API}/map/objects/${encodeURIComponent(code)}`, form.elements.operator.value);
      await loadMapModule();
      resetMapEditor();
      renderMapCanvas();
      alert("地图对象已删除");
    } catch (err) {
      alert(`删除失败: ${err.message}`);
    }
  });
}

function bindFlightEvents() {
  document.getElementById("plan-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      await createPlanFromForm(e.target);
      alert("飞行计划创建成功");
    } catch (err) {
      alert(`创建失败: ${err.message}`);
    }
  });
  document.querySelectorAll(".flight-filter").forEach((btn) => {
    btn.addEventListener("click", async () => {
      state.flight.statusFilter = btn.dataset.status || "";
      await loadFlightModule();
    });
  });
  document.getElementById("save-rules").addEventListener("click", async () => {
    try {
      await saveRuleForm();
      alert("审批规则已更新");
    } catch (err) {
      alert(`保存失败: ${err.message}`);
    }
  });
  document.getElementById("plan-table").addEventListener("click", async (e) => {
    const target = e.target;
    if (!(target instanceof HTMLElement)) return;
    const id = target.dataset.id;
    if (!id) return;
    try {
      if (target.classList.contains("btn-risk")) {
        state.flight.lastRisk = await apiPost(`${API}/flight/plans/${id}/risk-check`, {});
        renderRiskPanel();
      } else if (target.classList.contains("btn-submit")) {
        await apiPost(`${API}/flight/plans/${id}/submit`, {});
        await loadFlightModule();
      } else if (target.classList.contains("btn-approve")) {
        await apiPost(`${API}/flight/plans/${id}/approve`, { approver: "飞行服务中心审批员", comment: "审批通过" });
        await loadFlightModule();
      } else if (target.classList.contains("btn-reject")) {
        await apiPost(`${API}/flight/plans/${id}/reject`, { approver: "飞行服务中心审批员", comment: "请补充应急预案附件" });
        await loadFlightModule();
      } else if (target.classList.contains("btn-release")) {
        await apiPost(`${API}/flight/plans/${id}/release`, { released_by: "运行值班员", notes: "动态放行通过" });
        await loadFlightModule();
      } else if (target.classList.contains("btn-replay")) {
        await loadReplay(id, target.dataset.planNo || "");
      }
    } catch (err) {
      alert(`操作失败: ${err.message}`);
    }
  });
  document.getElementById("replay-slider").addEventListener("input", (e) => setReplayCursor(Number(e.target.value)));
  document.getElementById("replay-speed").addEventListener("change", () => {
    if (state.flight.replay.timer) playReplay();
  });
  document.getElementById("replay-play").addEventListener("click", playReplay);
  document.getElementById("replay-pause").addEventListener("click", clearReplayTimer);
  document.getElementById("replay-reset").addEventListener("click", () => {
    clearReplayTimer();
    setReplayCursor(0);
  });
  document.getElementById("replay-generate").addEventListener("click", async () => {
    try {
      if (!state.flight.replay.planId) throw new Error("请先选择一个回放计划");
      await apiPost(`${API}/flight/plans/${state.flight.replay.planId}/replay/generate`, {});
      await loadReplay(state.flight.replay.planId, state.flight.replay.planNo);
      alert("轨迹已重建");
    } catch (err) {
      alert(`重建失败: ${err.message}`);
    }
  });
}

function bindAirspaceEvents() {
  document.getElementById("refresh-airspace").addEventListener("click", () => loadAirspaceModule().catch((err) => alert(err.message)));
  document.getElementById("airspace-altitude").addEventListener("input", (e) => {
    state.airspace.ui.altitude = Number(e.target.value);
    document.getElementById("airspace-altitude-value").textContent = String(state.airspace.ui.altitude);
    renderAirspaceCanvas();
  });
  document.getElementById("airspace-time-slice").addEventListener("change", (e) => {
    state.airspace.ui.timeSlice = e.target.value;
    renderAirspaceCanvas();
  });
  [
    ["layer-zones", "zones"],
    ["layer-grids", "grids"],
    ["layer-facilities", "facilities"],
    ["layer-weather", "weather"],
  ].forEach(([id, key]) => {
    document.getElementById(id).addEventListener("change", (e) => {
      state.airspace.ui.layers[key] = e.target.checked;
      renderAirspaceCanvas();
    });
  });
}

async function checkHealth() {
  try {
    const data = await apiGet("/api/health");
    setHealth(`正常 (${data.time_utc})`, true);
  } catch (err) {
    setHealth(`异常 (${err.message})`, false);
  }
}

async function main() {
  initTabs();
  bindMapEvents();
  bindFlightEvents();
  bindAirspaceEvents();
  await Promise.all([loadMapModule(), loadFlightModule(), loadAirspaceModule(), checkHealth()]);
  renderReplayMeta();
  renderReplayCanvas();
  setInterval(() => loadMapModule().catch(() => {}), 12000);
}

main().catch((err) => {
  setHealth(`启动失败: ${err.message}`, false);
  alert(`系统启动失败: ${err.message}`);
});
