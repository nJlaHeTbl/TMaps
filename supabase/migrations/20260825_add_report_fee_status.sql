alter table public.toilet_reports
  add column if not exists is_free boolean;
