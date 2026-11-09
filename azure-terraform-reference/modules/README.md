# Module authoring standard

Each reusable module should have this layout:

```text
modules/<module-name>/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── README.md
```

Rules:
- Modules do not configure remote backends.
- Root configurations own provider/subscription/backend selection.
- Modules do not hardcode environment-specific values.
- Inputs must have types, descriptions, and validations where appropriate.
- Outputs expose only useful IDs and attributes.
- A module creates/manages resources only; consumers use data sources or remote-state outputs for resources owned elsewhere.
- Do not implement a silent "lookup then create" fallback.
- Keep module versions pinned by live roots.
- Test module changes in Dev before promotion.
