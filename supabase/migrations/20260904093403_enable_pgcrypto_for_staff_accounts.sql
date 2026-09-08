/*
# Enable pgcrypto for staff account password hashing

1. Purpose
- Install the PostgreSQL `pgcrypto` extension required by the existing staff account functions.
- Restores the `gen_salt()` and `crypt()` helpers used when administrators create or update team accounts.

2. Tables and columns
- No tables or columns are created or modified.

3. Security
- No RLS policies are changed.
- The extension only provides database cryptographic helpers; existing admin-only function checks remain unchanged.

4. Important notes
- This is a non-destructive compatibility fix for the existing account-management flow.
- It resolves the error shown when the team controller attempts to create or update a staff account.
*/

CREATE EXTENSION IF NOT EXISTS pgcrypto;