export type BlockSpan = { start: number; end: number };

type Kind = "blank" | "fence" | "toggle" | "table" | "heading" | "rule" | "list" | "quote" | "text";

const toggleStart = /^<\/?(?:details|summary|toggle)(?:[\s>-]|$)/;
const toggleEnd = /<\/(?:details|summary|toggle|toggle-header)>$/;

function kindOf(line: string): Kind {
	const text = line.trim();
	if (text === "") return "blank";
	if (text.startsWith("```")) return "fence";
	if (toggleStart.test(text) || toggleEnd.test(text)) return "toggle";
	if (text.startsWith("|")) return "table";
	if (/^#{1,6} /.test(text)) return "heading";
	if (text === "---") return "rule";
	if (/^(?:[-*] |\d+\. )/.test(text)) return "list";
	if (text.startsWith(">")) return "quote";
	return "text";
}

function indented(line: string) {
	return /^[ \t]/.test(line);
}

export function blockSpans(body: string): BlockSpan[] {
	const lines = body.split("\n");
	const kinds = lines.map(kindOf);
	const spans: BlockSpan[] = [];
	let i = 0;
	while (i < lines.length) {
		const kind = kinds[i];
		const start = i;
		if (kind === "blank" || kind === "toggle") {
			i++;
			continue;
		}
		if (kind === "fence") {
			i++;
			while (i < lines.length && kinds[i] !== "fence") i++;
			spans.push({ start, end: Math.min(i, lines.length - 1) });
			i++;
			continue;
		}
		i++;
		if (kind === "table" || kind === "quote" || kind === "text") {
			while (i < lines.length && kinds[i] === kind) i++;
		} else if (kind === "list") {
			while (
				i < lines.length &&
				(kinds[i] === "list" || (indented(lines[i]) && (kinds[i] === "text" || kinds[i] === "quote")))
			)
				i++;
		}
		spans.push({ start, end: i - 1 });
	}
	return spans;
}

export function blockSource(body: string, span: BlockSpan) {
	return body
		.split("\n")
		.slice(span.start, span.end + 1)
		.join("\n");
}

function trimmed(text: string) {
	return text.replace(/\s+$/, "") === "" ? "" : text.replace(/\n+$/, "");
}

export function replaceBlock(body: string, span: BlockSpan, text: string) {
	const lines = body.split("\n");
	const kept = trimmed(text);
	if (kept !== "") {
		lines.splice(span.start, span.end - span.start + 1, ...kept.split("\n"));
		return lines.join("\n");
	}
	lines.splice(span.start, span.end - span.start + 1);
	const at = span.start;
	if (at < lines.length && lines[at].trim() === "" && (at === 0 || lines[at - 1].trim() === "")) lines.splice(at, 1);
	else if (at >= lines.length && at > 0 && lines[at - 1].trim() === "") lines.splice(at - 1, 1);
	return lines.join("\n");
}

export function appendBlock(body: string, text: string) {
	const kept = trimmed(text);
	if (kept === "") return body;
	const content = body.replace(/(?:\n[ \t]*)+$/, "");
	if (content.trim() === "") return kept;
	return `${content}\n\n${kept}${body.endsWith("\n") ? "\n" : ""}`;
}
