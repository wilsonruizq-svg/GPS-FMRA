# Lugares con nombre (pin guardado)

Guarda la ubicación GPS actual con un nombre y, si quieres, la
comparte con el grupo.

## APPLY (Wilson)

1. Supabase → proyecto `dgmzewsxbnwxjpnrtgyb` → **SQL Editor**.
2. Copia todo:
   `supabase/migrations/20261102284000_named_places.sql`
3. **Run** → debe verse `named_places_ok = true`.

## Cómo usarlo en la app

1. En **Mapa**, toca el botón de **marcador** (junto a SOS / Mi ubicación).
2. Escribe un nombre (ej. «Casa», «Trabajo»).
3. Elige **Solo yo** o **Compartir con el grupo**.
4. Guardar. Aparece el pin con el nombre en el mapa.

Sin el SQL, la app mostrará aviso de APPLY.
