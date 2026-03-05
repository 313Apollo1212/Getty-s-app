-- Run this in Supabase SQL Editor to enable employee task execution tracking.

do $$
begin
  if not exists (
    select 1 from pg_type where typname = 'generated_task_outcome'
  ) then
    create type generated_task_outcome as enum ('done', 'not_done', 'needs_more_time');
  end if;
end
$$;

create table if not exists public.generated_task_actions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  category_title text not null,
  prompt text not null,
  scheduled_weekday integer not null check (scheduled_weekday between 1 and 7),
  original_weekday integer not null check (original_weekday between 1 and 7),
  priority integer not null check (priority between 1 and 5),
  estimated_minutes integer not null check (estimated_minutes > 0),
  outcome generated_task_outcome not null,
  extra_minutes integer check (extra_minutes is null or extra_minutes > 0),
  work_date date not null,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.generated_task_actions enable row level security;

drop policy if exists generated_task_actions_select_admin_or_owner
on public.generated_task_actions;
create policy generated_task_actions_select_admin_or_owner
on public.generated_task_actions
for select
to authenticated
using (public.is_admin() or employee_id = auth.uid());

drop policy if exists generated_task_actions_insert_owner
on public.generated_task_actions;
create policy generated_task_actions_insert_owner
on public.generated_task_actions
for insert
to authenticated
with check (employee_id = auth.uid());

drop policy if exists generated_task_actions_delete_admin
on public.generated_task_actions;
create policy generated_task_actions_delete_admin
on public.generated_task_actions
for delete
to authenticated
using (public.is_admin());
