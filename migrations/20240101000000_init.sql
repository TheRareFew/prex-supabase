-- Enable necessary extensions
create extension if not exists "uuid-ossp";

-- Create test table
CREATE TABLE test_table (
  id uuid default uuid_generate_v4() primary key,
  value TEXT NOT NULL,
  created_at timestamptz default now()
);

-- Add sample data
INSERT INTO test_table (value) VALUES ('test value');

-- Set up row level security
ALTER TABLE test_table ENABLE ROW LEVEL SECURITY;

-- Create policies for public read access
CREATE POLICY "Public profiles are viewable by everyone"
ON test_table FOR SELECT
USING ( true );

-- Create policies for authenticated users
CREATE POLICY "Authenticated users can insert their own data"
ON test_table FOR INSERT
TO authenticated
WITH CHECK ( true );

CREATE POLICY "Authenticated users can update their own data"
ON test_table FOR UPDATE
TO authenticated
USING ( true ); 