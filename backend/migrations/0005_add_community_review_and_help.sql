ALTER TABLE place_submissions ADD COLUMN submitter_key TEXT
  CHECK (submitter_key IS NULL OR length(submitter_key) BETWEEN 12 AND 80);

CREATE TABLE IF NOT EXISTS place_submission_review_votes (
  submission_id INTEGER NOT NULL REFERENCES place_submissions(id) ON DELETE CASCADE,
  voter_key TEXT NOT NULL CHECK (length(voter_key) BETWEEN 12 AND 80),
  is_valid INTEGER NOT NULL CHECK (is_valid IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (submission_id, voter_key)
);

CREATE INDEX IF NOT EXISTS place_submission_review_votes_submission_idx
  ON place_submission_review_votes (submission_id, is_valid);

CREATE TABLE IF NOT EXISTS place_help_requests (
  place_key TEXT PRIMARY KEY CHECK (length(place_key) BETWEEN 3 AND 120),
  lat REAL NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng REAL NOT NULL CHECK (lng BETWEEN -180 AND 180),
  requester_key TEXT NOT NULL CHECK (length(requester_key) BETWEEN 12 AND 80),
  request_type TEXT NOT NULL DEFAULT 'paper' CHECK (request_type = 'paper'),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS place_help_requests_expires_at_idx
  ON place_help_requests (expires_at);
