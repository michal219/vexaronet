-- Vexaronet: nahravani obrazku (web, e-shop). Verejne cteni, zapis jen clenove firmy do slozky sve firmy.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('site-images','site-images',true,3145728,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public=true,file_size_limit=3145728,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif'];
drop policy if exists si_insert on storage.objects;
create policy si_insert on storage.objects for insert to authenticated
 with check (bucket_id='site-images' and exists (select 1 from public.company_members m where m.user_id=auth.uid() and m.role in ('owner','admin') and m.company_id::text=(storage.foldername(name))[1]));
drop policy if exists si_delete on storage.objects;
create policy si_delete on storage.objects for delete to authenticated
 using (bucket_id='site-images' and exists (select 1 from public.company_members m where m.user_id=auth.uid() and m.role in ('owner','admin') and m.company_id::text=(storage.foldername(name))[1]));
