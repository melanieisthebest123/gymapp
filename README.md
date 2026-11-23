# gymapp

iPhone app for tracking weightlifting, with a 3D body model and an Apple Health dashboard.

## Features
- **Workouts:** log exercises, sets, reps and weight. Shows what you did last time and pre-fills it.
- **Exercise history:** every past set for each exercise, plus your bests and estimated 1-rep max.
- **3D body:** a muscle map colored by recent training volume, and a body-shape model driven by your measurements.
- **Progress:** strength charts, weekly volume, personal records, body weight.
- **Today:** Apple Watch, Polar and MyFitnessPal data, all read through Apple Health.

## Setup
1. `brew install xcodegen && xcodegen generate`
2. Open `GymApp.xcodeproj`, choose your team under Signing & Capabilities, and run.
3. In Polar Flow and MyFitnessPal, turn on Apple Health sync.

## Accounts (Supabase)
The app requires an account (email/password or Sign in with Apple). Data is stored on the phone and synced to Supabase.

1. Supabase dashboard → **SQL Editor** → paste and run [`supabase/schema.sql`](supabase/schema.sql).
2. **Sign in with Apple:** Authentication → Sign In / Providers → Apple → enable, and add `com.sorora.gymapp` under Client IDs.
3. Optional, for faster testing: Authentication → Sign In / Providers → Email → turn off "Confirm email".
