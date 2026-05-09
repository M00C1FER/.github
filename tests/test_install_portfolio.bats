#!/usr/bin/env bats

SCRIPT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/install-portfolio.sh"

@test "--list prints all 11 tool names" {
  run bash "$SCRIPT" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"mcp-citation-research"* ]]
  [[ "$output" == *"memory-tool-conformance"* ]]
  [[ "$output" == *"contract-net-router"* ]]
  [[ "$output" == *"consensus-engine"* ]]
  [[ "$output" == *"multi-agent-council"* ]]
  [[ "$output" == *"clear-benchmark"* ]]
  [[ "$output" == *"common-operating-picture"* ]]
  [[ "$output" == *"cli-parity-validator"* ]]
  [[ "$output" == *"mcts-research-explorer"* ]]
  [[ "$output" == *"mesh-review"* ]]
  [[ "$output" == *"gh-portfolio"* ]]
}

@test "--tools nonexistent errors clearly" {
  run bash "$SCRIPT" --tools nonexistent --pipx --unattended
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown tool entry-point: nonexistent"* ]]
}

@test "--unattended --tools cnr --pipx runs orchestrator dry-run mode" {
  run env PORTFOLIO_DRY_RUN=1 bash "$SCRIPT" --unattended --tools cnr --pipx
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"=== Installing contract-net-router"* ]]
  [[ "$output" == *"✓ contract-net-router"* ]]
}

@test "WSL CRLF self-heal works with CRLF-encoded copy" {
  tmpdir="$(mktemp -d)"
  cp "$SCRIPT" "$tmpdir/install-portfolio-crlf.sh"
  sed -i 's/$/\r/' "$tmpdir/install-portfolio-crlf.sh"

  run bash "$tmpdir/install-portfolio-crlf.sh" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"mcp-citation-research"* ]]
  rm -rf "$tmpdir"
}

@test "--all --unattended --pipx flag combination is accepted" {
  run env PORTFOLIO_DRY_RUN=1 bash "$SCRIPT" --all --unattended --pipx
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Portfolio install complete ==="* ]]
}
