-- AZKAR initial Supabase schema
--
-- Run this file once in the Supabase SQL Editor as the postgres/database
-- administrator against a NEW project whose public schema has no base tables.
-- It is intentionally not an upgrade or data migration. It creates no users
-- and does not change Auth provider settings. Review the post-deployment checks
-- and the RLS test scenarios at the end before enabling production signup.
--
-- Never place a service_role key in Flutter or a browser.

begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon')
    or not exists (select 1 from pg_roles where rolname = 'authenticated')
    or not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception 'This initial schema requires the standard Supabase roles.';
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
  ) then
    raise exception
      'AZKAR initial schema stopped: public already contains base tables. Do not use this initial schema as an upgrade.';
  end if;
end;
$$;

revoke create on schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated, service_role;

create function public.normalize_memorial_slug(value text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select pg_catalog.btrim(
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(
        pg_catalog.lower(pg_catalog.btrim(coalesce(value, ''))),
        '[[:space:]_]+',
        '-',
        'g'
      ),
      '-+',
      '-',
      'g'
    ),
    '-'
  );
$$;

create function public.is_valid_memorial_slug(value text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(
    value = public.normalize_memorial_slug(value)
      and pg_catalog.length(value) between 3 and 40
      and value ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
      and value <> all (array[
        'admin', 'api', 'assets', 'auth', 'c', 'dashboard', 'dedications',
        'dua', 'hadith', 'login', 'm', 'quran', 'register', 'settings',
        'videos', 'azkar'
      ]::text[]),
    false
  );
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length_check
    check (display_name is null or pg_catalog.length(display_name) <= 160)
);

create table public.memorial_pages (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  slug text not null,
  title text not null,
  deceased_name text,
  dedication_message text,
  description text,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint memorial_pages_owner_user_id_key unique (owner_user_id),
  constraint memorial_pages_slug_key unique (slug),
  constraint memorial_pages_slug_valid_check
    check (public.is_valid_memorial_slug(slug)),
  constraint memorial_pages_title_valid_check
    check (pg_catalog.length(pg_catalog.btrim(title)) between 1 and 160),
  constraint memorial_pages_deceased_name_length_check
    check (deceased_name is null or pg_catalog.length(deceased_name) <= 160),
  constraint memorial_pages_dedication_message_length_check
    check (
      dedication_message is null
      or pg_catalog.length(dedication_message) <= 4000
    ),
  constraint memorial_pages_description_length_check
    check (description is null or pg_catalog.length(description) <= 4000)
);

create table public.admin_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  display_name text,
  role text not null default 'editor',
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  constraint admin_profiles_role_check check (role in ('owner', 'editor')),
  constraint admin_profiles_email_length_check
    check (pg_catalog.length(email) <= 320),
  constraint admin_profiles_display_name_length_check
    check (display_name is null or pg_catalog.length(display_name) <= 160)
);

create table public.azkar (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  title text not null default '',
  arabic_text text not null default '',
  description text,
  source text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  font_family text,
  font_size integer,
  font_weight integer,
  line_height numeric,
  text_color text,
  background_color text,
  card_shape text,
  text_alignment text,
  gradient_enabled boolean not null default false,
  decoration_enabled boolean not null default true,
  border_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint azkar_font_size_check
    check (font_size is null or font_size between 14 and 72),
  constraint azkar_font_weight_check
    check (font_weight is null or font_weight between 300 and 900),
  constraint azkar_line_height_check
    check (line_height is null or line_height between 1.2 and 3.0)
);

create table public.quran_verses (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  title text not null default '',
  arabic_text text not null default '',
  description text,
  source text,
  translation text,
  surah_number integer,
  surah_name text,
  ayah_from integer,
  ayah_to integer,
  validation_hash text,
  dataset_version text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  font_family text,
  font_size integer,
  font_weight integer,
  line_height numeric,
  text_color text,
  background_color text,
  card_shape text,
  text_alignment text,
  gradient_enabled boolean not null default false,
  decoration_enabled boolean not null default true,
  border_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quran_verses_surah_number_check
    check (surah_number is null or surah_number between 1 and 114),
  constraint quran_verses_ayah_from_check
    check (ayah_from is null or ayah_from > 0),
  constraint quran_verses_ayah_to_check
    check (ayah_to is null or ayah_to > 0),
  constraint quran_verses_ayah_range_check
    check (ayah_from is null or ayah_to is null or ayah_from <= ayah_to),
  constraint quran_verses_font_size_check
    check (font_size is null or font_size between 14 and 72),
  constraint quran_verses_font_weight_check
    check (font_weight is null or font_weight between 300 and 900),
  constraint quran_verses_line_height_check
    check (line_height is null or line_height between 1.2 and 3.0)
);

