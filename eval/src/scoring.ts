export function exactMatch(expected: string, actual: string): number {
  return expected.trim().toLowerCase() === actual.trim().toLowerCase() ? 1 : 0;
}

// Numeric: 0.75^|diff|. Text: case-insensitive substring match.
export function oolongScore(expected: string, actual: string): number {
  const expectedTrimmed = expected.trim();
  const actualTrimmed = actual.trim();

  // Try to parse both as numbers
  const expectedNum = Number(expectedTrimmed);
  const actualNum = Number(actualTrimmed);

  if (!isNaN(expectedNum) && !isNaN(actualNum) && expectedTrimmed !== "" && actualTrimmed !== "") {
    const diff = Math.abs(expectedNum - actualNum);
    return Math.pow(0.75, diff);
  }

  // Check if expected appears as a case-insensitive substring of actual.
  // Handles comparison phrases ("more common than" in "Answer: X is more common than Y")
  // and labels wrapped in answer templates ("abbreviation" in "Label: abbreviation").
  if (actualTrimmed.toLowerCase().includes(expectedTrimmed.toLowerCase())) {
    return 1;
  }

  return 0;
}

export function f1Score(expected: string, actual: string): number {
  const tokenize = (s: string): string[] =>
    s
      .toLowerCase()
      .split(/[\s\p{P}]+/u)
      .filter((t) => t.length > 0);

  const expectedTokens = tokenize(expected);
  const actualTokens = tokenize(actual);

  if (expectedTokens.length === 0 && actualTokens.length === 0) {
    return 1;
  }
  if (expectedTokens.length === 0 || actualTokens.length === 0) {
    return 0;
  }

  const expectedCounts = new Map<string, number>();
  for (const t of expectedTokens) {
    expectedCounts.set(t, (expectedCounts.get(t) ?? 0) + 1);
  }

  let truePositives = 0;
  const usedCounts = new Map<string, number>();
  for (const t of actualTokens) {
    const available = (expectedCounts.get(t) ?? 0) - (usedCounts.get(t) ?? 0);
    if (available > 0) {
      truePositives++;
      usedCounts.set(t, (usedCounts.get(t) ?? 0) + 1);
    }
  }

  const precision = truePositives / actualTokens.length;
  const recall = truePositives / expectedTokens.length;

  if (precision + recall === 0) {
    return 0;
  }

  return (2 * precision * recall) / (precision + recall);
}

/**
 * ARC grid exact match scoring.
 *
 * Compares predicted and expected grids (2D arrays of integers).
 * Both are expected to be JSON strings representing 2D arrays.
 * Returns 1 if the grids have identical shape and values, 0 otherwise.
 *
 * Handles both single-grid and multi-grid (multiple test inputs) cases.
 *
 * Note: argument order is (expected, actual) to match the ScoringFn signature
 * used in this codebase.
 */
export function arcGridMatch(expected: string, actual: string): number {
  try {
    const predGrid = parseArcGrid(actual.trim());
    const expGrid = JSON.parse(expected);

    if (predGrid === null) return 0;

    return gridsEqual(predGrid, expGrid) ? 1 : 0;
  } catch {
    return 0;
  }
}

/**
 * Parse a predicted ARC grid from LLM output.
 * Handles various formats the model might return:
 * - Raw JSON: [[1,2],[3,4]]
 * - Markdown-wrapped: ```json\n[[1,2],[3,4]]\n```
 * - With explanation text before/after the JSON
 */
function parseArcGrid(text: string): unknown | null {
  // Try direct JSON parse first
  try {
    return JSON.parse(text);
  } catch {
    // Ignore
  }

  // Try extracting JSON from markdown code blocks
  const codeBlockMatch = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  if (codeBlockMatch) {
    try {
      return JSON.parse(codeBlockMatch[1].trim());
    } catch {
      // Ignore
    }
  }

  // Try finding the first JSON array in the text
  const arrayMatch = text.match(/(\[[\s\S]*\])/);
  if (arrayMatch) {
    try {
      return JSON.parse(arrayMatch[1]);
    } catch {
      // Ignore
    }
  }

  return null;
}

/**
 * Deep equality check for grids (2D or 3D arrays of numbers).
 */
function gridsEqual(a: unknown, b: unknown): boolean {
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((item, i) => gridsEqual(item, b[i]));
  }
  return a === b;
}
