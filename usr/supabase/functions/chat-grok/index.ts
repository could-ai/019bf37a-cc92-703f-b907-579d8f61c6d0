import "jsr:@supabase/functions-js/edge-runtime.d.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Get the request body
    const { messages } = await req.json()
    
    if (!messages) {
      return new Response(
        JSON.stringify({ error: 'Messages are required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 2. Get API Key
    const apiKey = Deno.env.get('GROK_API_KEY')
    if (!apiKey) {
      console.error('GROK_API_KEY is missing')
      return new Response(
        JSON.stringify({ error: 'Server configuration error: Missing API Key' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    console.log(`Sending ${messages.length} messages to Grok...`)

    // 3. Call Grok API
    const response = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'grok-2-latest', // Or 'grok-beta'
        messages: messages,
        stream: false,
        temperature: 0.7
      }),
    })

    // 4. Handle Grok API Response
    if (!response.ok) {
      const errorText = await response.text()
      console.error(`Grok API Error (${response.status}):`, errorText)
      
      // CRITICAL: Return 500 instead of 401 for upstream errors to avoid logging out the user
      return new Response(
        JSON.stringify({ 
          error: `AI Provider Error: ${response.status}`,
          details: errorText 
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    const data = await response.json()
    const reply = data.choices[0]?.message?.content

    if (!reply) {
      return new Response(
        JSON.stringify({ error: 'Empty response from AI' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // 5. Success
    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    console.error('Edge Function Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
