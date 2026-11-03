-- Run once in the Supabase SQL Editor to enable the group chat rooms.
create table if not exists public.community_messages (
  id uuid primary key default gen_random_uuid(),
  room_key text not null check (room_key in ('general', 'minecraft', 'recherche-joueurs', 'entraide')),
  sender_id uuid not null references public.profiles (user_id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 400),
  created_at timestamptz not null default now()
);

create index if not exists community_messages_room_created_idx
  on public.community_messages (room_key, created_at desc);

alter table public.community_messages enable row level security;
grant select, insert on public.community_messages to authenticated;

drop policy if exists "Authenticated users can read group messages"
  on public.community_messages;
create policy "Authenticated users can read group messages"
  on public.community_messages for select to authenticated using (true);

drop policy if exists "Authenticated users can send group messages as themselves"
  on public.community_messages;
create policy "Authenticated users can send group messages as themselves"
  on public.community_messages for insert to authenticated
  with check (sender_id = (select auth.uid()));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_messages'
  ) then
    execute 'alter publication supabase_realtime add table public.community_messages';
  end if;
end;
$$;
