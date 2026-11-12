# Lugares con nombre (pin guardado)

Guarda la ubicación GPS actual con un nombre y, si quieres, la
comparte con el grupo.

## APPLY (Wilson)

1. Supabase → proyecto `dgmzewsxbnwxjpnrtgyb` → **SQL Editor**.
2. Copia todo:
   `supabase/migrations/20261102284000_named_places.sql`
3. **Run** → debe verse `named_places_ok = true`.
4. Si **Guardar** falla (RLS) aunque el paso 3 fue OK, corre también:
   `supabase/migrations/20261102284100_named_places_rls_fix.sql`
   → `named_places_rls_ok = true`.
5. Recomendado (RPC estable): 
   `supabase/migrations/20261102284200_named_places_rpc.sql`
   → `save_named_place_ok = true`.

## Cómo usarlo en la app

1. En **Mapa**, toca el botón de **marcador** (junto a SOS / Mi ubicación).
2. Escribe un nombre (ej. «Casa», «Trabajo»).
3. Elige **Solo yo** o **Compartir con el grupo**.
4. **Guardar** (pin en el mapa) o **WhatsApp** (abre chat con nombre + enlace de mapas).

Sin el SQL, la app mostrará aviso de APPLY al guardar en la nube.