create table public.hadith (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  title text not null default '',
  arabic_text text not null default '',
  description text,
  source text,
  narrator text,
  hadith_number text,
  authenticity text not null default 'unverified',
  explanation text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  font_family text,
  font_size integer,
  font_weight integer,
  line_height numeric,
  text_color text,
  background_color text,
  card_shape text,
  text_alignment text,
  gradient_enabled boolean not null default false,
  decoration_enabled boolean not null default true,
  border_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hadith_authenticity_check
    check (authenticity in ('sahih', 'hasan', 'daif', 'unverified')),
  constraint hadith_font_size_check
    check (font_size is null or font_size between 14 and 72),
  constraint hadith_font_weight_check
    check (font_weight is null or font_weight between 300 and 900),
  constraint hadith_line_height_check
    check (line_height is null or line_height between 1.2 and 3.0)
);

create table public.duas (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  title text not null default '',
  arabic_text text not null default '',
  description text,
  source text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  font_family text,
  font_size integer,
  font_weight integer,
  line_height numeric,
  text_color text,
  background_color text,
  card_shape text,
  text_alignment text,
  gradient_enabled boolean not null default false,
  decoration_enabled boolean not null default true,
  border_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint duas_font_size_check
    check (font_size is null or font_size between 14 and 72),
  constraint duas_font_weight_check
    check (font_weight is null or font_weight between 300 and 900),
  constraint duas_line_height_check
    check (line_height is null or line_height between 1.2 and 3.0)
);

create table public.tasbeeh_cards (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  title text not null default '',
  arabic_text text not null default '',
  description text,
  source text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  font_family text,
  font_size integer,
  font_weight integer,
  line_height numeric,
  text_color text,
  background_color text,
  card_shape text,
  text_alignment text,
  gradient_enabled boolean not null default false,
  decoration_enabled boolean not null default true,
  border_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tasbeeh_cards_font_size_check
    check (font_size is null or font_size between 14 and 72),
  constraint tasbeeh_cards_font_weight_check
    check (font_weight is null or font_weight between 300 and 900),
  constraint tasbeeh_cards_line_height_check
    check (line_height is null or line_height between 1.2 and 3.0)
);

create table public.youtube_videos (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  title text not null default '',
  arabic_text text not null default '',
  description text,
  source text,
  video_url text,
  video_id text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  font_family text,
  font_size integer,
  font_weight integer,
  line_height numeric,
  text_color text,
  background_color text,
  card_shape text,
  text_alignment text,
  gradient_enabled boolean not null default false,
  decoration_enabled boolean not null default true,
  border_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint youtube_videos_font_size_check
    check (font_size is null or font_size between 14 and 72),
  constraint youtube_videos_font_weight_check
    check (font_weight is null or font_weight between 300 and 900),
  constraint youtube_videos_line_height_check
    check (line_height is null or line_height between 1.2 and 3.0)
);

create table public.dedications (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  title text not null default '',
  arabic_text text not null default '',
  dua_text text not null default '',
  description text,
  source text,
  person_name text,
  message text,
  recipient text not null default 'male',
  display_order integer not null default 0,
  is_published boolean not null default false,
  font_family text,
  font_size integer,
  font_weight integer,
  line_height numeric,
  text_color text,
  background_color text,
  card_shape text,
  text_alignment text,
  gradient_enabled boolean not null default false,
  decoration_enabled boolean not null default true,
  border_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dedications_recipient_check
    check (recipient in ('male', 'female', 'multiple')),
  constraint dedications_arabic_text_matches_dua_check
    check (arabic_text = dua_text),
  constraint dedications_font_size_check
    check (font_size is null or font_size between 14 and 72),
  constraint dedications_font_weight_check
    check (font_weight is null or font_weight between 300 and 900),
  constraint dedications_line_height_check
    check (line_height is null or line_height between 1.2 and 3.0)
);

create table public.homepage_cards (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references public.memorial_pages(id) on delete cascade,
  content_type text not null,
  content_id uuid not null,
  display_order integer not null default 0,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  constraint homepage_cards_content_type_check
    check (content_type in (
      'azkar', 'quran', 'hadith', 'dua', 'tasbeeh', 'youtube', 'dedication'
    ))
);

create table public.theme_settings (
  id text primary key default gen_random_uuid()::text,
  page_id uuid unique references public.memorial_pages(id) on delete cascade,
  primary_color text not null default '#064E3B',
  secondary_color text not null default '#D4AF37',
  background_color text not null default '#F8F5EC',
  surface_color text not null default '#FFFFFF',
  default_card_color text not null default '#FFFFFF',
  default_text_color text not null default '#243B35',
  default_font_family text not null default 'amiri',
  default_card_shape text not null default 'primary',
  updated_at timestamptz not null default now(),
  constraint theme_settings_global_id_check
    check (
      (page_id is null and id = 'global')
      or (page_id is not null and id <> 'global')
    )
);

