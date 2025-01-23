-- Drop all policies
DO $$ 
DECLARE 
    r RECORD;
BEGIN
    FOR r IN (SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

-- Drop all tables
DROP TABLE IF EXISTS "public"."messages" CASCADE;
DROP TABLE IF EXISTS "public"."tickets" CASCADE;
DROP TABLE IF EXISTS "public"."employees" CASCADE;
DROP TABLE IF EXISTS "public"."customers" CASCADE;

-- Drop all views
DROP VIEW IF EXISTS "public"."employee_profiles" CASCADE;

-- Drop all functions
DROP FUNCTION IF EXISTS "public"."update_updated_at_column" CASCADE;

-- Drop all types
DROP TYPE IF EXISTS "public"."department_type" CASCADE;
DROP TYPE IF EXISTS "public"."permission_type" CASCADE;
DROP TYPE IF EXISTS "public"."shift_type" CASCADE;
DROP TYPE IF EXISTS "public"."ticket_category_type" CASCADE;
DROP TYPE IF EXISTS "public"."ticket_priority_type" CASCADE;
DROP TYPE IF EXISTS "public"."ticket_status_type" CASCADE; 