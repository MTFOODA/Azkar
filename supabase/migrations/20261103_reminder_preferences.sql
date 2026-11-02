-- User-owned reminder preferences. Apply only after review in a non-production
-- Supabase project; this migration is not executed by the Flutter application.
begin;

create unique index if not exists memorial_pages_owner_id_id_idx
  on public.memorial_pages(owner_user_id, id);

create or replace function public.reminder_json_contains_private_location_keys(
  value jsonb
)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog
as $$
  with recursive nodes(node, key_name) as (
    select value, null::text
    union all
    select child.value, child.key_name
      from nodes parent
      cross join lateral (
        select entry.value, entry.key as key_name
          from pg_catalog.jsonb_each(
            case
              when pg_catalog.jsonb_typeof(parent.node) = 'object'
                then parent.node
              else '{}'::jsonb
            end
          ) entry
        union all
        select item.value, null::text
          from pg_catalog.jsonb_array_elements(
            case
              when pg_catalog.jsonb_typeof(parent.node) = 'array'
                then parent.node
              else '[]'::jsonb
            end
          ) item
      ) child
  )
  select exists (
    select 1
      from nodes
     where pg_catalog.lower(pg_catalog.btrim(key_name)) = any (
       array[
         'latitude',
         'longitude',
         'lat',
         'lng',
         'coordinates',
         'gps',
         'location'
       ]
     )
  );
$$;

create table if not exists public.user_reminder_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0),
  manual_city text,
  manual_country text,
  manual_country_code text,
  timezone_id text,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint user_reminder_preferences_city_country_check
    check (
      (manual_city is null and manual_country is null)
      or (
        manual_city is not null
        and manual_country is not null
        and pg_catalog.length(pg_catalog.btrim(manual_city)) between 1 and 160
        and pg_catalog.length(pg_catalog.btrim(manual_country)) between 1 and 160
      )
    ),
  constraint user_reminder_preferences_country_code_check
    check (
      manual_country_code is null
      or manual_country_code ~ '^[A-Z]{2}$'
    ),
  constraint user_reminder_preferences_country_code_location_check
    check (manual_city is not null or manual_country_code is null),
  constraint user_reminder_preferences_timezone_check
    check (
      timezone_id is null
      or (
        manual_city is not null
        and pg_catalog.length(timezone_id) between 1 and 100
      )
    ),
  constraint user_reminder_preferences_settings_object_check
    check (pg_catalog.jsonb_typeof(settings) = 'object'),
  constraint user_reminder_preferences_no_gps_settings_check
    check (
      not public.reminder_json_contains_private_location_keys(settings)
    )
);

create table if not exists public.user_reminder_configurations (
  user_id uuid not null
    references public.user_reminder_preferences(user_id) on delete cascade,
  id text not null,
  kind text not null,
  enabled boolean not null default false,
  memorial_page_id uuid,
  parameters jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint user_reminder_configurations_id_check
    check (pg_catalog.length(pg_catalog.btrim(id)) between 1 and 100),
  constraint user_reminder_configurations_kind_check
    check (pg_catalog.length(pg_catalog.btrim(kind)) between 1 and 80),
  constraint user_reminder_configurations_parameters_object_check
    check (pg_catalog.jsonb_typeof(parameters) = 'object'),
  constraint user_reminder_configurations_no_gps_check
    check (
      not public.reminder_json_contains_private_location_keys(parameters)
    ),
  constraint user_reminder_configurations_memorial_owner_fkey
    foreign key (user_id, memorial_page_id)
    references public.memorial_pages(owner_user_id, id)
    on delete cascade
);

alter table public.user_reminder_preferences enable row level security;
alter table public.user_reminder_configurations enable row level security;

drop policy if exists user_reminder_preferences_select_self
  on public.user_reminder_preferences;
create policy user_reminder_preferences_select_self
  on public.user_reminder_preferences
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_reminder_configurations_select_self
  on public.user_reminder_configurations;
create policy user_reminder_configurations_select_self
  on public.user_reminder_configurations
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.user_reminder_preferences
  from public, anon, authenticated;
