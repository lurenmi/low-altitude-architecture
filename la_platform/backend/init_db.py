from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = BASE_DIR / "data" / "low_altitude_platform.db"
SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"
SEED_PATH = DATA_DIR / "hangzhou_seed.json"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_utc(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def load_seed() -> dict:
    return json.loads(SEED_PATH.read_text(encoding="utf-8"))


def create_db(conn: sqlite3.Connection) -> None:
    schema_sql = SCHEMA_PATH.read_text(encoding="utf-8")
    conn.executescript(schema_sql)


def clear_tables(conn: sqlite3.Connection) -> None:
    tables = [
        "flight_replay_tracks",
        "map_edit_records",
        "approval_rule_logs",
        "approval_rule_sets",
        "realtime_aircraft",
        "plan_releases",
        "flight_approvals",
        "flight_risk_checks",
        "flight_plans",
        "aircraft_registry",
        "pilots",
        "organizations",
        "weather_cells",
        "airspace_grids",
        "airspace_zones",
        "facilities",
        "map_objects",
        "map_layers",
        "data_resources",
        "data_sources",
    ]
    for table in tables:
        conn.execute(f"DELETE FROM {table}")


def seed_approval_rules(conn: sqlite3.Connection) -> None:
    base_rule = {
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
    conn.execute(
        """
        INSERT INTO approval_rule_sets (rule_code, rule_name, config_json, enabled, updated_by, updated_at_utc)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            "FLIGHT_BASE_RULES",
            "飞行审批基础规则",
            json.dumps(base_rule, ensure_ascii=False),
            1,
            "system_seed",
            utc_now(),
        ),
    )


def seed_base(conn: sqlite3.Connection, seed: dict) -> dict:
    source_id_map = {}
    for item in seed["data_sources"]:
        cur = conn.execute(
            """
            INSERT INTO data_sources (source_name, source_type, source_url, last_verified_utc)
            VALUES (?, ?, ?, ?)
            """,
            (item["source_name"], item["source_type"], item["source_url"], item["last_verified_utc"]),
        )
        source_id_map[len(source_id_map) + 1] = cur.lastrowid

    for item in seed["data_resources"]:
        conn.execute(
            """
            INSERT INTO data_resources (resource_code, resource_name, resource_category, schema_version, owner_module, description)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                item["resource_code"],
                item["resource_name"],
                item["resource_category"],
                item["schema_version"],
                item["owner_module"],
                item["description"],
            ),
        )

    for item in seed["map_layers"]:
        conn.execute(
            """
            INSERT INTO map_layers (layer_code, layer_name, layer_type, is_default_visible, style_json)
            VALUES (?, ?, ?, ?, ?)
            """,
            (item["layer_code"], item["layer_name"], item["layer_type"], item["is_default_visible"], item["style_json"]),
        )

    for item in seed["map_objects"]:
        conn.execute(
            """
            INSERT INTO map_objects
              (object_code, object_name, object_type, geometry_type, geometry_json, district, risk_level, status, source_id, updated_at_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["object_code"],
                item["object_name"],
                item["object_type"],
                item["geometry_type"],
                item["geometry_json"],
                item["district"],
                item["risk_level"],
                item["status"],
                source_id_map.get(item["source_ref"]),
                utc_now(),
            ),
        )

    return source_id_map


def seed_airspace(conn: sqlite3.Connection, seed: dict) -> None:
    for item in seed["airspace_zones"]:
        conn.execute(
            """
            INSERT INTO airspace_zones
              (zone_code, zone_name, zone_type, min_altitude_m, max_altitude_m, district, status, polygon_json, effective_from_utc, effective_to_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["zone_code"],
                item["zone_name"],
                item["zone_type"],
                item["min_altitude_m"],
                item["max_altitude_m"],
                item["district"],
                item["status"],
                item["polygon_json"],
                item["effective_from_utc"],
                item["effective_to_utc"] or None,
            ),
        )

    for item in seed["airspace_grids"]:
        conn.execute(
            """
            INSERT INTO airspace_grids
              (grid_code, district, min_altitude_m, max_altitude_m, capacity_limit, current_load, risk_level)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["grid_code"],
                item["district"],
                item["min_altitude_m"],
                item["max_altitude_m"],
                item["capacity_limit"],
                item["current_load"],
                item["risk_level"],
            ),
        )

    for item in seed["facilities"]:
        conn.execute(
            """
            INSERT INTO facilities
              (facility_code, facility_name, facility_type, district, latitude, longitude, status, capacity, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["facility_code"],
                item["facility_name"],
                item["facility_type"],
                item["district"],
                item["latitude"],
                item["longitude"],
                item["status"],
                item["capacity"],
                item["metadata_json"],
            ),
        )

    for item in seed["weather_cells"]:
        conn.execute(
            """
            INSERT INTO weather_cells
              (cell_code, district, center_lat, center_lng, wind_speed_ms, visibility_km, rainfall_mm, risk_level, updated_at_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["cell_code"],
                item["district"],
                item["center_lat"],
                item["center_lng"],
                item["wind_speed_ms"],
                item["visibility_km"],
                item["rainfall_mm"],
                item["risk_level"],
                utc_now(),
            ),
        )


def seed_flight_service(conn: sqlite3.Connection, seed: dict) -> dict:
    org_id_by_code = {}
    for item in seed["organizations"]:
        cur = conn.execute(
            """
            INSERT INTO organizations (org_code, org_name, org_type, status)
            VALUES (?, ?, ?, ?)
            """,
            (item["org_code"], item["org_name"], item["org_type"], item["status"]),
        )
        org_id_by_code[item["org_code"]] = cur.lastrowid

    pilot_id_by_code = {}
    for item in seed["pilots"]:
        cur = conn.execute(
            """
            INSERT INTO pilots (pilot_code, pilot_name, license_level, license_expiry_utc, org_id, status)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                item["pilot_code"],
                item["pilot_name"],
                item["license_level"],
                item["license_expiry_utc"],
                org_id_by_code[item["org_code"]],
                item["status"],
            ),
        )
        pilot_id_by_code[item["pilot_code"]] = cur.lastrowid

    aircraft_id_by_code = {}
    for item in seed["aircraft_registry"]:
        cur = conn.execute(
            """
            INSERT INTO aircraft_registry (aircraft_code, aircraft_model, max_altitude_m, org_id, status)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                item["aircraft_code"],
                item["aircraft_model"],
                item["max_altitude_m"],
                org_id_by_code[item["org_code"]],
                item["status"],
            ),
        )
        aircraft_id_by_code[item["aircraft_code"]] = cur.lastrowid

    plan_seed_rows = []
    for item in seed["flight_plans"]:
        now = utc_now()
        cur = conn.execute(
            """
            INSERT INTO flight_plans
              (plan_no, task_name, task_type, org_id, pilot_id, aircraft_id, district, start_time_utc, end_time_utc, min_altitude_m, max_altitude_m, route_json, status, created_at_utc, updated_at_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["plan_no"],
                item["task_name"],
                item["task_type"],
                org_id_by_code[item["org_code"]],
                pilot_id_by_code[item["pilot_code"]],
                aircraft_id_by_code[item["aircraft_code"]],
                item["district"],
                item["start_time_utc"],
                item["end_time_utc"],
                item["min_altitude_m"],
                item["max_altitude_m"],
                item["route_json"],
                item["status"],
                now,
                now,
            ),
        )
        plan_seed_rows.append(
            {
                "id": cur.lastrowid,
                "plan_no": item["plan_no"],
                "route": json.loads(item["route_json"]),
                "start_time_utc": item["start_time_utc"],
                "end_time_utc": item["end_time_utc"],
                "min_altitude_m": item["min_altitude_m"],
                "max_altitude_m": item["max_altitude_m"],
            }
        )

    for item in seed["realtime_aircraft"]:
        conn.execute(
            """
            INSERT INTO realtime_aircraft
              (aircraft_code, aircraft_type, status, latitude, longitude, altitude_m, speed_ms, heading_deg, plan_no, updated_at_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["aircraft_code"],
                item["aircraft_type"],
                item["status"],
                item["latitude"],
                item["longitude"],
                item["altitude_m"],
                item["speed_ms"],
                item["heading_deg"],
                item["plan_no"] or None,
                utc_now(),
            ),
        )

    return {
        "plans": plan_seed_rows,
    }


def seed_replay_tracks(conn: sqlite3.Connection, plan_rows: list[dict]) -> None:
    for plan in plan_rows:
        route = plan["route"] if isinstance(plan["route"], list) else []
        if len(route) < 2:
            continue
        start = parse_utc(plan["start_time_utc"])
        end = parse_utc(plan["end_time_utc"])
        total_steps = max(len(route) * 6, 10)
        total_seconds = max(int((end - start).total_seconds()), total_steps)
        step_seconds = max(total_seconds // total_steps, 1)
        min_alt = float(plan["min_altitude_m"])
        max_alt = float(plan["max_altitude_m"])
        alt_delta = max(max_alt - min_alt, 5.0)

        seq = 1
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
                    plan["id"],
                    seq,
                    round(lat, 6),
                    round(lng, 6),
                    round(altitude, 2),
                    round(speed, 2),
                    event_type,
                    event_time,
                ),
            )
            seq += 1


def main() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    seed = load_seed()
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.row_factory = sqlite3.Row
        create_db(conn)
        clear_tables(conn)
        seed_approval_rules(conn)
        seed_base(conn, seed)
        seed_airspace(conn, seed)
        seeded = seed_flight_service(conn, seed)
        seed_replay_tracks(conn, seeded["plans"])
        conn.commit()
        print(f"[OK] database initialized: {DB_PATH}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
