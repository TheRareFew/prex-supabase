-- Drop existing tables (in reverse dependency order)
drop table if exists response_notes cascade;
drop table if exists manager_responses cascade;
drop table if exists manager_prompts cascade;
drop table if exists conversations cascade;

-- Drop existing trigger function
drop function if exists update_updated_at_column cascade;

-- Create conversations table
create table conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references auth.users not null,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Create manager_prompts table
create table manager_prompts (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid references conversations on delete cascade not null,
    prompt text not null,
    created_at timestamptz default now()
);

-- Create manager_responses table
create table manager_responses (
    id uuid primary key default uuid_generate_v4(),
    prompt_id uuid references manager_prompts on delete cascade not null,
    response text not null,
    created_at timestamptz default now()
);

-- Create response_notes table
create table response_notes (
    id uuid primary key default uuid_generate_v4(),
    response_id uuid references manager_responses on delete cascade not null,
    created_by uuid references auth.users not null,
    note text not null,
    created_at timestamptz default now()
);

-- Enable RLS
alter table conversations enable row level security;
alter table manager_prompts enable row level security;
alter table manager_responses enable row level security;
alter table response_notes enable row level security;

-- Grant access to authenticated users
grant all on conversations to authenticated;
grant all on manager_prompts to authenticated;
grant all on manager_responses to authenticated;
grant all on response_notes to authenticated;

-- Add RLS policies for conversations
create policy "Users can view their own conversations"
    on conversations for select
    to authenticated
    using (auth.uid() = user_id);

create policy "Users can insert their own conversations"
    on conversations for insert
    to authenticated
    with check (auth.uid() = user_id);

-- Add RLS policies for manager_prompts
create policy "Users can view prompts in their conversations"
    on manager_prompts for select
    to authenticated
    using (
        exists (
            select 1
            from conversations
            where id = manager_prompts.conversation_id
            and user_id = auth.uid()
        )
    );

create policy "Users can insert prompts in their conversations"
    on manager_prompts for insert
    to authenticated
    with check (
        exists (
            select 1
            from conversations
            where id = conversation_id
            and user_id = auth.uid()
        )
    );

-- Add RLS policies for manager_responses
create policy "Users can view responses to their prompts"
    on manager_responses for select
    to authenticated
    using (
        exists (
            select 1
            from manager_prompts p
            join conversations c on p.conversation_id = c.id
            where p.id = manager_responses.prompt_id
            and c.user_id = auth.uid()
        )
    );

create policy "Users can insert responses to their prompts"
    on manager_responses for insert
    to authenticated
    with check (
        exists (
            select 1
            from manager_prompts p
            join conversations c on p.conversation_id = c.id
            where p.id = prompt_id
            and c.user_id = auth.uid()
        )
    );

-- Add RLS policies for response_notes
create policy "Users can view notes on responses to their prompts"
    on response_notes for select
    to authenticated
    using (
        exists (
            select 1
            from manager_responses r
            join manager_prompts p on r.prompt_id = p.id
            join conversations c on p.conversation_id = c.id
            where r.id = response_notes.response_id
            and c.user_id = auth.uid()
        )
    );

create policy "Users can insert notes on responses to their prompts"
    on response_notes for insert
    to authenticated
    with check (
        exists (
            select 1
            from manager_responses r
            join manager_prompts p on r.prompt_id = p.id
            join conversations c on p.conversation_id = c.id
            where r.id = response_id
            and c.user_id = auth.uid()
        )
    );

-- Enable realtime
alter publication supabase_realtime add table conversations;
alter publication supabase_realtime add table manager_prompts;
alter publication supabase_realtime add table manager_responses;
alter publication supabase_realtime add table response_notes;

-- Create updated_at trigger for conversations
create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger conversations_updated_at
    before update on conversations
    for each row
    execute function update_updated_at_column();

-- First drop the existing foreign key constraint if exists
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'articles_created_by_fkey'
        AND table_name = 'articles'
    ) THEN
        ALTER TABLE articles 
        DROP CONSTRAINT articles_created_by_fkey;
    END IF;
END $$;

-- Add bot_id column if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'articles'
        AND column_name = 'bot_id'
    ) THEN
        ALTER TABLE articles
        ADD COLUMN bot_id uuid REFERENCES bots(id);
    END IF;
END $$;

-- Add creator check constraint if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'article_creator_check'
        AND table_name = 'articles'
    ) THEN
        ALTER TABLE articles
        ADD CONSTRAINT article_creator_check CHECK (
            (created_by IS NOT NULL AND bot_id IS NULL) OR
            (created_by IS NULL AND bot_id IS NOT NULL)
        );
    END IF;
END $$;

-- Add created_by foreign key if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'articles_created_by_fkey'
        AND table_name = 'articles'
    ) THEN
        ALTER TABLE articles
        ADD CONSTRAINT articles_created_by_fkey
        FOREIGN KEY (created_by)
        REFERENCES auth.users(id);
    END IF;
END $$;
