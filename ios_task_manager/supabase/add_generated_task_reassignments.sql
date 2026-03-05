-- Run this in Supabase SQL Editor to enable "Add Priority 5 tasks" reshuffling.

create table if not exists public.generated_task_reassignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  category_title text not null,
  prompt text not null,
  original_weekday integer not null check (original_weekday between 1 and 7),
  from_scheduled_weekday integer not null check (from_scheduled_weekday between 1 and 7),
  target_weekday integer not null check (target_weekday between 1 and 7),
  priority integer not null check (priority between 1 and 5),
  estimated_minutes integer not null check (estimated_minutes > 0),
  week_start_date date not null,
  created_at timestamptz not null default now(),
  unique (
    employee_id,
    week_start_date,
    category_title,
    prompt,
    original_weekday,
    from_scheduled_weekday,
    target_weekday,
    priority,
    estimated_minutes
  )
);

create index if not exists generated_task_reassignments_employee_week_idx
on public.generated_task_reassignments (employee_id, week_start_date);

alter table public.generated_task_reassignments enable row level security;

drop policy if exists generated_task_reassignments_select_admin_or_owner
on public.generated_task_reassignments;
create policy generated_task_reassignments_select_admin_or_owner
on public.generated_task_reassignments
for select
to authenticated
using (public.is_admin() or employee_id = auth.uid());

drop policy if exists generated_task_reassignments_insert_owner
on public.generated_task_reassignments;
create policy generated_task_reassignments_insert_owner
on public.generated_task_reassignments
for insert
to authenticated
with check (employee_id = auth.uid());

drop policy if exists generated_task_reassignments_delete_admin
on public.generated_task_reassignments;
create policy generated_task_reassignments_delete_admin
on public.generated_task_reassignments
for delete
to authenticated
using (public.is_admin());
