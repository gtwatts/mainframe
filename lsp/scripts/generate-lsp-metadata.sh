#!/usr/bin/env bash
# =============================================================================
# generate-lsp-metadata.sh - Generate FUNCTIONS.lsp.json from FUNCTIONS.json
# =============================================================================
# Description: Transforms FUNCTIONS.json into LSP-optimized format with
#              completion items, hover documentation, signature help,
#              examples, and related functions.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INPUT_PATH="${1:-$PROJECT_ROOT/FUNCTIONS.json}"
OUTPUT_PATH="${2:-$PROJECT_ROOT/FUNCTIONS.lsp.json}"

echo "Generating LSP metadata..."
echo "  Input:  $INPUT_PATH"
echo "  Output: $OUTPUT_PATH"

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for LSP metadata generation" >&2
    echo "Install with: apt install jq / brew install jq" >&2
    exit 1
fi

# Check input exists
if [[ ! -f "$INPUT_PATH" ]]; then
    echo "Error: FUNCTIONS.json not found at $INPUT_PATH" >&2
    exit 1
fi

# Owner-parity (A++ Phase 0): completions/signatures must show exactly one
# registration per function name — the canonical owner from MANIFEST.json's
# name_index. Fail closed when the manifest is missing: an ambiguous agent
# surface is worse than no surface.
MANIFEST_PATH="$PROJECT_ROOT/MANIFEST.json"
if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "Error: MANIFEST.json not found — run scripts/generate-manifest.py first" >&2
    exit 1
fi

# name -> owner module (canonical ID mf:<pack>:<module>:<name>; module is the
# third segment)
OWNERS_JSON=$(jq -c '.name_index | with_entries(.value = (.value | split(":")[2]))' "$MANIFEST_PATH")
SEMANTICS_JSON=$(jq -c '
  .exports | to_entries | map({
    key: .value.name,
    value: {
      canonicalId: .key,
      executionExposure: .value.execution_exposure,
      semanticStatus: .value.semantic_status,
      stability: .value.stability,
      declaredEffects: .value.declared_effects
    }
  }) | from_entries
' "$MANIFEST_PATH")

# Generate LSP-optimized metadata with rich information
jq --argjson owners "$OWNERS_JSON" --argjson semantics "$SEMANTICS_JSON" '
{
  version: .version,
  generated: (now | todate),
  index_format: "lsp-2.0",

  # Flatten functions into completion items with rich metadata
  # (owner-parity: keep only the canonical owner registration)
  completions: [
    .libraries | to_entries[] |
    .key as $lib_name |
    .value as $lib |
    select(.value.functions != null) |
    .value.functions | to_entries[] |
    select($owners[.key] == $lib_name) |
    {
      label: .key,
      kind: "Function",
      detail: (.value.signature // .key),
      documentation: (
        (.value.description // "MAINFRAME function") +
        (if .value.signature then ("\n\n**Signature:**\n```bash\n" + .value.signature + "\n```") else "" end) +
        (if .value.returns then ("\n\n**Returns:** `" + .value.returns + "`") else "" end) +
        (if .value.idempotent then "\n\n**Idempotent:** Yes" else "" end) +
        (if .value.pure then "\n\n**Pure function:** Yes" else "" end)
      ),
      insertText: .key,
      insertTextFormat: 1,  # PlainText

      # Sorting: prioritize by category, then alphabetically
      sortText: (
        "0-" + ($lib.category // "zz-other") + "-" + .key
      ),

      # Filter text includes function name, library, and description
      filterText: (.key + " " + $lib_name + " " + ($lib.description // "") | ascii_downcase),

      # Tags for categorization
      tags: ([
        ($lib.category // "other")
      ] + (if .value.pure == true then ["pure"] else [] end)
        + (if .value.idempotent == true then ["idempotent"] else [] end)),

      # Rich metadata for LSP features
      data: {
        library: $lib_name,
        libraryFile: $lib.file,
        libraryDescription: $lib.description,
        category: ($lib.category // "other"),
        signature: (.value.signature // .key),
        description: (.value.description // ""),
        returns: (.value.returns // ""),
        params: (.value.params // []),
        idempotent: (.value.idempotent // false),
        pure: (.value.pure // false),
        examples: (.value.examples // []),
        relatedFunctions: (.value.related // []),
        canonicalId: $semantics[.key].canonicalId,
        executionExposure: $semantics[.key].executionExposure,
        semanticStatus: $semantics[.key].semanticStatus,
        stability: $semantics[.key].stability,
        declaredEffects: $semantics[.key].declaredEffects
      }
    }
  ],

  # Build signature help index
  # (owner-parity: keep only the canonical owner registration)
  signatures: [
    .libraries | to_entries[] |
    .key as $lib_name |
    select(.value.functions != null) |
    .value.functions | to_entries[] |
    select($owners[.key] == $lib_name) |
    select(.value.params != null and (.value.params | length) > 0) |
    {
      function: .key,
      signature: (.value.signature // .key),
      description: (.value.description // ""),
      parameters: [
        .value.params[] |
        {
          label: .name,
          documentation: (.description // ""),
          position: .position,
          required: (.required // true),
          default: (.default // null)
        }
      ]
    }
  ],

  # Build library index for categorization
  libraries: [
    .libraries | to_entries[] |
    {
      name: .key,
      file: .value.file,
      description: (.value.description // ""),
      category: (.value.category // "other"),
      functionCount: (.value.functions | length)
    }
  ],

  # Category index for filtering
  categoryIndex: (
    .libraries | to_entries |
    group_by(.value.category // "other") |
    map({
      category: (.[0].value.category // "other"),
      libraries: [.[] | .key],
      functionCount: ([.[] | .value.functions | length] | add)
    })
  ),

  # Function count for validation (owner-filtered: counts unique exposed names)
  stats: {
    total_completions: ([.libraries | to_entries[] | .key as $lib | .value.functions | to_entries[] | select($owners[.key] == $lib)] | length),
    total_libraries: (.libraries | keys | length),
    total_signatures: ([.libraries | to_entries[] | .key as $lib | .value.functions | to_entries[] | select($owners[.key] == $lib) | select(.value.params != null and (.value.params | length) > 0)] | length),
    categories: (.stats.categories // [])
  }
}
' "$INPUT_PATH" > "$OUTPUT_PATH"

# Validate output
if [[ -f "$OUTPUT_PATH" ]]; then
    count=$(jq '.completions | length' "$OUTPUT_PATH")
    sigs=$(jq '.signatures | length' "$OUTPUT_PATH")
    libs=$(jq '.libraries | length' "$OUTPUT_PATH")
    echo "✓ Generated $count completion items"
    echo "✓ Generated $sigs signature help entries"
    echo "✓ Indexed $libs libraries"
    echo "Output: $OUTPUT_PATH"
else
    echo "Error: Failed to generate output" >&2
    exit 1
fi
