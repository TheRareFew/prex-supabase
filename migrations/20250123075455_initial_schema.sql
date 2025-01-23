-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant necessary permissions to auth schema
GRANT USAGE ON SCHEMA auth TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO postgres, anon, authenticated, service_role;

-- Create function to handle new user registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.customers (id)
  VALUES (new.id);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for new user registration
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create ENUMs first
create type "public"."department_type" as enum ('sales', 'marketing', 'support', 'engineering', 'other');
create type "public"."permission_type" as enum ('super_admin', 'admin', 'manager', 'agent');
create type "public"."shift_type" as enum ('morning', 'afternoon', 'evening', 'night');
create type "public"."ticket_category_type" as enum ('general', 'billing', 'technical', 'feedback', 'account', 'feature_request', 'other');
create type "public"."ticket_priority_type" as enum ('low', 'medium', 'high', 'critical');
create type "public"."ticket_status_type" as enum ('fresh', 'in_progress', 'closed');

-- Create tables with primary keys first
create table "public"."tickets" (
    "id" uuid not null default uuid_generate_v4() PRIMARY KEY,
    "name" text,
    "created_at" timestamp with time zone default CURRENT_TIMESTAMP,
    "updated_at" timestamp with time zone default CURRENT_TIMESTAMP,
    "resolved" boolean default false,
    "status" ticket_status_type default 'fresh'::ticket_status_type,
    "priority" ticket_priority_type default 'low'::ticket_priority_type,
    "category" ticket_category_type default 'general'::ticket_category_type,
    "assigned_to" uuid,
    "created_by" uuid not null
);

create table "public"."customers" (
    "id" uuid not null PRIMARY KEY,
    "product_interests" text[] default ARRAY[]::text[],
    "is_registered" boolean default true
);

create table "public"."employees" (
    "id" uuid not null PRIMARY KEY,
    "permissions" permission_type not null,
    "department" department_type not null,
    "shift" shift_type not null,
    "description" text
);

create table "public"."messages" (
    "id" uuid not null default uuid_generate_v4() PRIMARY KEY,
    "ticket_id" uuid not null,
    "created_by" uuid not null,
    "created_at" timestamp with time zone default CURRENT_TIMESTAMP,
    "message" text not null,
    "is_system_message" boolean default false
);

-- Enable RLS
alter table "public"."tickets" enable row level security;
alter table "public"."customers" enable row level security;
alter table "public"."employees" enable row level security;
alter table "public"."messages" enable row level security;

-- Add foreign key constraints
alter table "public"."customers" add constraint "customers_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id);
alter table "public"."employees" add constraint "employees_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id);
alter table "public"."messages" add constraint "messages_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table "public"."messages" add constraint "messages_ticket_id_fkey" FOREIGN KEY (ticket_id) REFERENCES tickets(id);
alter table "public"."tickets" add constraint "tickets_assigned_to_fkey" FOREIGN KEY (assigned_to) REFERENCES auth.users(id);
alter table "public"."tickets" add constraint "tickets_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id);

-- Create view
create or replace view "public"."employee_profiles" as
SELECT e.id,
    e.permissions,
    e.department,
    e.shift,
    e.description,
    (u.raw_user_meta_data ->> 'full_name'::text) AS full_name
FROM (employees e
    JOIN auth.users u ON ((u.id = e.id)));

-- Create function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$function$;

-- Grants
grant all on table "public"."customers" to "anon", "authenticated", "service_role";
grant all on table "public"."employees" to "anon", "authenticated", "service_role";
grant all on table "public"."messages" to "anon", "authenticated", "service_role";
grant all on table "public"."tickets" to "anon", "authenticated", "service_role";

-- RLS Policies
create policy "Anyone can read employee records"
on "public"."employees"
as permissive
for select
to public
using (true);

create policy "Users can delete own employee record"
on "public"."employees"
as permissive
for delete
to public
using ((auth.uid() = id));

create policy "Users can insert own employee record"
on "public"."employees"
as permissive
for insert
to public
with check ((auth.uid() = id));

create policy "Users can update own employee record"
on "public"."employees"
as permissive
for update
to public
using ((auth.uid() = id))
with check ((auth.uid() = id));

create policy "Anyone can read messages"
on "public"."messages"
as permissive
for select
to public
using (true);

create policy "Authenticated users can create messages"
on "public"."messages"
as permissive
for insert
to public
with check ((auth.role() = 'authenticated'::text));

create policy "Message creators and ticket owners can update messages"
on "public"."messages"
as permissive
for update
to public
using (
    (auth.uid() = created_by) OR
    (EXISTS (
        SELECT 1
        FROM tickets
        WHERE tickets.id = messages.ticket_id
        AND (tickets.created_by = auth.uid() OR tickets.assigned_to = auth.uid())
    )) OR
    (EXISTS (
        SELECT 1
        FROM employees
        WHERE employees.id = auth.uid()
        AND employees.permissions = ANY (ARRAY['manager'::permission_type, 'admin'::permission_type, 'super_admin'::permission_type])
    ))
);

create policy "Only managers and admins can delete messages"
on "public"."messages"
as permissive
for delete
to public
using (
    EXISTS (
        SELECT 1
        FROM employees
        WHERE employees.id = auth.uid()
        AND employees.permissions = ANY (ARRAY['manager'::permission_type, 'admin'::permission_type, 'super_admin'::permission_type])
    )
);

create policy "Anyone can read tickets"
on "public"."tickets"
as permissive
for select
to public
using (true);

create policy "Authenticated users can create tickets"
on "public"."tickets"
as permissive
for insert
to public
with check ((auth.role() = 'authenticated'::text));

create policy "Only managers and admins can delete tickets"
on "public"."tickets"
as permissive
for delete
to public
using (
    EXISTS (
        SELECT 1
        FROM employees
        WHERE employees.id = auth.uid()
        AND employees.permissions = ANY (ARRAY['manager'::permission_type, 'admin'::permission_type, 'super_admin'::permission_type])
    )
);

create policy "Ticket creators and assignees can update tickets"
on "public"."tickets"
as permissive
for update
to public
using (
    auth.uid() = created_by OR
    auth.uid() = assigned_to OR
    EXISTS (
        SELECT 1
        FROM employees
        WHERE employees.id = auth.uid()
        AND employees.permissions = ANY (ARRAY['manager'::permission_type, 'admin'::permission_type, 'super_admin'::permission_type])
    )
);

CREATE TRIGGER update_tickets_updated_at
    BEFORE UPDATE ON public.tickets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
