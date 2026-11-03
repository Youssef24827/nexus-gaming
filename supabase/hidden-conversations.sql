-- Run once to keep removed friends hidden across sessions and devices.
create table if not exists public.hidden_conversations (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

alter table public.hidden_conversations enable row level security;
grant select, insert, delete on public.hidden_conversations to authenticated;

drop policy if exists "Users can read their own hidden conversations"
  on public.hidden_conversations;
create policy "Users can read their own hidden conversations"
  on public.hidden_conversations for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users can hide their own conversations"
  on public.hidden_conversations;
create policy "Users can hide their own conversations"
  on public.hidden_conversations for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can unhide their own hidden conversations"
  on public.hidden_conversations;
create policy "Users can unhide their own hidden conversations"
  on public.hidden_conversations for delete to authenticated
  using (user_id = (select auth.uid()));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'hidden_conversations'
  ) then
    execute 'alter publication supabase_realtime add table public.hidden_conversations';
  end if;
end;
$$;
