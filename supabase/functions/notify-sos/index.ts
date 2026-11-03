// GPS-FMRA — Edge Function: push FCM al emitir SOS.
// Deploy: supabase functions deploy notify-sos --no-verify-jwt  (o con JWT)
// Secrets: FIREBASE_SERVICE_ACCOUNT_JSON, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Body JSON: { "sos_id": "<uuid>" }  o  { "group_id": "...", "user_id": "...", "display_name": "..." }
// Invocable desde la app tras insertar sos_events.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type SosRow = {
  id: string;
  group_id: string;
  user_id: string;
  status: string;
  lat: number | null;
  lon: number | null;
  profiles?: { display_name?: string | null } | null;
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";

    if (!supabaseUrl || !serviceKey) {
      return json({ ok: false, error: "missing_supabase_env" }, 500);
    }
    if (!saRaw) {
      return json({
        ok: false,
        error: "missing_firebase_service_account",
        hint:
          "Define el secret FIREBASE_SERVICE_ACCOUNT_JSON (JSON de la cuenta de servicio Firebase).",
      }, 503);
    }

    let sa: ServiceAccount;
    try {
      sa = JSON.parse(saRaw) as ServiceAccount;
    } catch {
      return json({ ok: false, error: "invalid_firebase_service_account" }, 500);
    }

    const body = await req.json().catch(() => ({})) as {
      sos_id?: string;
      group_id?: string;
      user_id?: string;
      display_name?: string;
    };

    const admin = createClient(supabaseUrl, serviceKey);

    let groupId = body.group_id ?? "";
    let senderId = body.user_id ?? "";
    let displayName = body.display_name?.trim() || "Integrante";
    let sosId = body.sos_id ?? "";
    let lat: number | null = null;
    let lon: number | null = null;

    if (sosId) {
      const { data, error } = await admin
        .from("sos_events")
        .select(
          "id, group_id, user_id, status, lat, lon, profiles(display_name)",
        )
        .eq("id", sosId)
        .maybeSingle();
      if (error || !data) {
        return json({ ok: false, error: "sos_not_found", detail: error?.message }, 404);
      }
      const row = data as SosRow;
      if (row.status !== "active") {
        return json({ ok: true, skipped: "not_active" });
      }
      groupId = row.group_id;
      senderId = row.user_id;
      sosId = row.id;
      lat = row.lat;
      lon = row.lon;
      const n = row.profiles?.display_name?.trim();
      if (n) displayName = n;
    }

    if (!groupId || !senderId) {
      return json({ ok: false, error: "missing_group_or_user" }, 400);
    }

    // service_role bypasses RLS — list active peers then their FCM tokens.
    const { data: members, error: memErr } = await admin
      .from("group_memberships")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("status", "active")
      .neq("user_id", senderId);
    if (memErr) {
      return json({ ok: false, error: "members_query_failed", detail: memErr.message }, 500);
    }
    const peerIds = ((members ?? []) as Array<{ user_id: string }>).map((m) =>
      m.user_id
    );
    if (peerIds.length === 0) {
      return json({ ok: true, sent: 0, reason: "no_peers" });
    }

    const { data: tokens, error: tokErr } = await admin
      .from("device_push_tokens")
      .select("user_id, token, platform")
      .in("user_id", peerIds);
    if (tokErr) {
      return json({ ok: false, error: "token_query_failed", detail: tokErr.message }, 500);
    }

    const list = (tokens ?? []) as Array<{ token: string; user_id: string }>;
    if (list.length === 0) {
      return json({ ok: true, sent: 0, reason: "no_peer_tokens" });
    }

    const accessToken = await getGoogleAccessToken(sa);
    const title = "SOS — GPS-FMRA";
    const bodyText = `¡SOS! ${displayName} necesita ayuda.`;

    let sent = 0;
    const failures: string[] = [];
    for (const row of list) {
      try {
        await sendFcmV1({
          projectId: sa.project_id,
          accessToken,
          deviceToken: row.token,
          title,
          body: bodyText,
          data: {
            type: "sos",
            sos_id: sosId || "",
            group_id: groupId,
            user_id: senderId,
            lat: lat?.toString() ?? "",
            lon: lon?.toString() ?? "",
          },
        });
        sent += 1;
      } catch (e) {
        failures.push(`${row.user_id}: ${(e as Error).message}`);
      }
    }

    return json({ ok: true, sent, failed: failures.length, failures });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message }, 500);
  }
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`oauth_token_${res.status}`);
  }
  const data = await res.json() as { access_token?: string };
  if (!data.access_token) throw new Error("oauth_missing_access_token");
  return data.access_token;
}

async function sendFcmV1(args: {
  projectId: string;
  accessToken: string;
  deviceToken: string;
  title: string;
  body: string;
  data: Record<string, string>;
}) {
  const url =
    `https://fcm.googleapis.com/v1/projects/${args.projectId}/messages:send`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${args.accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token: args.deviceToken,
        notification: {
          title: args.title,
          body: args.body,
        },
        data: args.data,
        android: {
          priority: "HIGH",
          notification: {
            channelId: "sos_alerts",
            priority: "HIGH",
            defaultSound: true,
          },
        },
      },
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`fcm_${res.status}:${text.slice(0, 180)}`);
  }
}

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(cleaned);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}
