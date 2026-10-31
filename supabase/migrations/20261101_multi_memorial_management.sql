-- Enable multiple independent memorial pages per existing account.
-- This is an incremental migration; do not run the initial-schema script again.
begin;

alter table public.memorial_pages
  drop constraint if exists memorial_pages_owner_user_id_key;

alter table public.memorial_pages
  add column if not exists deceased_gender text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.memorial_pages'::regclass
      and conname = 'memorial_pages_deceased_gender_check'
  ) then
    alter table public.memorial_pages
      add constraint memorial_pages_deceased_gender_check
      check (deceased_gender is null or deceased_gender in ('male', 'female'));
  end if;
end;
$$;

grant update (deceased_gender) on public.memorial_pages to authenticated;

create or replace function public.create_memorial_page(
  p_slug text,
  p_deceased_name text,
  p_deceased_gender text,
  p_dedication_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created_page public.memorial_pages%rowtype;
  owner_id uuid := (select auth.uid());
begin
  if owner_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to create a memorial page.';
  end if;
  if not public.is_valid_memorial_slug(p_slug) then
    raise exception using
      errcode = '22023',
      message = 'Invalid memorial page slug.';
  end if;
  if p_deceased_name is null
    or pg_catalog.length(pg_catalog.btrim(p_deceased_name)) not between 1 and 160 then
    raise exception using
      errcode = '22023',
      message = 'The deceased name must be between 1 and 160 characters.';
  end if;
  if p_deceased_gender is null
    or p_deceased_gender not in ('male', 'female') then
    raise exception using
      errcode = '22023',
      message = 'The deceased gender must be male or female.';
  end if;
  if p_dedication_message is not null
    and pg_catalog.length(p_dedication_message) > 4000 then
    raise exception using
      errcode = '22023',
      message = 'The dedication message must be 4000 characters or fewer.';
  end if;

  insert into public.memorial_pages(
    owner_user_id,
    slug,
    title,
    deceased_gender,
    deceased_name,
    dedication_message,
    is_published
  )
  values (
    owner_id,
    p_slug,
    pg_catalog.btrim(p_deceased_name),
    p_deceased_gender,
    pg_catalog.btrim(p_deceased_name),
    nullif(pg_catalog.btrim(p_dedication_message), ''),
    false
  )
  returning * into created_page;

  return pg_catalog.to_jsonb(created_page);
end;
$$;

create or replace function public.duplicate_memorial_page(
  p_source_page_id uuid,
  p_slug text,
  p_deceased_name text,
  p_deceased_gender text,
  p_dedication_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  source_page public.memorial_pages%rowtype;
  new_page public.memorial_pages%rowtype;
  content_rows jsonb;
  content_row jsonb;
  content_map jsonb := '{}'::jsonb;
  table_name text;
  content_type text;
  old_content_id text;
  new_content_id uuid;
  homepage_row record;
  mapped_content_id text;
  created_at_value timestamptz := pg_catalog.now();
begin
  if (select auth.uid()) is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to duplicate a memorial page.';
  end if;

  select *
    into source_page
    from public.memorial_pages
   where id = p_source_page_id
     and owner_user_id = (select auth.uid());

  if not found then
    raise exception using
      errcode = '42501',
      message = 'The selected memorial page is not owned by this account.';
  end if;

  if not public.is_valid_memorial_slug(p_slug) then
    raise exception using
      errcode = '22023',
      message = 'Invalid memorial page slug.';
  end if;
  if p_deceased_name is null
    or pg_catalog.length(pg_catalog.btrim(p_deceased_name)) not between 1 and 160 then
    raise exception using
      errcode = '22023',
      message = 'The deceased name must be between 1 and 160 characters.';
  end if;
  if p_deceased_gender is null
    or p_deceased_gender not in ('male', 'female') then
    raise exception using
      errcode = '22023',
      message = 'The deceased gender must be male or female.';
  end if;
  if p_dedication_message is not null
    and pg_catalog.length(p_dedication_message) > 4000 then
    raise exception using
      errcode = '22023',
      message = 'The dedication message must be 4000 characters or fewer.';
  end if;

  insert into public.memorial_pages(
    owner_user_id,
    slug,
    title,
    deceased_gender,
    deceased_name,
    dedication_message,
    description,
    is_published
  )
  values (
    source_page.owner_user_id,
    p_slug,
    pg_catalog.btrim(p_deceased_name),
    p_deceased_gender,
    pg_catalog.btrim(p_deceased_name),
    nullif(pg_catalog.btrim(p_dedication_message), ''),
    source_page.description,
    false
  )
  returning * into new_page;

  for table_name, content_type in
    select mapping.table_name, mapping.content_type
      from (values
        ('azkar', 'azkar'),
        ('quran_verses', 'quran'),
        ('hadith', 'hadith'),
        ('duas', 'dua'),
        ('tasbeeh_cards', 'tasbeeh'),
        ('youtube_videos', 'youtube'),
        ('dedications', 'dedication')
      ) as mapping(table_name, content_type)
  loop
    execute pg_catalog.format(
      'select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(row_data)), ''[]''::jsonb)
         from public.%I as row_data
        where page_id = $1',
      table_name
    )
    into content_rows
    using source_page.id;

    for content_row in
      select value from pg_catalog.jsonb_array_elements(content_rows)
    loop
      old_content_id := content_row ->> 'id';
      new_content_id := gen_random_uuid();

      execute pg_catalog.format(
        'insert into public.%1$I
         select (pg_catalog.jsonb_populate_record(
           null::public.%1$I,
           $1 || pg_catalog.jsonb_build_object(
             ''id'', $2,
             ''page_id'', $3,
             ''created_at'', $4,
             ''updated_at'', $4
           )
         )).*',
        table_name
      )
      using content_row, new_content_id, new_page.id, created_at_value;

      content_map := pg_catalog.jsonb_set(
        content_map,
        array[content_type, old_content_id],
        pg_catalog.to_jsonb(new_content_id::text),
        true
      );
    end loop;
  end loop;

  for homepage_row in
    select content_type, content_id, display_order, is_enabled
      from public.homepage_cards
     where page_id = source_page.id
     order by display_order, id
  loop
    mapped_content_id := content_map #>> array[
      homepage_row.content_type,
      homepage_row.content_id::text
    ];
    if mapped_content_id is not null then
      insert into public.homepage_cards(
        page_id,
        content_type,
        content_id,
        display_order,
        is_enabled
      )
      values (
        new_page.id,
        homepage_row.content_type,
        mapped_content_id::uuid,
        homepage_row.display_order,
        homepage_row.is_enabled
      );
    end if;
  end loop;

  insert into public.theme_settings(
    page_id,
    primary_color,
    secondary_color,
    background_color,
    surface_color,
    default_card_color,
    default_text_color,
    default_font_family,
    default_card_shape
  )
  select
    new_page.id,
    primary_color,
    secondary_color,
    background_color,
    surface_color,
    default_card_color,
    default_text_color,
    default_font_family,
    default_card_shape
  from public.theme_settings
  where page_id = source_page.id;

  return pg_catalog.to_jsonb(new_page);
end;
$$;

revoke all on function public.duplicate_memorial_page(
  uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.duplicate_memorial_page(
  uuid, text, text, text, text
) to authenticated;
revoke all on function public.create_memorial_page(
  text, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_memorial_page(
  text, text, text, text
) to authenticated;

commit;
