PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS data_sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_name TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_url TEXT NOT NULL UNIQUE,
  last_verified_utc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS data_resources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  resource_code TEXT NOT NULL UNIQUE,
  resource_name TEXT NOT NULL,
  resource_category TEXT NOT NULL,
  schema_version TEXT NOT NULL,
  owner_module TEXT NOT NULL,
  description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS map_layers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  layer_code TEXT NOT NULL UNIQUE,
  layer_name TEXT NOT NULL,
  layer_type TEXT NOT NULL,
  is_default_visible INTEGER NOT NULL DEFAULT 1,
  style_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS map_objects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  object_code TEXT NOT NULL UNIQUE,
  object_name TEXT NOT NULL,
  object_type TEXT NOT NULL,
  geometry_type TEXT NOT NULL,
  geometry_json TEXT NOT NULL,
  district TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  status TEXT NOT NULL,
  source_id INTEGER,
  updated_at_utc TEXT NOT NULL,
  FOREIGN KEY (source_id) REFERENCES data_sources(id)
);

CREATE TABLE IF NOT EXISTS airspace_zones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  zone_code TEXT NOT NULL UNIQUE,
  zone_name TEXT NOT NULL,
  zone_type TEXT NOT NULL,
  min_altitude_m INTEGER NOT NULL,
  max_altitude_m INTEGER NOT NULL,
  district TEXT NOT NULL,
  status TEXT NOT NULL,
  polygon_json TEXT NOT NULL,
  effective_from_utc TEXT NOT NULL,
  effective_to_utc TEXT
);

CREATE TABLE IF NOT EXISTS airspace_grids (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  grid_code TEXT NOT NULL UNIQUE,
  district TEXT NOT NULL,
  min_altitude_m INTEGER NOT NULL,
  max_altitude_m INTEGER NOT NULL,
  capacity_limit INTEGER NOT NULL,
  current_load INTEGER NOT NULL,
  risk_level TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS facilities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  facility_code TEXT NOT NULL UNIQUE,
  facility_name TEXT NOT NULL,
  facility_type TEXT NOT NULL,
  district TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  status TEXT NOT NULL,
  capacity INTEGER NOT NULL,
  metadata_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS weather_cells (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cell_code TEXT NOT NULL UNIQUE,
  district TEXT NOT NULL,
  center_lat REAL NOT NULL,
  center_lng REAL NOT NULL,
  wind_speed_ms REAL NOT NULL,
  visibility_km REAL NOT NULL,
  rainfall_mm REAL NOT NULL,
  risk_level TEXT NOT NULL,
  updated_at_utc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS organizations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  org_code TEXT NOT NULL UNIQUE,
  org_name TEXT NOT NULL,
  org_type TEXT NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pilots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pilot_code TEXT NOT NULL UNIQUE,
  pilot_name TEXT NOT NULL,
  license_level TEXT NOT NULL,
  license_expiry_utc TEXT NOT NULL,
  org_id INTEGER NOT NULL,
  status TEXT NOT NULL,
  FOREIGN KEY (org_id) REFERENCES organizations(id)
);

CREATE TABLE IF NOT EXISTS aircraft_registry (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  aircraft_code TEXT NOT NULL UNIQUE,
  aircraft_model TEXT NOT NULL,
  max_altitude_m INTEGER NOT NULL,
  org_id INTEGER NOT NULL,
  status TEXT NOT NULL,
  FOREIGN KEY (org_id) REFERENCES organizations(id)
);

CREATE TABLE IF NOT EXISTS flight_plans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_no TEXT NOT NULL UNIQUE,
  task_name TEXT NOT NULL,
  task_type TEXT NOT NULL,
  org_id INTEGER NOT NULL,
  pilot_id INTEGER NOT NULL,
  aircraft_id INTEGER NOT NULL,
  district TEXT NOT NULL,
  start_time_utc TEXT NOT NULL,
  end_time_utc TEXT NOT NULL,
  min_altitude_m INTEGER NOT NULL,
  max_altitude_m INTEGER NOT NULL,
  route_json TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  updated_at_utc TEXT NOT NULL,
  FOREIGN KEY (org_id) REFERENCES organizations(id),
  FOREIGN KEY (pilot_id) REFERENCES pilots(id),
  FOREIGN KEY (aircraft_id) REFERENCES aircraft_registry(id)
);

CREATE TABLE IF NOT EXISTS flight_risk_checks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id INTEGER NOT NULL,
  risk_level TEXT NOT NULL,
  risk_score INTEGER NOT NULL,
  issues_json TEXT NOT NULL,
  checked_at_utc TEXT NOT NULL,
  FOREIGN KEY (plan_id) REFERENCES flight_plans(id)
);

CREATE TABLE IF NOT EXISTS flight_approvals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id INTEGER NOT NULL,
  approval_node TEXT NOT NULL,
  approver TEXT NOT NULL,
  result TEXT NOT NULL,
  comment TEXT NOT NULL,
  approved_at_utc TEXT NOT NULL,
  FOREIGN KEY (plan_id) REFERENCES flight_plans(id)
);

CREATE TABLE IF NOT EXISTS plan_releases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id INTEGER NOT NULL,
  release_status TEXT NOT NULL,
  released_by TEXT NOT NULL,
  released_at_utc TEXT NOT NULL,
  notes TEXT NOT NULL,
  FOREIGN KEY (plan_id) REFERENCES flight_plans(id)
);

CREATE TABLE IF NOT EXISTS realtime_aircraft (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  aircraft_code TEXT NOT NULL,
  aircraft_type TEXT NOT NULL,
  status TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  altitude_m REAL NOT NULL,
  speed_ms REAL NOT NULL,
  heading_deg REAL NOT NULL,
  plan_no TEXT,
  updated_at_utc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS approval_rule_sets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rule_code TEXT NOT NULL UNIQUE,
  rule_name TEXT NOT NULL,
  config_json TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_by TEXT NOT NULL,
  updated_at_utc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS approval_rule_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id INTEGER NOT NULL,
  rule_code TEXT NOT NULL,
  matched INTEGER NOT NULL,
  detail_json TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  FOREIGN KEY (plan_id) REFERENCES flight_plans(id)
);

CREATE TABLE IF NOT EXISTS map_edit_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  object_code TEXT NOT NULL,
  action TEXT NOT NULL,
  before_json TEXT NOT NULL,
  after_json TEXT NOT NULL,
  operator TEXT NOT NULL,
  edited_at_utc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS flight_replay_tracks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id INTEGER NOT NULL,
  seq_no INTEGER NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  altitude_m REAL NOT NULL,
  speed_ms REAL NOT NULL,
  event_type TEXT NOT NULL,
  event_time_utc TEXT NOT NULL,
  FOREIGN KEY (plan_id) REFERENCES flight_plans(id)
);

CREATE INDEX IF NOT EXISTS idx_flight_replay_plan_seq ON flight_replay_tracks(plan_id, seq_no);
CREATE INDEX IF NOT EXISTS idx_map_edit_code_time ON map_edit_records(object_code, edited_at_utc);
