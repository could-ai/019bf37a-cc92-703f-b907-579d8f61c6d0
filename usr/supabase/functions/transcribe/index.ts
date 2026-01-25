export default async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  try {
    const formData = await req.formData();
    const audioBlob = formData.get('audio');

    if (!audioBlob || !(audioBlob instanceof File)) {
      return new Response(JSON.stringify({ error: 'No audio file provided' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Forward to Puter API for transcription
    const puterFormData = new FormData();
    puterFormData.append('audio', audioBlob);

    const response = await fetch('https://api.puter.com/v1/transcribe', {
      method: 'POST',
      body: puterFormData,
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Puter API error:', errorText);
      return new Response(JSON.stringify({ error: 'Transcription failed', details: errorText }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const result = await response.json();
    const transcription = result.transcription || result.text || '';

    return new Response(JSON.stringify({ text: transcription }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Transcription error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
};