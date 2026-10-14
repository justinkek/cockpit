import { createContext, type MouseEvent, type ReactNode, useContext } from "react";
import { Mermaid } from "@/app/mermaid";

export type Mentions = { nameOf?: (id: string) => string | undefined; onOpen?: (id: string) => boolean };

export const MentionContext = createContext<Mentions>({});

const CARD_NUMBER = /^(?:FEAT|BUG|TIME)-(\d+)$/;

export function mentionNames(records: { id: string; name: string }[]) {
	const byId = new Map(records.map((record) => [record.id, record.name]));
	const byNumber = new Map(
		records.flatMap((record) => {
			const number = record.id.match(CARD_NUMBER)?.[1];
			return number ? [[number, record.name] as const] : [];
		}),
	);
	return (id: string) => byId.get(id) ?? byNumber.get(id.match(CARD_NUMBER)?.[1] ?? "");
}

function Mention({ id }: { id: string }) {
	const { nameOf, onOpen } = useContext(MentionContext);
	const name = nameOf?.(id);
	const href = id.startsWith("EPIC-") ? `/epics?open=${id}` : `/card/${id}`;
	function open(event: MouseEvent<HTMLAnchorElement>) {
		if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
		if (onOpen?.(id)) event.preventDefault();
	}
	return (
		<a href={href} className="mention" title={name ? `${id}: ${name}` : id} onClick={open}>
			{id}
		</a>
	);
}

const mention = /(?<![A-Za-z0-9_/-])(?:FEAT|BUG|TIME|EPIC)-\d+(?![A-Za-z0-9_])/g;

function mentioned(text: string, key: string): ReactNode[] {
	const parts: ReactNode[] = [];
	let cursor = 0;
	for (const match of text.matchAll(mention)) {
		if (match.index > cursor) parts.push(text.slice(cursor, match.index));
		parts.push(<Mention key={`${key}-@${match.index}`} id={match[0]} />);
		cursor = match.index + match[0].length;
	}
	if (cursor < text.length) parts.push(text.slice(cursor));
	return parts;
}

type Anchor = { text: string; thread: string };

type Source = {
	lines: string[];
	origins: number[];
	anchors: Anchor[];
	onAnchor: (thread: string) => void;
	onCheck?: (line: number, done: boolean) => void;
};

function highlight(
	text: string,
	anchors: Anchor[],
	onAnchor: (thread: string) => void,
	key: string,
	linked = true,
): ReactNode[] {
	const plain = (slice: string, at: string) => (linked ? mentioned(slice, at) : [slice]);
	const spans = anchors
		.flatMap((anchor) => {
			const found: { start: number; end: number; thread: string }[] = [];
			let at = text.indexOf(anchor.text);
			while (at >= 0 && anchor.text.length > 0) {
				found.push({ start: at, end: at + anchor.text.length, thread: anchor.thread });
				at = text.indexOf(anchor.text, at + anchor.text.length);
			}
			return found;
		})
		.sort((a, b) => a.start - b.start);
	const parts: ReactNode[] = [];
	let cursor = 0;
	for (const span of spans) {
		if (span.start < cursor) continue;
		if (span.start > cursor) parts.push(...plain(text.slice(cursor, span.start), `${key}-${cursor}`));
		parts.push(
			<mark key={`${key}-${span.start}`} className="anchor" onClick={() => onAnchor(span.thread)}>
				{plain(text.slice(span.start, span.end), `${key}-${span.start}m`)}
			</mark>,
		);
		cursor = span.end;
	}
	if (cursor < text.length) parts.push(...plain(text.slice(cursor), `${key}-${cursor}`));
	return parts;
}

