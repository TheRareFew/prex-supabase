-- Remove the policies from initial schema if they exist
DROP POLICY IF EXISTS "managers_view_all_article_versions" ON article_versions;
DROP POLICY IF EXISTS "employees_view_own_article_versions" ON article_versions;
DROP POLICY IF EXISTS "employees_create_own_article_versions" ON article_versions;
DROP POLICY IF EXISTS "managers_create_article_versions" ON article_versions;
DROP POLICY IF EXISTS "managers_view_all_approval_requests" ON approval_requests;
DROP POLICY IF EXISTS "employees_view_own_approval_requests" ON approval_requests;
DROP POLICY IF EXISTS "employees_create_own_approval_requests" ON approval_requests;
DROP POLICY IF EXISTS "managers_update_approval_requests" ON approval_requests;

-- Create policies for article_versions

-- Managers can view all article versions
CREATE POLICY "managers_view_all_article_versions" ON article_versions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND employees.permissions IN ('manager', 'admin', 'super_admin')
    )
  );

-- Employees can view versions of their own articles
CREATE POLICY "employees_view_own_article_versions" ON article_versions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM articles
      WHERE articles.id = article_versions.article_id
      AND articles.created_by = auth.uid()
    )
  );

-- Employees can create versions for their own articles
CREATE POLICY "employees_create_own_article_versions" ON article_versions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM articles
      WHERE articles.id = article_versions.article_id
      AND articles.created_by = auth.uid()
    )
  );

-- Managers can create versions for any article
CREATE POLICY "managers_create_article_versions" ON article_versions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND employees.permissions IN ('manager', 'admin', 'super_admin')
    )
  );

-- Create policies for approval_requests

-- Managers can view all approval requests
CREATE POLICY "managers_view_all_approval_requests" ON approval_requests
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND employees.permissions IN ('manager', 'admin', 'super_admin')
    )
  );

-- Employees can view approval requests for their own articles
CREATE POLICY "employees_view_own_approval_requests" ON approval_requests
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM articles
      WHERE articles.id = approval_requests.article_id
      AND articles.created_by = auth.uid()
    )
  );

-- Employees can create approval requests for their own articles
CREATE POLICY "employees_create_own_approval_requests" ON approval_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM articles
      WHERE articles.id = approval_requests.article_id
      AND articles.created_by = auth.uid()
    )
  );

-- Managers can update approval requests (approve/reject)
CREATE POLICY "managers_update_approval_requests" ON approval_requests
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND employees.permissions IN ('manager', 'admin', 'super_admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND employees.permissions IN ('manager', 'admin', 'super_admin')
    )
  ); 