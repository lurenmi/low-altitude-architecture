from __future__ import annotations

import json
import random
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
FRONTEND_DIR = ROOT_DIR / "frontend"
DB_PATH = DATA_DIR / "low_altitude_platform.db"

DEFAULT_APPROVAL_RULE_CONFIG = {
    "max_altitude_high_m": 120,
    "max_altitude_warn_m": 100,
    "peak_windows_utc": [[6, 8], [14, 16]],
    "route_required_score": 45,
    "zone_intersect_high_score": 40,
    "zone_intersect_medium_score": 20,
    "altitude_high_score": 35,
    "altitude_warn_score": 15,
    "peak_window_score": 12,
    "risk_level_thresholds": {"medium": 30, "high": 60},
}

DISTRICT_CENTER = {
    "Binjiang": (30.2060, 120.2100),
    "Shangcheng": (30.2480, 120.2050),
    "Xihu": (30.2680, 120.1300),
    "Xiaoshan": (30.2360, 120.3000),
    "Hangzhou": (30.2741, 120.1551),
}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_utc(raw: str) -> datetime:
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))


def district_center(name: str) -> tuple[float, float]:
    for key, value in DISTRICT_CENTER.items():
        if key.lower() in (name or "").lower():
            return value
    return DISTRICT_CENTER["Hangzhou"]


def stable_code_seed(code: str) -> int:
    return sum(ord(ch) for ch in (code or ""))


