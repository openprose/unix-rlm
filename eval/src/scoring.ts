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
