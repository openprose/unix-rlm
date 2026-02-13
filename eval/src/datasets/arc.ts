/**
 * ARC-AGI-2 dataset loader.
 *
 * Loads ARC evaluation challenges and solutions from pre-downloaded JSON files.
 * Data is downloaded into eval/data/arc/ by the CI workflow (from the node-rlm
 * GitHub release) or manually.
 *
 * Each ARC task has training examples (input/output pairs) and test inputs
 * (input only). The model must discover the transformation rule from training
 * examples and apply it to the test inputs.
 */

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { EvalTask } from "./s-niah.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Data directory: eval/src/datasets/ -> eval/data/arc/
const DATA_DIR = join(__dirname, "..", "..", "data", "arc");

interface ArcChallenge {
	train: Array<{ input: number[][]; output: number[][] }>;
	test: Array<{ input: number[][] }>;
}

type ArcChallenges = Record<string, ArcChallenge>;
type ArcSolutions = Record<string, number[][][]>;

export interface ArcOptions {
	maxTasks?: number;
	selectedProblems?: string[];
}

export async function loadArcTasks(options: ArcOptions = {}): Promise<EvalTask[]> {
	const challengesPath = join(DATA_DIR, "arc-agi_evaluation_challenges.json");
	const solutionsPath = join(DATA_DIR, "arc-agi_evaluation_solutions.json");

	if (!existsSync(challengesPath) || !existsSync(solutionsPath)) {
		throw new Error(
			`ARC data not found at ${DATA_DIR}. ` +
			`Download it first (the CI workflow does this automatically).`,
		);
	}

	const challenges: ArcChallenges = JSON.parse(readFileSync(challengesPath, "utf-8"));
	const solutions: ArcSolutions = JSON.parse(readFileSync(solutionsPath, "utf-8"));

	let taskIds = Object.keys(challenges);

	// Filter to selected problems if specified
	if (options.selectedProblems && options.selectedProblems.length > 0) {
		const selected = new Set(options.selectedProblems);
		taskIds = taskIds.filter((id) => selected.has(id));
	}

	// Limit to maxTasks
	if (options.maxTasks && options.maxTasks > 0) {
		taskIds = taskIds.slice(0, options.maxTasks);
	}

	return taskIds.map((taskId) => {
		const challenge = challenges[taskId];
		const solution = solutions[taskId];

		if (!solution) {
			throw new Error(`No solution found for ARC task ${taskId}`);
		}

		// Build the context: the full task data as JSON
		const context = JSON.stringify({
			train: challenge.train,
			test: challenge.test,
		});

		// Build expected answer.
		// Most tasks have 1 test input; some have multiple.
		const expectedAnswer = challenge.test.length === 1
			? JSON.stringify(solution[0])
			: JSON.stringify(solution);

		return {
			id: `arc-${taskId}`,
			query: buildArcQuery(challenge),
			context,
			expectedAnswer,
			metadata: {
				numTrainExamples: challenge.train.length,
				numTestInputs: challenge.test.length,
			},
		};
	});
}

function buildArcQuery(challenge: ArcChallenge): string {
	const numTests = challenge.test.length;
	const returnFormat = numTests === 1
		? "Return the output as a JSON 2D array of integers, e.g.: [[1,2,3],[4,5,6]]"
		: `There are ${numTests} test inputs. Return an array of ${numTests} output grids as JSON, e.g.: [[[1,2],[3,4]], [[5,6],[7,8]]]`;

	return `You are solving an ARC-AGI task. The task data is available in the input file ($RLM_INPUT) as a JSON string.

The JSON contains:
- "train": Training examples, each with "input" and "output" grids (2D arrays of ints 0-9)
- "test": Test inputs with "input" grids only (you must predict the outputs)

Analyze all training examples to discover the transformation rule that maps each input to its output. The rule must be consistent across ALL training examples. Then apply it to the test input(s).

${returnFormat}

Return ONLY the raw JSON grid(s). No explanation, no markdown, no wrapping.`;
}
