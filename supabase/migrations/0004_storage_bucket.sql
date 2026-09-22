-- Storage for certificates and prize photos.
--
-- The bucket is private. Nothing is world-readable: the API issues a
-- short-lived signed URL when an advisor or the HOD opens a file, so a leaked
-- object key on its own is useless.
--
-- Uploads go through the API rather than straight from the phone, so the file
-- is checked - size, type, and that the caller owns the OD - before it is
-- stored. That is why there are no permissive policies here: only the service
-- role touches this bucket, and the service role key never leaves the server.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'od-files',
  'od-files',
  false,
  10485760,  -- 10 MB, matching the result_files check constraint
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Object keys are laid out as od/<od_request_id>/<kind>/<uuid>.<ext> so
-- everything belonging to one request can be found, and removed, together.
comment on table result_files is
  'Metadata for files in the od-files storage bucket. The bytes live in storage; object_key points at them.';
