import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the API key from secrets
    const apiKey = Deno.env.get('DEEPGRAM_API_KEY')
    if (!apiKey) {
      return new Response(
        JSON.stringify({ 
          error: 'DEEPGRAM_API_KEY is not set', 
          is_config_error: true 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse the multipart form data to get the audio file
    const formData = await req.formData()
    const audioFile = formData.get('audio')
    
    if (!audioFile) {
      throw new Error('No audio file found in request')
    }

    // Deepgram API Endpoint for pre-recorded audio
    // using nova-2 model which is fast and accurate
    const deepgramUrl = 'https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true'
    
    console.log('Sending audio to Deepgram...')

    const response = await fetch(deepgramUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Token ${apiKey}`,
        'Content-Type': audioFile.type || 'audio/wav', 
      },
      body: audioFile,
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error('Deepgram API error:', errorText)
      throw new Error(`Deepgram API error: ${response.status} ${errorText}`)
    }

    const data = await response.json()
    
    // Extract transcript from Deepgram response
    // Structure: results.channels[0].alternatives[0].transcript
    const transcript = data.results?.channels?.[0]?.alternatives?.[0]?.transcript || ''

    return new Response(
      JSON.stringify({ text: transcript }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Function error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
