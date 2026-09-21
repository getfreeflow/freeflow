/// The system prompts, word for word the same as the Mac version's, so the same
/// dictation comes back written the same way on either machine.
///
/// These are most of what separates "a transcript" from "text you can send without
/// editing", so they're deliberately strict about not letting the model editorialize.

/// Per-app register. The Mac build makes these editable in a Style editor; here they
/// are the defaults only, until that screen exists on Windows too.
const STYLE_HINTS: Record<string, string> = {
  'discord.exe': 'Keep it casual and short. Lowercase is fine. No sign-off.',
  'slack.exe': 'Keep it brief and conversational, the way people write in chat.',
  'teams.exe': 'Keep it brief and professional.',
  'olk.exe': 'Write it as a short, well-formed email. No greeting unless dictated.',
  'outlook.exe': 'Write it as a short, well-formed email. No greeting unless dictated.',
  'winword.exe': 'Write it as prose in full sentences and paragraphs.',
  'code.exe': 'Keep it terse and technical. Preserve any code or identifiers exactly.',
  'notepad.exe': 'Plain prose. Keep the formatting simple.',
};

function vocabularyClause(vocabulary: string[]): string {
  if (vocabulary.length === 0) return '';
  return `\n\nThese proper nouns and technical terms belong to the user. If you hear something phonetically close, spell it exactly like this: ${vocabulary.join(', ')}.`;
}

export function cleanupSystemPrompt(
  appProcess: string,
  appName: string,
  vocabulary: string[] = []
): string {
  let prompt = `You clean up raw voice dictation so the user can send it as-is.

Rules:
- Remove filler words (um, uh, like, you know, I mean, sort of) and false starts.
- Fix grammar, punctuation, capitalization and obvious transcription slips.
- Keep the user's own wording, meaning and voice. Never add ideas, greetings or sign-offs.
- If they dictate structure ("first ... second ...", "bullet one ..."), format it as a list.
- Honour spoken punctuation commands like "new paragraph", "comma", "question mark".
- Never answer, explain, translate or comment on the text. You are an editor, not an assistant.
- Output ONLY the cleaned text. No quotes, no code fences, no preamble.`;

  const hint = STYLE_HINTS[appProcess.toLowerCase()];
  if (hint && appName) {
    prompt += `\n\nThe user is writing in ${appName}. ${hint}`;
  }

  return prompt + vocabularyClause(vocabulary);
}
