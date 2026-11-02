-- NEXUS cross-device accounts and direct messaging
-- Run this once in the Supabase SQL Editor for project nexus-gaming.

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  pseudo text not null check (char_length(pseudo) between 3 and 20),
  pseudo_norm text generated always as (lower(btrim(pseudo))) stored unique,
  created_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  participant_a uuid not null references public.profiles (user_id) on delete cascade,
  participant_b uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint conversations_distinct_participants check (participant_a <> participant_b),
  constraint conversations_sorted_participants check (participant_a < participant_b),
  constraint conversations_unique_pair unique (participant_a, participant_b)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (user_id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 400),
  created_at timestamptz not null default now()
);

create index if not exists conversations_participant_a_idx on public.conversations (participant_a, created_at desc);
create index if not exists conversations_participant_b_idx on public.conversations (participant_b, created_at desc);
create index if not exists messages_conversation_created_idx on public.messages (conversation_id, created_at);

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

grant select on public.profiles to authenticated;
grant select, insert on public.conversations to authenticated;
grant select, insert on public.messages to authenticated;

create policy "Authenticated users can find pseudos"
  on public.profiles for select to authenticated using (true);

create policy "Participants can read conversations"
  on public.conversations for select to authenticated
  using ((select auth.uid()) in (participant_a, participant_b));

create policy "Participants can start conversations"
  on public.conversations for insert to authenticated
  with check ((select auth.uid()) in (participant_a, participant_b));

create policy "Participants can read messages"
  on public.messages for select to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and (select auth.uid()) in (c.participant_a, c.participant_b)
  ));

create policy "Participants can send messages as themselves"
  on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (select auth.uid()) in (c.participant_a, c.participant_b)
    )
  );

create or replace function public.create_nexus_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_pseudo text := btrim(new.raw_user_meta_data ->> 'pseudo');
begin
  if requested_pseudo is null or char_length(requested_pseudo) not between 3 and 20 then
    raise exception 'Pseudo must contain between 3 and 20 characters';
  end if;

  insert into public.profiles (user_id, pseudo)
  values (new.id, requested_pseudo);
  return new;
end;
$$;

revoke all on function public.create_nexus_profile_for_auth_user() from public, anon, authenticated;

create trigger on_nexus_auth_user_created
  after insert on auth.users
  for each row execute procedure public.create_nexus_profile_for_auth_user();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    execute 'alter publication supabase_realtime add table public.conversations';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    execute 'alter publication supabase_realtime add table public.messages';
  end if;
end;
$$;
