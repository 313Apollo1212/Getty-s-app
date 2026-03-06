-- Run this in Supabase SQL Editor to enable admin/employee questions chat.

create table if not exists public.employee_questions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  admin_id uuid references public.profiles(id) on delete set null,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  sender_role app_role not null,
  message_text text not null,
  created_at timestamptz not null default now()
);

create index if not exists employee_questions_employee_created_idx
on public.employee_questions (employee_id, created_at);

alter table public.employee_questions enable row level security;

drop policy if exists employee_questions_select_admin_or_owner
on public.employee_questions;
create policy employee_questions_select_admin_or_owner
on public.employee_questions
for select
to authenticated
using (public.is_admin() or employee_id = auth.uid());

drop policy if exists employee_questions_insert_admin
on public.employee_questions;
create policy employee_questions_insert_admin
on public.employee_questions
for insert
to authenticated
with check (
  public.is_admin()
  and sender_role = 'admin'::app_role
  and sender_id = auth.uid()
  and admin_id = auth.uid()
);

drop policy if exists employee_questions_insert_employee
on public.employee_questions;
create policy employee_questions_insert_employee
on public.employee_questions
for insert
to authenticated
with check (
  employee_id = auth.uid()
  and sender_role = 'employee'::app_role
  and sender_id = auth.uid()
);

drop policy if exists employee_questions_delete_admin
on public.employee_questions;
create policy employee_questions_delete_admin
on public.employee_questions
for delete
to authenticated
using (public.is_admin());
