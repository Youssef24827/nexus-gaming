-- Autoriser la signalisation WebRTC uniquement aux deux participants d'un DM.
drop policy if exists "Nexus friends can receive audio call signals" on realtime.messages;
create policy "Nexus friends can receive audio call signals"
on realtime.messages for select to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and exists (
    select 1 from public.conversations c
    where (select realtime.topic()) = 'nexus-call:' || c.id::text
      and (select auth.uid()) in (c.participant_a, c.participant_b)
  )
);

drop policy if exists "Nexus friends can send audio call signals" on realtime.messages;
create policy "Nexus friends can send audio call signals"
on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension = 'broadcast'
  and exists (
    select 1 from public.conversations c
    where (select realtime.topic()) = 'nexus-call:' || c.id::text
      and (select auth.uid()) in (c.participant_a, c.participant_b)
  )
);
