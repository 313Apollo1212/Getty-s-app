# iOS Task Manager (Flutter + Supabase)

Role-based task app:
- Admins can create users (admin/employee), reset passwords, create/edit dynamic tasks, and review submissions.
- Employees can log in, answer assigned tasks, and submit responses.
- Every answer is timestamped and visible to admins.

## Tech
- Flutter (iOS-first, works on Android/web too)
- Supabase Auth + Postgres + Row Level Security
- Supabase Edge Functions for admin-only user creation and password reset

## 1) Supabase setup

1. Create a Supabase project.
2. Run the SQL in [`supabase/schema.sql`](supabase/schema.sql) in the SQL editor.
3. Deploy edge functions:

```bash
supabase functions deploy admin-create-user
supabase functions deploy admin-reset-password
supabase functions deploy update-my-profile
supabase functions deploy admin-delete-user
```

4. Ensure function env vars include:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

5. Create your first admin user by running [`supabase/bootstrap_first_admin.sql`](supabase/bootstrap_first_admin.sql):
- Edit `v_username`, `v_full_name`, and `v_password` at the top of the file.
- Run the script once in Supabase SQL editor.
- Default values are currently username `admin` and password `admin`.
- After login, open `Profile` in the app to change username and password.

Username login format in the app uses a generated auth email:
- username `john` maps to `john@example.com`

## 2) Run Flutter app

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=YOUR_SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

## 3) Current behavior

### Admin
- View all users
- Add user (username, password, full name, role)
- Reset any user password
- Create task with dynamic questions (`text`, `number`, `dropdown`, `time`)
- Set expected answer time per task
- Edit existing tasks
- Review responses and set status:
  - `pending`
  - `submitted`
  - `revision_requested`
  - `approved`

### Employee
- View assigned tasks
- Answer dynamic fields
- Submit/resubmit when revision requested
- See expected time and submitted time

## Notes
- Push notifications are intentionally not included.
- Admin actions for user creation and password reset are server-side via edge functions (service role key is never shipped in app).
