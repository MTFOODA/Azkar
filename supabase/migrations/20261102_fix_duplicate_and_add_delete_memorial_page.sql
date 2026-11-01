-- Fixes duplicate_memorial_page and adds delete_memorial_page.
-- Idempotent and incremental; apply after 20261101_multi_memorial_management.sql.
--
-- Root cause of the duplication failure: the PL/pgSQL variable `content_type`
-- collided with the unqualified `content_type` column read from homepage_cards
-- (SQLSTATE 42702, "column reference is ambiguous"). The whole transaction was
-- rolled back, and the client only saw a generic database error. In addition,
-- jsonb_set() does not create missing intermediate keys, so the old-to-new
-- content id map was never populated.
begin;

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
  v_owner_id uuid := (select auth.uid());
  v_source public.memorial_pages%rowtype;
  v_new public.memorial_pages%rowtype;
  v_rows jsonb;
  v_row jsonb;
  v_map jsonb := '{}'::jsonb;
  v_table text;
  v_type text;
  v_old_id text;
  v_new_id uuid;
  v_home record;
  v_mapped text;
  v_now timestamptz := pg_catalog.now();
begin
  if v_owner_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to duplicate a memorial page.';
  end if;

  select *
    into v_source
    from public.memorial_pages as mp
   where mp.id = p_source_page_id
     and mp.owner_user_id = v_owner_id;

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
    v_source.owner_user_id,
    p_slug,
    pg_catalog.btrim(p_deceased_name),
    p_deceased_gender,
    pg_catalog.btrim(p_deceased_name),
    nullif(pg_catalog.btrim(p_dedication_message), ''),
    v_source.description,
    false
  )
  returning * into v_new;

  for v_table, v_type in
    select m.tbl, m.ctype
      from (values
        ('azkar', 'azkar'),
        ('quran_verses', 'quran'),
        ('hadith', 'hadith'),
        ('duas', 'dua'),
        ('tasbeeh_cards', 'tasbeeh'),
        ('youtube_videos', 'youtube'),
        ('dedications', 'dedication')
      ) as m(tbl, ctype)
  loop
    execute pg_catalog.format(
      'select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(row_data)), ''[]''::jsonb)
         from public.%I as row_data
        where page_id = $1',
      v_table
    )
    into v_rows
    using v_source.id;

    for v_row in
      select e.value from pg_catalog.jsonb_array_elements(v_rows) as e
    loop
      v_old_id := v_row ->> 'id';
      v_new_id := gen_random_uuid();

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
        v_table
      )
      using v_row, v_new_id, v_new.id, v_now;

      v_map := pg_catalog.jsonb_set(
        v_map,
        array[v_type],
        coalesce(v_map -> v_type, '{}'::jsonb)
          || pg_catalog.jsonb_build_object(v_old_id, v_new_id::text),
        true
      );
    end loop;
  end loop;

  for v_home in
    select hc.content_type as ctype,
           hc.content_id as cid,
           hc.display_order as ord,
           hc.is_enabled as enabled
      from public.homepage_cards as hc
     where hc.page_id = v_source.id
     order by hc.display_order, hc.id
  loop
    v_mapped := v_map #>> array[v_home.ctype, v_home.cid::text];
    if v_mapped is not null then
      insert into public.homepage_cards(
        page_id,
        content_type,
        content_id,
        display_order,
        is_enabled
      )
      values (
        v_new.id,
        v_home.ctype,
        v_mapped::uuid,
        v_home.ord,
        v_home.enabled
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
    v_new.id,
    ts.primary_color,
    ts.secondary_color,
    ts.background_color,
    ts.surface_color,
    ts.default_card_color,
    ts.default_text_color,
    ts.default_font_family,
    ts.default_card_shape
  from public.theme_settings as ts
  where ts.page_id = v_source.id;

  return pg_catalog.to_jsonb(v_new);
end;
$$;

-- Deletes one memorial page owned by the caller. Dependent rows (content,
-- homepage_cards, theme_settings) are removed by their existing
-- ON DELETE CASCADE foreign keys inside the same transaction.
create or replace function public.delete_memorial_page(p_page_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_owner_id uuid := (select auth.uid());
begin
  if v_owner_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to delete a memorial page.';
  end if;

  delete from public.memorial_pages as mp
   where mp.id = p_page_id
     and mp.owner_user_id = v_owner_id;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'The selected memorial page is not owned by this account.';
  end if;
end;
$$;

revoke all on function public.duplicate_memorial_page(
  uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.duplicate_memorial_page(
  uuid, text, text, text, text
) to authenticated;
revoke all on function public.delete_memorial_page(uuid)
  from public, anon, authenticated;
grant execute on function public.delete_memorial_page(uuid) to authenticated;

commit;
