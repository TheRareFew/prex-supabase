begin;
alter table public.article_notes enable row level security;
alter table public.ticket_notes enable row level security;
grant usage on schema public to authenticated;
grant all on all tables in schema public to authenticated;
revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from service_role;
commit;
