import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Check for API Key (Groq is used here for free/fast Whisper access)
    // You can get a free key at https://console.groq.com/keys
    const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY')
    
    // Fallback or Error if no key
    if (!GROQ_API_KEY) {
      return new Response(
        JSON.stringify({ 
          error: 'Missing GROQ_API_KEY. Please set it in Supabase Dashboard -> Edge Functions -> Secrets.',
          is_config_error: true 
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // 2. Parse the uploaded file
    const formData = await req.formData()
    const audioFile = formData.get('audio')

    if (!audioFile) {
      throw new Error('No audio file uploaded')
    }

    // 3. Prepare request to Groq API (OpenAI compatible)
    const groqFormData = new FormData()
    groqFormData.append('file', audioFile)
    groqFormData.append('model', 'whisper-large-v3') // State-of-the-art open model
    groqFormData.append('response_format', 'json')

    console.log('Sending audio to Groq API...')

    const response = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${GROQ_API_KEY}`,
      },
      body: groqFormData,
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error('Groq API Error:', errorText)
      throw new Error(`Groq API Error: ${response.status} ${errorText}`)
    }

    const data = await response.json()
    console.log('Transcription success:', data.text)

    // 4. Return the text
    return new Response(JSON.stringify({ text: data.text }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('Function Error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
