# Lugares con nombre (pin guardado)

Guarda la ubicación GPS actual con un nombre y, si quieres, la
comparte con el grupo o por WhatsApp.

## APPLY obligatorio (Wilson) — para que **Guardar** funcione

Supabase → proyecto `dgmzewsxbnwxjpnrtgyb` → **SQL Editor** → New query.

### 1) Tabla (si aún no):

Archivo: `supabase/migrations/20261102284000_named_places.sql`  
Éxito: `named_places_ok = true`

### 2) RPC (obligatorio para la app actual):

Archivo: `supabase/migrations/20261102284200_named_places_rpc.sql`  

O pega este SQL:

```sql
-- Ver archivo completo en el repo; éxito:
-- save_named_place_ok = true
```

Éxito: **`save_named_place_ok = true`**

Sin el RPC, Guardar muestra aviso de APPLY (WhatsApp sigue funcionando).

## Cómo usarlo

1. Mapa → botón **marcador**.
2. Nombre (ej. Casa).
3. Solo yo / Compartir con el grupo.
4. **Guardar** (nube + pin) o **WhatsApp** (texto + enlace mapas).
