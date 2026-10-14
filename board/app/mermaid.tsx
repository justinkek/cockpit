"use client";

import { useEffect, useId, useRef, useState } from "react";
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

export type Drawing = { svg: string | null; failed: boolean };

export function useMermaidSvg(source: string): Drawing {
	const id = `mermaid-${useId().replace(/[^A-Za-z0-9]/g, "")}`;
	const drawCount = useRef(0);
	const [drawing, setDrawing] = useState<Drawing>({ svg: null, failed: false });
	useEffect(() => {
		let live = true;
		const draw = () => {
			drawCount.current += 1;
			return drawn(`${id}-${drawCount.current}`, source, darkNow()).then((svg) => {
				if (live) setDrawing({ svg, failed: svg === null });
			});
		};
		draw();
		const stop = onThemeChange(draw);
		return () => {
			live = false;
			stop();
		};
	}, [id, source]);
	return drawing;
}