function inline(text: string, anchors: Anchor[], onAnchor: (thread: string) => void, key: string): ReactNode[] {
	const nodes: ReactNode[] = [];
	const pattern = /\[([^\]]+)\]\(([^)\s]+)\)|<(https?:[^>]+)>|`([^`]+)`|\*\*([^*]+)\*\*/g;
	let cursor = 0;
	let match: RegExpExecArray | null;
	let index = 0;
	while ((match = pattern.exec(text)) !== null) {
		if (match.index > cursor)
			nodes.push(...highlight(text.slice(cursor, match.index), anchors, onAnchor, `${key}-t${index}`));
		const part = `${key}-m${index}`;
		if (match[1] !== undefined) {
			nodes.push(
				<a key={part} href={match[2]} target="_blank" rel="noreferrer">
					{highlight(match[1], anchors, onAnchor, part, false)}
				</a>,
			);
		} else if (match[3] !== undefined) {
			nodes.push(
				<a key={part} href={match[3]} target="_blank" rel="noreferrer">
					{match[3]}
				</a>,
			);
		} else if (match[4] !== undefined) {
			nodes.push(<code key={part}>{highlight(match[4], anchors, onAnchor, part, false)}</code>);
		} else {
			nodes.push(<strong key={part}>{highlight(match[5], anchors, onAnchor, part)}</strong>);
		}
		cursor = match.index + match[0].length;
		index++;
	}
	if (cursor < text.length) nodes.push(...highlight(text.slice(cursor), anchors, onAnchor, `${key}-end`));
	return nodes;
}

function depthOf(line: string) {
	const tabs = line.match(/^\t*/)?.[0].length ?? 0;
	const spaces = Math.floor((line.match(/^ */)?.[0].length ?? 0) / 2);
	return tabs + spaces;
}

const opening = /^<details(?:\s[^>]*)?>/;
const closing = "</details>";
const summaryOpening = /^<summary(?:\s[^>]*)?>/;
const summaryClosing = "</summary>";
const summarised = /^<summary(?:\s[^>]*)?>(.*)<\/summary>$/;
const toggleTag = /^<(?:details|summary)[\s>]|^<\/details>/;
const section = /^#{1,2} /;

function continuesSummary(line: string) {
	const text = line.trim();
	return text !== "" && !text.startsWith("```") && !toggleTag.test(text) && !section.test(text);
}

function filled(lines: string[], from: number) {
	let at = from;
	while (at < lines.length && lines[at].trim() === "") at++;
	return at;
}

function untangled(lines: string[]): { lines: string[]; origins: number[] } {
	const out: string[] = [];
	const origins: number[] = [];
	const keep = (line: string, origin: number) => {
		out.push(line);
		origins.push(origin);
	};
	let fenced = false;
	let awaiting = false;
	for (let i = 0; i < lines.length; i++) {
		const raw = lines[i];
		let rest = raw.trim();
		if (fenced || rest.startsWith("```")) {
			if (rest.startsWith("```")) fenced = !fenced;
			keep(raw, i);
			awaiting = false;
			continue;
		}
		const parts: string[] = [];
		const open = rest.match(opening);
		if (open) {
			parts.push("<details>");
			rest = rest.slice(open[0].length).trim();
		}
		if ((open || awaiting) && summaryOpening.test(rest)) {
			let end = i;
			let gathered = rest;
			while (!gathered.includes(summaryClosing) && end + 1 < lines.length && continuesSummary(lines[end + 1]))
				gathered += ` ${lines[++end].trim()}`;
			const close = gathered.indexOf(summaryClosing);
			if (close >= 0) {
				parts.push(gathered.slice(0, close + summaryClosing.length));
				rest = gathered.slice(close + summaryClosing.length).trim();
				i = end;
			}
		}
		awaiting = (awaiting && parts.length === 0 && rest === "") || (open !== null && parts.length === 1 && rest === "");
		let closes = 0;
		while (rest.endsWith(closing)) {
			rest = rest.slice(0, -closing.length).trim();
			closes++;
		}
		if (parts.length === 0 && closes === 0) {
			keep(raw, i);
			continue;
		}
		if (rest !== "") parts.push(rest);
		parts.push(...Array<string>(closes).fill(closing));
		const indent = raw.slice(0, raw.length - raw.trimStart().length);
		for (const part of parts) keep(indent + part, i);
	}
	return { lines: out, origins };
}

