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
CREATE TYPE permission_type AS ENUM ('super_admin', 'admin', 'manager', 'agent');
CREATE TYPE department_type AS ENUM ('sales', 'marketing', 'support', 'engineering', 'other');
CREATE TYPE shift_type AS ENUM ('morning', 'afternoon', 'evening', 'night');
CREATE TYPE ticket_status_type AS ENUM ('fresh', 'in_progress', 'closed');
CREATE TYPE ticket_priority_type AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE ticket_category_type AS ENUM ('general', 'billing', 'technical', 'feedback', 'account', 'feature_request', 'other');
CREATE TYPE message_sender_type AS ENUM ('employee', 'customer');
CREATE TYPE article_status_type AS ENUM ('draft', 'pending_approval', 'approved', 'rejected', 'archived');
CREATE TYPE article_category_type AS ENUM ('general', 'product', 'service', 'troubleshooting', 'faq', 'policy', 'other');
CREATE TYPE approval_status_type AS ENUM ('pending', 'approved', 'rejected');

-- Create tables
CREATE TABLE employees (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    permissions permission_type NOT NULL,
    department department_type NOT NULL,
    shift shift_type NOT NULL,
    description TEXT DEFAULT NULL
);

CREATE TABLE customers (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    product_interests TEXT[] DEFAULT ARRAY[]::TEXT[],
    is_registered BOOLEAN DEFAULT TRUE
);

CREATE TABLE tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    resolved BOOLEAN DEFAULT FALSE,
    status ticket_status_type DEFAULT 'fresh',
    priority ticket_priority_type DEFAULT 'low',
    category ticket_category_type DEFAULT 'general',
    assigned_to UUID REFERENCES auth.users(id),
    created_by UUID NOT NULL REFERENCES auth.users(id)
);

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id UUID NOT NULL REFERENCES tickets(id),
    created_by UUID NOT NULL REFERENCES auth.users(id),
    sender_type message_sender_type NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    message TEXT NOT NULL,
    is_system_message BOOLEAN DEFAULT FALSE
);

CREATE TABLE articles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    description TEXT,
    content TEXT NOT NULL,
    status article_status_type DEFAULT 'draft',
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMPTZ,
    view_count INTEGER DEFAULT 0,
    is_faq BOOLEAN DEFAULT FALSE,
    category article_category_type DEFAULT 'general',
    slug TEXT UNIQUE NOT NULL
);

CREATE TABLE article_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    version_number INTEGER NOT NULL,
    change_summary TEXT,
    UNIQUE(article_id, version_number)
);

CREATE TABLE approval_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    version_id UUID NOT NULL REFERENCES article_versions(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES auth.users(id),
    submitted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    status approval_status_type DEFAULT 'pending',
    feedback TEXT
);

CREATE TABLE article_tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    UNIQUE(article_id, tag)
);

-- Enable RLS
ALTER TABLE "public"."tickets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."employees" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."articles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."article_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."approval_requests" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."article_tags" ENABLE ROW LEVEL SECURITY;

-- Create view
CREATE OR REPLACE VIEW "public"."employee_profiles" AS
SELECT 
    e.id,
    e.permissions,
    e.department,
    e.shift,
    e.description,
    (u.raw_user_meta_data->>'full_name')::text as full_name
FROM employees e
JOIN auth.users u ON u.id = e.id;

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
GRANT ALL ON TABLE "public"."customers" TO "anon", "authenticated", "service_role";
GRANT ALL ON TABLE "public"."employees" TO "anon", "authenticated", "service_role";
GRANT ALL ON TABLE "public"."messages" TO "anon", "authenticated", "service_role";
GRANT ALL ON TABLE "public"."tickets" TO "anon", "authenticated", "service_role";
GRANT ALL ON TABLE "public"."articles" TO "anon", "authenticated", "service_role";
GRANT ALL ON TABLE "public"."article_versions" TO "anon", "authenticated", "service_role";
GRANT ALL ON TABLE "public"."approval_requests" TO "anon", "authenticated", "service_role";
GRANT ALL ON TABLE "public"."article_tags" TO "anon", "authenticated", "service_role";

-- RLS Policies
CREATE POLICY "Anyone can read employee records"
ON "public"."employees"
AS permissive
FOR SELECT
TO public
USING (true);

CREATE POLICY "Users can delete own employee record"
ON "public"."employees"
AS permissive
FOR DELETE
TO public
USING ((auth.uid() = id));

CREATE POLICY "Users can insert own employee record"
ON "public"."employees"
AS permissive
FOR INSERT
TO public
WITH CHECK ((auth.uid() = id));

CREATE POLICY "Users can update own employee record"
ON "public"."employees"
AS permissive
FOR UPDATE
TO public
USING ((auth.uid() = id))
WITH CHECK ((auth.uid() = id));

CREATE POLICY "Anyone can read messages"
ON "public"."messages"
AS permissive
FOR SELECT
TO public
USING (true);

