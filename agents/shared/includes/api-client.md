## API client

- One file per endpoint, named for the resource with the method as a filename suffix - not a folder level (`sessionFork.GET.ts`, not `GET/sessionFork.ts`).
- Each file holds its own schema, resolver and definition. No registry to update - adding an endpoint is adding one file, and nothing else.
- Paths live in a per-service paths file, never inline in the endpoint files.
- A per-service factory binds base URL, service and version, so endpoint files never repeat them.
