"use client";

import { useRouter } from "next/navigation";

export function SprintPicker({
	sprints,
	value,
	measure,
}: {
	sprints: { id: string; label: string }[];
	value: string;
	measure: string;
}) {
	const router = useRouter();
	return (
		<select
			aria-label="Sprint"
			value={value}
			onChange={(event) => router.push(`/sprints?sprint=${encodeURIComponent(event.target.value)}&measure=${measure}`)}
		>
			{sprints.map((sprint) => (
				<option key={sprint.id} value={sprint.id}>
					{sprint.label}
				</option>
			))}
		</select>
	);
}
