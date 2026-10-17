"use client";

import type { HLJSApi, LanguageFn } from "highlight.js";
import { type CSSProperties, type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { copyText } from "@/app/keys";
import { useMermaidSvg } from "@/app/mermaid";

export const LANGUAGES: [string, string][] = [
	["", "Plain text"],
	["bash", "Bash"],
	["css", "CSS"],
	["diff", "Diff"],
	["dockerfile", "Dockerfile"],
	["go", "Go"],
	["html", "HTML"],
	["ini", "INI"],
	["java", "Java"],
	["javascript", "JavaScript"],
	["json", "JSON"],
	["kotlin", "Kotlin"],
	["markdown", "Markdown"],
	["mermaid", "Mermaid"],
	["python", "Python"],
	["ruby", "Ruby"],
	["rust", "Rust"],
	["sql", "SQL"],
	["swift", "Swift"],
	["tsx", "TSX"],
	["typescript", "TypeScript"],
	["xml", "XML"],
	["yaml", "YAML"],
];

const GRAMMARS: Record<string, string> = {
	bash: "bash",
	sh: "bash",
	shell: "bash",
	zsh: "bash",
	console: "bash",
	css: "css",
	dockerfile: "dockerfile",
	go: "go",
	html: "xml",
	xml: "xml",
	svg: "xml",
	ini: "ini",
	toml: "ini",
	gitattributes: "ini",
	java: "java",
	javascript: "javascript",
	js: "javascript",
	jsx: "javascript",
	mjs: "javascript",
	json: "json",
	jsonc: "json",
	kotlin: "kotlin",
	kt: "kotlin",
	markdown: "markdown",
	md: "markdown",
	mermaid: "mermaid",
	python: "python",
	py: "python",
	ruby: "ruby",
	rb: "ruby",
	rust: "rust",
	rs: "rust",
	sql: "sql",
	swift: "swift",
	typescript: "typescript",
	ts: "typescript",
	tsx: "typescript",
	yaml: "yaml",
	yml: "yaml",
};

const mermaidGrammar: LanguageFn = () => ({
	name: "Mermaid",
	keywords: {
		keyword:
			"graph flowchart sequenceDiagram classDiagram stateDiagram erDiagram gantt pie journey gitGraph mindmap timeline quadrantChart requirementDiagram participant actor as Note note over left right of loop alt else opt par and critical break rect end autonumber activate deactivate subgraph direction class classDef style linkStyle click title section dateFormat axisFormat state",
		literal: "TD TB BT RL LR true false",
	},
	contains: [
		{ scope: "comment", begin: /%%/, end: /$/ },
		{ scope: "string", begin: /"/, end: /"/ },
		{ scope: "string", begin: /\|/, end: /\|/ },
		{ scope: "string", begin: /\[/, end: /\]/ },
		{ scope: "string", begin: /\{/, end: /\}/ },
		{ scope: "string", begin: /:/, beginScope: "operator", end: /$/ },
		{ scope: "operator", match: /[-=.<>)]{2,}[x>)]?/ },
		{ scope: "number", match: /\b\d+(?:\.\d+)?\b/ },
	],
});

const LOADERS: Record<string, () => Promise<{ default: LanguageFn }>> = {
	bash: () => import("highlight.js/lib/languages/bash"),
	css: () => import("highlight.js/lib/languages/css"),
	dockerfile: () => import("highlight.js/lib/languages/dockerfile"),
	go: () => import("highlight.js/lib/languages/go"),
	ini: () => import("highlight.js/lib/languages/ini"),
	java: () => import("highlight.js/lib/languages/java"),
	javascript: () => import("highlight.js/lib/languages/javascript"),
	json: () => import("highlight.js/lib/languages/json"),
	kotlin: () => import("highlight.js/lib/languages/kotlin"),
	markdown: () => import("highlight.js/lib/languages/markdown"),
	mermaid: async () => ({ default: mermaidGrammar }),
	python: () => import("highlight.js/lib/languages/python"),
	ruby: () => import("highlight.js/lib/languages/ruby"),
	rust: () => import("highlight.js/lib/languages/rust"),
	sql: () => import("highlight.js/lib/languages/sql"),
	swift: () => import("highlight.js/lib/languages/swift"),
	typescript: () => import("highlight.js/lib/languages/typescript"),
	xml: () => import("highlight.js/lib/languages/xml"),
	yaml: () => import("highlight.js/lib/languages/yaml"),
};

