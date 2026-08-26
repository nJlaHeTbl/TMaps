CREATE TABLE IF NOT EXISTS place_location_corrections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  place_key TEXT NOT NULL CHECK (length(place_key) BETWEEN 3 AND 120),
  current_lat REAL NOT NULL CHECK (current_lat BETWEEN 40.45 AND 55.55),
  current_lng REAL NOT NULL CHECK (current_lng BETWEEN 46.45 AND 87.40),
  proposed_lat REAL NOT NULL CHECK (proposed_lat BETWEEN 40.45 AND 55.55),
  proposed_lng REAL NOT NULL CHECK (proposed_lng BETWEEN 46.45 AND 87.40),
  username TEXT NOT NULL CHECK (length(trim(username)) BETWEEN 2 AND 30),
  comment TEXT CHECK (comment IS NULL OR length(comment) <= 300),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TEXT
);

CREATE INDEX IF NOT EXISTS place_location_corrections_status_created_at_idx
  ON place_location_corrections (status, created_at DESC);

CREATE TABLE IF NOT EXISTS place_location_overrides (
  place_key TEXT PRIMARY KEY CHECK (length(place_key) BETWEEN 3 AND 120),
  lat REAL NOT NULL CHECK (lat BETWEEN 40.45 AND 55.55),
  lng REAL NOT NULL CHECK (lng BETWEEN 46.45 AND 87.40),
  location_correction_id INTEGER,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
