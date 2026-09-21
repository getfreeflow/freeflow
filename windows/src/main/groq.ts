/// The optional cleanup pass. Everything else in FreeFlow runs on this machine;
/// this is the one place text leaves it, and only when a key is set.

const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';

interface Choice {
  message?: { content?: string };
}

export async function complete(
  apiKey: string,
  model: string,
  system: string,
  user: string
): Promise<string> {
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
    }),
    // A cleanup pass that hangs is worse than no cleanup: the words are already
    // waiting to be inserted.
    signal: AbortSignal.timeout(15_000),
  });

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    if (response.status === 429) throw new Error('Groq rate limit reached, using the raw transcript');
    if (response.status === 401) throw new Error('That Groq key was rejected');
    throw new Error(`Groq returned ${response.status}. ${detail.slice(0, 120)}`);
  }

  const body = (await response.json()) as { choices?: Choice[] };
  const text = body.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error('Groq returned nothing');
  return text;
}
