alter table public.place_submissions
  add column if not exists submitter_key text
    check (
      submitter_key is null
      or char_length(submitter_key) between 12 and 80
    );

create table if not exists public.place_submission_review_votes (
  submission_id bigint not null
    references public.place_submissions(id) on delete cascade,
  voter_key text not null check (char_length(voter_key) between 12 and 80),
  is_valid boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (submission_id, voter_key)
);

create index if not exists place_submission_review_votes_submission_idx
  on public.place_submission_review_votes (submission_id, is_valid);

alter table public.place_submission_review_votes enable row level security;
revoke all on public.place_submission_review_votes from anon, authenticated;

create or replace function public.submit_place(
  p_lat double precision,
  p_lng double precision,
  p_username text,
  p_place_kind text,
  p_name text,
  p_is_free boolean,
  p_cleanliness integer,
  p_condition text,
  p_has_paper boolean,
  p_has_soap boolean,
  p_wheelchair_accessible boolean,
  p_phone_charging boolean,
  p_access_type text,
  p_submitter_key text,
  p_comment text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  submission_id bigint;
begin
  if p_lat not between 40.45 and 55.55
     or p_lng not between 46.45 and 87.40 then
    raise exception 'Точка должна находиться в Казахстане';
  end if;

  if p_place_kind not in (
    'community_toilet',
    'cafe',
    'fuel',
    'organization',
    'phone_charging',
    'ev_charging',
    'water'
  ) then
    raise exception 'Неизвестная категория';
  end if;

  if p_place_kind in ('cafe', 'fuel', 'organization')
     and (p_name is null or char_length(trim(p_name)) < 2) then
    raise exception 'Укажи название места';
  end if;

  if p_access_type not in (
    'public',
    'customers',
    'permissive',
    'destination',
    'unknown'
  ) then
    raise exception 'Неизвестный тип доступа';
  end if;

  if p_submitter_key is null
     or char_length(p_submitter_key) not between 12 and 80 then
    raise exception 'Некорректный ключ устройства';
  end if;

  insert into public.place_submissions (
    lat,
    lng,
    username,
    place_kind,
    name,
    is_free,
    cleanliness,
    condition,
    has_paper,
    has_soap,
    wheelchair_accessible,
    phone_charging,
    access_type,
    submitter_key,
    comment
  ) values (
    p_lat,
    p_lng,
    trim(p_username),
    p_place_kind,
    nullif(trim(p_name), ''),
    p_is_free,
    p_cleanliness,
    p_condition,
    p_has_paper,
    p_has_soap,
    p_wheelchair_accessible,
    p_phone_charging,
    p_access_type,
    p_submitter_key,
    nullif(trim(p_comment), '')
  )
  returning id into submission_id;

  return submission_id;
end;
$$;

revoke all on function public.submit_place(
  double precision,
  double precision,
  text,
  text,
  text,
  boolean,
  integer,
  text,
  boolean,
  boolean,
  boolean,
  boolean,
  text,
  text,
  text
) from public;

grant execute on function public.submit_place(
  double precision,
  double precision,
  text,
  text,
  text,
  boolean,
  integer,
  text,
  boolean,
  boolean,
  boolean,
  boolean,
  text,
  text,
  text
) to anon, authenticated;

create or replace function public.get_community_review_submissions()
returns table (
  submission_id bigint,
  lat double precision,
  lng double precision,
  place_kind text,
  name text,
  is_free boolean,
  cleanliness integer,
  condition text,
  has_paper boolean,
  has_soap boolean,
  wheelchair_accessible boolean,
  phone_charging boolean,
  access_type text,
  created_at timestamptz,
  review_available_at timestamptz,
  confirmation_count bigint,
  rejection_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    submission.id,
    submission.lat,
    submission.lng,
    submission.place_kind,
    submission.name,
    submission.is_free,
    submission.cleanliness,
    submission.condition,
    submission.has_paper,
    submission.has_soap,
    submission.wheelchair_accessible,
    submission.phone_charging,
    submission.access_type,
    submission.created_at,
    submission.created_at + interval '24 hours',
    count(*) filter (where vote.is_valid),
    count(*) filter (where not vote.is_valid)
  from public.place_submissions as submission
  left join public.place_submission_review_votes as vote
    on vote.submission_id = submission.id
  where submission.status = 'pending'
    and submission.created_at <= now() - interval '24 hours'
  group by submission.id
  order by submission.created_at desc
  limit 500;
$$;

revoke all on function public.get_community_review_submissions() from public;
grant execute on function public.get_community_review_submissions()
  to anon, authenticated;

create or replace function public.review_place_submission(
  p_submission_id bigint,
  p_voter_key text,
  p_is_valid boolean
)
returns table (
  status text,
  confirmation_count bigint,
  rejection_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  submission_status text;
  submission_created_at timestamptz;
  submission_submitter_key text;
  confirmations bigint;
  rejections bigint;
begin
  if p_voter_key is null
     or char_length(p_voter_key) not between 12 and 80 then
    raise exception 'Некорректный ключ устройства';
  end if;

  select
    submission.status,
    submission.created_at,
    submission.submitter_key
  into
    submission_status,
    submission_created_at,
    submission_submitter_key
  from public.place_submissions as submission
  where submission.id = p_submission_id
  for update;

  if not found then
    raise exception 'Заявка не найдена';
  end if;

  if submission_status <> 'pending' then
    raise exception 'Заявка уже обработана';
  end if;

  if submission_created_at > now() - interval '24 hours' then
    raise exception 'Заявка ещё ожидает ответа администратора';
  end if;

  if submission_submitter_key is not null
     and submission_submitter_key = p_voter_key then
    raise exception 'Свою заявку должен подтвердить другой человек';
  end if;

  insert into public.place_submission_review_votes (
    submission_id,
    voter_key,
    is_valid
  ) values (
    p_submission_id,
    p_voter_key,
    p_is_valid
  )
  on conflict (submission_id, voter_key)
  do update set
    is_valid = excluded.is_valid,
    updated_at = now();

  select
    count(*) filter (where vote.is_valid),
    count(*) filter (where not vote.is_valid)
  into confirmations, rejections
  from public.place_submission_review_votes as vote
  where vote.submission_id = p_submission_id;

  if confirmations >= 2 and confirmations >= rejections + 2 then
    update public.place_submissions as submission
    set status = 'approved'
    where submission.id = p_submission_id
      and submission.status = 'pending';
    submission_status := 'approved';
  elsif rejections >= 3 and rejections >= confirmations + 2 then
    update public.place_submissions as submission
    set status = 'rejected'
    where submission.id = p_submission_id
      and submission.status = 'pending';
    submission_status := 'rejected';
  end if;

  return query values (submission_status, confirmations, rejections);
end;
$$;

revoke all on function public.review_place_submission(
  bigint, text, boolean
) from public;
grant execute on function public.review_place_submission(
  bigint, text, boolean
) to anon, authenticated;

create or replace function public.dismiss_duplicate_place_submissions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.place_submissions as duplicate
  set status = 'rejected', reviewed_at = now()
  where duplicate.status = 'pending'
    and duplicate.id <> new.id
    and duplicate.place_kind = new.place_kind
    and abs(duplicate.lat - new.lat) <= 0.00008
    and abs(duplicate.lng - new.lng) <= 0.00008
    and (
      (duplicate.name is null and new.name is null)
      or lower(trim(duplicate.name)) = lower(trim(new.name))
    );

  return new;
end;
$$;

drop trigger if exists dismiss_duplicate_place_submissions
  on public.place_submissions;
create trigger dismiss_duplicate_place_submissions
after update of status on public.place_submissions
for each row
when (new.status = 'approved' and old.status <> 'approved')
execute function public.dismiss_duplicate_place_submissions();

create table if not exists public.place_help_requests (
  place_key text primary key check (char_length(place_key) between 3 and 120),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  requester_key text not null check (char_length(requester_key) between 12 and 80),
  request_type text not null default 'paper'
    check (request_type in ('paper')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '45 minutes')
);

create index if not exists place_help_requests_expires_at_idx
  on public.place_help_requests (expires_at);

alter table public.place_help_requests enable row level security;
revoke all on public.place_help_requests from anon, authenticated;

create or replace function public.get_active_place_help_requests()
returns table (
  place_key text,
  request_type text,
  created_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    request.place_key,
    request.request_type,
    request.created_at,
    request.expires_at
  from public.place_help_requests as request
  where request.expires_at > now()
  order by request.created_at desc
  limit 500;
$$;

revoke all on function public.get_active_place_help_requests() from public;
grant execute on function public.get_active_place_help_requests()
  to anon, authenticated;

create or replace function public.request_place_help(
  p_place_key text,
  p_lat double precision,
  p_lng double precision,
  p_requester_key text
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  request_expires_at timestamptz;
begin
  if p_place_key is null
     or char_length(trim(p_place_key)) not between 3 and 120 then
    raise exception 'Некорректная точка';
  end if;

  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Некорректные координаты';
  end if;

  if p_requester_key is null
     or char_length(p_requester_key) not between 12 and 80 then
    raise exception 'Некорректный ключ устройства';
  end if;

  request_expires_at := now() + interval '45 minutes';
  insert into public.place_help_requests (
    place_key,
    lat,
    lng,
    requester_key,
    request_type,
    created_at,
    expires_at
  ) values (
    trim(p_place_key),
    p_lat,
    p_lng,
    p_requester_key,
    'paper',
    now(),
    request_expires_at
  )
  on conflict (place_key)
  do update set
    lat = excluded.lat,
    lng = excluded.lng,
    requester_key = excluded.requester_key,
    request_type = excluded.request_type,
    created_at = excluded.created_at,
    expires_at = excluded.expires_at;

  return request_expires_at;
end;
$$;

revoke all on function public.request_place_help(
  text, double precision, double precision, text
) from public;
grant execute on function public.request_place_help(
  text, double precision, double precision, text
) to anon, authenticated;
