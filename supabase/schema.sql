-- NEXORA core database schema
-- Run once in Supabase Dashboard > SQL Editor.
-- Safe to re-run: tables, indexes, policies, and trigger are guarded.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 2 and 30),
  display_name text not null default 'NEXORA Member' check (char_length(display_name) between 1 and 60),
  avatar_url text,
  bio text not null default '' check (char_length(bio) <= 300),
  language text not null default 'en',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 500),
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_requests_not_self check (sender_id <> receiver_id),
  constraint friend_requests_pair_unique unique (sender_id, receiver_id)
);

create table if not exists public.friendships (
  user_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  constraint friendships_not_self check (user_id <> friend_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 5000),
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint messages_not_self check (sender_id <> receiver_id)
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_user_created_idx on public.posts (user_id, created_at desc);
create index if not exists likes_user_idx on public.post_likes (user_id);
create index if not exists comments_post_created_idx on public.comments (post_id, created_at);
create index if not exists friend_requests_receiver_status_idx on public.friend_requests (receiver_id, status);
create index if not exists messages_pair_created_idx on public.messages (sender_id, receiver_id, created_at desc);
create index if not exists messages_receiver_created_idx on public.messages (receiver_id, created_at desc);

-- Create a public profile automatically whenever an auth user is created.
create or replace function public.handle_new_nexora_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_username text;
  safe_username text;
begin
  base_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1), 'member'),
    '[^a-z0-9_]', '', 'g'
  ));
  safe_username := left(coalesce(nullif(base_username, ''), 'member'), 20)
    || '_' || left(replace(new.id::text, '-', ''), 8);

  insert into public.profiles (id, username, display_name, language)
  values (
    new.id,
    safe_username,
    left(coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1), 'NEXORA Member'), 60),
    coalesce(nullif(new.raw_user_meta_data ->> 'language', ''), 'en')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_nexora on auth.users;
create trigger on_auth_user_created_nexora
  after insert on auth.users
  for each row execute procedure public.handle_new_nexora_user();

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.comments enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.messages enable row level security;

-- Profiles are publicly readable to support the public social feed; only owners edit.
drop policy if exists "Profiles are viewable by everyone" on public.profiles;
create policy "Profiles are viewable by everyone" on public.profiles for select to anon, authenticated using (true);
drop policy if exists "Users create their own profile" on public.profiles;
create policy "Users create their own profile" on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Signed-in members can see the community feed; only authors can change their posts.
drop policy if exists "Authenticated users read posts" on public.posts;
create policy "Authenticated users read posts" on public.posts for select to authenticated using (true);
drop policy if exists "Users create own posts" on public.posts;
create policy "Users create own posts" on public.posts for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users update own posts" on public.posts;
create policy "Users update own posts" on public.posts for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users delete own posts" on public.posts;
create policy "Users delete own posts" on public.posts for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Authenticated users read likes" on public.post_likes;
create policy "Authenticated users read likes" on public.post_likes for select to authenticated using (true);
drop policy if exists "Users like as themselves" on public.post_likes;
create policy "Users like as themselves" on public.post_likes for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users remove their own likes" on public.post_likes;
create policy "Users remove their own likes" on public.post_likes for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Authenticated users read comments" on public.comments;
create policy "Authenticated users read comments" on public.comments for select to authenticated using (true);
drop policy if exists "Users create own comments" on public.comments;
create policy "Users create own comments" on public.comments for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users delete own comments" on public.comments;
create policy "Users delete own comments" on public.comments for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Participants read friend requests" on public.friend_requests;
create policy "Participants read friend requests" on public.friend_requests for select to authenticated using (auth.uid() = sender_id or auth.uid() = receiver_id);
drop policy if exists "Users send friend requests" on public.friend_requests;
create policy "Users send friend requests" on public.friend_requests for insert to authenticated with check (auth.uid() = sender_id);
drop policy if exists "Receivers respond to friend requests" on public.friend_requests;
create policy "Receivers respond to friend requests" on public.friend_requests for update to authenticated using (auth.uid() = receiver_id) with check (auth.uid() = receiver_id);

drop policy if exists "Users read their friendships" on public.friendships;
create policy "Users read their friendships" on public.friendships for select to authenticated using (auth.uid() = user_id or auth.uid() = friend_id);
drop policy if exists "Users create friendship rows for themselves" on public.friendships;
create policy "Users create friendship rows for themselves" on public.friendships for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users remove friendship rows for themselves" on public.friendships;
create policy "Users remove friendship rows for themselves" on public.friendships for delete to authenticated using (auth.uid() = user_id);

-- Only the sender and receiver may read a direct message.
drop policy if exists "Message participants read messages" on public.messages;
create policy "Message participants read messages" on public.messages for select to authenticated using (auth.uid() = sender_id or auth.uid() = receiver_id);
drop policy if exists "Users send messages as themselves" on public.messages;
create policy "Users send messages as themselves" on public.messages for insert to authenticated with check (auth.uid() = sender_id);
drop policy if exists "Receivers mark messages read" on public.messages;
create policy "Receivers mark messages read" on public.messages for update to authenticated using (auth.uid() = receiver_id) with check (auth.uid() = receiver_id);

-- Keep the public profile table discoverable through the Supabase Data API.
grant usage on schema public to anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.posts to authenticated;
grant select, insert, delete on public.post_likes to authenticated;
grant select, insert, delete on public.comments to authenticated;
grant select, insert, update on public.friend_requests to authenticated;
grant select, insert, delete on public.friendships to authenticated;
grant select, insert, update on public.messages to authenticated;
