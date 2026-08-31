CREATE TABLE IF NOT EXISTS pedestrian_alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL CHECK (lat BETWEEN 40.45 AND 55.55),
  lng REAL NOT NULL CHECK (lng BETWEEN 46.45 AND 87.4),
  alert_type TEXT NOT NULL CHECK (
    alert_type IN (
      'open', 'closed', 'ice', 'construction', 'snow', 'flooding', 'obstacle'
    )
  ),
  username TEXT NOT NULL,
  description TEXT,
  reporter_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS pedestrian_alerts_active_idx
  ON pedestrian_alerts (expires_at, lat, lng);

CREATE INDEX IF NOT EXISTS pedestrian_alerts_reporter_idx
  ON pedestrian_alerts (reporter_key, created_at);
