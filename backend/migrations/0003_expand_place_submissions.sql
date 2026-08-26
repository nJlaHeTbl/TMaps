PRAGMA foreign_keys = OFF;

CREATE TABLE toilets_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng REAL NOT NULL CHECK (lng BETWEEN -180 AND 180),
  username TEXT,
  name TEXT,
  is_free INTEGER NOT NULL DEFAULT 1 CHECK (is_free IN (0, 1)),
  cleanliness INTEGER CHECK (cleanliness BETWEEN 1 AND 5),
  condition TEXT CHECK (condition IS NULL OR condition IN ('Хорошее', 'Среднее', 'Плохое')),
  comment TEXT CHECK (comment IS NULL OR length(comment) <= 300),
  place_kind TEXT NOT NULL DEFAULT 'community_toilet' CHECK (
    place_kind IN (
      'community_toilet', 'cafe', 'fuel', 'organization',
      'phone_charging', 'ev_charging', 'water'
    )
  ),
  has_toilet INTEGER NOT NULL DEFAULT 1 CHECK (has_toilet IN (0, 1)),
  has_paper INTEGER CHECK (has_paper IS NULL OR has_paper IN (0, 1)),
  has_soap INTEGER CHECK (has_soap IS NULL OR has_soap IN (0, 1)),
  wheelchair_accessible INTEGER CHECK (wheelchair_accessible IS NULL OR wheelchair_accessible IN (0, 1)),
  phone_charging INTEGER CHECK (phone_charging IS NULL OR phone_charging IN (0, 1)),
  access_type TEXT NOT NULL DEFAULT 'public' CHECK (
    access_type IN ('public', 'customers', 'permissive', 'destination', 'unknown')
  ),
  submission_id INTEGER UNIQUE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO toilets_new (
  id, lat, lng, username, name, is_free, cleanliness, condition, comment,
  place_kind, has_toilet, access_type, submission_id, created_at
)
SELECT
  id, lat, lng, username, name, is_free, cleanliness, condition, comment,
  place_kind, has_toilet, access_type, submission_id, created_at
FROM toilets;

DROP TABLE toilets;
ALTER TABLE toilets_new RENAME TO toilets;

CREATE TABLE place_submissions_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL CHECK (lat BETWEEN 40.45 AND 55.55),
  lng REAL NOT NULL CHECK (lng BETWEEN 46.45 AND 87.40),
  username TEXT NOT NULL CHECK (length(trim(username)) BETWEEN 2 AND 30),
  place_kind TEXT NOT NULL CHECK (
    place_kind IN (
      'community_toilet', 'cafe', 'fuel', 'organization',
      'phone_charging', 'ev_charging', 'water'
    )
  ),
  name TEXT CHECK (name IS NULL OR length(trim(name)) BETWEEN 2 AND 80),
  is_free INTEGER NOT NULL CHECK (is_free IN (0, 1)),
  cleanliness INTEGER NOT NULL CHECK (cleanliness BETWEEN 1 AND 5),
  condition TEXT NOT NULL CHECK (condition IN ('Хорошее', 'Среднее', 'Плохое')),
  has_paper INTEGER CHECK (has_paper IS NULL OR has_paper IN (0, 1)),
  has_soap INTEGER CHECK (has_soap IS NULL OR has_soap IN (0, 1)),
  wheelchair_accessible INTEGER CHECK (wheelchair_accessible IS NULL OR wheelchair_accessible IN (0, 1)),
  phone_charging INTEGER CHECK (phone_charging IS NULL OR phone_charging IN (0, 1)),
  access_type TEXT NOT NULL DEFAULT 'public' CHECK (
    access_type IN ('public', 'customers', 'permissive', 'destination', 'unknown')
  ),
  comment TEXT CHECK (comment IS NULL OR length(comment) <= 300),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TEXT,
  published_toilet_id INTEGER
);

INSERT INTO place_submissions_new (
  id, lat, lng, username, place_kind, is_free, cleanliness, condition,
  comment, status, created_at, reviewed_at, published_toilet_id
)
SELECT
  id, lat, lng, username, place_kind, is_free, cleanliness, condition,
  comment, status, created_at, reviewed_at, published_toilet_id
FROM place_submissions;

DROP TABLE place_submissions;
ALTER TABLE place_submissions_new RENAME TO place_submissions;
CREATE INDEX place_submissions_status_created_at_idx
  ON place_submissions (status, created_at DESC);

PRAGMA foreign_keys = ON;