let core: Promise<HLJSApi> | null = null;
const registered = new Map<string, Promise<boolean>>();

async function highlighted(code: string, language: string): Promise<string | null> {
	const grammar = GRAMMARS[language.toLowerCase()];
	const load = grammar ? LOADERS[grammar] : undefined;
	if (!grammar || !load) return null;
	core ??= import("highlight.js/lib/core").then((loaded) => loaded.default);
	const hljs = await core;
	if (!registered.has(grammar)) {
		registered.set(
			grammar,
			load()
				.then((loaded) => {
					hljs.registerLanguage(grammar, loaded.default);
					return true;
				})
				.catch(() => false),
		);
	}
	if (!(await registered.get(grammar))) return null;
	try {
		return hljs.highlight(code, { language: grammar, ignoreIllegals: true }).value;
	} catch {
		return null;
	}
}

function useHighlighted(code: string, language: string) {
	const [html, setHtml] = useState<{ code: string; language: string; value: string } | null>(null);
	useEffect(() => {
		let live = true;
		highlighted(code, language).then((value) => {
			if (live) setHtml(value === null ? null : { code, language, value });
		});
		return () => {
			live = false;
		};
	}, [code, language]);
	return html && html.code === code && html.language === language ? html.value : null;
}

const DIFF_KINDS: [RegExp, string][] = [
	[/^(?:\+\+\+|---)(?: |$)/, "meta"],
	[/^={3,}/, "heading"],
	[/^@@/, "hunk"],
	[/^\+/, "add"],
	[/^-/, "del"],
	[/^!/, "mod"],
];

export function diffKind(line: string) {
	return DIFF_KINDS.find(([pattern]) => pattern.test(line))?.[1] ?? "same";
}

const SHORT: Record<string, string> = {
	sh: "bash",
	shell: "bash",
	zsh: "bash",
	js: "javascript",
	jsx: "javascript",
	ts: "typescript",
	yml: "yaml",
	md: "markdown",
	py: "python",
	rb: "ruby",
	rs: "rust",
	kt: "kotlin",
	text: "",
	txt: "",
	plaintext: "",
};

export function nameOf(language: string) {
	const lower = language.toLowerCase();
	const known = LANGUAGES.find(([id]) => id === (SHORT[lower] ?? lower));
	return known ? known[1] : language || "Plain text";
}

function CopyButton({ text, label = "Copy" }: { text: string; label?: string }) {
	const [copied, setCopied] = useState<boolean | null>(null);
	useEffect(() => {
		if (copied === null) return;
		const timer = window.setTimeout(() => setCopied(null), 1500);
		return () => window.clearTimeout(timer);
	}, [copied]);
	return (
		<button type="button" className="code-tool" onClick={async () => setCopied(await copyText(text))}>
			{copied === null ? label : copied ? "Copied" : "Could not copy"}
		</button>
	);
}

function LanguagePicker({ language, onLanguage }: { language: string; onLanguage?: (language: string) => void }) {
	if (!onLanguage) return <span className="code-language">{nameOf(language)}</span>;
	const known = LANGUAGES.some(([id]) => id === language);
	return (
		<select
			className="code-language"
			aria-label="Language of the code block"
			value={language}
			onChange={(event) => onLanguage(event.target.value)}
		>
			{!known && <option value={language}>{nameOf(language)}</option>}
			{LANGUAGES.map(([id, name]) => (
				<option key={id} value={id}>
					{name}
				</option>
			))}
		</select>
	);
}

