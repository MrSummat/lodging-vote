# Lodging vote

A small page where friends pick a house for a get-together. Each guest picks their name from the list and votes anonymously. The host pays part of each house, and each guest sees their share:

```
share per guest = (house total − host contribution) ÷ number of guests on the list
host contribution = % of the total, or a fixed € amount (set per house, capped at the total)
```

Example: a €1,000 house where the host pays €500 and there are 10 guests costs **€50 per person**.

- **Guest view:** `https://<you>.github.io/lodging-vote/`
- **Admin view:** `https://<you>.github.io/lodging-vote/?admin`

Guests see each house's price per person, vote totals and who has voted. They never see who voted for what, and the full house prices are not sent to them (they could still work them out from the per-person price). The database only allows access through the functions in `supabase/schema.sql`, so this is enforced by the database, not just hidden in the page.

## Setup (about 10 minutes)

1. **Create a Supabase project** (free) at https://supabase.com.
2. **Run the schema:** open `supabase/schema.sql` and change `change-me-please` at the bottom to your own admin key. Paste the whole file into **SQL Editor** in Supabase and click **Run**.
3. **Connect the page:** in Supabase go to **Project Settings → API Keys** (or **Data API**) and copy the project URL and the **anon** / **publishable** key. Paste both at the top of the `<script>` in `index.html`:
   ```js
   const SUPABASE_URL = 'https://abcd1234.supabase.co';
   const SUPABASE_KEY = 'sb_publishable_...'; // or the legacy anon key (eyJ...)
   ```
   This key is meant to be public. Never use the `service_role` / secret key here.
4. **Publish:** commit, push, then in GitHub go to **Settings → Pages → Deploy from branch → `main` / root**.
5. **Fill it in:** open `…/?admin`, enter your admin key, then add the guests (not yourself) and the houses with the amount you're paying.
6. Send your friends the plain URL.

## Notes

- A guest's vote is remembered on the device they voted from. If they vote again from another device, the new vote replaces the old one, so there is still only one vote per guest.
- Removing a guest also deletes their vote, and the price per person is recalculated.
- Closing voting in the admin view freezes the results.
- You can open `index.html` directly from disk for local testing. It talks to the same Supabase project.
