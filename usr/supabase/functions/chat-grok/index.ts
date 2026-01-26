import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'
import * as jose from "jsr:@panva/jose@6"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// JWT Verification Setup
const jwks = jose.createRemoteJWKSet(
  new URL(`${Deno.env.get("SUPABASE_URL")}/auth/v1/.well-known/jwks.json`)
)
const issuer = Deno.env.get("SB_JWT_ISSUER") ?? `${Deno.env.get("SUPABASE_URL")}/auth/v1`

async function requireUser(req: Request) {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader) throw new Error("Missing Authorization header")
  
  const token = authHeader.split(" ")[1]
  if (!token) throw new Error("Missing Bearer token")

  try {
    const { payload } = await jose.jwtVerify(token, jwks, { issuer })
    return payload // contains sub (user_id), role, etc.
  } catch (err) {
    console.error("JWT Verification failed:", err)
    throw new Error("Invalid JWT")
  }
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Verify User
    const user = await requireUser(req)
    const userId = user.sub

    // 2. Parse Input
    const { content } = await req.json()
    if (!content) {
      throw new Error("Missing 'content' in request body")
    }

    // 3. Setup Supabase Admin Client (to access DB)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 4. Fetch User's Notes (Memory)
    const { data: notesData, error: notesError } = await supabase
      .from('notes')
      .select('content')
      .eq('user_id', userId)
    
    if (notesError) throw new Error(`Failed to fetch notes: ${notesError.message}`)
    
    const notesList = notesData?.map(n => n.content) || []
    const notesContext = notesList.length > 0 
      ? notesList.map((n, i) => `- ${n}`).join('\n') 
      : "No notes yet."

    // 5. Call Grok API
    const grokApiKey = Deno.env.get('GROK_API_KEY')
    if (!grokApiKey) throw new Error("GROK_API_KEY is not set")

    const systemPrompt = `You are Memo, a personal memory assistant.
You have access to the user's personal notes.
Your goal is to answer the user's request based on these notes, AND to extract any new personal information to save.

Current Notes:
${notesContext}

Instructions:
1. Analyze the User Input.
2. If the user provides NEW information (facts, preferences, events, plans) that is not already in the notes, extract it.
3. If the user asks a question, answer it using the Current Notes.
4. You MUST return a JSON object with this exact structure:
{
  "reply": "Your conversational response to the user",
  "new_notes": ["extracted note 1", "extracted note 2"]
}
If there are no new notes to save, "new_notes" should be an empty list [].
Do not output markdown code blocks. Output raw JSON only.`

    const response = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${grokApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'grok-beta', // or grok-2-latest
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: content }
        ],
        temperature: 0.3, // Lower temperature for more consistent JSON
        stream: false
      }),
    })

    if (!response.ok) {
      const errText = await response.text()
      throw new Error(`Grok API Error: ${response.status} ${errText}`)
    }

    const aiData = await response.json()
    const aiContent = aiData.choices[0]?.message?.content

    if (!aiContent) throw new Error("Empty response from AI")

    // 6. Parse AI Response (JSON)
    let parsedResponse
    try {
      // Clean up potential markdown code blocks if the AI adds them
      const cleanJson = aiContent.replace(/```json\n?|\n?```/g, '').trim()
      parsedResponse = JSON.parse(cleanJson)
    } catch (e) {
      console.error("Failed to parse JSON from AI:", aiContent)
      // Fallback if JSON parsing fails
      parsedResponse = { 
        reply: aiContent, 
        new_notes: [] 
      }
    }

    // 7. Save New Notes
    if (parsedResponse.new_notes && Array.isArray(parsedResponse.new_notes) && parsedResponse.new_notes.length > 0) {
      const notesToInsert = parsedResponse.new_notes.map((note: string) => ({
        user_id: userId,
        content: note
      }))
      
      const { error: insertError } = await supabase
        .from('notes')
        .insert(notesToInsert)
      
      if (insertError) {
        console.error("Failed to save notes:", insertError)
        // We don't fail the request, just log it
      }
    }

    // 8. Return Response
    return new Response(JSON.stringify({ 
      reply: parsedResponse.reply,
      saved_notes: parsedResponse.new_notes 
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error: any) {
    console.error("Edge Function Error:", error)
    
    // Return 500 for internal errors, but 401 only for JWT issues
    const status = error.message === "Invalid JWT" || error.message === "Missing Authorization header" ? 401 : 500
    
    return new Response(JSON.stringify({ error: error.message }), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
