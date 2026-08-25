ALTER TABLE toilet_reports
  ADD COLUMN is_free INTEGER CHECK (is_free IS NULL OR is_free IN (0, 1));
