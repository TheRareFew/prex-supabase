-- Create bots table
create table bots (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz default now()
);

-- Insert default bot
insert into bots (id, name)
values ('00000000-0000-0000-0000-000000000000', 'AI Bot');

-- Add bot_id to messages
alter table messages
add column bot_id uuid references bots(id);

-- Update messages constraint
alter table messages
drop constraint if exists messages_created_by_fkey;

alter table messages
add constraint messages_created_by_check
check (
  (created_by is not null and bot_id is null) or
  (created_by is null and bot_id is not null)
); 