create table public.admin_audit_logs (
  id bigint generated always as identity primary key,
  page_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('insert', 'update', 'delete')),
  entity_table text not null,
  entity_id text,
  created_at timestamptz not null default now()
);

create unique index homepage_cards_page_content_uidx
  on public.homepage_cards (page_id, content_type, content_id)
  where page_id is not null;
create unique index homepage_cards_global_content_uidx
  on public.homepage_cards (content_type, content_id)
  where page_id is null;

create index memorial_pages_public_slug_idx
  on public.memorial_pages (slug)
  where is_published;

create index azkar_tenant_public_order_idx
  on public.azkar (page_id, is_published, display_order, id);
create index quran_verses_tenant_public_order_idx
  on public.quran_verses (page_id, is_published, display_order, id);
create index hadith_tenant_public_order_idx
  on public.hadith (page_id, is_published, display_order, id);
create index duas_tenant_public_order_idx
  on public.duas (page_id, is_published, display_order, id);
create index tasbeeh_cards_tenant_public_order_idx
  on public.tasbeeh_cards (page_id, is_published, display_order, id);
create index youtube_videos_tenant_public_order_idx
  on public.youtube_videos (page_id, is_published, display_order, id);
create index dedications_tenant_public_order_idx
  on public.dedications (page_id, is_published, display_order, id);
create index homepage_cards_tenant_order_idx
  on public.homepage_cards (page_id, display_order, id);
create index admin_audit_logs_page_created_idx
  on public.admin_audit_logs (page_id, created_at desc);
create index admin_audit_logs_actor_created_idx
  on public.admin_audit_logs (actor_user_id, created_at desc);

create function public.owns_memorial_page(target_page_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.memorial_pages p
    where p.id = target_page_id
      and p.owner_user_id = (select auth.uid())
  );
$$;

create function public.is_published_memorial_page(target_page_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.memorial_pages p
    where p.id = target_page_id
      and p.is_published
  );
$$;

create function public.is_active_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.admin_profiles a
    where a.user_id = (select auth.uid())
      and a.is_active
  );
$$;

create function public.homepage_reference_is_valid(
  target_page_id uuid,
  target_type text,
  target_content_id uuid,
  require_published boolean default true
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if require_published then
    if target_page_id is not null
      and not public.is_published_memorial_page(target_page_id) then
      return false;
    end if;
  elsif target_page_id is null then
    if not public.is_active_platform_admin() then
      return false;
    end if;
  elsif not public.owns_memorial_page(target_page_id) then
    return false;
  end if;

  case target_type
    when 'azkar' then
      return exists (
        select 1 from public.azkar c
        where c.id = target_content_id
          and c.page_id is not distinct from target_page_id
          and (not require_published or c.is_published)
      );
    when 'quran' then
      return exists (
        select 1 from public.quran_verses c
        where c.id = target_content_id
          and c.page_id is not distinct from target_page_id
          and (not require_published or c.is_published)
      );
    when 'hadith' then
      return exists (
        select 1 from public.hadith c
        where c.id = target_content_id
          and c.page_id is not distinct from target_page_id
          and (not require_published or c.is_published)
      );
    when 'dua' then
      return exists (
        select 1 from public.duas c
        where c.id = target_content_id
          and c.page_id is not distinct from target_page_id
          and (not require_published or c.is_published)
      );
    when 'tasbeeh' then
      return exists (
        select 1 from public.tasbeeh_cards c
        where c.id = target_content_id
          and c.page_id is not distinct from target_page_id
          and (not require_published or c.is_published)
      );
    when 'youtube' then
      return exists (
        select 1 from public.youtube_videos c
        where c.id = target_content_id
          and c.page_id is not distinct from target_page_id
          and (not require_published or c.is_published)
      );
    when 'dedication' then
      return exists (
        select 1 from public.dedications c
        where c.id = target_content_id
          and c.page_id is not distinct from target_page_id
          and (not require_published or c.is_published)
      );
    else
      return false;
  end case;
end;
$$;

create function public.create_profile_and_memorial_page()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  raw_slug text;
  requested_slug text;
  page_title text;
  display_name text;
begin
  display_name := nullif(
    pg_catalog.left(
      pg_catalog.btrim(new.raw_user_meta_data ->> 'display_name'),
      160
    ),
    ''
  );
  raw_slug := nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'page_slug'), '');
  page_title := nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'page_title'), '');

  if raw_slug is null then
    requested_slug := 'member-' || pg_catalog.replace(new.id::text, '-', '');
  else
    requested_slug := public.normalize_memorial_slug(raw_slug);
    if not public.is_valid_memorial_slug(requested_slug) then
      raise exception using
        errcode = '22023',
        message = 'Invalid memorial page slug.';
    end if;
  end if;

  if page_title is null then
    page_title := coalesce(
      display_name,
      nullif(pg_catalog.split_part(coalesce(new.email, ''), '@', 1), ''),
      'صفحتي'
    );
  end if;

  if pg_catalog.length(page_title) > 160 then
    raise exception using
      errcode = '22023',
      message = 'Memorial page title must be 160 characters or fewer.';
  end if;

  insert into public.profiles(id, display_name)
  values (new.id, display_name);

  begin
    insert into public.memorial_pages(owner_user_id, slug, title)
    values (new.id, requested_slug, page_title);
  exception
    when unique_violation then
      raise exception using
        errcode = '23505',
        message = 'The requested memorial page slug is unavailable.',
        constraint = 'memorial_pages_slug_key';
  end;

  return new;
