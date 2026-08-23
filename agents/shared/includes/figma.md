## Figma source of truth

- Always extract design values and screen copy (text content) from Figma MCP - never estimate from screenshots or write placeholder text.
- If Figma MCP is unavailable during dev, stop and flag the blocker rather than proceeding with estimated values. Do not build UI components or screens without Figma access.
- When extracting tokens, find the Styles/Tokens page in the Figma file first and extract from there, not from component instances.
- Cross-reference screen mockups against the token set to catch any gaps.
- When writing tech steps for a ticket with UI work, each UI action item must reference the source Figma frame (frame name and nodeId) so the implementing agent can jump to it directly without searching the file.
