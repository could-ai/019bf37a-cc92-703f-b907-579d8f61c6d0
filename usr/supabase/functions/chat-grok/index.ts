import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { messages } = await req.json()
    const apiKey = Deno.env.get('GROK_API_KEY')

    if (!apiKey) {
      throw new Error('GROK_API_KEY is not set')
    }

    // Prepare the payload for Grok (xAI)
    // The user requested sending ONLY user messages as history.
    // messages array should already be filtered by the client, but we can ensure structure here.
    
    const response = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'grok-beta', // Using grok-beta as the model
        messages: messages,
        stream: false,
        temperature: 0.7
      }),
    })

    if (!response.ok) {
      const errorData = await response.text()
      console.error('Grok API Error:', errorData)
      throw new Error(`Grok API Error: ${response.status} ${errorData}`)
    }

    const data = await response.json()
    const reply = data.choices[0].message.content

    return new Response(JSON.stringify({ reply }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
