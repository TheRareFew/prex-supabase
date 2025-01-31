begin;

-- Grant usage on schema
grant usage on schema public to anon, authenticated;

-- Grant table access to authenticated users
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
grant all on all routines in schema public to authenticated;

-- Enable RLS on all tables
alter table if exists public.tickets enable row level security;
alter table if exists public.ticket_notes enable row level security;
alter table if exists public.articles enable row level security;
alter table if exists public.article_notes enable row level security;
alter table if exists public.employees enable row level security;
alter table if exists public.messages enable row level security;

-- Tickets policies
create policy "Users can view all tickets"
    on public.tickets for select
    to authenticated
    using (true);

create policy "Users can insert tickets"
    on public.tickets for insert
    to authenticated
    with check (true);

create policy "Users can update their own tickets"
    on public.tickets for update
    to authenticated
    using (auth.uid() = created_by);

-- Ticket notes policies
create policy "Users can view all ticket notes"
    on public.ticket_notes for select
    to authenticated
    using (true);

create policy "Users can create ticket notes"
    on public.ticket_notes for insert
    to authenticated
    with check (true);

-- Articles policies
create policy "Users can view all articles"
    on public.articles for select
    to authenticated
    using (true);

create policy "Users can create articles"
    on public.articles for insert
    to authenticated
    with check (true);

-- Article notes policies
create policy "Users can view all article notes"
    on public.article_notes for select
    to authenticated
    using (true);

create policy "Users can create article notes"
    on public.article_notes for insert
    to authenticated
    with check (true);

-- Messages policies
create policy "Users can view all messages"
    on public.messages for select
    to authenticated
    using (true);

create policy "Users can create messages"
    on public.messages for insert
    to authenticated
    with check (true);

-- Employees policies
create policy "Users can view all employees"
    on public.employees for select
    to authenticated
    using (true);

commit; 