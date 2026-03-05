-- Bulk create recurring weekly tasks + check questions with yes-details enabled.
-- Run in Supabase SQL Editor.
--
-- BEFORE RUNNING:
-- 1) Set v_employee_username and v_admin_username below.
-- 2) Set show/expected start date/time below.
-- 3) This script creates up to 500 weekly occurrences ("until stopped" queue).
--
-- Notes:
-- - Questions are stored as dropdown type with check metadata, matching app behavior.
-- - "Alert admin on unwanted answer" is OFF for all questions (no unwanted metadata added).
-- - The second DRYING ROOM section is named "DRYING ROOM CLEANING" to keep categories distinct.
-- - Re-running this script updates expected_at for matching existing rows (same employee + title + show_at).
-- - With v_replace_existing_pending = true, it deletes existing pending generated rows first.

do $$
declare
  v_employee_username text := 'a1';
  v_admin_username text := 'admin';
  v_timezone text := 'America/Los_Angeles';
  v_show_start_date date := date '2026-03-04';
  v_show_local_time time := time '17:00';
  v_expected_start_date date := date '2026-03-05';
  v_expected_local_time time := time '05:00';
  v_weeks_to_generate integer := 500;
  v_replace_existing_pending boolean := true;

  v_employee_id uuid;
  v_admin_id uuid;

  v_deleted_assignments integer := 0;
  v_updated_assignments integer := 0;
  v_inserted_assignments integer := 0;
  v_inserted_questions integer := 0;
