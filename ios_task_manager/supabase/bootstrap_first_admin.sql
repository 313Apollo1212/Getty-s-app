-- One-time bootstrap for the first admin account.
-- Run this in Supabase SQL editor after schema.sql.
--
-- 1) Edit the three values below.
-- 2) Execute this script once.
-- 3) Sign in from Flutter with:
--    username = v_username
--    password = v_password
--
-- Username is mapped to auth email as: <username>@example.com

do $$
declare
  v_username text := lower(trim('admin'));
  v_full_name text := trim('First Admin');
  v_password text := 'admin';

  v_email text;
  v_user_id uuid;
begin
  if v_username = '' then
    raise exception 'Username cannot be empty.';
  end if;

  if v_full_name = '' then
    raise exception 'Full name cannot be empty.';
  end if;

  if length(v_password) < 4 then
    raise exception 'Password must be at least 4 characters.';
  end if;

  if exists (select 1 from public.profiles where role = 'admin') then
    raise exception 'At least one admin already exists. Use admin UI to manage users.';
  end if;

  v_email := v_username || '@example.com';

  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Auth user with email % already exists.', v_email;
  end if;

  v_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(v_password, gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object(
      'username', v_username,
      'full_name', v_full_name,
      'role', 'admin'
    ),
    now(),
    now()
  );

  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    created_at,
    updated_at,
    last_sign_in_at
  )
  values (
    gen_random_uuid(),
    v_user_id,
    v_user_id::text,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email',
    now(),
    now(),
    now()
  );

  insert into public.profiles (id, username, full_name, role)
  values (v_user_id, v_username, v_full_name, 'admin');

  raise notice 'Admin created. Username: %, Email: %', v_username, v_email;
end $$;
