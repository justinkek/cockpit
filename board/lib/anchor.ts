const MARKUP = "(?:\\*\\*|`|\\[|\\]\\([^)\\s]*\\)|<|>)*";
const OPENING = "(?:\\*\\*|`|\\[|<)?";
const CLOSING = "(?:\\*\\*|`|\\]\\([^)\\s]*\\)|>)?";

function literal(character: string) {
	if (character === " ") return "[ \\t]+";
	return character.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function anchorFor(selected: string, body: string): string | null {
	const text = selected.replace(/\s+/g, " ").trim();
	if (text === "") return null;
	if (body.includes(text)) return text;
	const pattern = new RegExp(OPENING + [...text].map(literal).join(MARKUP) + CLOSING);
	return body.match(pattern)?.[0] ?? null;
}
