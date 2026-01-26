import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*", // 生产建议换成你的域名
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
const grokKey = Deno.env.get("GROK_API_KEY") ?? ""

if (!supabaseUrl || !anonKey) throw new Error("Missing SUPABASE_URL or SUPABASE_ANON_KEY")
if (!grokKey) throw new Error("Missing GROK_API_KEY")

const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })

async function getAuthedUser(req: Request) {
  const authHeader = req.headers.get("Authorization") || req.headers.get("authorization")
  if (!authHeader?.toLowerCase().startsWith("bearer ")) return null

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })

  const { data, error } = await supabase.auth.getUser()
  if (error) return null
  return data.user ?? null
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  try {
    const user = await getAuthedUser(req)
    if (!user || user.role !== "authenticated") return json({ error: "Unauthorized" }, 401)

    const body = await req.json().catch(() => null)
    const messages = body?.messages

    if (!Array.isArray(messages) || messages.length === 0) {
      return json({ error: "messages must be a non-empty array" }, 400)
    }
    if (messages.length > 50) {
      return json({ error: "too many messages" }, 400)
    }

    // 可选：限制每条 content 长度，避免巨大 payload
    for (const m of messages) {
      if (!m || typeof m !== "object") return json({ error: "invalid message" }, 400)
      if (typeof m.role !== "string" || typeof m.content !== "string") return json({ error: "invalid message shape" }, 400)
      if (m.content.length > 8000) return json({ error: "message too long" }, 400)
    }

    const resp = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${grokKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-4",
        messages,
        stream: false,
        temperature: 0.7,
      }),
    })

    if (!resp.ok) {
      const text = await resp.text()
      return json({ error: `AI Provider Error: ${resp.status}`, details: text }, 500)
    }

    const data = await resp.json()
    const reply = data?.choices?.[0]?.message?.content
    if (!reply) return json({ error: "Empty response from AI" }, 500)

    return json({ reply })
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500)
  }
})
