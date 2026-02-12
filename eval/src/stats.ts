/** Shared statistics helpers used by both harness.ts and analyze.ts. */

export function sorted(arr: number[]): number[] {
	return [...arr].sort((a, b) => a - b);
}

export function mean(arr: number[]): number {
	if (arr.length === 0) return 0;
	return arr.reduce((a, b) => a + b, 0) / arr.length;
}

export function median(arr: number[]): number {
	if (arr.length === 0) return 0;
	const s = sorted(arr);
	const mid = Math.floor(s.length / 2);
	return s.length % 2 !== 0 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

export function percentile(arr: number[], p: number): number {
	if (arr.length === 0) return 0;
	const s = sorted(arr);
	const index = Math.ceil((p / 100) * s.length) - 1;
	return s[Math.max(0, index)];
}

export function std(arr: number[]): number {
	if (arr.length === 0) return 0;
	const m = mean(arr);
	return Math.sqrt(arr.reduce((sum, v) => sum + (v - m) ** 2, 0) / arr.length);
}
