import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 1. Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 2. Parse body
    const { messages } = await req.json()

    // 3. Validate input
    if (!messages || !Array.isArray(messages)) {
      return new Response(
        JSON.stringify({ error: 'Messages array is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 4. Call Grok API
    const apiKey = Deno.env.get('GROK_API_KEY')
    if (!apiKey) {
      console.error('Missing GROK_API_KEY')
      return new Response(
        JSON.stringify({ error: 'Server configuration error: Missing API Key' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('Sending request to Grok API...')
    
    const response = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'grok-2-latest',
        messages: messages,
        stream: false
      }),
    })

    const data = await response.json()

    if (!response.ok) {
      console.error('Grok API Error:', data)
      // CRITICAL: Map 401 from Grok to 500 to avoid triggering client-side logout
      // The client interprets 401 as "User Session Expired", but here it means "Invalid API Key"
      const status = response.status === 401 ? 500 : response.status
      
      return new Response(
        JSON.stringify({ 
          error: `AI Provider Error (${response.status}): ${data.error?.message || 'Unknown error'}` 
        }),
        { status: status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. Return response
    const reply = data.choices[0]?.message?.content
    if (!reply) {
      return new Response(
        JSON.stringify({ error: 'No response from AI' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Function Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