end;
$$;

create trigger azkar_provision_owner_page
after insert on auth.users
for each row execute function public.create_profile_and_memorial_page();

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function public.prevent_theme_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.id is distinct from old.id
    or new.page_id is distinct from old.page_id then
    raise exception 'Theme row identity and page scope are immutable';
  end if;
  return new;
end;
$$;

create function public.write_admin_audit_log()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  row_page_id uuid;
  row_id text;
begin
  if tg_table_name = 'memorial_pages' then
    row_id := case when tg_op = 'DELETE' then old.id::text else new.id::text end;
    row_page_id := case when tg_op = 'DELETE' then old.id else new.id end;
  elsif tg_op = 'DELETE' then
    row_page_id := old.page_id;
    row_id := old.id::text;
  else
    row_page_id := new.page_id;
    row_id := new.id::text;
  end if;

  if tg_table_name = 'memorial_pages'
    or row_page_id is not null
    or public.is_active_platform_admin() then
    insert into public.admin_audit_logs(
      page_id, actor_user_id, action, entity_table, entity_id
    )
    values (
      row_page_id,
      (select auth.uid()),
      pg_catalog.lower(tg_op),
      tg_table_name,
      row_id
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();
create trigger memorial_pages_set_updated_at
before update on public.memorial_pages
for each row execute function public.set_updated_at();
create trigger azkar_set_updated_at
before update on public.azkar
for each row execute function public.set_updated_at();
create trigger quran_verses_set_updated_at
before update on public.quran_verses
for each row execute function public.set_updated_at();
create trigger hadith_set_updated_at
before update on public.hadith
for each row execute function public.set_updated_at();
create trigger duas_set_updated_at
before update on public.duas
for each row execute function public.set_updated_at();
create trigger tasbeeh_cards_set_updated_at
before update on public.tasbeeh_cards
for each row execute function public.set_updated_at();
create trigger youtube_videos_set_updated_at
before update on public.youtube_videos
for each row execute function public.set_updated_at();
create trigger dedications_set_updated_at
before update on public.dedications
for each row execute function public.set_updated_at();
create trigger theme_settings_set_updated_at
before update on public.theme_settings
for each row execute function public.set_updated_at();
create trigger theme_settings_prevent_identity_change
before update on public.theme_settings
for each row execute function public.prevent_theme_identity_change();

create trigger memorial_pages_audit
after insert or update or delete on public.memorial_pages
for each row execute function public.write_admin_audit_log();
create trigger azkar_audit
after insert or update or delete on public.azkar
for each row execute function public.write_admin_audit_log();
create trigger quran_verses_audit
after insert or update or delete on public.quran_verses
for each row execute function public.write_admin_audit_log();
create trigger hadith_audit
after insert or update or delete on public.hadith
for each row execute function public.write_admin_audit_log();
create trigger duas_audit
after insert or update or delete on public.duas
for each row execute function public.write_admin_audit_log();
create trigger tasbeeh_cards_audit
after insert or update or delete on public.tasbeeh_cards
for each row execute function public.write_admin_audit_log();
create trigger youtube_videos_audit
after insert or update or delete on public.youtube_videos
for each row execute function public.write_admin_audit_log();
create trigger dedications_audit
after insert or update or delete on public.dedications
for each row execute function public.write_admin_audit_log();
create trigger homepage_cards_audit
after insert or update or delete on public.homepage_cards
for each row execute function public.write_admin_audit_log();
create trigger theme_settings_audit
after insert or update or delete on public.theme_settings
for each row execute function public.write_admin_audit_log();

alter table public.profiles enable row level security;
alter table public.memorial_pages enable row level security;
alter table public.admin_profiles enable row level security;
alter table public.azkar enable row level security;
alter table public.quran_verses enable row level security;
alter table public.hadith enable row level security;
alter table public.duas enable row level security;
alter table public.tasbeeh_cards enable row level security;
alter table public.youtube_videos enable row level security;
alter table public.dedications enable row level security;
alter table public.homepage_cards enable row level security;
alter table public.theme_settings enable row level security;
alter table public.admin_audit_logs enable row level security;

create policy profiles_select_self
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_update_self
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy memorial_pages_select_owner_or_published
  on public.memorial_pages for select to anon, authenticated
  using (
    is_published
    or owner_user_id = (select auth.uid())
  );
create policy memorial_pages_update_owner
  on public.memorial_pages for update to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()));

