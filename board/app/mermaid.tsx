"use client";

import { type CSSProperties, useEffect, useId, useRef, useState } from "react";
import { darkNow, onThemeChange } from "@/app/theme";

async function drawn(id: string, source: string, dark: boolean): Promise<string | null> {
	const { default: mermaid } = await import("mermaid");
	mermaid.initialize({
		startOnLoad: false,
		securityLevel: "strict",
		suppressErrorRendering: true,
		theme: dark ? "dark" : "default",
	});
	try {
		return (await mermaid.render(id, source)).svg;
	} catch {
		return null;
	}
}

export function Mermaid({ source, style }: { source: string; style?: CSSProperties }) {
	const id = `mermaid-${useId().replace(/[^A-Za-z0-9]/g, "")}`;
	const drawCount = useRef(0);
	const [svg, setSvg] = useState<string | null>(null);
	useEffect(() => {
		let live = true;
		const draw = () => {
			drawCount.current += 1;
			return drawn(`${id}-${drawCount.current}`, source, darkNow()).then((result) => {
				if (live) setSvg(result);
			});
		};
		draw();
		const stop = onThemeChange(draw);
		return () => {
			live = false;
			stop();
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
