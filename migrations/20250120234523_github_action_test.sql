-- Insert a test record with timestamp
INSERT INTO test_table (value) 
VALUES (CONCAT('GitHub Actions deployment test at ', CURRENT_TIMESTAMP::text));

-- Verify the insert and show timestamp
DO $$
DECLARE
    v_latest_record text;
BEGIN
    SELECT value INTO v_latest_record 
    FROM test_table 
    ORDER BY created_at DESC 
    LIMIT 1;
    
    RAISE NOTICE 'Latest test record: %', v_latest_record;
END $$;