create policy admin_profiles_select_self
  on public.admin_profiles for select to authenticated
  using (user_id = (select auth.uid()));

create policy azkar_select_tenant_or_published
  on public.azkar for select to anon, authenticated
  using (
    (page_id is null and (is_published or public.is_active_platform_admin()))
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or (
          is_published
          and public.is_published_memorial_page(page_id)
        )
      )
    )
  );
create policy azkar_insert_owner_or_platform_admin
  on public.azkar for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy azkar_update_owner_or_platform_admin
  on public.azkar for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy azkar_delete_owner_or_platform_admin
  on public.azkar for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy quran_verses_select_tenant_or_published
  on public.quran_verses for select to anon, authenticated
  using (
    (page_id is null and (is_published or public.is_active_platform_admin()))
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or (
          is_published
          and public.is_published_memorial_page(page_id)
        )
      )
    )
  );
create policy quran_verses_insert_owner_or_platform_admin
  on public.quran_verses for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy quran_verses_update_owner_or_platform_admin
  on public.quran_verses for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy quran_verses_delete_owner_or_platform_admin
  on public.quran_verses for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy hadith_select_tenant_or_published
  on public.hadith for select to anon, authenticated
  using (
    (page_id is null and (is_published or public.is_active_platform_admin()))
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or (
          is_published
          and public.is_published_memorial_page(page_id)
        )
      )
    )
  );
create policy hadith_insert_owner_or_platform_admin
  on public.hadith for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy hadith_update_owner_or_platform_admin
  on public.hadith for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy hadith_delete_owner_or_platform_admin
  on public.hadith for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy duas_select_tenant_or_published
  on public.duas for select to anon, authenticated
  using (
    (page_id is null and (is_published or public.is_active_platform_admin()))
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or (
          is_published
          and public.is_published_memorial_page(page_id)
        )
      )
    )
  );
create policy duas_insert_owner_or_platform_admin
  on public.duas for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy duas_update_owner_or_platform_admin
  on public.duas for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy duas_delete_owner_or_platform_admin
  on public.duas for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy tasbeeh_cards_select_tenant_or_published
  on public.tasbeeh_cards for select to anon, authenticated
  using (
    (page_id is null and (is_published or public.is_active_platform_admin()))
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or (
          is_published
          and public.is_published_memorial_page(page_id)
        )
      )
    )
  );
create policy tasbeeh_cards_insert_owner_or_platform_admin
  on public.tasbeeh_cards for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy tasbeeh_cards_update_owner_or_platform_admin
  on public.tasbeeh_cards for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy tasbeeh_cards_delete_owner_or_platform_admin
  on public.tasbeeh_cards for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy youtube_videos_select_tenant_or_published
  on public.youtube_videos for select to anon, authenticated
  using (
    (page_id is null and (is_published or public.is_active_platform_admin()))
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or (
          is_published
          and public.is_published_memorial_page(page_id)
        )
      )
    )
  );
create policy youtube_videos_insert_owner_or_platform_admin
  on public.youtube_videos for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy youtube_videos_update_owner_or_platform_admin
  on public.youtube_videos for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy youtube_videos_delete_owner_or_platform_admin
  on public.youtube_videos for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy dedications_select_tenant_or_published
  on public.dedications for select to anon, authenticated
  using (
    (page_id is null and (is_published or public.is_active_platform_admin()))
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or (
          is_published
          and public.is_published_memorial_page(page_id)
        )
      )
    )
  );
create policy dedications_insert_owner_or_platform_admin
  on public.dedications for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy dedications_update_owner_or_platform_admin
  on public.dedications for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy dedications_delete_owner_or_platform_admin
  on public.dedications for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy homepage_cards_select_owner_or_public
  on public.homepage_cards for select to anon, authenticated
  using (
    (
      page_id is null
      and (
        public.is_active_platform_admin()
        or (
          is_enabled
          and public.homepage_reference_is_valid(
            null, content_type, content_id, true
          )
        )
      )
    )
    or (
      page_id is not null
      and public.owns_memorial_page(page_id)
    )
    or (
      page_id is not null
      and is_enabled
      and public.is_published_memorial_page(page_id)
      and public.homepage_reference_is_valid(
        page_id, content_type, content_id, true
      )
    )
  );
