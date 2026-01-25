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
    // Get the request body
    const { messages } = await req.json()
    
    // Get the API key from secrets
    const apiKey = Deno.env.get('GROK_API_KEY')
    if (!apiKey) {
      console.error('GROK_API_KEY is not set')
      return new Response(
        JSON.stringify({ error: 'Server configuration error: API Key missing' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Call Grok API
    // Using 'grok-2-latest' as it is the current stable model, or fallback to 'grok-beta'
    const response = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'grok-2-latest', 
        messages: messages,
        temperature: 0.7,
      }),
    })

    const data = await response.json()

    if (!response.ok) {
      console.error('Grok API Error:', data)
      return new Response(
        JSON.stringify({ error: `Grok API Error: ${data.error?.message || response.statusText}` }),
        { status: response.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract the reply
    const reply = data.choices?.[0]?.message?.content
    if (!reply) {
      throw new Error('Invalid response format from Grok API')
    }

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )

  } catch (error) {
    console.error('Function Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
