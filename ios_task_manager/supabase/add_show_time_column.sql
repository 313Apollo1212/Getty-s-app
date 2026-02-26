alter table public.task_assignments
add column if not exists show_at timestamptz;

update public.task_assignments
set show_at = expected_at
where show_at is null;

alter table public.task_assignments
alter column show_at set not null;
