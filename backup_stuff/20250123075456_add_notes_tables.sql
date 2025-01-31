-- Create article_notes table
CREATE TABLE article_notes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL REFERENCES auth.users(id)
);

-- Create ticket_notes table
CREATE TABLE ticket_notes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by UUID NOT NULL REFERENCES auth.users(id)
);

-- Enable RLS
ALTER TABLE article_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_notes ENABLE ROW LEVEL SECURITY;

-- Grant permissions
GRANT ALL ON article_notes TO authenticated;
GRANT ALL ON ticket_notes TO authenticated;

-- Article Notes RLS Policies
CREATE POLICY "article_notes_select_policy" ON article_notes
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM articles
        WHERE articles.id = article_notes.article_id
        AND (
            articles.created_by = auth.uid()
            OR EXISTS (
                SELECT 1 FROM employees
                WHERE id = auth.uid()
            )
        )
    )
);

CREATE POLICY "article_notes_insert_policy" ON article_notes
FOR INSERT TO authenticated
WITH CHECK (
    auth.uid() = created_by
    AND EXISTS (
        SELECT 1 FROM articles
        WHERE articles.id = article_notes.article_id
        AND (
            articles.created_by = auth.uid()
            OR EXISTS (
                SELECT 1 FROM employees
                WHERE id = auth.uid()
            )
        )
    )
);

CREATE POLICY "article_notes_update_policy" ON article_notes
FOR UPDATE TO authenticated
USING (
    auth.uid() = created_by
    OR EXISTS (
        SELECT 1 FROM employees
        WHERE id = auth.uid()
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
);

CREATE POLICY "article_notes_delete_policy" ON article_notes
FOR DELETE TO authenticated
USING (
    auth.uid() = created_by
    OR EXISTS (
        SELECT 1 FROM employees
        WHERE id = auth.uid()
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
);

-- Ticket Notes RLS Policies
CREATE POLICY "ticket_notes_select_policy" ON ticket_notes
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM tickets
        WHERE tickets.id = ticket_notes.ticket_id
        AND (
            tickets.created_by = auth.uid()
            OR tickets.assigned_to = auth.uid()
            OR EXISTS (
                SELECT 1 FROM employees
                WHERE id = auth.uid()
            )
        )
    )
);

CREATE POLICY "ticket_notes_insert_policy" ON ticket_notes
FOR INSERT TO authenticated
WITH CHECK (
    auth.uid() = created_by
    AND EXISTS (
        SELECT 1 FROM tickets
        WHERE tickets.id = ticket_notes.ticket_id
        AND (
            tickets.created_by = auth.uid()
            OR tickets.assigned_to = auth.uid()
            OR EXISTS (
                SELECT 1 FROM employees
                WHERE id = auth.uid()
            )
        )
    )
);

CREATE POLICY "ticket_notes_update_policy" ON ticket_notes
FOR UPDATE TO authenticated
USING (
    auth.uid() = created_by
    OR EXISTS (
        SELECT 1 FROM employees
        WHERE id = auth.uid()
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
);

CREATE POLICY "ticket_notes_delete_policy" ON ticket_notes
FOR DELETE TO authenticated
USING (
    auth.uid() = created_by
    OR EXISTS (
        SELECT 1 FROM employees
        WHERE id = auth.uid()
        AND permissions IN ('manager', 'admin', 'super_admin')
    )
); 