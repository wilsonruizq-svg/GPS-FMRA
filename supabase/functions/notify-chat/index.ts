// GPS-FMRA — Edge Function: push FCM al enviar mensaje de chat.
// Deploy: npx supabase functions deploy notify-chat
// Secrets: FIREBASE_SERVICE_ACCOUNT_JSON (+ SUPABASE_URL / SERVICE_ROLE inyectados)
//
// Body JSON: {
//   "group_id": "<uuid>",
//   "message_id": "<uuid>",
//   "sender_id": "<uuid>",
//   "display_name": "Nombre",
//   "body": "texto del mensaje"
// }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
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
      group_id?: string;
      message_id?: string;
      sender_id?: string;
      display_name?: string;
      body?: string;
    };

    const groupId = (body.group_id ?? "").trim();
    const senderId = (body.sender_id ?? "").trim();
    const messageId = (body.message_id ?? "").trim();
    const displayName = (body.display_name ?? "").trim() || "Integrante";
    const text = (body.body ?? "").trim() || "Nuevo mensaje";

    if (!groupId || !senderId) {
      return json({ ok: false, error: "missing_group_or_sender" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);

    const { data: members, error: memErr } = await admin
      .from("group_memberships")
      .select("user_id")
      .eq("group_id", groupId)
      .eq("status", "active")
      .neq("user_id", senderId);
    if (memErr) {
      return json({
        ok: false,
        error: "members_query_failed",
        detail: memErr.message,
      }, 500);
    }
    const peerIds = ((members ?? []) as Array<{ user_id: string }>).map(
      (m) => m.user_id,
    );
    if (peerIds.length === 0) {
      return json({ ok: true, sent: 0, reason: "no_peers" });
    }

    const { data: tokens, error: tokErr } = await admin
      .from("device_push_tokens")
      .select("user_id, token, platform")
      .in("user_id", peerIds);
    if (tokErr) {
      return json({
        ok: false,
        error: "token_query_failed",
        detail: tokErr.message,
      }, 500);
    }

    const list = (tokens ?? []) as Array<{ token: string; user_id: string }>;
    if (list.length === 0) {
      return json({ ok: true, sent: 0, reason: "no_peer_tokens" });
    }

    const accessToken = await getGoogleAccessToken(sa);
    const title = "Chat — GPS-FMRA";
    const preview = text.length > 120 ? `${text.slice(0, 117)}…` : text;
    const bodyText = `${displayName}: ${preview}`;

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
            type: "chat",
            group_id: groupId,
            message_id: messageId,
            sender_id: senderId,
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
            channelId: "chat_messages",
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
