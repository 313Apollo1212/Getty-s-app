create extension if not exists pgcrypto;

create type app_role as enum ('admin', 'employee');
create type task_status as enum ('pending', 'submitted', 'revision_requested', 'approved');
create type question_input_type as enum ('text', 'number', 'dropdown', 'time');
create type generated_task_outcome as enum ('done', 'not_done', 'needs_more_time');

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  full_name text not null,
  role app_role not null default 'employee',
  created_at timestamptz not null default now()
);

create table if not exists public.task_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete restrict,
  title text not null,
  instructions text not null default '',
  show_at timestamptz not null,
  expected_at timestamptz not null,
  status task_status not null default 'pending',
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.assignment_questions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.task_assignments(id) on delete cascade,
  prompt text not null,
  input_type question_input_type not null,
  dropdown_options jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.question_answers (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.task_assignments(id) on delete cascade,
  question_id uuid not null references public.assignment_questions(id) on delete cascade,
  employee_id uuid not null references public.profiles(id) on delete cascade,
  answer_text text not null,
  answered_at timestamptz not null default now(),
  unique (assignment_id, question_id, employee_id)
);

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

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists task_assignments_set_updated_at on public.task_assignments;
create trigger task_assignments_set_updated_at
before update on public.task_assignments
for each row execute function public.set_updated_at();

create or replace function public.current_role()
returns app_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role = 'admin'::app_role from public.profiles where id = auth.uid()), false);
$$;

alter table public.profiles enable row level security;
alter table public.task_assignments enable row level security;
alter table public.assignment_questions enable row level security;
alter table public.question_answers enable row level security;
alter table public.generated_task_actions enable row level security;
alter table public.generated_task_reassignments enable row level security;

alter table public.task_assignments
add column if not exists show_at timestamptz;

update public.task_assignments
set show_at = expected_at
where show_at is null;

alter table public.task_assignments
alter column show_at set not null;

-- Profiles
create policy if not exists profiles_select_authenticated
on public.profiles
for select
to authenticated
using (true);

create policy if not exists profiles_update_admin
on public.profiles
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Task assignments
create policy if not exists tasks_select_admin_or_assignee
on public.task_assignments
for select
to authenticated
using (public.is_admin() or employee_id = auth.uid());

create policy if not exists tasks_insert_admin
on public.task_assignments
for insert
to authenticated
with check (public.is_admin());

create policy if not exists tasks_update_admin
on public.task_assignments
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy if not exists tasks_update_assignee
on public.task_assignments
for update
to authenticated
using (employee_id = auth.uid())
with check (employee_id = auth.uid());

create policy if not exists tasks_delete_admin
on public.task_assignments
for delete
to authenticated
using (public.is_admin());

-- Assignment questions
create policy if not exists questions_select_admin_or_assignee
on public.assignment_questions
for select
to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.task_assignments a
    where a.id = assignment_id and a.employee_id = auth.uid()
  )
);

create policy if not exists questions_manage_admin
on public.assignment_questions
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Question answers
create policy if not exists answers_select_admin_or_owner
on public.question_answers
for select
to authenticated
using (public.is_admin() or employee_id = auth.uid());

create policy if not exists answers_insert_owner
on public.question_answers
for insert
to authenticated
with check (employee_id = auth.uid());

create policy if not exists answers_update_owner
on public.question_answers
for update
to authenticated
using (employee_id = auth.uid())
with check (employee_id = auth.uid());

create policy if not exists answers_delete_admin
on public.question_answers
for delete
to authenticated
using (public.is_admin());

-- Generated task actions
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

-- Generated task reassignments
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
