# CampConnect (iOS)

A year-round engagement platform for summer camps. CampConnect turns the summer
experience into a structured, off-season loop that keeps campers emotionally
connected to their camp identity — driving re-enrollment and referrals.

**This repo is the native iOS app (SwiftUI) + the Supabase backend schema.**
It is a working MVP scaffold of the *camper* experience.

> Sibling project: the older Expo/React Native prototype lives at
> `~/CampConnect` and is unrelated to this codebase.

---

## The product in one screen

No social feed. No likes. No comments. Just a structured participation loop:

```
Counselor video  →  Challenge  →  Camper submission  →  Operator review  →  Badge
   (summer)         (released        (photo/video/         (approve)        (+ points)
                     monthly)          text)
```

- **Challenges** — a camp picks ~12–18 from a shared template library and sequences
  them across the off-season. Each carries the *star counselor's* video.
- **Submissions** — one per camper per challenge (photo, video, or text).
- **Badges & points** — progression and camp identity, no public leaderboard.

---

## What's in this scaffold

| Area | Status |
|------|--------|
| Supabase schema + RLS (`supabase/schema.sql`) | ✅ |
| Seed data: demo camp, 12 challenge templates, badges, a season (`supabase/seed.sql`) | ✅ |
| Storage buckets + policies (`supabase/storage.sql`) | ✅ |
| Auth (email/password) + session store | ✅ |
| Camper home: active challenges, status per challenge | ✅ |
| Challenge detail: counselor video, instructions, submit | ✅ |
| Submission flow: photo/video (PhotosPicker) + text, upload to storage | ✅ |
| Badges grid + camp identity profile | ✅ |
| **Operator app** (schedule challenges, review queue, award badges) | ⬜ next |
| **Push notifications** (challenge-released nudges) | ⬜ next |
| **Auto-badge rules** (award on Nth completion, etc.) | ⬜ next |

---

## Architecture

```
CampConnect/
├── App/            App entry, config, root routing
├── Models/         Codable structs mirroring the Postgres tables
├── Services/       SupabaseManager, SessionStore (auth), CampService (data)
├── Features/       Auth, Home (challenges), Challenges (detail+submit), Badges, Profile
├── Components/     Reusable SwiftUI pieces (chips, buttons, state views)
├── Theme/          Colors + layout constants
└── Resources/      Info.plist, asset catalog, Secrets.plist (git-ignored)
```

- **Backend:** Supabase (Postgres + Auth + Storage). Access is enforced by
  Row-Level Security, so the anon key shipped in the app can't bypass per-camp
  isolation. See `supabase/schema.sql` for every policy.
- **No custom server** — the app talks straight to Supabase via `supabase-swift`.

---

## Prerequisites

1. **Xcode** — not installed on this machine, and there's a version constraint:
   this Mac runs **macOS 13.7 (Ventura)**, so the latest Xcode (16.x, App Store)
   **won't install** — it needs macOS 14+. You need **Xcode 15.2**, the last
   version that runs on Ventura 13.5+. Get it from
   [developer.apple.com/download/all](https://developer.apple.com/download/all)
   (free Apple ID; search "Xcode 15.2", download the `.xip`, expand it into
   `/Applications`). Xcode 15.2 ships Swift 5.9.2 + the iOS 17.2 SDK, which this
   project targets. *(Or build on a Mac running macOS 14+ with current Xcode.)*
2. **XcodeGen** — a prebuilt copy was downloaded to
   `/tmp/xcodegen_dist/xcodegen/bin/xcodegen` (the Homebrew formula tried to
   compile from source and failed on this OS). It generates `.xcodeproj` from
   `project.yml`. The committed `CampConnect.xcodeproj` was already generated, so
   you only need XcodeGen if you change `project.yml`.
3. A **Supabase project** (free tier is fine) — https://supabase.com.

> **Swift version note:** the Supabase SDK is pinned `from: 2.5.1`. If SPM in
> Xcode 15.2 complains that a resolved version needs a newer Swift toolchain,
> pin a maxVersion in `project.yml` (e.g. `maxVersion: 2.8.4`) and regenerate.

---

## Setup

### 1. Backend (Supabase)

In your Supabase project's **SQL editor**, run in order:

```
supabase/schema.sql     # tables, enums, RLS, signup trigger
supabase/storage.sql    # storage buckets + policies
supabase/seed.sql       # demo camp + challenge library + a season
```

Then **disable email confirmation** for quick local testing
(Authentication → Providers → Email → turn off "Confirm email"), or confirm via
the link Supabase emails you.

### 2. App secrets

```sh
cp CampConnect/Resources/Secrets.example.plist CampConnect/Resources/Secrets.plist
```

Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` (Supabase → Settings → API).
`Secrets.plist` is git-ignored.

### 3. Generate + open the project

The `.xcodeproj` is **not** committed (it's generated from `project.yml`, the
XcodeGen way — avoids churn/merge conflicts). Generate it, then open:

```sh
cd ~/CampConnect-iOS
/tmp/xcodegen_dist/xcodegen/bin/xcodegen generate   # re-run after editing project.yml
open CampConnect.xcodeproj
```

> The prebuilt XcodeGen lives at `/tmp/xcodegen_dist/` (ephemeral). If it's gone,
> re-download `xcodegen.zip` from the XcodeGen GitHub releases, or `brew install
> xcodegen` on a Mac running macOS 14+.

Pick a simulator (e.g. iPhone 15) and hit **Run**.

### 4. Try it

1. **Create an account** in the app (sign up).
2. To see challenges, attach your account to the demo camp. In the SQL editor:
   ```sql
   update profiles
     set camp_id = '00000000-0000-0000-0000-000000000001'
     where id = (select id from auth.users where email = 'you@example.com');
   ```
   (Operators normally do this; we'll build that UI next.)
3. Reopen the app → the three active challenges appear. Open one, submit a
   photo/video/text, and watch it move to **In review**.

---

## ⚠️ COPPA / kids under 13 (read before piloting)

Campers are typically minors, many under 13. U.S. **COPPA** requires verifiable
parental consent before collecting personal info from under-13s — and these kids
upload **photos and videos of themselves**, which is exactly the sensitive data
COPPA governs.

This scaffold is built with that in mind but is **not yet compliant**:

- The schema already models `created_by`, `guardian_consent_at`, and
  `guardian_email` on `profiles` — camper accounts are meant to be **provisioned
  by the camp/operator with a parent's consent**, not self-registered by kids.
- The sign-up screen tells under-13 users to get a camp invite instead.

**Before any real pilot with kids:** implement the operator-driven invite +
verifiable parental consent flow, a data-retention/deletion policy, and review
your storage privacy posture with counsel. Don't collect kid media until that's
done.

---

## Roadmap (next session candidates)

1. **Operator app** — schedule/sequence challenges, review queue (approve/reject),
   award badges, upload counselor videos. This is the "engagement operator layer."
2. **Auto-badge engine** — DB trigger/function that awards badges + points on
   approval (e.g. "Trailblazer" after 3 outdoor challenges).
3. **Parental consent + invites** — the COPPA flow above.
4. **Push notifications** — nudge campers when a new challenge releases.
5. **Recap videos / highlights** — periodic, operator-generated, still no feed.
6. **Android** — separate codebase later (this is native SwiftUI, iOS-first).
```