function Frame({
	language,
	onLanguage,
	tools,
	style,
	className = "",
	children,
}: {
	language: string;
	onLanguage?: (language: string) => void;
	tools: ReactNode;
	style?: CSSProperties;
	className?: string;
	children: ReactNode;
}) {
	return (
		<div className={`code-block ${className}`.trim()} style={style}>
			<div className="code-head">
				<LanguagePicker language={language} onLanguage={onLanguage} />
				<span className="code-tools">{tools}</span>
			</div>
			{children}
		</div>
	);
}

function Highlighted({ code, language }: { code: string; language: string }) {
	const html = useHighlighted(code, language);
	if (html === null) return <pre className="md-code">{code}</pre>;
	return (
		<pre className="md-code">
			<code className="hljs" dangerouslySetInnerHTML={{ __html: html }} />
		</pre>
	);
}

type Mode = "code" | "diagram" | "split";

const MODES: [Mode, string, string][] = [
	["code", "Code", "Show the code only"],
	["diagram", "Preview", "Show the diagram only"],
	["split", "Split", "Show the code and the diagram"],
];

function download(svg: string, name: string) {
	const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
	const link = document.createElement("a");
	link.href = url;
	link.download = name;
	document.body.append(link);
	link.click();
	link.remove();
	window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function DiagramZoom({ svg, onClose }: { svg: string; onClose: () => void }) {
	const stage = useRef<HTMLDivElement>(null);
	const canvas = useRef<HTMLDivElement>(null);
	const [view, setView] = useState({ scale: 1, x: 0, y: 0 });
	const [fit, setFit] = useState(1);
	const dragging = useRef<{ x: number; y: number; fromX: number; fromY: number } | null>(null);

	useLayoutEffect(() => {
		const box = stage.current;
		const drawing = canvas.current?.querySelector("svg");
		if (!box || !drawing) return;
		const frame = drawing.viewBox.baseVal;
		const width = frame?.width || drawing.getBoundingClientRect().width || 1;
		const height = frame?.height || drawing.getBoundingClientRect().height || 1;
		drawing.setAttribute("width", String(width));
		drawing.setAttribute("height", String(height));
		drawing.style.maxWidth = "none";
		const scale = Math.min(2, (box.clientWidth - 32) / width, (box.clientHeight - 32) / height);
		setFit(scale);
		setView({ scale, x: 0, y: 0 });
	}, [svg]);

	useEffect(() => {
		const box = stage.current;
		function onKey(event: KeyboardEvent) {
			if (event.key !== "Escape") return;
			event.preventDefault();
			event.stopPropagation();
			onClose();
		}
		function onWheel(event: WheelEvent) {
			event.preventDefault();
			const factor = Math.exp(-event.deltaY * 0.0015);
			setView((now) => ({ ...now, scale: Math.min(8, Math.max(0.1, now.scale * factor)) }));
		}
		window.addEventListener("keydown", onKey, true);
		box?.addEventListener("wheel", onWheel, { passive: false });
		const before = document.body.style.overflow;
		document.body.style.overflow = "hidden";
		return () => {
			window.removeEventListener("keydown", onKey, true);
			box?.removeEventListener("wheel", onWheel);
			document.body.style.overflow = before;
		};
	}, [onClose]);

	const zoom = (factor: number) =>
		setView((now) => ({ ...now, scale: Math.min(8, Math.max(0.1, now.scale * factor)) }));

	return createPortal(
		<div className="diagram-zoom" role="dialog" aria-modal="true" aria-label="Diagram">
			<div className="diagram-zoom-bar">
				<button type="button" className="code-tool" onClick={() => zoom(1 / 1.25)} aria-label="Zoom out">
					−
				</button>
				<span className="diagram-zoom-scale">{Math.round(view.scale * 100)}%</span>
				<button type="button" className="code-tool" onClick={() => zoom(1.25)} aria-label="Zoom in">
					+
				</button>
				<button type="button" className="code-tool" onClick={() => setView({ scale: fit, x: 0, y: 0 })}>
					Fit
				</button>
				<button type="button" className="code-tool" onClick={() => download(svg, "diagram.svg")}>
					Download SVG
				</button>
				<button type="button" className="code-tool" onClick={onClose}>
					Close
				</button>
			</div>
			<div
				ref={stage}
				className="diagram-zoom-stage"
				onPointerDown={(event) => {
					event.currentTarget.setPointerCapture(event.pointerId);
					dragging.current = { x: event.clientX, y: event.clientY, fromX: view.x, fromY: view.y };
				}}
				onPointerMove={(event) => {
					const from = dragging.current;
					if (!from) return;
					setView((now) => ({
						...now,
						x: from.fromX + event.clientX - from.x,
						y: from.fromY + event.clientY - from.y,
					}));
				}}
				onPointerUp={() => {
					dragging.current = null;
				}}
				onPointerCancel={() => {
					dragging.current = null;
				}}
			>
				<div
					ref={canvas}
					className="diagram-zoom-canvas"
					style={{ transform: `translate(-50%, -50%) translate(${view.x}px, ${view.y}px) scale(${view.scale})` }}
					dangerouslySetInnerHTML={{ __html: svg }}
				/>
			</div>
		</div>,
		document.body,
	);
}

function MermaidBlock({
	code,
	language,
	style,
	onLanguage,
}: {
	code: string;
	language: string;
	style?: CSSProperties;
	onLanguage?: (language: string) => void;
}) {
	const [mode, setMode] = useState<Mode>("diagram");
	const [zoomed, setZoomed] = useState(false);
	const { svg, failed } = useMermaidSvg(code);
	const diagram = svg ? (
		<div className="md-diagram" dangerouslySetInnerHTML={{ __html: svg }} />
	) : (
		<div className="diagram-missing">
			{failed && <p className="diagram-failed">This diagram could not be drawn - its source is below.</p>}
			<pre className="md-code">{code}</pre>
		</div>
	);
	return (
		<Frame
			language={language}
			onLanguage={onLanguage}
			style={style}
			className={`mermaid-block mode-${mode}`}
			tools={
				<>
					<span className="code-modes" role="group" aria-label="Show">
						{MODES.map(([value, label, title]) => (
							<button
								key={value}
								type="button"
								className={`code-tool${mode === value ? " on" : ""}`}
								aria-pressed={mode === value}
								title={title}
								onClick={() => setMode(value)}
							>
								{label}
							</button>
						))}
					</span>
					<button
						type="button"
						className="code-tool"
						disabled={!svg}
						title="Open the diagram larger"
						onClick={() => setZoomed(true)}
					>
						Zoom
					</button>
					<button
						type="button"
						className="code-tool"
						disabled={!svg}
						title="Download the diagram as an SVG file"
						onClick={() => svg && download(svg, "diagram.svg")}
					>
						SVG
					</button>
					<CopyButton text={code} />
				</>
			}
		>
			<div className="mermaid-views">
				{mode !== "diagram" && <Highlighted code={code} language={language} />}
				{mode !== "code" && diagram}
			</div>
			{zoomed && svg && <DiagramZoom svg={svg} onClose={() => setZoomed(false)} />}
		</Frame>
	);
}

export function CodeBlock({
	language,
	code,
	style,
	onLanguage,
}: {
	language: string;
	code: string[];
	style?: CSSProperties;
	onLanguage?: (language: string) => void;
}) {
	const text = code.join("\n");
	if (language === "mermaid")
		return <MermaidBlock code={text} language={language} style={style} onLanguage={onLanguage} />;
	const tools = <CopyButton text={text} />;
	if (language === "diff") {
		return (
			<Frame language={language} onLanguage={onLanguage} style={style} tools={tools}>
				<pre className="md-code md-diff">
					<span className="diff-lines">
						{code.map((line, n) => (
							<span key={n} className={`diff-line ${diffKind(line)}`}>
								{line}
							</span>
						))}
					</span>
				</pre>
			</Frame>
		);
	}
	return (
		<Frame language={language} onLanguage={onLanguage} style={style} tools={tools}>
			<Highlighted code={text} language={language} />
		</Frame>
	);
}
