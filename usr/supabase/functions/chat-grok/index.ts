import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
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
  return { user: data.user, supabase }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  try {
    // 1. Auth Check
    const authResult = await getAuthedUser(req)
    if (!authResult || !authResult.user || authResult.user.role !== "authenticated") {
      return json({ error: "Unauthorized" }, 401)
    }
    const { user, supabase } = authResult

    // 2. Parse Input
    const body = await req.json().catch(() => null)
    let userMessage = ""
    
    // Fix: Handle both 'content' (Flutter) and 'messages' (Legacy) to prevent 400 error
    if (body.content) {
      userMessage = body.content
    } else if (body.messages && Array.isArray(body.messages)) {
      const lastMsg = body.messages[body.messages.length - 1]
      if (lastMsg.role === 'user') userMessage = lastMsg.content
    }

    if (!userMessage || typeof userMessage !== "string") {
      return json({ error: "content must be a non-empty string" }, 400)
    }

    // 3. Fetch Notes (Memory)
    const { data: notesData } = await supabase
      .from('notes')
      .select('content')
      .order('created_at', { ascending: true })
    
    // 4. Construct System Prompt
    // Base prompt without notes
    let systemPrompt = `You are Memo, a personal memory assistant.
Your goal is to chat with the user AND extract important personal information to save to their notes.

INSTRUCTIONS:
1. Answer the user's question or chat naturally.
2. If the user provides NEW personal information (e.g., "My name is Alice", "I like sushi"), extract it.
3. You MUST return a valid JSON object.

JSON FORMAT:
{
  "reply": "Your response...",
  "new_notes": ["Note 1"]
}`

    // Only inject notes if they exist
    if (notesData && notesData.length > 0) {
        const notesContext = notesData.map((n: any) => `- ${n.content}`).join('\n');
        systemPrompt = `You are Memo, a personal memory assistant.
Your goal is to chat with the user AND extract important personal information to save to their notes.

CURRENT NOTES (Memory):
${notesContext}

INSTRUCTIONS:
1. Answer the user's question or chat naturally based on the Current Notes.
2. If the user provides NEW personal information, extract it.
3. You MUST return a valid JSON object.

JSON FORMAT:
{
  "reply": "Your response...",
  "new_notes": ["Note 1"]
}`
    }

    const messages = [
      { role: "system", content: systemPrompt },
      { role: "user", content: userMessage }
    ]

    // 5. Call Grok
    const resp = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${grokKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-beta",
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
    const rawContent = data?.choices?.[0]?.message?.content
    if (!rawContent) return json({ error: "Empty response from AI" }, 500)

    // 6. Parse JSON Response
    let parsed;
    try {
      const cleanContent = rawContent.replace(/```json\n?|\n?```/g, "").trim();
      parsed = JSON.parse(cleanContent);
    } catch (e) {
      console.error("Failed to parse JSON:", rawContent)
      parsed = { reply: rawContent, new_notes: [] }
    }

    const reply = parsed.reply || rawContent
    const newNotes = Array.isArray(parsed.new_notes) ? parsed.new_notes : []

    // 7. Save New Notes
    let savedNotes = []
    if (newNotes.length > 0) {
      const notesToInsert = newNotes.map((note: string) => ({
        user_id: user.id,
        content: note
      }))
      
      const { data: insertedNotes } = await supabase
        .from('notes')
        .insert(notesToInsert)
        .select()
      
      if (insertedNotes) savedNotes = insertedNotes
    }

    return json({ reply, saved_notes: savedNotes })

  } catch (e: any) {
    return json({ error: String(e?.message ?? e) }, 500)
  }
})