create policy homepage_cards_insert_owner_or_platform_admin
  on public.homepage_cards for insert to authenticated
  with check (
    (page_id is null and public.is_active_platform_admin()
      and public.homepage_reference_is_valid(
        null, content_type, content_id, false
      ))
    or (
      page_id is not null
      and public.owns_memorial_page(page_id)
      and public.homepage_reference_is_valid(
        page_id, content_type, content_id, false
      )
    )
  );
create policy homepage_cards_update_owner_or_platform_admin
  on public.homepage_cards for update to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and public.is_active_platform_admin()
      and public.homepage_reference_is_valid(
        null, content_type, content_id, false
      ))
    or (
      page_id is not null
      and public.owns_memorial_page(page_id)
      and public.homepage_reference_is_valid(
        page_id, content_type, content_id, false
      )
    )
  );
create policy homepage_cards_delete_owner_or_platform_admin
  on public.homepage_cards for delete to authenticated
  using (
    (page_id is null and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy theme_settings_select_owner_or_public
  on public.theme_settings for select to anon, authenticated
  using (
    (page_id is null and id = 'global')
    or (
      page_id is not null
      and (
        public.owns_memorial_page(page_id)
        or public.is_published_memorial_page(page_id)
      )
    )
  );
create policy theme_settings_insert_owner_or_platform_admin
  on public.theme_settings for insert to authenticated
  with check (
    (page_id is null and id = 'global'
      and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );
create policy theme_settings_update_owner_or_platform_admin
  on public.theme_settings for update to authenticated
  using (
    (page_id is null and id = 'global'
      and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  )
  with check (
    (page_id is null and id = 'global'
      and public.is_active_platform_admin())
    or (page_id is not null and public.owns_memorial_page(page_id))
  );

create policy admin_audit_logs_select_owner_or_platform_admin
  on public.admin_audit_logs for select to authenticated
  using (
    public.is_active_platform_admin()
    or (
      page_id is not null
      and public.owns_memorial_page(page_id)
    )
  );

revoke all on table
  public.profiles, public.memorial_pages, public.admin_profiles,
  public.azkar, public.quran_verses, public.hadith, public.duas,
  public.tasbeeh_cards, public.youtube_videos, public.dedications,
  public.homepage_cards, public.theme_settings, public.admin_audit_logs
  from public, anon, authenticated, service_role;

grant select on table
  public.memorial_pages, public.azkar, public.quran_verses, public.hadith,
  public.duas, public.tasbeeh_cards, public.youtube_videos, public.dedications,
  public.homepage_cards, public.theme_settings
  to anon;

grant select on table
  public.profiles, public.memorial_pages, public.admin_profiles,
  public.azkar, public.quran_verses, public.hadith, public.duas,
  public.tasbeeh_cards, public.youtube_videos, public.dedications,
  public.homepage_cards, public.theme_settings, public.admin_audit_logs
  to authenticated;

grant update (display_name) on public.profiles to authenticated;
grant update (
  slug, title, deceased_name, dedication_message, description, is_published
) on public.memorial_pages to authenticated;

grant insert (
  page_id, title, arabic_text, description, source, display_order,
  is_published, font_family, font_size, font_weight, line_height, text_color,
  background_color, card_shape, text_alignment, gradient_enabled,
  decoration_enabled, border_enabled
) on public.azkar, public.duas, public.tasbeeh_cards to authenticated;
grant update (
  title, arabic_text, description, source, display_order, is_published,
  font_family, font_size, font_weight, line_height, text_color,
  background_color, card_shape, text_alignment, gradient_enabled,
  decoration_enabled, border_enabled
) on public.azkar, public.duas, public.tasbeeh_cards to authenticated;
grant delete on public.azkar, public.duas, public.tasbeeh_cards to authenticated;

grant insert (
  page_id, title, arabic_text, description, source, translation,
  surah_number, surah_name, ayah_from, ayah_to, validation_hash,
  dataset_version, display_order, is_published, font_family, font_size,
  font_weight, line_height, text_color, background_color, card_shape,
  text_alignment, gradient_enabled, decoration_enabled, border_enabled
) on public.quran_verses to authenticated;
grant update (
  title, arabic_text, description, source, translation, surah_number,
  surah_name, ayah_from, ayah_to, validation_hash, dataset_version,
  display_order, is_published, font_family, font_size, font_weight,
  line_height, text_color, background_color, card_shape, text_alignment,
  gradient_enabled, decoration_enabled, border_enabled
) on public.quran_verses to authenticated;
grant delete on public.quran_verses to authenticated;

grant insert (
  page_id, title, arabic_text, description, source, narrator, hadith_number,
  authenticity, explanation, display_order, is_published, font_family,
  font_size, font_weight, line_height, text_color, background_color,
  card_shape, text_alignment, gradient_enabled, decoration_enabled,
  border_enabled
) on public.hadith to authenticated;
grant update (
  title, arabic_text, description, source, narrator, hadith_number,
  authenticity, explanation, display_order, is_published, font_family,
  font_size, font_weight, line_height, text_color, background_color,
  card_shape, text_alignment, gradient_enabled, decoration_enabled,
  border_enabled
) on public.hadith to authenticated;
grant delete on public.hadith to authenticated;

grant insert (
  page_id, title, arabic_text, dua_text, description, source, person_name,
  message, recipient, display_order, is_published, font_family, font_size,
  font_weight, line_height, text_color, background_color, card_shape,
  text_alignment, gradient_enabled, decoration_enabled, border_enabled
) on public.dedications to authenticated;
grant update (
  title, arabic_text, dua_text, description, source, person_name, message,
  recipient, display_order, is_published, font_family, font_size,
  font_weight, line_height, text_color, background_color, card_shape,
  text_alignment, gradient_enabled, decoration_enabled, border_enabled
) on public.dedications to authenticated;
grant delete on public.dedications to authenticated;

grant insert (
  page_id, title, arabic_text, description, source, video_url, video_id,
  display_order, is_published, font_family, font_size, font_weight,
  line_height, text_color, background_color, card_shape, text_alignment,
  gradient_enabled, decoration_enabled, border_enabled
) on public.youtube_videos to authenticated;
grant update (
  title, arabic_text, description, source, video_url, video_id,
  display_order, is_published, font_family, font_size, font_weight,
  line_height, text_color, background_color, card_shape, text_alignment,
  gradient_enabled, decoration_enabled, border_enabled
) on public.youtube_videos to authenticated;
grant delete on public.youtube_videos to authenticated;

grant insert (page_id, content_type, content_id, display_order, is_enabled)
  on public.homepage_cards to authenticated;
grant update (display_order, is_enabled, content_type, content_id)
  on public.homepage_cards to authenticated;
grant delete on public.homepage_cards to authenticated;

grant insert (
  id, page_id, primary_color, secondary_color, background_color,
  surface_color, default_card_color, default_text_color,
  default_font_family, default_card_shape
) on public.theme_settings to authenticated;
grant update (
  primary_color, secondary_color, background_color, surface_color,
  default_card_color, default_text_color, default_font_family,
  default_card_shape, id, page_id
) on public.theme_settings to authenticated;

grant all on table
  public.profiles, public.memorial_pages, public.admin_profiles,
  public.azkar, public.quran_verses, public.hadith, public.duas,
  public.tasbeeh_cards, public.youtube_videos, public.dedications,
  public.homepage_cards, public.theme_settings, public.admin_audit_logs
  to service_role;
revoke all on sequence public.admin_audit_logs_id_seq
  from public, anon, authenticated, service_role;
grant usage, select on sequence public.admin_audit_logs_id_seq to service_role;

revoke all on function public.normalize_memorial_slug(text)
  from public, anon, authenticated, service_role;
revoke all on function public.is_valid_memorial_slug(text)
  from public, anon, authenticated, service_role;
revoke all on function public.owns_memorial_page(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.is_published_memorial_page(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.is_active_platform_admin()
  from public, anon, authenticated, service_role;
revoke all on function public.homepage_reference_is_valid(uuid, text, uuid, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.create_profile_and_memorial_page()
  from public, anon, authenticated, service_role;
revoke all on function public.set_updated_at()
  from public, anon, authenticated, service_role;
revoke all on function public.prevent_theme_identity_change()
  from public, anon, authenticated, service_role;
revoke all on function public.write_admin_audit_log()
  from public, anon, authenticated, service_role;

grant execute on function public.normalize_memorial_slug(text) to authenticated;
grant execute on function public.is_valid_memorial_slug(text) to authenticated;
grant execute on function public.owns_memorial_page(uuid) to anon, authenticated;
grant execute on function public.is_published_memorial_page(uuid)
  to anon, authenticated;
grant execute on function public.is_active_platform_admin()
  to anon, authenticated;
grant execute on function public.homepage_reference_is_valid(uuid, text, uuid, boolean)
  to anon, authenticated;

do $$
declare
  table_name text;
  expected_tables text[] := array[
    'profiles', 'memorial_pages', 'admin_profiles', 'azkar', 'quran_verses',
    'hadith', 'duas', 'tasbeeh_cards', 'youtube_videos', 'dedications',
    'homepage_cards', 'theme_settings', 'admin_audit_logs'
  ];
begin
  foreach table_name in array expected_tables loop
    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = table_name
        and c.relkind = 'r'
        and c.relrowsecurity
    ) then
      raise exception 'Schema verification failed for public.% or its RLS.', table_name;
    end if;

    if has_table_privilege(
      'anon', pg_catalog.format('public.%I', table_name), 'INSERT'
    ) or has_table_privilege(
      'anon', pg_catalog.format('public.%I', table_name), 'UPDATE'
    ) or has_table_privilege(
      'anon', pg_catalog.format('public.%I', table_name), 'DELETE'
    ) or has_table_privilege(
      'anon', pg_catalog.format('public.%I', table_name), 'TRUNCATE'
    ) or has_table_privilege(
      'anon', pg_catalog.format('public.%I', table_name), 'REFERENCES'
    ) or has_table_privilege(
      'anon', pg_catalog.format('public.%I', table_name), 'TRIGGER'
    ) then
      raise exception 'Schema verification failed: anon can write public.%.', table_name;
    end if;
  end loop;

  if has_table_privilege('anon', 'public.azkar', 'SELECT') is not true
    or has_table_privilege('anon', 'public.memorial_pages', 'SELECT') is not true then
    raise exception 'Schema verification failed: public reads are not granted.';
  end if;

  if has_table_privilege('anon', 'public.profiles', 'SELECT')
    or has_table_privilege('anon', 'public.admin_profiles', 'SELECT')
    or has_table_privilege('anon', 'public.admin_audit_logs', 'SELECT') then
    raise exception 'Schema verification failed: anon can read private tables.';
  end if;

  if has_function_privilege(
    'anon',
    'public.create_profile_and_memorial_page()',
    'EXECUTE'
  ) then
    raise exception 'Schema verification failed: anon can execute the signup trigger function.';
  end if;

  if has_function_privilege(
    'anon',
    'public.normalize_memorial_slug(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.is_valid_memorial_slug(text)',
    'EXECUTE'
  ) then
    raise exception 'Schema verification failed: anon can execute slug helpers.';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and not coalesce(p.proconfig, array[]::text[])
        @> array['search_path=pg_catalog']::text[]
  ) then
    raise exception
      'Schema verification failed: a SECURITY DEFINER function is missing the fixed search_path.';
  end if;
end;
$$;

commit;

-- Post-deployment verification queries (run after the schema transaction):
--
-- 1. Confirm all expected tables have RLS enabled:
-- select c.relname as table_name, c.relrowsecurity as rls_enabled
-- from pg_class c
-- join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relkind = 'r'
-- order by c.relname;
--
-- 2. Inspect policies and exact table grants:
-- select tablename, policyname, roles, cmd, qual, with_check
-- from pg_policies
-- where schemaname = 'public'
-- order by tablename, policyname;
-- select table_name, grantee, privilege_type
-- from information_schema.role_table_grants
-- where table_schema = 'public'
--   and grantee in ('anon', 'authenticated')
-- order by table_name, grantee, privilege_type;
--
-- 3. Verify all SECURITY DEFINER functions have a fixed search_path:
-- select p.oid::regprocedure as function_name, p.proconfig
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.prosecdef
-- order by function_name;
--
-- 4. RLS acceptance scenarios (use two separate test Auth users and the
--    publishable/anon key; never use a service_role key in the client):
--    a. Register Owner A and Owner B with distinct available slugs. Confirm
--       each gets exactly one profiles row and one unpublished page, with
--       distinct owner_user_id/page_id values.
--    b. Attempt a duplicate slug and an invalid/reserved slug. Signup must
--       fail atomically: no Auth user, profile, or page is left behind.
--    c. As Owner A, create a draft and published content row. A's dashboard
--       can read/edit both. Owner B cannot select, update, or delete A's rows;
--       attempts to insert with A's page_id are rejected.
--    d. As Owner A, add a homepage card referencing Owner B's content. The
--       insert/update is rejected. A valid same-page card is accepted.
--    e. With no JWT (anon), neither private page slug nor unpublished page
--       content is visible. Publish Owner A's page: anon can read its page,
--       published content, enabled valid homepage cards, and theme, but not
--       drafts or disabled homepage cards.
--    f. With anon credentials, INSERT/UPDATE/DELETE against every public
--       table must fail with insufficient privilege. Authenticated non-owner
--       writes to another tenant must be denied by RLS.
--    g. An ordinary owner cannot read/write admin_profiles or global content.
--       An active platform admin may manage the global rows but is not given
--       ownership of tenant pages or tenant content.
--    h. Confirm Tasbeeh interactions create no database rows; counts stay
--       local and are isolated by page/card keys in the Flutter client.
