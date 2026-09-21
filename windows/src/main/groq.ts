/// The optional cleanup pass. Everything else in FreeFlow runs on this machine;
/// this is the one place text leaves it, and only when a key is set.

const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';

interface Choice {
  message?: { content?: string };
}

/// Groq retires models and moves others onto paid plans, and when that happens
/// every request with the old id fails. Rather than leave cleanup broken until
/// someone notices, a rejected model is retried once on a model a free key can
/// still reach.
const FALLBACK_MODEL = 'openai/gpt-oss-120b';

export async function complete(
  apiKey: string,
  model: string,
  system: string,
  user: string
): Promise<string> {
  try {
    return await request(apiKey, model, system, user);
  } catch (error) {
    if (error instanceof ModelUnavailable && model !== FALLBACK_MODEL) {
      return request(apiKey, FALLBACK_MODEL, system, user);
    }
    throw error;
  }
}

/// Thrown when Groq refuses the model itself, as opposed to the key or the text.
class ModelUnavailable extends Error {}

async function request(
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

    // A retired, renamed or plan-gated model comes back as a 404, or as a 400
    // naming the model. Either way the model is the problem, not the request.
    const aboutTheModel =
      response.status === 404 ||
      (response.status === 400 && /model/i.test(detail)) ||
      (response.status === 403 && /model/i.test(detail));
    if (aboutTheModel) {
      throw new ModelUnavailable(`Groq will not serve ${model}. ${detail.slice(0, 120)}`);
    }

    throw new Error(`Groq returned ${response.status}. ${detail.slice(0, 120)}`);
  }

  const body = (await response.json()) as { choices?: Choice[] };
  const text = body.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error('Groq returned nothing');
  return text;
}