begin
  select p.id
  into v_employee_id
  from public.profiles p
  where lower(p.username) = lower(v_employee_username)
    and p.role = 'employee'::app_role
  limit 1;

  if v_employee_id is null then
    raise exception 'Employee username not found (or not employee role): %', v_employee_username;
  end if;

  select p.id
  into v_admin_id
  from public.profiles p
  where lower(p.username) = lower(v_admin_username)
    and p.role = 'admin'::app_role
  limit 1;

  if v_admin_id is null then
    raise exception 'Admin username not found (or not admin role): %', v_admin_username;
  end if;

  create temporary table tmp_category_questions (
    category_key text not null,
    title text not null,
    sort_order integer not null,
    prompt text not null
  ) on commit drop;

  insert into tmp_category_questions (category_key, title, sort_order, prompt)
  values
    -- MOTHERS
    ('mothers', 'MOTHERS', 1, 'Water Moms'),
    ('mothers', 'MOTHERS', 2, 'Soil Moisture'),
    ('mothers', 'MOTHERS', 3, 'Inspect for Bugs: Top of Leaf, Under Leaf'),
    ('mothers', 'MOTHERS', 4, 'Do you need to Prune'),
    ('mothers', 'MOTHERS', 5, 'Do you need to take Clones'),
    ('mothers', 'MOTHERS', 6, 'Are Mothers touching each other or walls (if so rotate/prune)'),
    ('mothers', 'MOTHERS', 7, 'Do mothers need to be fed'),
    ('mothers', 'MOTHERS', 8, 'Remove dead leaves'),
    ('mothers', 'MOTHERS', 9, 'Do you need to Spray Soap and Water'),

    -- CLONES
    ('clones', 'CLONES', 1, 'Take Clones this week'),
    ('clones', 'CLONES', 2, 'Water Clones'),
    ('clones', 'CLONES', 3, 'Burp Clones'),
    ('clones', 'CLONES', 4, 'Check Temperature 78 to 82 F'),
    ('clones', 'CLONES', 5, 'Are clones healthy and growing'),
    ('clones', 'CLONES', 6, 'Do you see roots appearing'),
    ('clones', 'CLONES', 7, 'Transplant Clones to 2 Gals'),
    ('clones', 'CLONES', 8, 'Report dead clones to Zack-Metrc'),
    ('clones', 'CLONES', 9, 'Clean Clones Machines'),

    -- VEG 2 GALS
    ('veg_2_gals', 'VEG 2 GALS', 1, 'Water 2 gallon pots'),
    ('veg_2_gals', 'VEG 2 GALS', 2, 'Remove dead plants-let zack know for metrc'),
    ('veg_2_gals', 'VEG 2 GALS', 3, 'Top plants'),
    ('veg_2_gals', 'VEG 2 GALS', 4, 'Remove Dead Leaves and Space out Plants'),
    ('veg_2_gals', 'VEG 2 GALS', 5, 'Inspect for Bugs: Top of Leaf, underside, spray if needed'),
    ('veg_2_gals', 'VEG 2 GALS', 6, 'Take 2 Gal pots to Flower Room'),
    ('veg_2_gals', 'VEG 2 GALS', 7, 'Take Soil up to Veg Room'),

    -- FLOWER ROOM
    ('flower_room', 'FLOWER ROOM', 1, 'Transplant'),
    ('flower_room', 'FLOWER ROOM', 2, 'Water Plants'),
    ('flower_room', 'FLOWER ROOM', 3, 'Deleaf week 4'),
    ('flower_room', 'FLOWER ROOM', 4, 'Looks for bugs'),
    ('flower_room', 'FLOWER ROOM', 5, 'Check if all fans are running'),
    ('flower_room', 'FLOWER ROOM', 6, 'Check if all lights are working'),
    ('flower_room', 'FLOWER ROOM', 7, 'Check Temp Highs and Lows'),
    ('flower_room', 'FLOWER ROOM', 8, 'Check Humidity Highs and Lows'),
    ('flower_room', 'FLOWER ROOM', 9, 'Deleaf week 8'),
    ('flower_room', 'FLOWER ROOM', 10, 'Harvest Rows'),
    ('flower_room', 'FLOWER ROOM', 11, 'pH test rows'),
    ('flower_room', 'FLOWER ROOM', 12, 'Reamend soils'),
    ('flower_room', 'FLOWER ROOM', 13, 'Soil Test and send off to lab'),

    -- DRYING ROOM
    ('drying_room', 'DRYING ROOM', 1, 'Check Humidity and Temperature'),
    ('drying_room', 'DRYING ROOM', 2, 'Inspect drying buds for mold'),
    ('drying_room', 'DRYING ROOM', 3, 'Bucking'),
    ('drying_room', 'DRYING ROOM', 4, 'Sort out A B C Buds'),
    ('drying_room', 'DRYING ROOM', 5, 'Trim Buds'),
    ('drying_room', 'DRYING ROOM', 6, 'Packaging buds'),

    -- DRYING ROOM (second section in your list)
    ('drying_room_cleaning', 'DRYING ROOM CLEANING', 1, 'vacuum Flower room'),
    ('drying_room_cleaning', 'DRYING ROOM CLEANING', 2, 'Vacuum Veg Room'),
    ('drying_room_cleaning', 'DRYING ROOM CLEANING', 3, 'Vacuum West Entrance'),
    ('drying_room_cleaning', 'DRYING ROOM CLEANING', 4, 'Vacuum Stairs'),
    ('drying_room_cleaning', 'DRYING ROOM CLEANING', 5, 'Organize West Room'),
    ('drying_room_cleaning', 'DRYING ROOM CLEANING', 6, 'Clean Water Troughs'),

    -- OTHER TASK
    ('other_task', 'OTHER TASK', 1, 'Make a list of supplies that you will need in 14 days'),
    ('other_task', 'OTHER TASK', 2, 'Order Metrc Tags for Plants'),
    ('other_task', 'OTHER TASK', 3, 'Water outside plants'),
    ('other_task', 'OTHER TASK', 4, 'Prune outside plants');

  create temporary table tmp_categories as
  select distinct category_key, title
  from tmp_category_questions;

  if v_replace_existing_pending then
    delete from public.task_assignments a
    using tmp_categories c
    where a.employee_id = v_employee_id
      and a.title = c.title
      and a.status = 'pending'::task_status;

    get diagnostics v_deleted_assignments = row_count;
  end if;

  create temporary table tmp_schedule as
  select
    (
      ((v_show_start_date + (week_idx * interval '1 week'))::timestamp + v_show_local_time)
      at time zone v_timezone
    ) as show_at,
    (
      ((v_expected_start_date + (week_idx * interval '1 week'))::timestamp + v_expected_local_time)
      at time zone v_timezone
    ) as expected_at
  from generate_series(0, v_weeks_to_generate - 1) as week_idx;

  create temporary table tmp_target_assignments (
    assignment_id uuid not null,
    category_key text not null
  ) on commit drop;

  with updated as (
    update public.task_assignments a
    set expected_at = s.expected_at
    from tmp_categories c
    cross join tmp_schedule s
    where a.employee_id = v_employee_id
      and a.title = c.title
      and a.show_at = s.show_at
      and a.expected_at is distinct from s.expected_at
    returning a.id
  )
  select count(*) into v_updated_assignments from updated;

  with inserted as (
    insert into public.task_assignments (
      employee_id,
      created_by,
      title,
      instructions,
      show_at,
      expected_at,
      status
    )
    select
      v_employee_id,
      v_admin_id,
      c.title,
      '',
      s.show_at,
      s.expected_at,
      'pending'::task_status
    from tmp_categories c
    cross join tmp_schedule s
    where not exists (
      select 1
      from public.task_assignments a
      where a.employee_id = v_employee_id
        and a.title = c.title
        and a.show_at = s.show_at
    )
    returning id, title, show_at
  )
  select count(*) into v_inserted_assignments from inserted;

  insert into tmp_target_assignments (assignment_id, category_key)
  select
    a.id,
    c.category_key
  from public.task_assignments a
  join tmp_categories c
    on c.title = a.title
  join tmp_schedule s
    on s.show_at = a.show_at
  where a.employee_id = v_employee_id;

  with inserted_questions as (
    insert into public.assignment_questions (
      assignment_id,
      prompt,
      input_type,
      dropdown_options,
      sort_order
    )
    select
      t.assignment_id,
      q.prompt,
      'dropdown',
      jsonb_build_array(
        '__type:check',
        '__meta:check_yes_details:1',
        'Yes',
        'No'
      ),
      q.sort_order
    from tmp_target_assignments t
    join tmp_category_questions q
      on q.category_key = t.category_key
    where not exists (
      select 1
      from public.assignment_questions aq
      where aq.assignment_id = t.assignment_id
        and aq.prompt = q.prompt
    )
    returning id
  )
  select count(*) into v_inserted_questions from inserted_questions;

  raise notice 'Done. Deleted % pending assignments, updated % existing assignments, inserted % assignments, inserted % questions for employee "%".',
    v_deleted_assignments, v_updated_assignments, v_inserted_assignments, v_inserted_questions, v_employee_username;
end
$$;
