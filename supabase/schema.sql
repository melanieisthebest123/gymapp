-- GymApp database setup.
-- Paste this whole file into Supabase → SQL Editor → New query → Run. Safe to run more than once.

create table if not exists public.exercises (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  primary_muscles text[] not null default '{}',
  secondary_muscles text[] not null default '{}',
  is_custom boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.workout_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz,
  notes text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.exercise_entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  session_id uuid not null references public.workout_sessions on delete cascade,
  exercise_id uuid references public.exercises on delete set null,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.set_entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  entry_id uuid not null references public.exercise_entries on delete cascade,
  position int not null default 0,
  reps int not null default 0,
  weight_kg double precision not null default 0,
  is_warmup boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.body_measurements (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  measured_at timestamptz not null,
  weight_kg double precision,
  body_fat_percent double precision,
  chest_cm double precision,
  waist_cm double precision,
  hips_cm double precision,
  arm_cm double precision,
  thigh_cm double precision,
  calf_cm double precision,
  shoulders_cm double precision,
  created_at timestamptz not null default now()
);

create index if not exists exercises_user_idx on public.exercises (user_id);
create index if not exists workout_sessions_user_idx on public.workout_sessions (user_id);
create index if not exists exercise_entries_user_idx on public.exercise_entries (user_id);
create index if not exists set_entries_user_idx on public.set_entries (user_id);
create index if not exists body_measurements_user_idx on public.body_measurements (user_id);

-- Row level security: every user can only see and change their own rows.
do $$
declare t text;
begin
  foreach t in array array['exercises','workout_sessions','exercise_entries','set_entries','body_measurements'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format('create policy "own rows" on public.%I for all to authenticated
                    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
  end loop;
end $$;

-- Lets a signed-in user permanently delete their own account (required by the App Store).
-- All their data is removed through the "on delete cascade" references above.
create or replace function public.delete_user()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke all on function public.delete_user() from public, anon;
grant execute on function public.delete_user() to authenticated;