revoke all on table public.user_reminder_configurations
  from public, anon, authenticated;
grant select on table public.user_reminder_preferences to authenticated;
grant select on table public.user_reminder_configurations to authenticated;

create or replace function public.save_user_reminder_preferences(
  p_user_id uuid,
  p_expected_revision bigint,
  p_manual_city text,
  p_manual_country text,
  p_manual_country_code text,
  p_timezone_id text,
  p_settings jsonb,
  p_configurations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  owner_id uuid := (select auth.uid());
  current_row public.user_reminder_preferences%rowtype;
  configuration jsonb;
  memorial_page_id uuid;
begin
  if owner_id is null or p_user_id is distinct from owner_id then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to save reminder preferences.';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception using
      errcode = '22023',
      message = 'Invalid reminder preferences revision.';
  end if;
  if p_settings is null or pg_catalog.jsonb_typeof(p_settings) <> 'object'
    or p_configurations is null
    or pg_catalog.jsonb_typeof(p_configurations) <> 'array' then
    raise exception using
      errcode = '22023',
      message = 'Reminder settings must be an object and configurations an array.';
  end if;
  if pg_catalog.jsonb_array_length(p_configurations) > 100 then
    raise exception using
      errcode = '22023',
      message = 'At most 100 reminder configurations are allowed.';
  end if;
  if public.reminder_json_contains_private_location_keys(p_settings) then
    raise exception using
      errcode = '22023',
      message = 'GPS coordinates cannot be synchronized.';
  end if;
  if (p_manual_city is null) <> (p_manual_country is null)
    or (p_manual_city is not null
      and pg_catalog.length(pg_catalog.btrim(p_manual_city)) not between 1 and 160)
    or (p_manual_country is not null
      and pg_catalog.length(pg_catalog.btrim(p_manual_country)) not between 1 and 160)
    or (p_manual_country_code is not null
      and (
        p_manual_city is null
        or p_manual_country_code !~ '^[A-Z]{2}$'
      ))
    or (p_timezone_id is not null and (
      p_manual_city is null
      or (
        p_timezone_id !~ '^[A-Za-z_+-]+(/[A-Za-z0-9_+-]+)+$'
        and p_timezone_id <> 'UTC'
      )
      or not exists (
        select 1
          from pg_catalog.pg_timezone_names timezone
         where timezone.name = p_timezone_id
      )
    )) then
    raise exception using
      errcode = '22023',
      message = 'Invalid manually selected prayer location.';
  end if;
  if p_settings ? 'calculation_method'
    and p_settings -> 'calculation_method' <> 'null'::jsonb
    and (pg_catalog.jsonb_typeof(p_settings -> 'calculation_method') <> 'number'
      or (p_settings ->> 'calculation_method') !~ '^[0-9]+$'
      or (p_settings ->> 'calculation_method')::integer not in
        (0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23)) then
    raise exception using
      errcode = '22023',
      message = 'Unsupported prayer calculation method.';
  end if;
  if p_settings ? 'asr_method'
    and (pg_catalog.jsonb_typeof(p_settings -> 'asr_method') <> 'number'
      or (p_settings ->> 'asr_method') !~ '^[0-9]+$'
      or (p_settings ->> 'asr_method')::integer not in (0, 1)) then
    raise exception using
      errcode = '22023',
      message = 'Unsupported Asr calculation method.';
  end if;
  if exists (
    select 1
      from pg_catalog.jsonb_object_keys(p_settings) as keys(setting_key)
     where keys.setting_key not in (
       'calculation_method',
       'asr_method',
       'prayer_reminders_enabled',
       'prayer_time_notifications_enabled',
       'post_prayer_tasbeeh_enabled',
       'post_prayer_delay_minutes',
       'morning_azkar_enabled',
       'morning_azkar_time',
       'evening_azkar_enabled',
       'evening_azkar_time',
       'friday_kahf_enabled',
       'friday_kahf_time',
       'quiet_hours_start',
       'quiet_hours_end',
       'hide_notification_content'
     )
  ) then
    raise exception using
      errcode = '22023',
      message = 'Unsupported reminder setting.';
  end if;

  if exists (
    select 1
      from (values
        ('prayer_reminders_enabled'),
        ('prayer_time_notifications_enabled'),
        ('post_prayer_tasbeeh_enabled'),
        ('morning_azkar_enabled'),
        ('evening_azkar_enabled'),
        ('friday_kahf_enabled'),
        ('hide_notification_content')
      ) as boolean_setting(setting_key)
     where p_settings ? setting_key
       and pg_catalog.jsonb_typeof(p_settings -> setting_key) <> 'boolean'
  ) then
    raise exception using
      errcode = '22023',
      message = 'Reminder toggle settings must be boolean.';
  end if;
  if p_settings ? 'post_prayer_delay_minutes'
    and (pg_catalog.jsonb_typeof(p_settings -> 'post_prayer_delay_minutes') <> 'number'
      or (p_settings ->> 'post_prayer_delay_minutes') !~ '^(0|[1-9][0-9]*)$'
      or (p_settings ->> 'post_prayer_delay_minutes')::integer not between 0 and 1440) then
    raise exception using
      errcode = '22023',
      message = 'Post-prayer delay must be between zero and 1440 minutes.';
  end if;
  if exists (
    select 1
      from (values
        ('morning_azkar_time'),
        ('evening_azkar_time'),
        ('friday_kahf_time'),
        ('quiet_hours_start'),
        ('quiet_hours_end')
      ) as time_setting(setting_key)
     where p_settings ? setting_key
       and p_settings -> setting_key <> 'null'::jsonb
       and (pg_catalog.jsonb_typeof(p_settings -> setting_key) <> 'string'
         or (p_settings ->> setting_key) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
  ) then
    raise exception using
      errcode = '22023',
      message = 'Reminder times must use the HH:MM 24-hour format.';
  end if;
  if exists (
    select 1
      from (values
        ('morning_azkar_time'),
        ('evening_azkar_time'),
        ('friday_kahf_time')
      ) as required_time_setting(setting_key)
     where p_settings ? setting_key
       and p_settings -> setting_key = 'null'::jsonb
  ) then
    raise exception using
      errcode = '22023',
      message = 'Enabled reminder time settings cannot be null.';
  end if;
  if (p_settings ? 'quiet_hours_start')
     <> (p_settings ? 'quiet_hours_end') then
    raise exception using
      errcode = '22023',
      message = 'Both quiet-hours times must be configured together.';
  end if;
  if coalesce(
       p_settings -> 'quiet_hours_start' = 'null'::jsonb,
       false
     ) <> coalesce(
       p_settings -> 'quiet_hours_end' = 'null'::jsonb,
       false
     ) then
    raise exception using
      errcode = '22023',
      message = 'Both quiet-hours times must be configured together.';
  end if;

  for configuration in
    select value from pg_catalog.jsonb_array_elements(p_configurations)
  loop
    if pg_catalog.jsonb_typeof(configuration) <> 'object'
      or pg_catalog.jsonb_typeof(configuration -> 'id') <> 'string'
      or pg_catalog.length(pg_catalog.btrim(configuration ->> 'id')) = 0
      or pg_catalog.jsonb_typeof(configuration -> 'kind') <> 'string'
      or pg_catalog.length(pg_catalog.btrim(configuration ->> 'kind')) = 0
      or pg_catalog.jsonb_typeof(configuration -> 'enabled') <> 'boolean'
      or (configuration ? 'parameters'
        and pg_catalog.jsonb_typeof(configuration -> 'parameters') <> 'object')
      or (configuration -> 'parameters' is not null
        and public.reminder_json_contains_private_location_keys(
          configuration -> 'parameters'
        )) then
      raise exception using
        errcode = '22023',
        message = 'Invalid reminder configuration.';
    end if;
    if configuration ? 'memorial_page_id'
      and configuration -> 'memorial_page_id' <> 'null'::jsonb then
      begin
        memorial_page_id := (configuration ->> 'memorial_page_id')::uuid;
      exception when invalid_text_representation then
        raise exception using
          errcode = '22023',
          message = 'Invalid memorial page reference in reminder configuration.';
      end;
      if not exists (
        select 1 from public.memorial_pages page
         where page.id = memorial_page_id
           and page.owner_user_id = owner_id
      ) then
        raise exception using
          errcode = '42501',
          message = 'A referenced memorial page is not owned by this account.';
      end if;
    end if;
  end loop;

  if exists (
    select config_item.json_value ->> 'id'
      from pg_catalog.jsonb_array_elements(p_configurations)
        as config_item(json_value)
     group by config_item.json_value ->> 'id'
    having pg_catalog.count(*) > 1
  ) then
    raise exception using
      errcode = '22023',
      message = 'Reminder configuration IDs must be unique.';
  end if;

  -- Insert a revision-zero row before locking so first writes also use an
  -- atomic compare-and-save path when two devices synchronize concurrently.
  insert into public.user_reminder_preferences(user_id)
  values (owner_id)
  on conflict (user_id) do nothing;

  select *
    into current_row
    from public.user_reminder_preferences
   where user_id = owner_id
   for update;

  if current_row.revision <> p_expected_revision then
    return pg_catalog.jsonb_build_object(
      'status', 'conflict',
      'current', pg_catalog.to_jsonb(current_row) || pg_catalog.jsonb_build_object(
        'configurations',
        coalesce((
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'id', saved_configuration.id,
              'kind', saved_configuration.kind,
              'enabled', saved_configuration.enabled,
              'memorial_page_id', saved_configuration.memorial_page_id,
              'parameters', saved_configuration.parameters
            ) order by saved_configuration.id
          )
          from public.user_reminder_configurations saved_configuration
          where saved_configuration.user_id = owner_id
        ), '[]'::jsonb)
      )
    );
  end if;

  update public.user_reminder_preferences
     set manual_city = nullif(pg_catalog.btrim(p_manual_city), ''),
         manual_country = nullif(pg_catalog.btrim(p_manual_country), ''),
         manual_country_code = p_manual_country_code,
         timezone_id = p_timezone_id,
         settings = p_settings,
         revision = current_row.revision + 1,
         updated_at = pg_catalog.now()
   where user_id = owner_id
   returning * into current_row;

  delete from public.user_reminder_configurations
   where user_id = owner_id;

  for configuration in
    select value from pg_catalog.jsonb_array_elements(p_configurations)
  loop
    memorial_page_id := null;
    if configuration -> 'memorial_page_id' is not null
      and configuration -> 'memorial_page_id' <> 'null'::jsonb then
      memorial_page_id := (configuration ->> 'memorial_page_id')::uuid;
    end if;
    insert into public.user_reminder_configurations(
      user_id, id, kind, enabled, memorial_page_id, parameters
    )
    values (
      owner_id,
      configuration ->> 'id',
      configuration ->> 'kind',
      (configuration ->> 'enabled')::boolean,
      memorial_page_id,
      coalesce(configuration -> 'parameters', '{}'::jsonb)
    );
  end loop;

  return pg_catalog.jsonb_build_object(
    'status', 'saved',
    'record', pg_catalog.to_jsonb(current_row) || pg_catalog.jsonb_build_object(
      'configurations',
      coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', saved_configuration.id,
            'kind', saved_configuration.kind,
            'enabled', saved_configuration.enabled,
            'memorial_page_id', saved_configuration.memorial_page_id,
            'parameters', saved_configuration.parameters
          ) order by saved_configuration.id
        )
        from public.user_reminder_configurations saved_configuration
        where saved_configuration.user_id = owner_id
      ), '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.save_user_reminder_preferences(
  uuid, bigint, text, text, text, text, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.save_user_reminder_preferences(
  uuid, bigint, text, text, text, text, jsonb, jsonb
) to authenticated;

revoke all on function public.reminder_json_contains_private_location_keys(
  jsonb
) from public, anon, authenticated;

commit;
