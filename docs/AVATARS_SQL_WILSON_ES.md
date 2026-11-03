# Foto de perfil — SQL para Wilson (ERROR 42501)

## Qué pasó

Al correr `20261102250000_avatars_storage.sql` apareció:

`ERROR: 42501: must be owner of table objects`

Eso lo provocaba un `COMMENT ON storage.objects` (en hosted no eres dueño
de esa tabla). **sos_events** y **device_push_tokens** no dependen de esto;
si ya los aplicaste, están bien.

## Qué correr ahora

Archivo nuevo (seguro en SQL Editor hosted):

**`supabase/migrations/20261102251000_avatars_storage_hosted.sql`**

Pasos:

1. Abre [Supabase](https://supabase.com/dashboard) → tu proyecto → **SQL Editor** → **New query**.
2. Abre el archivo de arriba en el PC, copia **todo** el contenido.
3. Pégalo en el editor → **Run**.
4. Éxito esperado: **Success. No rows returned** (a veces muestra 1 fila del bucket).
5. Ve a **Storage → Buckets** y confirma que existe **`avatars`** (Public).
6. En la app: Ajustes → Perfil → Añadir foto de nuevo.

No hace falta volver a aplicar `sos_events` ni `device_push_tokens`.
