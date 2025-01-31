-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "http" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";

-- Create required ENUM types if not exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_sender_type') THEN
        CREATE TYPE message_sender_type AS ENUM ('employee', 'customer');
    END IF;
END $$;

-- Create required tables if not exist
CREATE TABLE IF NOT EXISTS bots (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- Insert default bot if not exists
INSERT INTO bots (id, name)
VALUES ('00000000-0000-0000-0000-000000000000', 'AI Bot')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS tickets (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    resolved boolean DEFAULT false,
    status text DEFAULT 'fresh',
    priority text DEFAULT 'low',
    category text DEFAULT 'general',
    assigned_to uuid,
    created_by uuid
);

-- Create messages table if not exists
CREATE TABLE IF NOT EXISTS messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id uuid REFERENCES tickets(id),
    created_by uuid REFERENCES auth.users(id),
    bot_id uuid REFERENCES bots(id),
    sender_type message_sender_type,
    created_at timestamptz DEFAULT now(),
    message text,
    is_system_message boolean DEFAULT false,
    CONSTRAINT message_source_check CHECK (
        (created_by IS NOT NULL AND bot_id IS NULL) OR
        (created_by IS NULL AND bot_id IS NOT NULL)
    )
);

-- Enable realtime for tables
ALTER PUBLICATION supabase_realtime ADD TABLE tickets;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS handle_customer_message_webhook ON messages;

-- Create webhook function
CREATE OR REPLACE FUNCTION handle_customer_message()
RETURNS TRIGGER AS $$
DECLARE
  is_bot_assigned BOOLEAN;
BEGIN
  -- Check if ticket is assigned to a bot
  SELECT EXISTS (
    SELECT 1 
    FROM tickets t
    JOIN bots b ON t.assigned_to = b.id
    WHERE t.id = NEW.ticket_id
  ) INTO is_bot_assigned;

  -- Only proceed if message is from customer, not system, and ticket assigned to bot
  IF NEW.sender_type = 'customer' 
     AND NOT NEW.is_system_message 
     AND is_bot_assigned THEN
    
    -- Call webhook using net.http_post
    PERFORM net.http_post(
      -- URL (use host.docker.internal for local dev)
      url := 'http://host.docker.internal:54321/functions/v1/handle-message',
      -- Headers must be jsonb
      headers := '{"Content-Type": "application/json"}'::jsonb,
      -- Body must be jsonb
      body := jsonb_build_object(
        'message_id', NEW.id,
        'ticket_id', NEW.ticket_id,
        'message', NEW.message,
        'user_id', NEW.created_by
      )
    );

    -- Log for debugging
    RAISE LOG 'Webhook sent for message_id: % (ticket assigned to bot)', NEW.id;
  ELSE
    -- Log why webhook not sent
    IF NOT (NEW.sender_type = 'customer' AND NOT NEW.is_system_message) THEN
      RAISE LOG 'Webhook not sent: not customer message or is system message';
    ELSIF NOT is_bot_assigned THEN
      RAISE LOG 'Webhook not sent: ticket not assigned to bot';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
CREATE TRIGGER handle_customer_message_webhook
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_message();

-- Drop existing assigned_to constraint if exists
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'tickets_assigned_to_fkey'
    ) THEN
        ALTER TABLE tickets DROP CONSTRAINT tickets_assigned_to_fkey;
    END IF;
END $$;

-- Add proper foreign key constraint
ALTER TABLE tickets 
ADD CONSTRAINT tickets_assigned_to_fkey 
FOREIGN KEY (assigned_to) 
REFERENCES bots(id);

-- Create function to ensure bot exists
CREATE OR REPLACE FUNCTION ensure_bot_exists()
RETURNS TRIGGER AS $$
BEGIN
  -- If assigned_to is set and points to a bot that doesn't exist
  IF NEW.assigned_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM bots WHERE id = NEW.assigned_to
  ) THEN
    -- Create the bot
    INSERT INTO bots (id, name)
    VALUES (NEW.assigned_to, 'Support Bot ' || NEW.assigned_to)
    ON CONFLICT (id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to ensure bot exists before ticket insert/update
CREATE TRIGGER ensure_bot_exists_trigger
BEFORE INSERT OR UPDATE ON tickets
FOR EACH ROW
EXECUTE FUNCTION ensure_bot_exists();

-- Add RLS policies for bots table
ALTER TABLE bots ENABLE ROW LEVEL SECURITY;

-- Viewable by all authenticated users
CREATE POLICY "Bots are viewable by all users"
  ON bots FOR SELECT
  TO authenticated
  USING (true);

-- Allow inserts from triggers
CREATE POLICY "Bots can be inserted by triggers"
  ON bots FOR INSERT
  TO authenticated
  WITH CHECK (true);
