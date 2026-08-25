PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS toilets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng REAL NOT NULL CHECK (lng BETWEEN -180 AND 180),
  username TEXT,
  name TEXT,
  is_free INTEGER NOT NULL DEFAULT 1 CHECK (is_free IN (0, 1)),
  cleanliness INTEGER CHECK (cleanliness BETWEEN 1 AND 5),
  condition TEXT CHECK (condition IS NULL OR condition IN ('Хорошее', 'Среднее', 'Плохое')),
  comment TEXT CHECK (comment IS NULL OR length(comment) <= 300),
  place_kind TEXT NOT NULL DEFAULT 'community_toilet'
    CHECK (place_kind IN ('community_toilet', 'phone_charging', 'ev_charging', 'water')),
  has_toilet INTEGER NOT NULL DEFAULT 1 CHECK (has_toilet IN (0, 1)),
  access_type TEXT NOT NULL DEFAULT 'public'
    CHECK (access_type IN ('public', 'customers', 'permissive', 'destination', 'unknown')),
  submission_id INTEGER UNIQUE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS toilet_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  place_key TEXT NOT NULL CHECK (length(place_key) BETWEEN 3 AND 120),
  lat REAL NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng REAL NOT NULL CHECK (lng BETWEEN -180 AND 180),
  username TEXT NOT NULL CHECK (length(trim(username)) BETWEEN 2 AND 30),
  cleanliness INTEGER NOT NULL CHECK (cleanliness BETWEEN 1 AND 5),
  condition TEXT NOT NULL CHECK (condition IN ('Хорошее', 'Среднее', 'Плохое')),
  is_free INTEGER CHECK (is_free IS NULL OR is_free IN (0, 1)),
  has_toilet INTEGER CHECK (has_toilet IS NULL OR has_toilet IN (0, 1)),
  has_paper INTEGER CHECK (has_paper IS NULL OR has_paper IN (0, 1)),
  has_soap INTEGER CHECK (has_soap IS NULL OR has_soap IN (0, 1)),
  wheelchair_accessible INTEGER CHECK (wheelchair_accessible IS NULL OR wheelchair_accessible IN (0, 1)),
  phone_charging INTEGER CHECK (phone_charging IS NULL OR phone_charging IN (0, 1)),
  access_type TEXT NOT NULL DEFAULT 'unknown'
    CHECK (access_type IN ('public', 'customers', 'permissive', 'destination', 'unknown')),
  comment TEXT CHECK (comment IS NULL OR length(comment) <= 300),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS toilet_reports_place_key_created_at_idx
  ON toilet_reports (place_key, created_at DESC);

CREATE TABLE IF NOT EXISTS place_votes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  place_key TEXT NOT NULL CHECK (length(place_key) BETWEEN 3 AND 120),
  voter_key TEXT NOT NULL CHECK (length(voter_key) BETWEEN 12 AND 80),
  is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (place_key, voter_key)
);

CREATE TABLE IF NOT EXISTS place_submissions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL CHECK (lat BETWEEN 40.45 AND 55.55),
  lng REAL NOT NULL CHECK (lng BETWEEN 46.45 AND 87.40),
  username TEXT NOT NULL CHECK (length(trim(username)) BETWEEN 2 AND 30),
  place_kind TEXT NOT NULL
    CHECK (place_kind IN ('community_toilet', 'phone_charging', 'ev_charging', 'water')),
  is_free INTEGER NOT NULL CHECK (is_free IN (0, 1)),
  cleanliness INTEGER NOT NULL CHECK (cleanliness BETWEEN 1 AND 5),
  condition TEXT NOT NULL CHECK (condition IN ('Хорошее', 'Среднее', 'Плохое')),
  comment TEXT CHECK (comment IS NULL OR length(comment) <= 300),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TEXT,
  published_toilet_id INTEGER
);

CREATE INDEX IF NOT EXISTS place_submissions_status_created_at_idx
  ON place_submissions (status, created_at DESC);

CREATE TABLE IF NOT EXISTS rate_limits (
  bucket_key TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  hits INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (bucket_key, window_start)
);