def build_grid_polygon(grid_code: str, district: str) -> list[list[float]]:
    base_lat, base_lng = district_center(district)
    seed = stable_code_seed(grid_code)
    lat_offset = ((seed % 9) - 4) * 0.008
    lng_offset = (((seed // 9) % 9) - 4) * 0.010
    center_lat = base_lat + lat_offset
    center_lng = base_lng + lng_offset
    half_lat = 0.010
    half_lng = 0.014
    return [
        [round(center_lat - half_lat, 6), round(center_lng - half_lng, 6)],
        [round(center_lat - half_lat, 6), round(center_lng + half_lng, 6)],
        [round(center_lat + half_lat, 6), round(center_lng + half_lng, 6)],
        [round(center_lat + half_lat, 6), round(center_lng - half_lng, 6)],
    ]


def weather_heat_value(wind_speed_ms: float, visibility_km: float, rainfall_mm: float) -> float:
    score = 0.0
    score += min(max(wind_speed_ms / 15.0, 0.0), 1.0) * 0.5
    score += min(max((10.0 - visibility_km) / 10.0, 0.0), 1.0) * 0.3
    score += min(max(rainfall_mm / 5.0, 0.0), 1.0) * 0.2
    return round(min(max(score, 0.0), 1.0), 3)


def db_connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def row_to_dict(row: sqlite3.Row) -> dict:
    return {k: row[k] for k in row.keys()}


def json_loads_safe(raw: str, fallback):
    try:
        return json.loads(raw)
    except Exception:
        return fallback


def parse_body(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", "0"))
    if length <= 0:
        return {}
    body = handler.rfile.read(length).decode("utf-8")
    if not body.strip():
        return {}
    return json.loads(body)


def send_json(handler: BaseHTTPRequestHandler, payload: dict, status: int = 200) -> None:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    handler.wfile.write(data)


def send_text(handler: BaseHTTPRequestHandler, text: str, status: int = 200, content_type: str = "text/plain; charset=utf-8") -> None:
    data = text.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    handler.wfile.write(data)


def points_bbox(points: list[list[float]]) -> tuple[float, float, float, float]:
    lat_values = [p[0] for p in points]
    lng_values = [p[1] for p in points]
    return min(lat_values), min(lng_values), max(lat_values), max(lng_values)


def polygon_bbox(points: list[list[float]]) -> tuple[float, float, float, float]:
    lat_values = [p[0] for p in points]
    lng_values = [p[1] for p in points]
    return min(lat_values), min(lng_values), max(lat_values), max(lng_values)


def bbox_intersects(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


def get_plan_with_refs(conn: sqlite3.Connection, plan_id: int) -> dict | None:
    row = conn.execute(
        """
        SELECT
          p.*,
          o.org_name,
          pi.pilot_name,
          a.aircraft_code,
          a.aircraft_model
        FROM flight_plans p
        JOIN organizations o ON p.org_id = o.id
        JOIN pilots pi ON p.pilot_id = pi.id
        JOIN aircraft_registry a ON p.aircraft_id = a.id
        WHERE p.id = ?
        """,
        (plan_id,),
    ).fetchone()
    if not row:
        return None
    data = row_to_dict(row)
    data["route"] = json_loads_safe(data["route_json"], [])
    data.pop("route_json", None)
    return data


def get_active_rule_set(conn: sqlite3.Connection) -> dict:
    row = conn.execute(
        """
        SELECT id, rule_code, rule_name, config_json, enabled, updated_by, updated_at_utc
        FROM approval_rule_sets
        WHERE enabled = 1
        ORDER BY updated_at_utc DESC, id DESC
        LIMIT 1
        """
    ).fetchone()
    if not row:
        return {
            "rule_code": "FLIGHT_BASE_RULES",
            "rule_name": "飞行审批基础规则",
            "config": DEFAULT_APPROVAL_RULE_CONFIG,
            "enabled": 1,
            "updated_by": "system_default",
            "updated_at_utc": utc_now(),
        }
    data = row_to_dict(row)
    cfg = json_loads_safe(data["config_json"], {})
    merged = dict(DEFAULT_APPROVAL_RULE_CONFIG)
    merged.update(cfg if isinstance(cfg, dict) else {})
    return {
        "id": data["id"],
        "rule_code": data["rule_code"],
        "rule_name": data["rule_name"],
        "config": merged,
        "enabled": data["enabled"],
        "updated_by": data["updated_by"],
        "updated_at_utc": data["updated_at_utc"],
    }


def validate_rule_config(config: dict) -> dict:
    merged = dict(DEFAULT_APPROVAL_RULE_CONFIG)
    merged.update(config or {})
    number_keys = [
        "max_altitude_high_m",
        "max_altitude_warn_m",
        "route_required_score",
        "zone_intersect_high_score",
        "zone_intersect_medium_score",
        "altitude_high_score",
        "altitude_warn_score",
        "peak_window_score",
    ]
    for key in number_keys:
        if not isinstance(merged.get(key), (int, float)):
            raise ValueError(f"invalid number config: {key}")
    thresholds = merged.get("risk_level_thresholds", {})
    if not isinstance(thresholds, dict) or "medium" not in thresholds or "high" not in thresholds:
        raise ValueError("risk_level_thresholds must contain medium/high")
    peak_windows = merged.get("peak_windows_utc", [])
    if not isinstance(peak_windows, list):
        raise ValueError("peak_windows_utc must be an array")
    for i, pair in enumerate(peak_windows):
        if not isinstance(pair, list) or len(pair) != 2:
            raise ValueError(f"invalid peak_windows_utc[{i}]")
    if merged["max_altitude_warn_m"] > merged["max_altitude_high_m"]:
        raise ValueError("max_altitude_warn_m cannot exceed max_altitude_high_m")
    return merged


def compute_risk(conn: sqlite3.Connection, plan_id: int) -> dict:
    plan = get_plan_with_refs(conn, plan_id)
    if not plan:
        return {"ok": False, "message": "plan not found"}

    rule_set = get_active_rule_set(conn)
    cfg = rule_set["config"]

    issues: list[dict] = []
    logs: list[dict] = []
    score = 0
    route = plan["route"] if isinstance(plan["route"], list) else []
    checked_at = utc_now()

    if not route:
        issues.append({"level": "high", "code": "EMPTY_ROUTE", "message": "未提供航线"})
        logs.append(
            {
                "rule_code": "ROUTE_REQUIRED",
                "matched": 1,
                "detail": {"score_add": cfg["route_required_score"], "message": "航线为空"},
            }
        )
        score += int(cfg["route_required_score"])
    else:
        logs.append({"rule_code": "ROUTE_REQUIRED", "matched": 0, "detail": {"message": "航线完整"}})
        rb = points_bbox(route)
        zones = conn.execute(
            """
            SELECT zone_code, zone_name, zone_type, max_altitude_m, polygon_json
            FROM airspace_zones
            WHERE status = 'active'
            """
        ).fetchall()
        intersect_count = 0
        for zone in zones:
            poly = json_loads_safe(zone["polygon_json"], [])
            if not poly:
                continue
            zb = polygon_bbox(poly)
            if bbox_intersects(rb, zb):
                intersect_count += 1
                level = "high" if zone["zone_type"] in ("no_fly", "temporary_control") else "medium"
                issues.append(
                    {
                        "level": level,
                        "code": "ZONE_INTERSECT",
                        "message": f"航线与 {zone['zone_name']} 存在空间相交",
                        "zone_code": zone["zone_code"],
                    }
                )
                score += int(cfg["zone_intersect_high_score"] if level == "high" else cfg["zone_intersect_medium_score"])
        logs.append(
            {
                "rule_code": "ZONE_INTERSECT",
                "matched": 1 if intersect_count > 0 else 0,
                "detail": {"intersect_count": intersect_count},
            }
        )

    if plan["max_altitude_m"] > cfg["max_altitude_high_m"]:
        issues.append(
            {
                "level": "high",
                "code": "ALTITUDE_TOO_HIGH",
                "message": f"申报高度超过 {cfg['max_altitude_high_m']}m 监管阈值",
            }
        )
        logs.append(
            {
                "rule_code": "ALTITUDE_HIGH",
                "matched": 1,
                "detail": {"max_altitude_m": plan["max_altitude_m"], "threshold": cfg["max_altitude_high_m"]},
            }
        )
        score += int(cfg["altitude_high_score"])
    elif plan["max_altitude_m"] > cfg["max_altitude_warn_m"]:
        issues.append(
            {
                "level": "medium",
                "code": "ALTITUDE_WARNING",
                "message": f"申报高度超过 {cfg['max_altitude_warn_m']}m 建议阈值",
            }
        )
        logs.append(
            {
                "rule_code": "ALTITUDE_WARN",
                "matched": 1,
                "detail": {"max_altitude_m": plan["max_altitude_m"], "threshold": cfg["max_altitude_warn_m"]},
            }
        )
        score += int(cfg["altitude_warn_score"])
    else:
        logs.append({"rule_code": "ALTITUDE_WARN", "matched": 0, "detail": {"max_altitude_m": plan["max_altitude_m"]}})

    hour = parse_utc(plan["start_time_utc"]).hour
    in_peak = False
    for pair in cfg["peak_windows_utc"]:
        start_h = int(pair[0])
        end_h = int(pair[1])
        if start_h <= hour <= end_h:
            in_peak = True
            break
    if in_peak:
        issues.append({"level": "medium", "code": "PEAK_WINDOW", "message": "位于飞行高峰时段，建议二次容量复核"})
        logs.append({"rule_code": "PEAK_WINDOW", "matched": 1, "detail": {"hour": hour}})
        score += int(cfg["peak_window_score"])
    else:
        logs.append({"rule_code": "PEAK_WINDOW", "matched": 0, "detail": {"hour": hour}})

    thresholds = cfg["risk_level_thresholds"]
    risk_level = "low"
    if score >= int(thresholds["high"]):
        risk_level = "high"
    elif score >= int(thresholds["medium"]):
        risk_level = "medium"

    if not issues:
        issues.append({"level": "low", "code": "PASS", "message": "规则校验通过"})

    conn.execute(
        """
        INSERT INTO flight_risk_checks (plan_id, risk_level, risk_score, issues_json, checked_at_utc)
        VALUES (?, ?, ?, ?, ?)
        """,
        (plan_id, risk_level, score, json.dumps(issues, ensure_ascii=False), checked_at),
    )
    for item in logs:
        conn.execute(
            """
            INSERT INTO approval_rule_logs (plan_id, rule_code, matched, detail_json, created_at_utc)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                plan_id,
                item["rule_code"],
                int(item["matched"]),
                json.dumps(item["detail"], ensure_ascii=False),
                checked_at,
            ),
        )
    conn.commit()

    return {
        "ok": True,
        "plan_id": plan_id,
        "risk_level": risk_level,
        "risk_score": score,
        "issues": issues,
        "rule_set": {
            "rule_code": rule_set["rule_code"],
            "rule_name": rule_set["rule_name"],
            "updated_by": rule_set["updated_by"],
            "updated_at_utc": rule_set["updated_at_utc"],
        },
        "rule_logs": logs,
    }


def map_row_to_output(row: sqlite3.Row) -> dict:
    item = row_to_dict(row)
    item["geometry"] = json_loads_safe(item["geometry_json"], {})
    item.pop("geometry_json", None)
    return item


def validate_geometry(geometry_type: str, geometry) -> None:
    if geometry_type == "point":
        if not isinstance(geometry, dict) or "lat" not in geometry or "lng" not in geometry:
            raise ValueError("point geometry must be object with lat/lng")
    elif geometry_type in ("polyline", "polygon"):
        if not isinstance(geometry, list) or len(geometry) < 2:
            raise ValueError(f"{geometry_type} geometry must contain at least 2 points")
        for i, p in enumerate(geometry):
            if not isinstance(p, list) or len(p) != 2:
                raise ValueError(f"invalid point at index {i}")
    else:
        raise ValueError("geometry_type must be point/polyline/polygon")


def generate_object_code() -> str:
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    return f"OBJ_CUSTOM_{stamp}{random.randint(100, 999)}"


def build_object_snapshot(row: sqlite3.Row | None) -> dict:
    if not row:
        return {}
    item = row_to_dict(row)
    return {
        "object_code": item["object_code"],
        "object_name": item["object_name"],
        "object_type": item["object_type"],
        "geometry_type": item["geometry_type"],
        "geometry": json_loads_safe(item["geometry_json"], {}),
        "district": item["district"],
        "risk_level": item["risk_level"],
        "status": item["status"],
        "updated_at_utc": item["updated_at_utc"],
    }


def insert_map_edit_record(
    conn: sqlite3.Connection, object_code: str, action: str, before_data: dict, after_data: dict, operator: str
) -> None:
    conn.execute(
        """
        INSERT INTO map_edit_records (object_code, action, before_json, after_json, operator, edited_at_utc)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            object_code,
            action,
            json.dumps(before_data, ensure_ascii=False),
            json.dumps(after_data, ensure_ascii=False),
            operator,
            utc_now(),
        ),
    )


def create_replay_tracks_for_plan(conn: sqlite3.Connection, plan_id: int) -> int:
    plan = conn.execute(
        """
        SELECT route_json, start_time_utc, end_time_utc, min_altitude_m, max_altitude_m
        FROM flight_plans
        WHERE id = ?
        """,
        (plan_id,),
    ).fetchone()
    if not plan:
        raise ValueError("plan not found")

    route = json_loads_safe(plan["route_json"], [])
    if not isinstance(route, list) or len(route) < 2:
        raise ValueError("plan route invalid")

    conn.execute("DELETE FROM flight_replay_tracks WHERE plan_id = ?", (plan_id,))

    start = parse_utc(plan["start_time_utc"])
    end = parse_utc(plan["end_time_utc"])
    total_steps = max(len(route) * 6, 10)
    total_seconds = max(int((end - start).total_seconds()), total_steps)
    step_seconds = max(total_seconds // total_steps, 1)
    min_alt = float(plan["min_altitude_m"])
    max_alt = float(plan["max_altitude_m"])
    alt_delta = max(max_alt - min_alt, 5.0)

    created = 0
    for i in range(total_steps + 1):
        ratio = i / total_steps
        seg_pos = ratio * (len(route) - 1)
        left_idx = min(int(seg_pos), len(route) - 2)
        right_idx = left_idx + 1
        local_ratio = seg_pos - left_idx
        left = route[left_idx]
        right = route[right_idx]
        lat = left[0] + (right[0] - left[0]) * local_ratio
        lng = left[1] + (right[1] - left[1]) * local_ratio
        altitude = min_alt + alt_delta * (0.4 + 0.6 * ratio)
        speed = 9.0 + 3.0 * (1.0 - abs(0.5 - ratio))
        event_type = "takeoff" if i == 0 else "landing" if i == total_steps else "cruise"
        event_time = (start + timedelta(seconds=i * step_seconds)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        conn.execute(
            """
            INSERT INTO flight_replay_tracks
              (plan_id, seq_no, latitude, longitude, altitude_m, speed_ms, event_type, event_time_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                plan_id,
                i + 1,
                round(lat, 6),
                round(lng, 6),
                round(altitude, 2),
                round(speed, 2),
                event_type,
                event_time,
            ),
        )
        created += 1
    conn.commit()
    return created


class AppHandler(BaseHTTPRequestHandler):
    server_version = "LowAltitudePlatform/1.1"

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        if path.startswith("/api/"):
            self.handle_api_get(path, query)
            return
        self.handle_static(path)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if not path.startswith("/api/"):
            send_json(self, {"ok": False, "message": "not found"}, 404)
            return
        self.handle_api_post(path)

    def do_PUT(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if not path.startswith("/api/"):
            send_json(self, {"ok": False, "message": "not found"}, 404)
            return
        self.handle_api_put(path)

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if not path.startswith("/api/"):
            send_json(self, {"ok": False, "message": "not found"}, 404)
            return
        self.handle_api_delete(path)

    def handle_api_get(self, path: str, query: dict) -> None:
        with db_connect() as conn:
            if path == "/api/health":
                send_json(self, {"ok": True, "service": "low_altitude_platform", "time_utc": utc_now()})
                return

            if path == "/api/v1/data/sources":
                rows = conn.execute("SELECT source_name, source_type, source_url, last_verified_utc FROM data_sources ORDER BY id").fetchall()
                send_json(self, {"ok": True, "items": [row_to_dict(r) for r in rows]})
                return

            if path == "/api/v1/map/summary":
                counts = {
                    "zones": conn.execute("SELECT COUNT(1) c FROM airspace_zones WHERE status='active'").fetchone()["c"],
                    "routes": conn.execute(
                        "SELECT COUNT(1) c FROM map_objects WHERE object_type='route' AND status <> 'deleted'"
                    ).fetchone()["c"],
                    "facilities": conn.execute("SELECT COUNT(1) c FROM facilities").fetchone()["c"],
                    "aircraft_online": conn.execute("SELECT COUNT(1) c FROM realtime_aircraft").fetchone()["c"],
                }
                send_json(self, {"ok": True, "summary": counts})
                return

            if path == "/api/v1/map/layers":
                rows = conn.execute("SELECT layer_code, layer_name, layer_type, is_default_visible, style_json FROM map_layers ORDER BY id").fetchall()
                items = [row_to_dict(r) for r in rows]
                for item in items:
                    item["style"] = json_loads_safe(item["style_json"], {})
                    item.pop("style_json", None)
                send_json(self, {"ok": True, "items": items})
                return

            if path == "/api/v1/map/objects":
                object_type = query.get("type", [""])[0]
                include_deleted = query.get("include_deleted", ["0"])[0] == "1"
                status = query.get("status", [""])[0]
                sql = """
                  SELECT object_code, object_name, object_type, geometry_type, geometry_json, district, risk_level, status, updated_at_utc
                  FROM map_objects
                  WHERE 1 = 1
                """
                params: list = []
                if not include_deleted:
                    sql += " AND status <> 'deleted'"
                if object_type:
                    sql += " AND object_type = ?"
                    params.append(object_type)
                if status:
                    sql += " AND status = ?"
                    params.append(status)
                sql += " ORDER BY updated_at_utc DESC, id DESC"
                rows = conn.execute(sql, params).fetchall()
                send_json(self, {"ok": True, "items": [map_row_to_output(r) for r in rows]})
                return

            if path == "/api/v1/map/edit-records":
                object_code = query.get("object_code", [""])[0]
                sql = """
                  SELECT object_code, action, before_json, after_json, operator, edited_at_utc
                  FROM map_edit_records
                """
                params: list = []
                if object_code:
                    sql += " WHERE object_code = ?"
                    params.append(object_code)
                sql += " ORDER BY edited_at_utc DESC, id DESC LIMIT 50"
                rows = conn.execute(sql, params).fetchall()
                items = []
                for row in rows:
                    item = row_to_dict(row)
                    item["before"] = json_loads_safe(item["before_json"], {})
                    item["after"] = json_loads_safe(item["after_json"], {})
                    item.pop("before_json", None)
                    item.pop("after_json", None)
                    items.append(item)
                send_json(self, {"ok": True, "items": items})
                return

            if path == "/api/v1/map/aircraft":
                rows = conn.execute(
                    """
                    SELECT aircraft_code, aircraft_type, status, latitude, longitude, altitude_m, speed_ms, heading_deg, plan_no, updated_at_utc
                    FROM realtime_aircraft
                    ORDER BY aircraft_code
                    """
                ).fetchall()
                send_json(self, {"ok": True, "items": [row_to_dict(r) for r in rows]})
                return

            if path == "/api/v1/flight/plans":
                status = query.get("status", [""])[0]
                sql = """
                  SELECT
                    p.id, p.plan_no, p.task_name, p.task_type, p.district, p.start_time_utc, p.end_time_utc,
                    p.min_altitude_m, p.max_altitude_m, p.status, p.route_json, p.updated_at_utc,
                    o.org_name, pi.pilot_name, a.aircraft_code
                  FROM flight_plans p
                  JOIN organizations o ON p.org_id = o.id
                  JOIN pilots pi ON p.pilot_id = pi.id
                  JOIN aircraft_registry a ON p.aircraft_id = a.id
                """
                params: list = []
                if status:
                    sql += " WHERE p.status = ?"
                    params.append(status)
                sql += " ORDER BY p.updated_at_utc DESC"
                rows = conn.execute(sql, params).fetchall()
                items = [row_to_dict(r) for r in rows]
                for item in items:
                    item["route"] = json_loads_safe(item["route_json"], [])
                    item.pop("route_json", None)
                send_json(self, {"ok": True, "items": items})
                return

            if path == "/api/v1/flight/approvals":
                rows = conn.execute(
                    """
                    SELECT a.id, p.plan_no, a.approval_node, a.approver, a.result, a.comment, a.approved_at_utc
                    FROM flight_approvals a
                    JOIN flight_plans p ON a.plan_id = p.id
                    ORDER BY a.approved_at_utc DESC
                    """
                ).fetchall()
                send_json(self, {"ok": True, "items": [row_to_dict(r) for r in rows]})
                return

            if path == "/api/v1/flight/approval-rules":
                rows = conn.execute(
                    """
                    SELECT id, rule_code, rule_name, config_json, enabled, updated_by, updated_at_utc
                    FROM approval_rule_sets
                    ORDER BY updated_at_utc DESC, id DESC
                    """
                ).fetchall()
                items = []
                for row in rows:
                    item = row_to_dict(row)
                    item["config"] = json_loads_safe(item["config_json"], {})
                    item.pop("config_json", None)
                    items.append(item)
                active = get_active_rule_set(conn)
                send_json(
                    self,
                    {
                        "ok": True,
                        "active_rule": {
                            "rule_code": active["rule_code"],
                            "rule_name": active["rule_name"],
                            "config": active["config"],
                            "updated_by": active["updated_by"],
                            "updated_at_utc": active["updated_at_utc"],
                        },
                        "items": items,
                    },
                )
                return

            replay_match = re.fullmatch(r"/api/v1/flight/plans/(\d+)/replay", path)
            if replay_match:
                plan_id = int(replay_match.group(1))
                plan = conn.execute("SELECT id, plan_no, task_name, status FROM flight_plans WHERE id = ?", (plan_id,)).fetchone()
                if not plan:
                    send_json(self, {"ok": False, "message": "plan not found"}, 404)
                    return
                points = conn.execute(
                    """
                    SELECT seq_no, latitude, longitude, altitude_m, speed_ms, event_type, event_time_utc
                    FROM flight_replay_tracks
                    WHERE plan_id = ?
                    ORDER BY seq_no
                    """,
                    (plan_id,),
                ).fetchall()
                send_json(
                    self,
                    {
                        "ok": True,
                        "plan": row_to_dict(plan),
                        "points": [row_to_dict(r) for r in points],
                        "total_points": len(points),
                    },
                )
                return

            if path == "/api/v1/airspace/zones":
                rows = conn.execute(
                    """
                    SELECT zone_code, zone_name, zone_type, min_altitude_m, max_altitude_m, district, status, polygon_json, effective_from_utc, effective_to_utc
                    FROM airspace_zones
                    ORDER BY id
                    """
                ).fetchall()
                items = [row_to_dict(r) for r in rows]
                for item in items:
                    item["polygon"] = json_loads_safe(item["polygon_json"], [])
                    item.pop("polygon_json", None)
                send_json(self, {"ok": True, "items": items})
                return

            if path == "/api/v1/airspace/grids":
                rows = conn.execute(
                    """
                    SELECT grid_code, district, min_altitude_m, max_altitude_m, capacity_limit, current_load, risk_level
                    FROM airspace_grids
                    ORDER BY district, grid_code
                    """
                ).fetchall()
                send_json(self, {"ok": True, "items": [row_to_dict(r) for r in rows]})
                return

            if path == "/api/v1/airspace/facilities":
                rows = conn.execute(
                    """
                    SELECT facility_code, facility_name, facility_type, district, latitude, longitude, status, capacity, metadata_json
                    FROM facilities
                    ORDER BY district, facility_name
                    """
                ).fetchall()
                items = [row_to_dict(r) for r in rows]
                for item in items:
                    item["metadata"] = json_loads_safe(item["metadata_json"], {})
                    item.pop("metadata_json", None)
                send_json(self, {"ok": True, "items": items})
                return

            if path == "/api/v1/airspace/weather":
                rows = conn.execute(
                    """
                    SELECT cell_code, district, center_lat, center_lng, wind_speed_ms, visibility_km, rainfall_mm, risk_level, updated_at_utc
                    FROM weather_cells
                    ORDER BY district
                    """
                ).fetchall()
                send_json(self, {"ok": True, "items": [row_to_dict(r) for r in rows]})
                return

            if path == "/api/v1/airspace/visualization":
                zone_rows = conn.execute(
                    """
                    SELECT zone_code, zone_name, zone_type, min_altitude_m, max_altitude_m, district, status, polygon_json
                    FROM airspace_zones
                    WHERE status = 'active'
                    ORDER BY id
                    """
                ).fetchall()
                zones = []
                for row in zone_rows:
                    item = row_to_dict(row)
                    item["polygon"] = json_loads_safe(item["polygon_json"], [])
                    item.pop("polygon_json", None)
                    zones.append(item)

                grid_rows = conn.execute(
                    """
                    SELECT grid_code, district, min_altitude_m, max_altitude_m, capacity_limit, current_load, risk_level
                    FROM airspace_grids
                    ORDER BY district, grid_code
                    """
                ).fetchall()
                grids = []
                for row in grid_rows:
                    item = row_to_dict(row)
                    total = item["capacity_limit"] or 0
                    load = item["current_load"] or 0
                    item["occupancy_percent"] = round((load / total) * 100, 2) if total else 0.0
                    item["polygon"] = build_grid_polygon(item["grid_code"], item["district"])
                    grids.append(item)

                facility_rows = conn.execute(
                    """
                    SELECT facility_code, facility_name, facility_type, district, latitude, longitude, status, capacity
                    FROM facilities
                    ORDER BY district, facility_name
                    """
                ).fetchall()
                facilities = [row_to_dict(r) for r in facility_rows]

                weather_rows = conn.execute(
                    """
                    SELECT cell_code, district, center_lat, center_lng, wind_speed_ms, visibility_km, rainfall_mm, risk_level, updated_at_utc
                    FROM weather_cells
                    ORDER BY district
                    """
                ).fetchall()
                weather = []
                for row in weather_rows:
                    item = row_to_dict(row)
                    item["heat_value"] = weather_heat_value(item["wind_speed_ms"], item["visibility_km"], item["rainfall_mm"])
                    weather.append(item)

                send_json(
                    self,
                    {
                        "ok": True,
                        "scene": {"city": "Hangzhou", "time_utc": utc_now()},
                        "zones": zones,
                        "grids": grids,
                        "facilities": facilities,
                        "weather": weather,
                    },
                )
                return

            if path == "/api/v1/airspace/capacity":
                row = conn.execute(
                    """
                    SELECT
                      SUM(capacity_limit) total_capacity,
                      SUM(current_load) current_load
                    FROM airspace_grids
                    """
                ).fetchone()
                total = row["total_capacity"] or 0
                load = row["current_load"] or 0
                ratio = round((load / total) * 100, 2) if total else 0.0
                send_json(self, {"ok": True, "capacity": {"total": total, "load": load, "occupancy_percent": ratio}})
                return

        send_json(self, {"ok": False, "message": "not found"}, 404)

    def handle_api_post(self, path: str) -> None:
        try:
            payload = parse_body(self)
        except Exception as exc:
            send_json(self, {"ok": False, "message": f"invalid json: {exc}"}, 400)
            return

        with db_connect() as conn:
            if path == "/api/v1/flight/plans":
                try:
                    new_id = self.create_plan(conn, payload)
                    plan = get_plan_with_refs(conn, new_id)
                    send_json(self, {"ok": True, "item": plan}, 201)
                except ValueError as exc:
                    send_json(self, {"ok": False, "message": str(exc)}, 400)
                return

            if path == "/api/v1/flight/approval-rules":
                try:
                    config = validate_rule_config(payload.get("config", {}))
                    rule_code = payload.get("rule_code", "FLIGHT_BASE_RULES")
                    rule_name = payload.get("rule_name", "飞行审批基础规则")
                    enabled = int(payload.get("enabled", 1))
                    operator = payload.get("updated_by", "rule_admin")
                    now = utc_now()
                    existing = conn.execute("SELECT id FROM approval_rule_sets WHERE rule_code = ?", (rule_code,)).fetchone()
                    if existing:
                        conn.execute(
                            """
                            UPDATE approval_rule_sets
                            SET rule_name = ?, config_json = ?, enabled = ?, updated_by = ?, updated_at_utc = ?
                            WHERE rule_code = ?
                            """,
                            (rule_name, json.dumps(config, ensure_ascii=False), enabled, operator, now, rule_code),
                        )
                    else:
                        conn.execute(
                            """
                            INSERT INTO approval_rule_sets (rule_code, rule_name, config_json, enabled, updated_by, updated_at_utc)
                            VALUES (?, ?, ?, ?, ?, ?)
                            """,
                            (rule_code, rule_name, json.dumps(config, ensure_ascii=False), enabled, operator, now),
                        )
                    conn.commit()
                    send_json(self, {"ok": True})
                except ValueError as exc:
                    send_json(self, {"ok": False, "message": str(exc)}, 400)
                return

            if path == "/api/v1/map/objects":
                try:
                    item = self.create_map_object(conn, payload)
                    send_json(self, {"ok": True, "item": item}, 201)
                except ValueError as exc:
                    send_json(self, {"ok": False, "message": str(exc)}, 400)
                return

            risk_match = re.fullmatch(r"/api/v1/flight/plans/(\d+)/risk-check", path)
            if risk_match:
                plan_id = int(risk_match.group(1))
                result = compute_risk(conn, plan_id)
                send_json(self, result, 200 if result["ok"] else 404)
                return

            submit_match = re.fullmatch(r"/api/v1/flight/plans/(\d+)/submit", path)
            if submit_match:
                self.transition_plan_status(conn, int(submit_match.group(1)), "pending_review")
                send_json(self, {"ok": True})
                return

            approve_match = re.fullmatch(r"/api/v1/flight/plans/(\d+)/approve", path)
            if approve_match:
                plan_id = int(approve_match.group(1))
                approver = payload.get("approver", "飞行服务中心审批员")
                comment = payload.get("comment", "审批通过")
                self.transition_plan_status(conn, plan_id, "approved")
                conn.execute(
                    """
                    INSERT INTO flight_approvals (plan_id, approval_node, approver, result, comment, approved_at_utc)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (plan_id, "flight_service_center", approver, "approved", comment, utc_now()),
                )
                conn.commit()
                send_json(self, {"ok": True})
                return

            reject_match = re.fullmatch(r"/api/v1/flight/plans/(\d+)/reject", path)
            if reject_match:
                plan_id = int(reject_match.group(1))
                approver = payload.get("approver", "飞行服务中心审批员")
                comment = payload.get("comment", "退回补正")
                self.transition_plan_status(conn, plan_id, "returned")
                conn.execute(
                    """
                    INSERT INTO flight_approvals (plan_id, approval_node, approver, result, comment, approved_at_utc)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (plan_id, "flight_service_center", approver, "returned", comment, utc_now()),
                )
                conn.commit()
                send_json(self, {"ok": True})
                return

            release_match = re.fullmatch(r"/api/v1/flight/plans/(\d+)/release", path)
            if release_match:
                plan_id = int(release_match.group(1))
                by = payload.get("released_by", "运行值班员")
                notes = payload.get("notes", "动态放行通过")
                plan = conn.execute("SELECT status FROM flight_plans WHERE id = ?", (plan_id,)).fetchone()
                if not plan:
                    send_json(self, {"ok": False, "message": "plan not found"}, 404)
                    return
                if plan["status"] != "approved":
                    send_json(self, {"ok": False, "message": "only approved plan can be released"}, 400)
                    return
                self.transition_plan_status(conn, plan_id, "released")
                conn.execute(
                    """
                    INSERT INTO plan_releases (plan_id, release_status, released_by, released_at_utc, notes)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (plan_id, "released", by, utc_now(), notes),
                )
                conn.commit()
                send_json(self, {"ok": True})
                return

            replay_match = re.fullmatch(r"/api/v1/flight/plans/(\d+)/replay/generate", path)
            if replay_match:
                try:
                    count = create_replay_tracks_for_plan(conn, int(replay_match.group(1)))
                    send_json(self, {"ok": True, "generated_points": count})
                except ValueError as exc:
                    send_json(self, {"ok": False, "message": str(exc)}, 400)
                return

        send_json(self, {"ok": False, "message": "not found"}, 404)

    def handle_api_put(self, path: str) -> None:
        try:
            payload = parse_body(self)
        except Exception as exc:
            send_json(self, {"ok": False, "message": f"invalid json: {exc}"}, 400)
            return
        edit_match = re.fullmatch(r"/api/v1/map/objects/([^/]+)", path)
        if not edit_match:
            send_json(self, {"ok": False, "message": "not found"}, 404)
            return
        with db_connect() as conn:
            try:
                item = self.update_map_object(conn, edit_match.group(1), payload)
                send_json(self, {"ok": True, "item": item})
            except ValueError as exc:
                send_json(self, {"ok": False, "message": str(exc)}, 400)

    def handle_api_delete(self, path: str) -> None:
        delete_match = re.fullmatch(r"/api/v1/map/objects/([^/]+)", path)
        if not delete_match:
            send_json(self, {"ok": False, "message": "not found"}, 404)
            return
        with db_connect() as conn:
            object_code = delete_match.group(1)
            operator = self.headers.get("X-Operator", "map_operator")
            row = conn.execute("SELECT * FROM map_objects WHERE object_code = ?", (object_code,)).fetchone()
            if not row:
                send_json(self, {"ok": False, "message": "object not found"}, 404)
                return
            before = build_object_snapshot(row)
            now = utc_now()
            conn.execute("UPDATE map_objects SET status = 'deleted', updated_at_utc = ? WHERE object_code = ?", (now, object_code))
            after = dict(before)
            after["status"] = "deleted"
            after["updated_at_utc"] = now
            insert_map_edit_record(conn, object_code, "delete", before, after, operator)
            conn.commit()
            send_json(self, {"ok": True})

    def transition_plan_status(self, conn: sqlite3.Connection, plan_id: int, target_status: str) -> None:
        row = conn.execute("SELECT id FROM flight_plans WHERE id = ?", (plan_id,)).fetchone()
        if not row:
            raise ValueError("plan not found")
        conn.execute(
            "UPDATE flight_plans SET status = ?, updated_at_utc = ? WHERE id = ?",
            (target_status, utc_now(), plan_id),
        )
        conn.commit()

    def create_plan(self, conn: sqlite3.Connection, payload: dict) -> int:
        required = ["task_name", "task_type", "org_code", "pilot_code", "aircraft_code", "district", "start_time_utc", "end_time_utc"]
        for key in required:
            if not payload.get(key):
                raise ValueError(f"missing field: {key}")

        route = payload.get("route", [])
        if not isinstance(route, list):
            raise ValueError("route must be a list of [lat,lng]")
        if len(route) < 2:
            raise ValueError("route must contain at least 2 points")

        org_row = conn.execute("SELECT id FROM organizations WHERE org_code = ?", (payload["org_code"],)).fetchone()
        pilot_row = conn.execute("SELECT id FROM pilots WHERE pilot_code = ?", (payload["pilot_code"],)).fetchone()
        aircraft_row = conn.execute("SELECT id FROM aircraft_registry WHERE aircraft_code = ?", (payload["aircraft_code"],)).fetchone()
        if not org_row or not pilot_row or not aircraft_row:
            raise ValueError("invalid org_code/pilot_code/aircraft_code")

        plan_no = payload.get("plan_no") or f"FP-HZ-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        now = utc_now()
        cur = conn.execute(
            """
            INSERT INTO flight_plans
              (plan_no, task_name, task_type, org_id, pilot_id, aircraft_id, district, start_time_utc, end_time_utc, min_altitude_m, max_altitude_m, route_json, status, created_at_utc, updated_at_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                plan_no,
                payload["task_name"],
                payload["task_type"],
                org_row["id"],
                pilot_row["id"],
                aircraft_row["id"],
                payload["district"],
                payload["start_time_utc"],
                payload["end_time_utc"],
                int(payload.get("min_altitude_m", 60)),
                int(payload.get("max_altitude_m", 120)),
                json.dumps(route, ensure_ascii=False),
                "draft",
                now,
                now,
            ),
        )
        conn.commit()
        return int(cur.lastrowid)

    def create_map_object(self, conn: sqlite3.Connection, payload: dict) -> dict:
        object_name = str(payload.get("object_name", "")).strip()
        object_type = str(payload.get("object_type", "")).strip()
        geometry_type = str(payload.get("geometry_type", "")).strip()
        district = str(payload.get("district", "")).strip() or "Hangzhou"
        risk_level = str(payload.get("risk_level", "medium")).strip() or "medium"
        status = str(payload.get("status", "enabled")).strip() or "enabled"
        geometry = payload.get("geometry")
        operator = str(payload.get("operator", "map_operator")).strip() or "map_operator"
        if not object_name:
            raise ValueError("object_name is required")
        if not object_type:
            raise ValueError("object_type is required")
        validate_geometry(geometry_type, geometry)
        object_code = str(payload.get("object_code", "")).strip() or generate_object_code()
        exists = conn.execute("SELECT id FROM map_objects WHERE object_code = ?", (object_code,)).fetchone()
        if exists:
            raise ValueError(f"object_code already exists: {object_code}")
        now = utc_now()
        conn.execute(
            """
            INSERT INTO map_objects
              (object_code, object_name, object_type, geometry_type, geometry_json, district, risk_level, status, source_id, updated_at_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                object_code,
                object_name,
                object_type,
                geometry_type,
                json.dumps(geometry, ensure_ascii=False),
                district,
                risk_level,
                status,
                None,
                now,
            ),
        )
        row = conn.execute("SELECT * FROM map_objects WHERE object_code = ?", (object_code,)).fetchone()
        after = build_object_snapshot(row)
        insert_map_edit_record(conn, object_code, "create", {}, after, operator)
        conn.commit()
        return map_row_to_output(row)

    def update_map_object(self, conn: sqlite3.Connection, object_code: str, payload: dict) -> dict:
        row = conn.execute("SELECT * FROM map_objects WHERE object_code = ?", (object_code,)).fetchone()
        if not row:
            raise ValueError("object not found")
        data = build_object_snapshot(row)
        operator = str(payload.get("operator", "map_operator")).strip() or "map_operator"
        allowed = ["object_name", "object_type", "geometry_type", "district", "risk_level", "status"]
        for key in allowed:
            if key in payload and payload[key] is not None:
                data[key] = payload[key]
        if "geometry" in payload:
            data["geometry"] = payload["geometry"]
        validate_geometry(str(data["geometry_type"]), data["geometry"])

        now = utc_now()
        conn.execute(
            """
            UPDATE map_objects
            SET object_name = ?, object_type = ?, geometry_type = ?, geometry_json = ?, district = ?, risk_level = ?, status = ?, updated_at_utc = ?
            WHERE object_code = ?
            """,
            (
                data["object_name"],
                data["object_type"],
                data["geometry_type"],
                json.dumps(data["geometry"], ensure_ascii=False),
                data["district"],
                data["risk_level"],
                data["status"],
                now,
                object_code,
            ),
        )
        new_row = conn.execute("SELECT * FROM map_objects WHERE object_code = ?", (object_code,)).fetchone()
        insert_map_edit_record(conn, object_code, "update", build_object_snapshot(row), build_object_snapshot(new_row), operator)
        conn.commit()
        return map_row_to_output(new_row)

    def handle_static(self, path: str) -> None:
        if path in ("", "/"):
            path = "/index.html"
        safe = path.lstrip("/")
        file_path = (FRONTEND_DIR / safe).resolve()
        if not str(file_path).startswith(str(FRONTEND_DIR.resolve())):
            send_text(self, "forbidden", 403)
            return
        if not file_path.exists() or not file_path.is_file():
            send_text(self, "not found", 404)
            return

        if file_path.suffix == ".html":
            ctype = "text/html; charset=utf-8"
        elif file_path.suffix == ".css":
            ctype = "text/css; charset=utf-8"
        elif file_path.suffix == ".js":
            ctype = "application/javascript; charset=utf-8"
        elif file_path.suffix == ".json":
            ctype = "application/json; charset=utf-8"
        else:
            ctype = "application/octet-stream"
        send_text(self, file_path.read_text(encoding="utf-8"), 200, ctype)


def run_server(port: int = 8090) -> None:
    if not DB_PATH.exists():
        raise FileNotFoundError(f"database not found: {DB_PATH}. run init_db.py first")
    server = ThreadingHTTPServer(("0.0.0.0", port), AppHandler)
    print(f"[OK] low altitude platform running at http://localhost:{port}")
    print("[OK] api health: /api/health")
    server.serve_forever()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Low altitude platform API server")
    parser.add_argument("--port", type=int, default=8090)
    args = parser.parse_args()
    run_server(args.port)
