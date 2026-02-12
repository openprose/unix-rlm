/**
 * OOLONG dataset loader.
 *
 * Loads the OOLONG-synth benchmark from pre-downloaded JSONL data files.
 * The dataset is hosted on HuggingFace: oolongbench/oolong-synth
 *
 * Data files should be placed in eval/data/oolong/ as JSONL.
 * Use the download script or copy from another repo that has them cached.
 *
 * The RLM paper evaluated on the trec_coarse split: 50 tasks over 131K tokens each.
 * We filter by dataset="trec_coarse" and context_len=131072 to match the paper.
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { EvalTask } from "./s-niah.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Data directory
const DATA_DIR = join(__dirname, "..", "..", "data", "oolong");

/**
 * Actual schema of the OOLONG-synth JSONL rows.
 */
interface OolongRow {
	id: number;
	context_len: number;
	dataset: string;
	context_window_text: string;
	context_window_text_with_labels: string;
	question: string;
	task_group: string;
	task: string;
	answer: string;
	answer_type: string;
	input_subset: string;
	num_labels: number;
	context_window_id: number;
}

/**
 * Normalize OOLONG answer strings.
 *
 * The HuggingFace dataset stores answers as Python list literals, e.g.:
 *   "['abbreviation']"  -> "abbreviation"
 *   "['more common than']" -> "more common than"
 *   "['42']" -> "42"
 *   "[42]" -> "42"
 *
 * Returns the first element as a string (matching the official scorer's
 * `ast.literal_eval()[0]` behavior).
 */
function normalizeAnswer(raw: string): string {
	const trimmed = raw.trim();

	// Check for Python list format: ['value'] or [value]
	const listMatch = trimmed.match(/^\[(.+)\]$/s);
	if (!listMatch) return trimmed;

	const inner = listMatch[1];

	let current = "";
	let inQuote = false;
	let quoteChar = "";

	for (let i = 0; i < inner.length; i++) {
		const ch = inner[i];
		if (!inQuote && (ch === "'" || ch === '"')) {
			inQuote = true;
			quoteChar = ch;
		} else if (inQuote && ch === quoteChar) {
			inQuote = false;
		} else if (!inQuote && ch === ",") {
			// Stop at first comma — we only want the first element
			break;
		} else {
			current += ch;
		}
	}

	return current.trim() || trimmed;
}

/**
 * Load all rows from the downloaded JSONL files in DATA_DIR.
 */
function loadRows(): OolongRow[] {
	const files = readdirSync(DATA_DIR).filter(
		(f) => f.endsWith(".jsonl") || f.endsWith(".json"),
	);

	if (files.length === 0) {
		throw new Error(
			`No data files found in ${DATA_DIR}. Place OOLONG JSONL files there first.`,
		);
	}

	const rows: OolongRow[] = [];

	for (const file of files) {
		const content = readFileSync(join(DATA_DIR, file), "utf-8");

		if (file.endsWith(".jsonl")) {
			for (const line of content.split("\n")) {
				const trimmed = line.trim();
				if (!trimmed) continue;
				try {
					rows.push(JSON.parse(trimmed) as OolongRow);
				} catch {
					// Skip malformed lines
				}
			}
		} else {
			try {
				const parsed = JSON.parse(content);
				if (Array.isArray(parsed)) {
					rows.push(...(parsed as OolongRow[]));
				} else {
					rows.push(parsed as OolongRow);
				}
			} catch {
				// Skip malformed files
			}
		}
	}

	return rows;
}

export interface OolongOptions {
	datasetFilter?: string; // e.g. "trec_coarse"
	contextLength?: number; // filter by context_len (default: 131072 = 128K tokens)
	maxTasks?: number;
}

/**
 * Load OOLONG tasks from pre-downloaded data.
 *
 * Reads all JSONL files from eval/data/oolong/, filters by dataset name
 * and context length, normalizes answers, and returns EvalTask[].
 */
export async function loadOolongTasks(options: OolongOptions = {}): Promise<EvalTask[]> {
	const datasetFilter = options.datasetFilter ?? "trec_coarse";
	const contextLength = options.contextLength ?? 131072;

	// loadRows() throws with a clear error if no data files exist.
	const rows = loadRows();

	let filtered = rows.filter((r) => r.dataset === datasetFilter);

	if (filtered.length === 0) {
		const datasets = [...new Set(rows.map((r) => r.dataset))];
		console.error(
			`Warning: No rows found with dataset="${datasetFilter}". ` +
			`Available datasets: ${datasets.join(", ")}. ` +
			`Falling back to all rows.`,
		);
		filtered = rows;
	}

	if (contextLength) {
		const lenFiltered = filtered.filter((r) => r.context_len === contextLength);
		if (lenFiltered.length > 0) {
			filtered = lenFiltered;
		} else {
			// Fall back to the largest context_len available
			const maxLen = Math.max(...filtered.map((r) => r.context_len));
			console.error(
				`Warning: No rows with context_len=${contextLength}. ` +
				`Using largest available: ${maxLen}`,
			);
			filtered = filtered.filter((r) => r.context_len === maxLen);
		}
	}

	if (options.maxTasks && options.maxTasks < filtered.length) {
		filtered = filtered.slice(0, options.maxTasks);
	}

	return filtered.map((row, index) => ({
		id: `oolong-${datasetFilter}-${index}`,
		query: row.question,
		context: row.context_window_text,
		expectedAnswer: normalizeAnswer(row.answer),
		metadata: {
			dataset: row.dataset,
			contextLen: row.context_len,
			taskGroup: row.task_group,
			task: row.task,
			answerType: row.answer_type,
			inputSubset: row.input_subset,
			numLabels: row.num_labels,
			contextWindowId: row.context_window_id,
		},
	}));
}
