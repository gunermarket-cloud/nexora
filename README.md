# NEXORA — One World. One Connection.

NEXORA is currently in its first working web-app build. The sign-in screen and initial feed UI are present; the live social features depend on the Supabase database setup.

## Supabase database setup

1. Open the NEXORA Supabase project.
2. Go to **SQL Editor** and create a new query.
3. Copy and run the complete contents of [supabase/schema.sql](supabase/schema.sql).
4. Confirm that the tables `profiles`, `posts`, `post_likes`, `comments`, `friend_requests`, `friendships`, and `messages` appear under **Table Editor**.
5. In **Authentication → URL Configuration**, set the Site URL to `https://nexora-one-world-one-1.vercel.app` and add that exact origin as a Redirect URL (and the preview URL only if you intend to test previews).
6. In **Authentication → Providers**, enable Google only after the OAuth client is configured with the Supabase callback URL shown by Supabase.

The schema creates a profile automatically when a new Supabase Auth user is created and enables row-level security on all social tables. Direct messages are readable only by their sender and receiver.

## Current implementation boundary

- Email/password registration and login handlers exist in `index.html`.
- Google and GitHub OAuth handlers exist, but provider configuration must be verified in Supabase.
- The current feed reads posts and likes from Supabase; post creation, likes and comment insertion are wired in the client.
- Friend and message database tables are foundations only; their user-facing screens and workflows still need implementation.
- A successful Vercel deployment does not by itself prove that Supabase registration, OAuth, or database policies are working.

Never commit Supabase service-role keys, OAuth client secrets, or user passwords. The browser must use only the Supabase publishable/anon key.
