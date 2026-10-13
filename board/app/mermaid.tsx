"use client";

import { type CSSProperties, useEffect, useId, useRef, useState } from "react";

async function drawn(id: string, source: string, dark: boolean): Promise<Error | string> {
	const { default: mermaid } = await import("mermaid");
	mermaid.initialize({
		startOnLoad: false,
		securityLevel: "strict",
		suppressErrorRendering: true,
		theme: dark ? "dark" : "default",
	});
	try {
		return (await mermaid.render(id, source)).svg;
	} catch (failure) {
		return failure instanceof Error ? failure : new Error(String(failure));
	}
}

export function Mermaid({ source, style }: { source: string; style?: CSSProperties }) {
	const id = `mermaid-${useId().replace(/[^A-Za-z0-9]/g, "")}`;
	const drawCount = useRef(0);
	const [svg, setSvg] = useState<string | null>(null);
	useEffect(() => {
		let live = true;
		const scheme = window.matchMedia("(prefers-color-scheme: dark)");
		const draw = () => {
			drawCount.current += 1;
			return drawn(`${id}-${drawCount.current}`, source, scheme.matches).then((result) => {
				if (live) setSvg(result instanceof Error ? null : result);
			});
		};
		draw();
		scheme.addEventListener("change", draw);
		return () => {
			live = false;
			scheme.removeEventListener("change", draw);
		};
	}, [id, source]);
	if (svg === null)
		return (
			<pre className="md-code" style={style}>
				{source}
			</pre>
		);
	return <div className="md-diagram" style={style} dangerouslySetInnerHTML={{ __html: svg }} />;
}
