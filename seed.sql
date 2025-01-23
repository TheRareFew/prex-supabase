-- Drop existing tables and types
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS tickets;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS employees;

DROP TYPE IF EXISTS permission_type;
DROP TYPE IF EXISTS department_type;
DROP TYPE IF EXISTS shift_type;
DROP TYPE IF EXISTS ticket_status_type;
DROP TYPE IF EXISTS ticket_priority_type;
DROP TYPE IF EXISTS ticket_category_type;

-- Create extensions if they don't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create ENUM types
CREATE TYPE permission_type AS ENUM ('super_admin', 'admin', 'manager', 'agent');
CREATE TYPE department_type AS ENUM ('sales', 'marketing', 'support', 'engineering', 'other');
CREATE TYPE shift_type AS ENUM ('morning', 'afternoon', 'evening', 'night');
CREATE TYPE ticket_status_type AS ENUM ('fresh', 'in_progress', 'closed');
CREATE TYPE ticket_priority_type AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE ticket_category_type AS ENUM ('general', 'billing', 'technical', 'feedback', 'account', 'feature_request', 'other');

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
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    message TEXT NOT NULL,
    is_system_message BOOLEAN DEFAULT FALSE
);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger for tickets table
CREATE TRIGGER update_tickets_updated_at
    BEFORE UPDATE ON tickets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for employees table
CREATE POLICY "Anyone can read employee records"
ON employees FOR SELECT
USING (true);

CREATE POLICY "Users can insert own employee record"
ON employees FOR INSERT
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own employee record"
ON employees FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can delete own employee record"
ON employees FOR DELETE
USING (auth.uid() = id);

-- Create RLS policies for tickets table
CREATE POLICY "Anyone can read tickets"
ON tickets FOR SELECT
USING (true);

CREATE POLICY "Authenticated users can create tickets"
ON tickets FOR INSERT
WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Ticket creators and assignees can update tickets"
ON tickets FOR UPDATE
USING (
    auth.uid() = created_by 
    OR auth.uid() = assigned_to
    OR EXISTS (
        SELECT 1 FROM employees 
        WHERE id = auth.uid() 
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
);

CREATE POLICY "Only managers and admins can delete tickets"
ON tickets FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM employees 
        WHERE id = auth.uid() 
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
);

-- Create view for employees with user metadata
CREATE OR REPLACE VIEW employee_profiles AS
SELECT 
    e.id,
    e.permissions,
    e.department,
    e.shift,
    e.description,
    (u.raw_user_meta_data->>'full_name')::text as full_name
FROM employees e
JOIN auth.users u ON u.id = e.id;

-- The view will inherit RLS policies from the underlying employees table
-- No need for separate RLS policies on the view

-- Create RLS policies for messages table
CREATE POLICY "Anyone can read messages"
ON messages FOR SELECT
USING (true);

CREATE POLICY "Authenticated users can create messages"
ON messages FOR INSERT
WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Message creators and ticket owners can update messages"
ON messages FOR UPDATE
USING (
    auth.uid() = created_by 
    OR EXISTS (
        SELECT 1 FROM tickets 
        WHERE tickets.id = messages.ticket_id 
        AND (tickets.created_by = auth.uid() OR tickets.assigned_to = auth.uid())
    )
    OR EXISTS (
        SELECT 1 FROM employees 
        WHERE id = auth.uid() 
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
);

CREATE POLICY "Only managers and admins can delete messages"
ON messages FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM employees 
        WHERE id = auth.uid() 
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
);
