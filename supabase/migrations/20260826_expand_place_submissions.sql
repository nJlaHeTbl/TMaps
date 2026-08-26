alter table public.place_submissions
  drop constraint if exists place_submissions_place_kind_check;

alter table public.place_submissions
  add constraint place_submissions_place_kind_check
  check (
    place_kind in (
      'community_toilet',
      'cafe',
      'fuel',
      'organization',
      'phone_charging',
      'ev_charging',
      'water'
    )
  ),
  add column if not exists name text
    check (name is null or char_length(trim(name)) between 2 and 80),
  add column if not exists has_paper boolean,
  add column if not exists has_soap boolean,
  add column if not exists wheelchair_accessible boolean,
  add column if not exists phone_charging boolean,
  add column if not exists access_type text not null default 'public'
    check (
      access_type in (
        'public',
        'customers',
        'permissive',
        'destination',
        'unknown'
      )
    );

alter table public.toilets
  add column if not exists name text,
  add column if not exists has_paper boolean,
  add column if not exists has_soap boolean,
  add column if not exists wheelchair_accessible boolean,
  add column if not exists phone_charging boolean;

drop function if exists public.submit_place(
  double precision,
  double precision,
  text,
  text,
  boolean,
  integer,
  text,
  text
);

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
  text
) to anon, authenticated;

create or replace function public.publish_approved_place_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status <> 'approved' then
    insert into public.toilets (
      lat,
      lng,
      username,
      name,
      is_free,
      cleanliness,
      condition,
      comment,
      place_kind,
      has_toilet,
      has_paper,
      has_soap,
      wheelchair_accessible,
      phone_charging,
      access_type
    ) values (
      new.lat,
      new.lng,
      new.username,
      new.name,
      new.is_free,
      new.cleanliness,
      new.condition,
      new.comment,
      new.place_kind,
      new.place_kind = 'community_toilet',
      new.has_paper,
      new.has_soap,
      new.wheelchair_accessible,
      new.phone_charging,
      new.access_type
    )
    returning id into new.published_toilet_id;
    new.reviewed_at = now();
  elsif new.status = 'rejected' and old.status <> 'rejected' then
    new.reviewed_at = now();
  end if;

  return new;
end;
$$;
