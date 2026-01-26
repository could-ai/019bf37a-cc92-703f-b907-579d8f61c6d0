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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)

  try {
    // 1. Initialize Supabase Client with User's Auth Header
    // This uses the standard Supabase Auth mechanism (getUser) instead of manual JWT verification
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // 2. Verify User
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      console.error("Auth Error:", authError);
      return json({ error: "Unauthorized" }, 401);
    }

    // 3. Parse Request Body
    const body = await req.json().catch(() => ({}));
    const userContent = body.content; 

    if (!userContent || typeof userContent !== 'string') {
      return json({ error: "Missing or invalid 'content' field" }, 400);
    }

    // 4. Fetch User's Notes (Memory)
    // We fetch ALL notes as requested to provide full context
    const { data: notes, error: notesError } = await supabase
      .from('notes')
      .select('content')
      .order('created_at', { ascending: true });

    if (notesError) {
      console.error("Notes Fetch Error:", notesError);
      return json({ error: "Failed to fetch memory" }, 500);
    }

    const notesList = notes?.map(n => n.content) || [];
    const notesContext = notesList.length > 0 
      ? notesList.join("\n- ") 
      : "No previous notes.";

    // 5. Construct Prompt for Grok
    const systemPrompt = `You are Memo, an intelligent personal assistant.
    
YOUR GOAL:
1. Answer the user's message helpfully.
2. Identify if the user provided any NEW personal information, facts, or reminders that should be saved to memory.

CURRENT MEMORY (Notes):
- ${notesContext}

OUTPUT FORMAT:
You must respond in strict JSON format:
{
  "reply": "Your response to the user here.",
  "new_notes": ["Note 1", "Note 2"] 
}
If there are no new notes to save, "new_notes" should be an empty array [].
Do not include markdown formatting (like \`\`\`json). Just the raw JSON string.`;

    const messages = [
      { role: "system", content: systemPrompt },
      { role: "user", content: userContent }
    ];

    // 6. Call Grok API
    // Using grok-beta for better JSON support, or falling back to the fast model if needed.
    // Given the requirement for structured output, a smarter model is preferred.
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
        temperature: 0.3,
        response_format: { type: "json_object" }
      }),
    });

    if (!resp.ok) {
      const text = await resp.text();
      console.error("Grok API Error:", text);
      return json({ error: `AI Provider Error: ${resp.status}` }, 500);
    }

    const data = await resp.json();
    const rawContent = data?.choices?.[0]?.message?.content;

    if (!rawContent) return json({ error: "Empty response from AI" }, 500);

    // 7. Parse AI Response
    let parsedResponse;
    try {
      parsedResponse = JSON.parse(rawContent);
    } catch (e) {
      console.error("JSON Parse Error:", e, rawContent);
      // Fallback if AI didn't return JSON
      parsedResponse = { 
        reply: rawContent, 
        new_notes: [] 
      };
    }

    // 8. Save New Notes
    const newNotes = parsedResponse.new_notes;
    if (Array.isArray(newNotes) && newNotes.length > 0) {
      const notesToInsert = newNotes.map(note => ({
        user_id: user.id,
        content: note
      }));

      const { error: insertError } = await supabase
        .from('notes')
        .insert(notesToInsert);
      
      if (insertError) {
        console.error("Notes Insert Error:", insertError);
      }
    }

    return json({ 
      reply: parsedResponse.reply,
      saved_notes: newNotes 
    });

  } catch (e) {
    console.error("Server Error:", e);
    return json({ error: String(e?.message ?? e) }, 500);
  }
});