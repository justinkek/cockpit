import type { InboxItem } from "@/lib/shared";
import { pageOf } from "@/lib/shared";

const KEY = "cockpit-notify";
export const INBOX_READ = "cockpit-inbox-read";
export const NOTIFY_CHANGED = "cockpit-notify-change";

export type NotifyState = "unsupported" | "insecure" | "denied" | "off" | "on";

export function notifyState(): NotifyState {
	if (typeof window === "undefined" || !("Notification" in window)) return "unsupported";
	if (!window.isSecureContext) return "insecure";
	if (Notification.permission === "denied") return "denied";
	let wanted = false;
	try {
		wanted = window.localStorage.getItem(KEY) === "on";
	} catch {}
	return wanted && Notification.permission === "granted" ? "on" : "off";
}

export async function setNotify(on: boolean): Promise<NotifyState> {
	if (on && notifyState() === "off" && Notification.permission !== "granted") {
		await Notification.requestPermission();
	}
	try {
		if (on && Notification.permission === "granted") window.localStorage.setItem(KEY, "on");
		else window.localStorage.removeItem(KEY);
	} catch {}
	window.dispatchEvent(new Event(NOTIFY_CHANGED));
	return notifyState();
}

export function itemKey(item: InboxItem) {
	return `${item.kind}:${item.id}:${item.comment ?? item.at}`;
}

export function itemHref(item: InboxItem) {
	return item.id.startsWith("EPIC-") ? `/epics?open=${item.id}` : pageOf(item.id);
}

export function itemTitle(item: InboxItem) {
	if (item.kind === "comment") return `${item.author} commented on ${item.id}`;
	if (item.kind === "blocked") return `${item.id} is blocked`;
	return `${item.id} is waiting in ${item.status}`;
}

export function itemDetail(item: InboxItem) {
	if (item.kind === "waiting") return item.name;
	return `${item.name}: ${(item.text ?? "").split("\n")[0]}`;
}

export function announce(item: InboxItem) {
	if (notifyState() !== "on") return;
	const shown = new Notification(itemTitle(item), { body: itemDetail(item), tag: itemKey(item) });
	shown.onclick = () => {
		window.focus();
		window.location.assign(itemHref(item));
		shown.close();
	};
}
