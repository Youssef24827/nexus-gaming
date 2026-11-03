-- Allow every authenticated community member to send their own group messages.
grant select, insert on public.community_group_messages to authenticated;
drop policy if exists "Members can send group messages" on public.community_group_messages;
drop policy if exists "Community members can send their own messages" on public.community_group_messages;
create policy "Community members can send their own messages"
on public.community_group_messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and public.is_nexus_community_member(community_id)
);
