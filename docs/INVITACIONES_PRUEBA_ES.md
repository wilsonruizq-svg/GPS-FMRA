# Probar invitaciones (Fase 1) — dos cuentas

Requisito: aplicar en Supabase la migración
`supabase/migrations/20261102200000_accept_invitation_rpc.sql`
(ver `supabase/APPLY_ES.md`).

## Cuentas

| Rol en la prueba | Acción |
|------------------|--------|
| **Cuenta A** (admin) | Crea el grupo e invita |
| **Cuenta B** (integrante) | Acepta el código y se une |

Usa dos correos distintos (o un emulador + un teléfono).
Si “Confirm email” está activo, desactívalo para pruebas (APPLY_ES.md).

## Pasos

1. **Cuenta A** — inicia sesión → pestaña **Grupos** → **Crear grupo**
   (ej. `Familia prueba`).
2. En el detalle del grupo deberías ver “Eres admin…”.
3. Pulsa el icono **Invitar** → copia el **código** o el **enlace**
   `gpsfmra://invite/…`.
4. Cierra sesión (Ajustes).
5. **Cuenta B** — crea cuenta / inicia sesión → **Grupos** →
   **Unirme con código** → pega el código o el enlace → **Aceptar invitación**.
6. B debe ver el grupo y el rol **Integrante**.
7. Vuelve a **Cuenta A** → abre el grupo → B aparece en la lista.
8. (Opcional) Reutiliza el mismo código con otra cuenta: debe fallar
   (“ya fue usada”).

## Qué valida

- Token en claro solo en UI; en BD solo `token_hash`.
- Un uso + caducidad (7 días).
- Join con rol `member`; el creador sigue como `group_admin`.
- RLS: solo admin genera invitaciones; aceptación vía RPC `accept_invitation`.
