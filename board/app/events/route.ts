import { followBoard, type Heard } from "@/lib/watch";

export const dynamic = "force-dynamic";

const BEAT = 25000;

function event(heard: Heard) {
	if ("revision" in heard) return `data: ${heard.revision}\n\n`;
	return `event: failure\ndata: ${heard.error.replace(/\s*\n\s*/g, " ")}\n\n`;
}

export function GET(request: Request) {
	const encoder = new TextEncoder();
	let finish = () => {};
	const stream = new ReadableStream<Uint8Array>({
		start(controller) {
			let open = true;
			function send(text: string) {
				if (!open) return;
				try {
					controller.enqueue(encoder.encode(text));
				} catch {
					finish();
				}
			}
			send("retry: 2000\n\n");
			const unfollow = followBoard((heard) => send(event(heard)));
			const beat = setInterval(() => send(": beat\n\n"), BEAT);
			finish = () => {
				if (!open) return;
				open = false;
				clearInterval(beat);
				unfollow();
				try {
					controller.close();
				} catch {}
			};
			request.signal.addEventListener("abort", finish);
		},
		cancel() {
			finish();
		},
	});
	return new Response(stream, {
		headers: {
			"Content-Type": "text/event-stream; charset=utf-8",
			"Cache-Control": "no-store, no-transform",
			Connection: "keep-alive",
			"X-Accel-Buffering": "no",
		},
	});
}
