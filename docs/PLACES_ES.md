# Lugares con foto + categorías (carpetas)

Guarda la ubicación GPS con **nombre**, **detalle** y **foto**.  
Si eliges **Compartir con el grupo**, todos los miembros la ven en la
pestaña **Grupos**, **debajo** del grupo familiar (no dentro de
“Ver integrantes”).

Las **categorías** (Restaurantes, Negocios…) organizan ubicaciones y son
independientes del grupo de tracking familiar.

## APPLY (Wilson) — SQL Editor

Proyecto `dgmzewsxbnwxjpnrtgyb` → **SQL Editor** → New query.

1. Si falta la tabla base: `20261102284000_named_places.sql`
2. **Obligatorio ahora:**  
   `supabase/migrations/20261102284300_named_places_photos.sql`  
   → Run completo.  
   Éxito: **`named_places_photos_ok = true`**

Crea:

- `place_categories` (carpetas por `family_group`)
- columnas `description`, `photo_path`, `category_id` en `named_places`
- RPC `save_named_place` + `create_place_category`
- bucket Storage **`place-photos`**

## Uso

1. **Grupos** → debajo del grupo familiar → **Nueva carpeta** (ej. Restaurantes).
2. **Mapa** → marcador → nombre + detalle + foto → Compartir con el grupo →
   elige categoría → Guardar.
3. En **Grupos**, debajo del grupo: carpetas desplegables con foto/título/detalle.
4. Papelera para eliminar ubicación o categoría.