function blocksOf(source: Source, from: number, base: number, nested: boolean): { blocks: ReactNode[]; next: number } {
	const { lines, anchors, onAnchor } = source;
	const blocks: ReactNode[] = [];
	let i = from;
	while (i < lines.length) {
		const raw = lines[i];
		const line = raw.trimStart();
		const depth = Math.max(0, depthOf(raw) - base);
		const key = `b${i}`;
		const style = depth > 0 ? { marginLeft: `${depth * 18}px` } : undefined;

		if (nested && section.test(line)) return { blocks, next: i };

		if (line.trimEnd() === closing) {
			if (nested) return { blocks, next: i + 1 };
			i++;
			continue;
		}

		if (line.trimEnd() === "<details>") {
			const ahead = filled(lines, i + 1);
			const summary = lines[ahead]?.trim().match(summarised);
			const next = summary ? ahead + 1 : i + 1;
			const title = summary?.[1].trim() || "Details";
			const first = filled(lines, next);
			const body = Math.min(depthOf(raw) + 1, first < lines.length ? depthOf(lines[first]) : depthOf(raw) + 1);
			const inner = blocksOf(source, next, body, true);
			blocks.push(
				<details key={key} className="md-details" style={style}>
					<summary>{inline(title, anchors, onAnchor, key)}</summary>
					<div className="md-details-body">{inner.blocks}</div>
				</details>,
			);
			i = inner.next;
			continue;
		}

		if (line.startsWith("```")) {
			const margin = new RegExp(`^[ \\t]{0,${raw.length - line.length}}`);
			const language = line.slice(3).trim();
			const code: string[] = [];
			i++;
			while (i < lines.length && !lines[i].trimStart().startsWith("```")) code.push(lines[i++].replace(margin, ""));
			i++;
			if (language === "mermaid") {
				blocks.push(<Mermaid key={key} source={code.join("\n")} style={style} />);
				continue;
			}
			blocks.push(
				<pre key={key} className="md-code" style={style}>
					{code.join("\n")}
				</pre>,
			);
			continue;
		}

		if (line.startsWith("|")) {
			const rows: string[][] = [];
			while (i < lines.length && lines[i].trimStart().startsWith("|")) {
				const cells = lines[i]
					.trim()
					.replace(/^\||\|$/g, "")
					.split(/(?<!\\)\|/)
					.map((cell) => cell.trim().replace(/\\\|/g, "|"));
				if (!cells.every((cell) => /^-+$/.test(cell))) rows.push(cells);
				i++;
			}
			const [head, ...body] = rows;
			blocks.push(
				<div key={key} className="md-table" style={style}>
					<table>
						<thead>
							<tr>
								{head?.map((cell, c) => (
									<th key={c}>{inline(cell, anchors, onAnchor, `${key}h${c}`)}</th>
								))}
							</tr>
						</thead>
						<tbody>
							{body.map((row, r) => (
								<tr key={r}>
									{row.map((cell, c) => (
										<td key={c}>{inline(cell, anchors, onAnchor, `${key}r${r}c${c}`)}</td>
									))}
								</tr>
							))}
						</tbody>
					</table>
				</div>,
			);
			continue;
		}

		const heading = line.match(/^(#{1,3}) (.*)$/);
		const todo = line.match(/^- \[( |x)\] (.*)$/);
		const bullet = line.match(/^[-*] (.*)$/);
		const numbered = line.match(/^\d+\. (.*)$/);
		const quote = line.match(/^> ?(.*)$/);

		if (heading) {
			const Tag = `h${heading[1].length + 2}` as "h3" | "h4" | "h5";
			blocks.push(
				<Tag key={key} className="md-heading" style={style}>
					{inline(heading[2], anchors, onAnchor, key)}
				</Tag>,
			);
		} else if (todo) {
			const done = todo[1] === "x";
			const origin = source.origins[i];
			blocks.push(
				<div key={key} className={`md-todo${done ? " done" : ""}`} style={style} data-line={origin}>
					<input
						type="checkbox"
						checked={done}
						disabled={!source.onCheck}
						aria-label={done ? "Mark not done" : "Mark done"}
						onChange={() => source.onCheck?.(origin, !done)}
					/>
					<span>{inline(todo[2], anchors, onAnchor, key)}</span>
				</div>,
			);
		} else if (bullet || numbered) {
			blocks.push(
				<div key={key} className="md-item" style={style}>
					<span className="marker" aria-hidden="true">
						{numbered ? "•" : "•"}
					</span>
					<span>{inline((bullet ?? numbered)?.[1] ?? "", anchors, onAnchor, key)}</span>
				</div>,
			);
		} else if (quote) {
			blocks.push(
				<blockquote key={key} className="md-quote" style={style}>
					{inline(quote[1], anchors, onAnchor, key)}
				</blockquote>,
			);
		} else if (line === "---") {
			blocks.push(<hr key={key} />);
		} else if (line === "") {
			blocks.push(<div key={key} className="md-gap" />);
		} else {
			blocks.push(
				<p key={key} className="md-p" style={style}>
					{inline(line, anchors, onAnchor, key)}
				</p>,
			);
		}
		i++;
	}
	return { blocks, next: i };
}

export function Markdown({
	source,
	anchors = [],
	onAnchor = () => {},
	onCheck,
}: {
	source: string;
	anchors?: Anchor[];
	onAnchor?: (thread: string) => void;
	onCheck?: (line: number, done: boolean) => void;
}) {
	const { lines, origins } = untangled(source.split("\n"));
	return <div className="md">{blocksOf({ lines, origins, anchors, onAnchor, onCheck }, 0, 0, false).blocks}</div>;
}
