/** S-NIAH (Single Needle in a Haystack) dataset generator. */

export interface EvalTask {
  id: string;
  query: string;
  context: string;
  expectedAnswer: string;
  metadata?: Record<string, unknown>;
}

// Word list for generating filler text
const FILLER_WORDS = [
  "The", "committee", "discussed", "various", "aspects", "of", "the",
  "proposed", "development", "plan", "including", "budget", "allocations",
  "timeline", "estimates", "resource", "requirements", "and", "potential",
  "risks", "associated", "with", "implementation", "across", "multiple",
  "departments", "throughout", "organization", "Several", "members",
  "raised", "concerns", "about", "feasibility", "while", "others",
  "expressed", "optimism", "regarding", "expected", "outcomes", "in",
  "quarterly", "review", "session", "management", "presented", "findings",
  "from", "recent", "analysis", "conducted", "by", "external",
  "consultants", "who", "recommended", "strategic", "approach", "for",
  "achieving", "long", "term", "objectives", "set", "forth", "previous",
  "fiscal", "year", "planning", "documents", "were", "reviewed",
  "updated", "reflect", "current", "market", "conditions", "regulatory",
  "changes", "that", "could", "impact", "operations", "going", "forward",
  "into", "next", "period", "After", "thorough", "deliberation",
  "group", "agreed", "proceed", "with", "modified", "version",
  "original", "proposal", "incorporating", "feedback", "received",
  "during", "stakeholder", "engagement", "sessions", "held", "over",
  "past", "several", "weeks", "Additional", "research", "was",
  "requested", "to", "address", "remaining", "questions", "before",
  "final", "decision", "can", "be", "made",
];

// Project names for needle generation
const PROJECT_NAMES = [
  "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
  "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima",
  "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo",
  "Sierra", "Tango", "Uniform", "Victor", "Whiskey", "Xray",
];

// Code words for needle generation
const CODE_ADJECTIVES = [
  "crimson", "azure", "golden", "silver", "emerald", "cobalt",
  "amber", "violet", "scarlet", "onyx", "ivory", "jade",
  "coral", "sapphire", "bronze", "copper", "pearl", "ruby",
];

const CODE_NOUNS = [
  "falcon", "phoenix", "dragon", "eagle", "wolf", "panther",
  "hawk", "tiger", "cobra", "viper", "orca", "raven",
  "fox", "lion", "bear", "shark", "condor", "mantis",
];

// Default context lengths in characters
export const DEFAULT_CONTEXT_LENGTHS = [8192, 16384, 32768, 65536, 131072, 262144];

/**
 * Simple seeded pseudo-random number generator (mulberry32).
 * Deterministic for reproducibility.
 */
function createRng(seed: number) {
  let state = seed;
  return function next(): number {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generateFillerParagraph(rng: () => number, targetChars: number): string {
  const sentences: string[] = [];
  let totalChars = 0;

  while (totalChars < targetChars) {
    const sentenceLength = Math.floor(rng() * 15) + 8; // 8-22 words
    const words: string[] = [];
    for (let i = 0; i < sentenceLength; i++) {
      words.push(FILLER_WORDS[Math.floor(rng() * FILLER_WORDS.length)]);
    }
    words[0] = words[0].charAt(0).toUpperCase() + words[0].slice(1);
    const sentence = words.join(" ") + ".";
    sentences.push(sentence);
    totalChars += sentence.length + 1; // +1 for space between sentences
  }

  return sentences.join(" ");
}

function generateNeedle(rng: () => number): { needle: string; projectId: string; code: string } {
  const projectName = PROJECT_NAMES[Math.floor(rng() * PROJECT_NAMES.length)];
  const projectNum = Math.floor(rng() * 900) + 100; // 100-999
  const projectId = `${projectName}${projectNum}`;

  const adjective = CODE_ADJECTIVES[Math.floor(rng() * CODE_ADJECTIVES.length)];
  const noun = CODE_NOUNS[Math.floor(rng() * CODE_NOUNS.length)];
  const codeNum = Math.floor(rng() * 9000) + 1000; // 1000-9999
  const code = `${adjective}-${noun}-${codeNum}`;

  const needle = `The secret code for Project ${projectId} is: ${code}`;

  return { needle, projectId, code };
}

function buildContext(
  rng: () => number,
  needle: string,
  targetLength: number,
): string {
  const needlePosition = rng(); // 0.0-1.0: position fraction

  const needleChars = needle.length + 2; // +2 for surrounding newlines
  const fillerChars = Math.max(0, targetLength - needleChars);
  const beforeChars = Math.floor(fillerChars * needlePosition);
  const afterChars = fillerChars - beforeChars;

  const before = generateFillerParagraph(rng, beforeChars);
  const after = generateFillerParagraph(rng, afterChars);

  return `${before}\n${needle}\n${after}`;
}

export interface SNIAHOptions {
  tasksPerLength?: number;
  contextLengths?: number[];
  seed?: number;
}

/**
 * Generate S-NIAH eval tasks.
 *
 * Each task has a unique needle embedded in filler text at a random position.
 * The query asks for the needle's code value.
 */
export function generateSNIAHTasks(options: SNIAHOptions = {}): EvalTask[] {
  const tasksPerLength = options.tasksPerLength ?? 8;
  const contextLengths = options.contextLengths ?? DEFAULT_CONTEXT_LENGTHS;
  const seed = options.seed ?? 42;

  const rng = createRng(seed);
  const tasks: EvalTask[] = [];

  for (const contextLen of contextLengths) {
    for (let i = 0; i < tasksPerLength; i++) {
      const { needle, projectId, code } = generateNeedle(rng);
      const context = buildContext(rng, needle, contextLen);

      tasks.push({
        id: `s-niah-${contextLen}-${i}`,
        query: `What is the secret code for Project ${projectId}?`,
        context,
        expectedAnswer: code,
        metadata: {
          contextLength: contextLen,
          taskIndex: i,
          needlePosition: context.indexOf(needle) / context.length,
        },
      });
    }
  }

  return tasks;
}
