-- Weekly Reveal ciphertext objects are immutable after their first upload.
-- Exact publish retries recover through the metadata RPC and never overwrite
-- an existing object.

drop policy if exists "weekly reveal: author upserts" on storage.objects;
