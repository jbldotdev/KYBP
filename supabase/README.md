# Supabase setup

1. In **Authentication → URL Configuration**, set **Site URL** to
   `https://jbldotdev.github.io/KYBP/` and add that same URL under **Redirect
   URLs**. The password-reset flow returns users to this page to choose a new
   password. Add `http://localhost:3000/**` to Redirect URLs only if you also
   use a local development server.
2. In the Supabase Dashboard for this project, open **SQL Editor**, paste in
   [`schema.sql`](./schema.sql), and run it once. Reload the GitHub Pages app
   after the SQL completes.
3. In **Authentication → Settings**, disable public sign-ups unless open
   account registration is explicitly desired. Create staff accounts from
   **Authentication → Users**. The database trigger creates each new user's
   KYBP profile with no app access by default.
4. Promote the first administrator by copying that user's UUID from
   **Authentication → Users** and running this query in the SQL Editor. Replace
   the email with the administrator's sign-in email:

   ```sql
   update public.kybp_profiles
   set role = 'Admin', forms = 'Both'
   where user_id = (
     select id from auth.users where email = 'admin@example.com'
   );
   ```

5. Sign in to the app as that administrator. Add or update staff roles in
   **Access** using each staff member's Auth user UUID. The app never stores
   staff passwords itself; Supabase Auth handles email/password authentication.
6. Existing browser-local records are not uploaded automatically. Export them
   from the old app to Excel/CSV, then use the Admin **Import Excel/CSV** action
   in the Supabase-backed app. Review the imported data before using it.

The publishable key in `index.html` is intended for browser use. Do not put a
Supabase secret or service-role key in this repository. Row-level security in
`schema.sql` is required: records are visible only to authenticated users with
matching form access, edits require Admin or Editor access, and deletion is
Admin-only. Public form submissions can be inserted without sign-in but can
only be read and processed by Admins.

## Offline record backup

Admins can open **Records** and use **Download complete offline backup** to
download every shared record as a timestamped JSON file. The backup includes
all record fields and signatures; treat it as confidential business data and
store it in a secure location. Keep more than one copy and periodically verify
that a downloaded file opens and contains the expected record count. This
download is a backup copy only; it does not restore records to Supabase.
