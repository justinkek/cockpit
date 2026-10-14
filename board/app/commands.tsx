"use client";

import type { Lists } from "@/app/fields";
import type { Command, Page } from "@/app/palette";
import { applyTheme } from "@/app/theme";
import { EMOJI } from "@/lib/emoji";
import { boardColumns, type Card, FIBONACCI, phaseOf, TIMEBOXES, TYPES, timeboxText } from "@/lib/shared";

export type Edits = {
	label: string;
	move: (column: string) => void;
	edit: (field: string, value: string, change: Partial<Card>) => void;
	archive?: () => void;
	duplicate?: () => void;
};

function dot(column: string) {
	return <span className={`dot phase-${phaseOf(column)}`} aria-hidden="true" />;
}

export function movePage(kind: "card" | "epic", current: string | undefined, edits: Edits): Page {
	return {
		title: `Move ${edits.label} to`,
		items: boardColumns(kind).map((column) => ({
			id: `move:${column}`,
			label: column,
			icon: dot(column),
			hint: column === current ? "Current" : undefined,
			run: () => edits.move(column),
		})),
	};
}

export function epicPage(lists: Lists, current: string | null | undefined, edits: Edits): Page {
	return {
		title: `Set the epic of ${edits.label}`,
		items: [
			{ id: "epic:none", label: "No epic", run: () => edits.edit("epic", "", { epic: null }) },
			...lists.epics.map((epic) => ({
				id: `epic:${epic.id}`,
				label: epic.name,
				hint: epic.id === current ? "Current" : epic.id,
				keywords: epic.id,
				run: () => edits.edit("epic", epic.id, { epic: epic.id }),
			})),
		],
	};
}

function choicePage(title: string, items: Command[]): Page {
	return { title, items };
}

export function iconCommand(record: Card | null, edits: Edits): Command {
	return {
		id: "do:icon",
		group: edits.label,
		label: "Set icon…",
		keywords: "emoji",
		next: () =>
			choicePage(`Set the icon of ${edits.label}`, [
				{ id: "icon:none", label: "No icon", run: () => edits.edit("icon", "", { icon: null }) },
				...EMOJI.map((entry) => ({
					id: `icon:${entry.emoji}`,
					label: `${entry.emoji}  ${entry.words.split(" ")[0]}`,
					keywords: entry.words,
					hint: entry.emoji === record?.icon ? "Current" : undefined,
					run: () => edits.edit("icon", entry.emoji, { icon: entry.emoji }),
				})),
			]),
	};
}

export function recordCommands(
	kind: "card" | "epic" | null,
	record: Card | null,
	lists: Lists,
	edits: Edits | null,
): Command[] {
	if (!kind || !edits) return [];
	const group = edits.label;
	const commands: Command[] = [
		{
			id: "do:move",
			group,
			label: "Move to…",
			hint: "S",
			keywords: "status column",
			next: () => movePage(kind, record?.status, edits),
		},
	];
	if (kind === "card") {
		commands.push(
			{ id: "do:epic", group, label: "Set epic…", hint: "E", next: () => epicPage(lists, record?.epic, edits) },
			{
				id: "do:type",
				group,
				label: "Set type…",
				next: () =>
					choicePage(
						`Set the type of ${edits.label}`,
						TYPES.map((type) => ({
							id: `type:${type}`,
							label: type,
							hint: type === record?.type ? "Current" : undefined,
							run: () => edits.edit("type", type, { type }),
						})),
					),
			},
			{
				id: "do:sprint",
				group,
				label: "Set sprint…",
				next: () =>
					choicePage(`Set the sprint of ${edits.label}`, [
						{ id: "sprint:none", label: "No sprint", run: () => edits.edit("sprint", "", { sprint: null }) },
						...lists.sprints.map((sprint) => ({
							id: `sprint:${sprint.id}`,
							label: sprint.name,
							hint: sprint.id === record?.sprint ? "Current" : (sprint.start ?? undefined),
							run: () => edits.edit("sprint", sprint.id, { sprint: sprint.id }),
						})),
					]),
			},
			{
				id: "do:complexity",
				group,
				label: "Set complexity…",
				keywords: "points estimate",
				next: () =>
					choicePage(`Set the complexity of ${edits.label}`, [
						{ id: "points:none", label: "Not set", run: () => edits.edit("complexity", "", { complexity: null }) },
						...FIBONACCI.map((points) => ({
							id: `points:${points}`,
							label: String(points),
							hint: points === record?.complexity ? "Current" : undefined,
							run: () => edits.edit("complexity", String(points), { complexity: points }),
						})),
					]),
			},
			{
				id: "do:timebox",
				group,
				label: "Set timebox…",
				keywords: "minutes budget time",
				next: () =>
					choicePage(`Set the timebox of ${edits.label}`, [
						{
							id: "timebox:none",
							label: "No timebox",
							run: () => edits.edit("timebox_mins", "", { timebox_mins: null }),
						},
						...TIMEBOXES.map((minutes) => ({
							id: `timebox:${minutes}`,
							label: timeboxText(minutes),
							keywords: `${minutes} minutes`,
							hint:
								minutes === record?.timebox_mins
									? "Current"
									: timeboxText(minutes).endsWith("min")
										? undefined
										: `${minutes} min`,
							run: () => edits.edit("timebox_mins", String(minutes), { timebox_mins: minutes }),
						})),
					]),
			},
		);
	}
	commands.push(iconCommand(record, edits));
	if (edits.duplicate) {
		commands.push({ id: "do:duplicate", group, label: "Duplicate", keywords: "copy clone", run: edits.duplicate });
	}
	if (edits.archive) {
		commands.push({ id: "do:archive", group, label: "Archive", keywords: "remove delete hide", run: edits.archive });
	}
	return commands;
}

export function themeCommands(): Command[] {
	return (["system", "light", "dark"] as const).map((theme) => ({
		id: `theme:${theme}`,
		group: "Preferences",
		label: `Theme: ${theme === "system" ? "follow the system" : theme}`,
		keywords: "appearance dark light mode",
		run: () => applyTheme(theme),
	}));
}

export function cardCommands(cards: { id: string; name: string; status: string }[], open: (id: string) => void) {
	return cards.map((card) => ({
		id: `card:${card.id}`,
		group: "Cards",
		label: card.name,
		hint: card.id,
		keywords: `${card.id} ${card.id.split("-").at(-1)}`,
		icon: dot(card.status),
		run: () => open(card.id),
	}));
}
