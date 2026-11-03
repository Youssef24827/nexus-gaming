-- Reserve private community audio-call signaling for current community members.
drop policy if exists "Nexus community members can receive audio call signals" on realtime.messages;
create policy "Nexus community members can receive audio call signals"
on realtime.messages for select to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and exists (
    select 1 from public.community_members cm
    where (select realtime.topic()) = 'nexus-community-call:' || cm.community_id::text
      and cm.user_id = (select auth.uid())
  )
);

drop policy if exists "Nexus community members can send audio call signals" on realtime.messages;
create policy "Nexus community members can send audio call signals"
on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension = 'broadcast'
  and exists (
    select 1 from public.community_members cm
    where (select realtime.topic()) = 'nexus-community-call:' || cm.community_id::text
      and cm.user_id = (select auth.uid())
  )
);
