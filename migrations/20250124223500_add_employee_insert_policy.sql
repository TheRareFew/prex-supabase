-- Add insert policy for employees table
create policy "Users can insert their own employee record"
    on public.employees for insert
    to authenticated
    with check (auth.uid() = id);

-- Add update policy for employees to manage their own record
create policy "Users can update their own employee record"
    on public.employees for update
    to authenticated
    using (auth.uid() = id); 