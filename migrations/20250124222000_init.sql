-- Create ENUMs
create type permission_type as enum ('super_admin', 'admin', 'manager', 'agent');
create type department_type as enum ('sales', 'marketing', 'support', 'engineering', 'other');
create type shift_type as enum ('morning', 'afternoon', 'evening', 'night');
create type ticket_status_type as enum ('fresh', 'in_progress', 'closed');
create type ticket_priority_type as enum ('low', 'medium', 'high', 'critical');
create type ticket_category_type as enum ('general', 'billing', 'technical', 'feedback', 'account', 'feature_request', 'other');
create type article_status_type as enum ('draft', 'pending_approval', 'approved', 'rejected', 'archived');
create type article_category_type as enum ('general', 'product', 'service', 'troubleshooting', 'faq', 'policy', 'other');
create type approval_status_type as enum ('pending', 'approved', 'rejected');
create type message_sender_type as enum ('employee', 'customer');

-- Create tables
create table employees (
    id uuid primary key references auth.users,
    permissions permission_type,
    department department_type,
    shift shift_type,
    description text
);

create table customers (
    id uuid primary key references auth.users,
    product_interests text[] default '{}',
    is_registered boolean default true
);

create table tickets (
    id uuid primary key default uuid_generate_v4(),
    name text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    resolved boolean default false,
    status ticket_status_type default 'fresh',
    priority ticket_priority_type default 'low',
    category ticket_category_type default 'general',
    assigned_to uuid references auth.users,
    created_by uuid references auth.users
);

create table ticket_notes (
    id uuid primary key default uuid_generate_v4(),
    ticket_id uuid references tickets on delete cascade,
    content text,
    created_at timestamptz default now(),
    created_by uuid references auth.users
);

create table messages (
    id uuid primary key default uuid_generate_v4(),
    ticket_id uuid references tickets,
    created_by uuid references auth.users,
    sender_type message_sender_type,
    created_at timestamptz default now(),
    message text,
    is_system_message boolean default false
);

create table articles (
    id uuid primary key default uuid_generate_v4(),
    title text,
    description text,
    content text,
    status article_status_type default 'draft',
    created_by uuid references auth.users,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    published_at timestamptz,
    view_count integer default 0,
    is_faq boolean default false,
    category article_category_type default 'general',
    slug text unique
);

create table article_notes (
    id uuid primary key default uuid_generate_v4(),
    article_id uuid references articles on delete cascade,
    content text,
    created_at timestamptz default now(),
    created_by uuid references auth.users
);

create table article_versions (
    id uuid primary key default uuid_generate_v4(),
    article_id uuid references articles on delete cascade,
    title text,
    description text,
    content text,
    created_at timestamptz default now(),
    created_by uuid references auth.users,
    version_number integer,
    change_summary text,
    unique(article_id, version_number)
);

create table approval_requests (
    id uuid primary key default uuid_generate_v4(),
    article_id uuid references articles on delete cascade,
    version_id uuid references article_versions on delete cascade,
    submitted_by uuid references auth.users,
    submitted_at timestamptz default now(),
    reviewed_by uuid references auth.users,
    reviewed_at timestamptz,
    status approval_status_type default 'pending',
    feedback text
);

create table article_tags (
    id uuid primary key default uuid_generate_v4(),
    article_id uuid references articles on delete cascade,
    tag text,
    unique(article_id, tag)
);

-- Create views
create view employee_profiles as
select 
    e.id,
    e.permissions,
    e.department,
    e.shift,
    e.description,
    u.raw_user_meta_data->>'full_name' as full_name,
    u.email
from employees e
join auth.users u on e.id = u.id; 