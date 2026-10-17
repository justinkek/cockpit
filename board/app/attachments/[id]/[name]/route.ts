import { readFile } from "node:fs/promises";
import path from "node:path";
import { BoardError, findRenamed, listAttachments } from "@/lib/board";

export const dynamic = "force-dynamic";

const TYPES: Record<string, string> = {
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".gif": "image/gif",
	".webp": "image/webp",
	".avif": "image/avif",
	".svg": "image/svg+xml",
	".pdf": "application/pdf",
	".html": "text/html; charset=utf-8",
	".htm": "text/html; charset=utf-8",
	".txt": "text/plain; charset=utf-8",
	".md": "text/plain; charset=utf-8",
	".log": "text/plain; charset=utf-8",
	".csv": "text/csv; charset=utf-8",
	".json": "application/json; charset=utf-8",
	".mp4": "video/mp4",
	".webm": "video/webm",
	".mov": "video/quicktime",
	".mp3": "audio/mpeg",
	".wav": "audio/wav",
	".zip": "application/zip",
};

async function attachmentsOf(id: string): Promise<string[] | null> {
	try {
		return await listAttachments(id);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
	}
	const renamed = await findRenamed(id);
	return renamed ? listAttachments(renamed) : null;
}

export async function GET(_request: Request, { params }: { params: Promise<{ id: string; name: string }> }) {
	const { id, name } = await params;
	const files = await attachmentsOf(id);
	const file = files?.find((candidate) => path.basename(candidate) === name);
	if (!file) return new Response(`No attachment ${name} on ${id}`, { status: 404 });
	const type = TYPES[path.extname(name).toLowerCase()] ?? "application/octet-stream";
	return new Response(new Uint8Array(await readFile(file)), {
		headers: {
			"Content-Type": type,
			"Content-Disposition": `inline; filename*=UTF-8''${encodeURIComponent(name)}`,
			"Content-Security-Policy": "sandbox allow-scripts allow-popups allow-downloads",
			"X-Content-Type-Options": "nosniff",
			"Cache-Control": "no-store",
		},
	});
}
