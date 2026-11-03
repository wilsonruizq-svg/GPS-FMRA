# PIN de salida del grupo (modo quiosco)

El **admin del grupo familiar** puede configurar un PIN numérico. Mientras
esté activo, los integrantes (y el propio admin) deben introducirlo para:

- **Cerrar sesión** (Ajustes → Cerrar sesión)
- **Salir con el botón Atrás** del sistema cuando estás en la pantalla
  principal (mapa / grupos / ajustes)

Es un bloqueo suave de app: no impide forzar cierre desde el sistema
Android ni desinstalar.

## Cómo lo configura Wilson (admin)

1. Aplica la migración SQL si aún no está en Supabase:
   `supabase/migrations/20261102220000_group_exit_pin.sql`
   (ver `supabase/APPLY_ES.md`).
2. Abre la app e inicia sesión con la cuenta admin.
3. Ve a **Grupos** → toca tu grupo familiar.
4. En la sección **PIN de salida**:
   - **Configurar PIN de salida** → elige 4–8 dígitos → confirma → Guardar.
   - Para cambiarlo: **Cambiar PIN de salida**.
   - Para desactivarlo: **Quitar PIN de salida**.
5. Comparte el PIN solo con quien deba poder salir / cerrar sesión.

El PIN **nunca se guarda en claro**: Supabase lo hashea con bcrypt
(`crypt` / `gen_salt('bf')`) en las RPC `set_group_exit_pin` /
`verify_exit_pin`.

## Si no pide PIN

- El grupo aún no tiene PIN configurado, o
- Falta aplicar la migración `20261102220000_group_exit_pin.sql`.