CREATE POLICY "Authenticated users can create messages"
ON "public"."messages"
AS permissive
FOR INSERT
TO public
WITH CHECK ((auth.role() = 'authenticated'::text));

CREATE POLICY "Message creators and ticket owners can update messages"
ON "public"."messages"
AS permissive
FOR UPDATE
TO public
USING (
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

CREATE POLICY "Only managers and admins can delete messages"
ON "public"."messages"
AS permissive
FOR DELETE
TO public
USING (
    EXISTS (
        SELECT 1
        FROM employees
        WHERE employees.id = auth.uid()
        AND employees.permissions = ANY (ARRAY['manager'::permission_type, 'admin'::permission_type, 'super_admin'::permission_type])
    )
);

CREATE POLICY "Anyone can read tickets"
ON "public"."tickets"
AS permissive
FOR SELECT
TO public
USING (true);

CREATE POLICY "Authenticated users can create tickets"
ON "public"."tickets"
AS permissive
FOR INSERT
TO public
WITH CHECK ((auth.role() = 'authenticated'::text));

CREATE POLICY "Only managers and admins can delete tickets"
ON "public"."tickets"
AS permissive
FOR DELETE
TO public
USING (
    EXISTS (
        SELECT 1
        FROM employees
        WHERE employees.id = auth.uid()
        AND employees.permissions = ANY (ARRAY['manager'::permission_type, 'admin'::permission_type, 'super_admin'::permission_type])
    )
);

CREATE POLICY "Ticket creators and assignees can update tickets"
ON "public"."tickets"
AS permissive
FOR UPDATE
TO public
USING (
    auth.uid() = created_by OR
    auth.uid() = assigned_to OR
    EXISTS (
        SELECT 1
        FROM employees
        WHERE employees.id = auth.uid()
        AND employees.permissions = ANY (ARRAY['manager'::permission_type, 'admin'::permission_type, 'super_admin'::permission_type])
    )
);

-- Knowledge Base RLS Policies - UPDATED
DROP POLICY IF EXISTS "Anyone can read published articles" ON articles;
DROP POLICY IF EXISTS "Employees can read all articles" ON articles;
DROP POLICY IF EXISTS "Employees can create articles" ON articles;
DROP POLICY IF EXISTS "Article owners and managers can update articles" ON articles;
DROP POLICY IF EXISTS "Users can view approved articles" ON articles;
DROP POLICY IF EXISTS "Users can create articles" ON articles;
DROP POLICY IF EXISTS "Users can update their own articles" ON articles;
DROP POLICY IF EXISTS "Users can delete their own articles" ON articles;

-- Drop existing policies
DROP POLICY IF EXISTS "articles_select_policy" ON articles;
DROP POLICY IF EXISTS "articles_insert_policy" ON articles;
DROP POLICY IF EXISTS "articles_update_policy" ON articles;
DROP POLICY IF EXISTS "articles_delete_policy" ON articles;

-- Create more permissive policies for debugging
CREATE POLICY "articles_select_policy"
ON articles FOR SELECT
USING (true);  -- Allow all reads for debugging

CREATE POLICY "articles_insert_policy"
ON articles FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM employees
        WHERE employees.id = auth.uid()
    )
);

CREATE POLICY "articles_update_policy"
ON articles FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM employees
        WHERE employees.id = auth.uid()
    )
);

CREATE POLICY "articles_delete_policy"
ON articles FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM employees
        WHERE employees.id = auth.uid()
    )
);

-- Simplified article_tags policies
DROP POLICY IF EXISTS "Users can view article tags" ON article_tags;
DROP POLICY IF EXISTS "Users can manage tags for their articles" ON article_tags;
DROP POLICY IF EXISTS "Anyone can read article tags" ON article_tags;
DROP POLICY IF EXISTS "Article owners and managers can manage tags" ON article_tags;

CREATE POLICY "article_tags_select_policy"
ON article_tags FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM articles
        WHERE articles.id = article_tags.article_id
        AND (
            articles.status = 'approved'
            OR articles.created_by = auth.uid()
            OR EXISTS (
                SELECT 1 FROM employees
                WHERE id = auth.uid()
                AND permissions IN ('manager', 'admin', 'super_admin')
            )
        )
    )
);

CREATE POLICY "article_tags_insert_policy"
ON article_tags FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM articles
        WHERE articles.id = article_tags.article_id
        AND articles.created_by = auth.uid()
    )
);

CREATE POLICY "article_tags_delete_policy"
ON article_tags FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM articles
        WHERE articles.id = article_tags.article_id
        AND articles.created_by = auth.uid()
    )
);

-- Grant necessary permissions
GRANT ALL ON articles TO authenticated;
GRANT ALL ON article_tags TO authenticated;
GRANT ALL ON article_versions TO authenticated;
GRANT ALL ON approval_requests TO authenticated;
