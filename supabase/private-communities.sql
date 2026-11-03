-- Communities privées et conversations de groupe Nexus.
create table if not exists public.communities (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 40),
  created_by uuid not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.community_members (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);

create table if not exists public.community_group_messages (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  sender_id uuid not null references public.profiles(user_id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 400),
  created_at timestamptz not null default now()
);

create index if not exists community_members_user_idx on public.community_members(user_id, community_id);
create index if not exists community_group_messages_chat_idx on public.community_group_messages(community_id, created_at);

alter table public.communities enable row level security;
alter table public.community_members enable row level security;
alter table public.community_group_messages enable row level security;
grant select on public.communities, public.community_members to authenticated;
grant select, insert on public.community_group_messages to authenticated;

create or replace function public.is_nexus_community_member(p_community_id uuid)
returns boolean language sql stable security definer set search_path = ''
as 'select exists (select 1 from public.community_members cm where cm.community_id = p_community_id and cm.user_id = auth.uid())';
revoke all on function public.is_nexus_community_member(uuid) from public;
grant execute on function public.is_nexus_community_member(uuid) to authenticated;

drop policy if exists "Community members can view their communities" on public.communities;
create policy "Community members can view their communities" on public.communities
  for select to authenticated using (public.is_nexus_community_member(id));
drop policy if exists "Members can view community membership" on public.community_members;
create policy "Members can view community membership" on public.community_members
  for select to authenticated using (public.is_nexus_community_member(community_id));
drop policy if exists "Members can read group messages" on public.community_group_messages;
create policy "Members can read group messages" on public.community_group_messages
  for select to authenticated using (public.is_nexus_community_member(community_id));
drop policy if exists "Members can send group messages" on public.community_group_messages;
create policy "Members can send group messages" on public.community_group_messages
  for insert to authenticated with check (sender_id = (select auth.uid()) and public.is_nexus_community_member(community_id));

create or replace function public.create_nexus_community(p_name text, p_member_ids uuid[] default '{}'::uuid[])
returns uuid language plpgsql security definer set search_path = '' as $nexus$
declare
  v_creator uuid := auth.uid();
  v_community uuid;
  v_member uuid;
begin
  if v_creator is null then raise exception 'Sign in required'; end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 2 and 40 then
    raise exception 'Le nom doit contenir entre 2 et 40 caractères';
  end if;
  insert into public.communities(name, created_by) values (btrim(p_name), v_creator) returning id into v_community;
  insert into public.community_members(community_id, user_id) values (v_community, v_creator);
  for v_member in select distinct member_id from unnest(coalesce(p_member_ids, '{}'::uuid[])) as invited(member_id)
  loop
    if v_member <> v_creator then
      if not exists (
        select 1 from public.conversations c
        where c.participant_a = least(v_creator, v_member) and c.participant_b = greatest(v_creator, v_member)
      ) then raise exception 'Chaque membre invité doit être ton ami'; end if;
      insert into public.community_members(community_id, user_id) values (v_community, v_member);
    end if;
  end loop;
  return v_community;
end;
$nexus$;
revoke all on function public.create_nexus_community(text, uuid[]) from public;
grant execute on function public.create_nexus_community(text, uuid[]) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='community_members') then
    alter publication supabase_realtime add table public.community_members;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='community_group_messages') then
    alter publication supabase_realtime add table public.community_group_messages;
  end if;
end;
$$;
