import type { ReactNode } from "react";
import { Mermaid } from "@/app/mermaid";

type Anchor = { text: string; thread: string };

function highlight(text: string, anchors: Anchor[], onAnchor: (thread: string) => void, key: string): ReactNode[] {
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
		if (span.start > cursor) parts.push(text.slice(cursor, span.start));
		parts.push(
			<mark key={`${key}-${span.start}`} className="anchor" onClick={() => onAnchor(span.thread)}>
				{text.slice(span.start, span.end)}
			</mark>,
		);
		cursor = span.end;
	}
	if (cursor < text.length) parts.push(text.slice(cursor));
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
					{highlight(match[1], anchors, onAnchor, part)}
				</a>,
			);
		} else if (match[3] !== undefined) {
			nodes.push(
				<a key={part} href={match[3]} target="_blank" rel="noreferrer">
					{match[3]}
				</a>,
			);
		} else if (match[4] !== undefined) {
			nodes.push(<code key={part}>{highlight(match[4], anchors, onAnchor, part)}</code>);
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

const opening = /^<details(?:\s[^>]*)?>(.*)$/;
const summarised = /^<summary>(.*)<\/summary>$/;

function blocksOf(
	lines: string[],
	from: number,
	base: number,
	nested: boolean,
	anchors: Anchor[],
	onAnchor: (thread: string) => void,
): { blocks: ReactNode[]; next: number } {
	const blocks: ReactNode[] = [];
	let i = from;
	while (i < lines.length) {
		const raw = lines[i];
		const line = raw.trimStart();
		const depth = Math.max(0, depthOf(raw) - base);
		const key = `b${i}`;
		const style = depth > 0 ? { marginLeft: `${depth * 18}px` } : undefined;

		if (line.trimEnd() === "</details>") {
			if (nested) return { blocks, next: i + 1 };
			i++;
			continue;
		}

		const toggle = line.trimEnd().match(opening);
		if (toggle) {
			let summary = toggle[1].trim();
			let next = i + 1;
			if (summary === "" && next < lines.length && summarised.test(lines[next].trim())) summary = lines[next++].trim();
			const title = summary.match(summarised)?.[1] ?? (summary || "Details");
			const inner = blocksOf(lines, next, depthOf(raw) + 1, true, anchors, onAnchor);
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
			blocks.push(
				<div key={key} className={`md-todo${todo[1] === "x" ? " done" : ""}`} style={style}>
					<span className="box" aria-hidden="true">
						{todo[1] === "x" ? "✓" : ""}
					</span>
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
}: {
	source: string;
	anchors?: Anchor[];
	onAnchor?: (thread: string) => void;
}) {
	return <div className="md">{blocksOf(source.split("\n"), 0, 0, false, anchors, onAnchor).blocks}</div>;
}
